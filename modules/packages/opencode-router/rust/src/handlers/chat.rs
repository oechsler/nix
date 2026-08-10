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

        let mut request_with_model = request_body.clone();
        request_with_model["model"] = Value::String(candidate.clone());
        request_with_model = add_agent_instruction(&request_with_model, &state.config, has_tools);

        match forward_to_backend(&state, candidate, &request_with_model, is_stream, &auth, &registry).await {
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
                forward_streaming(response).await
            } else {
                let json: Value = response.json().await?;
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
            let response = state
                .chatgpt_backend
                .forward("/v1/responses", responses_body)
                .await?;

            if is_stream {
                forward_chatgpt_streaming(response, model).await
            } else {
                let json: Value = response.json().await?;
                let chat_completion = responses_to_chat_completion(&json, model, None, false, "", "");
                Ok(axum::Json(chat_completion).into_response())
            }
        }
        "ollama" => {
            let response = state
                .ollama_backend
                .forward("/api/chat", body.clone())
                .await?;

            if is_stream {
                forward_streaming(response).await
            } else {
                let json: Value = response.json().await?;
                Ok(axum::Json(json).into_response())
            }
        }
        _ => Err(RouterError::UnsupportedProvider(provider)),
    }
}

async fn forward_streaming(response: reqwest::Response) -> Result<Response> {
    let mut stream = response.bytes_stream();
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();

    tokio::spawn(async move {
        while let Some(chunk) = stream.next().await {
            match chunk {
                Ok(bytes) => {
                    if tx.send(Ok(bytes)).is_err() {
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

async fn forward_chatgpt_streaming(response: reqwest::Response, model: &str) -> Result<Response> {
    let mut stream = response.bytes_stream();
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    let model = model.to_string();

    tokio::spawn(async move {
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

fn add_agent_instruction(body: &Value, config: &Config, has_tools: bool) -> Value {
    if !has_tools {
        return body.clone();
    }

    let mut forwarded = body.clone();
    let messages = forwarded.get("messages").and_then(|m| m.as_array()).cloned().unwrap_or_default();

    let task_info = analyze_tasks(&messages);
    let mut instruction_text = config.agent_instruction.text.trim().to_string();

    if task_info.has_open_tasks {
        instruction_text.push_str(&format!(
            " You have {} open task(s) and {} completed task(s). Continue working on your open tasks before starting new ones.",
            task_info.open_count, task_info.completed_count
        ));
    }

    let instruction = serde_json::json!({
        "role": "system",
        "content": instruction_text
    });

    let mut new_messages = vec![instruction];
    new_messages.extend(messages);
    forwarded["messages"] = Value::Array(new_messages);

    forwarded
}
