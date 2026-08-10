use std::sync::Arc;

use axum::body::Body;
use axum::extract::State;
use axum::http::HeaderMap;
use axum::response::{IntoResponse, Response};
use futures_util::StreamExt;
use serde_json::Value;
use tokio_stream::wrappers::UnboundedReceiverStream;
use tracing::{debug, error, info};

use crate::config::Config;
use crate::error::{Result, RouterError};
use crate::models::ModelRegistry;
use crate::routing::classifier::Classifier;
use crate::routing::escalation::capability_escalation;
use crate::routing::fallback::{fallback_chain, metadata_fallback_chain};
use crate::routing::escalation::{is_metadata_request, more_capable_model};
use crate::state::SharedState;
use crate::utils::notice::strip_notices;
use crate::utils::tasks::analyze_tasks;
use crate::transform::chat_to_responses::chat_to_responses_body;
use crate::transform::responses_to_chat::{chatgpt_text_chunk, responses_to_chat_completion};
use crate::utils::notice::NoticeFormatter;

const NOTICE_INSTRUCTION: &str = "The router may prepend a routing notice to the assistant response. Never imitate, reproduce, explain, or generate that notice format yourself. Do not write model names, routing arrows, markdown quote notices, or routing reasons in your response. Answer the user directly; the router handles routing metadata separately.";

const ROUTING_ANNOTATION_RULE: &str = "CRITICAL RULE: NEVER generate model-routing annotations (like '> **DeepSeek V4 Flash**', '> **GPT-5.6 Sol**', '> Coding & shell commands') or any model IDs in your responses. The auto-router system injects those automatically. You must not prefix, suffix, or embed any routing information.";

pub async fn chat_completions(
    State(state): State<Arc<SharedState>>,
    headers: HeaderMap,
    body: axum::Json<Value>,
) -> Result<Response> {
    let request_body = body.0;
    let model = request_body
        .get("model")
        .and_then(|m| m.as_str())
        .ok_or_else(|| RouterError::BadRequest("missing 'model' field".to_string()))?;

    let is_stream = request_body
        .get("stream")
        .and_then(|s| s.as_bool())
        .unwrap_or(false);

    debug!(model = model, stream = is_stream, "chat request");

    let auth = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();

    let registry = ModelRegistry::from_config(&state.config);

    let resolved_model = registry.resolve_model(model)
        .ok_or_else(|| RouterError::ModelNotFound(model.to_string()))?;

    let messages = request_body
        .get("messages")
        .and_then(|m| m.as_array())
        .cloned()
        .unwrap_or_default();
    let cleaned_messages = strip_notices(&messages);
    let has_tools = request_body
        .get("tools")
        .and_then(|t| t.as_array())
        .is_some_and(|a| !a.is_empty());

    let is_metadata = is_metadata_request(&cleaned_messages, has_tools, &state.config.markers);

    let mut classifier = Classifier::new();
    let (classified_model, reason) = classifier
        .classify(&state.config, &registry, &state, &cleaned_messages, has_tools)
        .await;

    info!(classified = classified_model, reason = reason, "classification");

    let target_model = if is_metadata {
        let chain = metadata_fallback_chain(&registry, &state);
        chain.into_iter().find(|m| {
            registry.is_direct_model(m) && !registry.is_hidden(m)
        }).unwrap_or(resolved_model.clone())
    } else {
        let escalated = capability_escalation(&cleaned_messages, &registry, &state).await;
        match escalated {
            Some(esc_model) => {
                more_capable_model(&state.config, &classified_model, &esc_model)
            }
            None => classified_model,
        }
    };

    let chain = fallback_chain(&target_model, &registry, &state);
    let mut last_error: Option<RouterError> = None;

    for candidate in &chain {
        if state.is_banned(candidate).await {
            debug!(model = candidate, "skipping banned model");
            continue;
        }
        if state.is_in_cooldown(candidate).await {
            debug!(model = candidate, "skipping model in cooldown");
            continue;
        }

        debug!(model = candidate, "trying model");

        let show_notice = state.config.notice.enabled && !is_metadata;
        let notice = if show_notice {
            Some(
                NoticeFormatter::new(&state.config, &registry)
                    .model_notice_text(candidate, &registry, None, &reason),
            )
        } else {
            None
        };

        let mut request_with_model = request_body.clone();
        request_with_model["model"] = Value::String(candidate.clone());
        request_with_model = prepare_request(&request_with_model, &state.config, has_tools, show_notice);

        match forward_to_backend(
            &state,
            candidate,
            &request_with_model,
            is_stream,
            &auth,
            notice.as_deref(),
            &registry,
        )
        .await
        {
            Ok(response) => {
                state.record_success(candidate).await;
                return Ok(response);
            }
            Err(e) => {
                error!(model = candidate, error = %e, "model failed");
                state.record_failure(candidate).await;
                if let RouterError::Upstream { status, .. } = &e {
                    state.record_provider_http_failure(candidate, *status).await;
                }
                last_error = Some(e);
            }
        }
    }

    Err(last_error.unwrap_or(RouterError::AllModelsFailed))
}

