use serde_json::Value;

pub fn responses_to_chat_completion(
    response: &Value,
    routed_model: &str,
    _original_model: Option<&str>,
    show_notice: bool,
    _classification_reason: &str,
    notice_text: &str,
) -> Value {
    let mut text_parts = Vec::new();
    let mut reasoning_parts = Vec::new();
    let mut tool_calls = Vec::new();

    if let Some(output) = response.get("output").and_then(|o| o.as_array()) {
        for item in output {
            let item_type = item.get("type").and_then(|t| t.as_str()).unwrap_or("");
            match item_type {
                "message" => {
                    if let Some(content) = item.get("content").and_then(|c| c.as_array()) {
                        for c in content {
                            let ct = c.get("type").and_then(|t| t.as_str()).unwrap_or("");
                            if matches!(ct, "output_text" | "text") {
                                text_parts.push(c.get("text").and_then(|t| t.as_str()).unwrap_or("").to_string());
                            }
                        }
                    }
                }
                "reasoning" => {
                    if let Some(summary) = item.get("summary").and_then(|s| s.as_array()) {
                        for s in summary {
                            let st = s.get("type").and_then(|t| t.as_str()).unwrap_or("");
                            if matches!(st, "summary_text" | "text") {
                                reasoning_parts.push(s.get("text").and_then(|t| t.as_str()).unwrap_or("").to_string());
                            }
                        }
                    }
                }
                "function_call" => {
                    tool_calls.push(serde_json::json!({
                        "id": item.get("call_id").or_else(|| item.get("id")).and_then(|v| v.as_str()).unwrap_or(""),
                        "type": "function",
                        "function": {
                            "name": item.get("name").and_then(|n| n.as_str()).unwrap_or(""),
                            "arguments": item.get("arguments").and_then(|a| a.as_str()).unwrap_or("{}"),
                        },
                    }));
                }
                _ => {}
            }
        }
    }

    let mut content = text_parts.join("");
    if show_notice {
        content = format!("{}\n\n{}", notice_text, content);
    }

    let mut message = serde_json::json!({
        "role": "assistant",
        "content": content,
    });

    if !tool_calls.is_empty() {
        message["tool_calls"] = Value::Array(tool_calls);
    }
    if !reasoning_parts.is_empty() {
        message["reasoning_content"] = Value::String(reasoning_parts.join(""));
    }

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    serde_json::json!({
        "id": response.get("id").and_then(|v| v.as_str()).unwrap_or("chatgpt-response"),
        "object": "chat.completion",
        "created": now,
        "model": response.get("model").and_then(|v| v.as_str()).unwrap_or(routed_model),
        "choices": [{"index": 0, "message": message, "finish_reason": "stop"}],
    })
}

pub fn chatgpt_text_chunk(event: &Value, model: &str) -> Option<Value> {
    let event_type = event.get("type").and_then(|t| t.as_str())?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    let delta = if matches!(
        event_type,
        "response.output_text.delta" | "response.text.delta"
    ) {
        serde_json::json!({"content": event.get("delta").and_then(|d| d.as_str()).unwrap_or("")})
    } else if matches!(
        event_type,
        "response.reasoning.delta"
            | "response.reasoning_text.delta"
            | "response.reasoning_summary_text.delta"
    ) {
        serde_json::json!({"reasoning_content": event.get("delta").and_then(|d| d.as_str()).unwrap_or("")})
    } else {
        return None;
    };

    Some(serde_json::json!({
        "id": event.get("response_id").and_then(|v| v.as_str()).unwrap_or("chatgpt-response"),
        "object": "chat.completion.chunk",
        "created": now,
        "model": model,
        "choices": [{"index": 0, "delta": delta, "finish_reason": null}],
    }))
}