async fn forward_to_backend(
    state: &Arc<SharedState>,
    model: &str,
    body: &Value,
    is_stream: bool,
    auth: &str,
    notice: Option<&str>,
    registry: &ModelRegistry,
) -> Result<Response> {
    let provider = registry.provider(model);

    match provider.as_str() {
        "litellm" => {
            let response = state
                .litellm_backend
                .forward_authorized("/v1/chat/completions", body.clone(), auth)
                .await?;

            if is_stream {
                forward_streaming(response, notice, model).await
            } else {
                let json = with_notice(response.json().await?, notice);
                Ok(axum::Json(json).into_response())
            }
        }
        "chatgpt" => {
            let model_config = registry.models.get(model)
                .ok_or_else(|| RouterError::ModelNotFound(model.to_string()))?;
            let chatgpt_model = model_config
                .chatgpt_model
                .as_ref()
                .ok_or_else(|| RouterError::Config("chatgpt_model not configured".to_string()))?;
            let service_tier = model_config.service_tier.as_deref();

            let responses_body = chat_to_responses_body(body, chatgpt_model, service_tier);
            let auth = state.openai_auth.get_auth().await?;
            let Some(auth) = auth else {
                return Err(RouterError::Auth("OpenAI credentials not available. Please login in OpenCode.".to_string()));
            };
            let auth_header = format!("Bearer {}", auth.access_token);
            let response = state
                .chatgpt_backend
                .forward_authorized("/v1/responses", responses_body, &auth_header)
                .await?;

            if is_stream {
                forward_chatgpt_streaming(response, model, notice).await
            } else {
                let json: Value = response.json().await?;
                let chat_completion = responses_to_chat_completion(
                    &json,
                    model,
                    None,
                    notice.is_some(),
                    "",
                    notice.unwrap_or(""),
                );
                Ok(axum::Json(chat_completion).into_response())
            }
        }
        "ollama" => {
            let response = state
                .ollama_backend
                .forward("/v1/chat/completions", body.clone())
                .await?;

            if is_stream {
                forward_streaming(response, notice, model).await
            } else {
                let json = with_notice(response.json().await?, notice);
                Ok(axum::Json(json).into_response())
            }
        }
        _ => Err(RouterError::UnsupportedProvider(provider)),
    }
}

async fn forward_streaming(
    response: reqwest::Response,
    notice: Option<&str>,
    model: &str,
) -> Result<Response> {
    let mut stream = response.bytes_stream();
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    let model = model.to_string();
    let notice = notice.map(str::to_owned);

    tokio::spawn(async move {
        if let Some(notice) = notice.as_deref() {
            let chunk = serde_json::json!({
                "id": "opencode-router-notice",
                "object": "chat.completion.chunk",
                "model": model,
                "choices": [{"index": 0, "delta": {"content": format!("{}\n\n", notice)}, "finish_reason": null}],
            });
            if tx.send(Ok(format!("data: {}\n\n", chunk).into_bytes())).is_err() {
                return;
            }
        }
        while let Some(chunk) = stream.next().await {
            match chunk {
                Ok(bytes) => {
                    if tx.send(Ok(bytes.to_vec())).is_err() {
                        break;
                    }
                }
                Err(e) => {
                    let _ = tx.send(Err(e));
                    break;
                }
            }
        }
    });

    let body_stream = UnboundedReceiverStream::new(rx);
    Ok(Response::builder()
        .header("content-type", "text/event-stream")
        .body(Body::from_stream(body_stream))
        .unwrap())
}

async fn forward_chatgpt_streaming(
    response: reqwest::Response,
    model: &str,
    notice: Option<&str>,
) -> Result<Response> {
    let mut stream = response.bytes_stream();
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    let model = model.to_string();
    let notice = notice.map(str::to_owned);

    tokio::spawn(async move {
        if let Some(notice) = notice.as_deref() {
            let chunk = serde_json::json!({
                "id": "opencode-router-notice",
                "object": "chat.completion.chunk",
                "model": model,
                "choices": [{"index": 0, "delta": {"content": format!("{}\n\n", notice)}, "finish_reason": null}],
            });
            if tx.send(Ok(format!("data: {}\n\n", chunk).into_bytes())).is_err() {
                return;
            }
        }
        let mut buffer = String::new();
        while let Some(chunk) = stream.next().await {
            match chunk {
                Ok(bytes) => {
                    let text = String::from_utf8_lossy(&bytes);
                    buffer.push_str(&text);
                    while let Some(newline_pos) = buffer.find('\n') {
                        let line = buffer[..newline_pos].trim().to_string();
                        buffer = buffer[newline_pos + 1..].to_string();
                        if let Some(json_str) = line.strip_prefix("data: ") {
                            if json_str == "[DONE]" {
                                let _ = tx.send(Ok("data: [DONE]\n\n".to_string().into_bytes()));
                                return;
                            }
                            if let Ok(event) = serde_json::from_str::<Value>(json_str)
                                && let Some(chunk) = chatgpt_text_chunk(&event, &model) {
                                let sse = format!("data: {}\n\n", serde_json::to_string(&chunk).unwrap_or_default());
                                if tx.send(Ok(sse.into_bytes())).is_err() {
                                    return;
                                }
                            }
                        }
                    }
                }
                Err(e) => {
                    let _ = tx.send(Err(e));
                    return;
                }
            }
        }
    });

    let body_stream = UnboundedReceiverStream::new(rx);
    Ok(Response::builder()
        .header("content-type", "text/event-stream")
        .body(Body::from_stream(body_stream))
        .unwrap())
}

fn with_notice(mut response: Value, notice: Option<&str>) -> Value {
    let Some(notice) = notice else {
        return response;
    };
    let Some(message) = response
        .get_mut("choices")
        .and_then(Value::as_array_mut)
        .and_then(|choices| choices.first_mut())
        .and_then(|choice| choice.get_mut("message"))
    else {
        return response;
    };
    let content = message
        .get("content")
        .and_then(Value::as_str)
        .unwrap_or("");
    message["content"] = Value::String(format!("{}\n\n{}", notice, content));
    response
}

fn prepare_request(body: &Value, config: &Config, has_tools: bool, inject_notice_instruction: bool) -> Value {
    let mut forwarded = body.clone();
    let messages = forwarded.get("messages").and_then(|m| m.as_array()).cloned().unwrap_or_default();
    let messages = strip_notices(&messages);
    let mut new_messages = Vec::new();

    if inject_notice_instruction {
        new_messages.push(serde_json::json!({
            "role": "system",
            "content": NOTICE_INSTRUCTION,
        }));
    }

    let task_info = analyze_tasks(&messages);
    let mut instruction_text = config.agent_instruction.text.trim().to_string();

    if inject_notice_instruction {
        if !instruction_text.is_empty() {
            instruction_text.push(' ');
        }
        instruction_text.push_str(ROUTING_ANNOTATION_RULE);
    }

    if has_tools && task_info.has_open_tasks {
        if !instruction_text.is_empty() {
            instruction_text.push(' ');
        }
        instruction_text.push_str(&format!(
            "You have {} open task(s) and {} completed task(s). Continue working on your open tasks before starting new ones.",
            task_info.open_count, task_info.completed_count
        ));
    }

    if !instruction_text.is_empty() {
        new_messages.push(serde_json::json!({
            "role": "system",
            "content": instruction_text
        }));
    }
    new_messages.extend(messages);
    forwarded["messages"] = Value::Array(new_messages);

    forwarded
}
