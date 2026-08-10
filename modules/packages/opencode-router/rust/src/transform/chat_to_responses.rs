use serde_json::Value;

pub fn chat_to_responses_content(content: &Value, assistant: bool) -> Vec<Value> {
    let item_type = if assistant { "output_text" } else { "input_text" };
    match content {
        Value::String(s) => {
            vec![serde_json::json!({"type": item_type, "text": s})]
        }
        Value::Array(items) => {
            let mut result = Vec::new();
            for part in items {
                if let Some(text) = part.get("text") {
                    result.push(serde_json::json!({"type": item_type, "text": text.as_str().unwrap_or("")}));
                }
            }
            result
        }
        other => {
            vec![serde_json::json!({"type": item_type, "text": other.to_string()})]
        }
    }
}

pub fn chat_tools_to_responses_tools(tools: &Value) -> Vec<Value> {
    let Some(arr) = tools.as_array() else {
        return Vec::new();
    };
    let mut result = Vec::new();
    for tool in arr {
        if tool.get("type").and_then(|t| t.as_str()) == Some("function")
            && let Some(func) = tool.get("function") {
            let name = func.get("name").and_then(|n| n.as_str());
            if let Some(name) = name {
                result.push(serde_json::json!({
                    "type": "function",
                    "name": name,
                    "description": func.get("description").and_then(|d| d.as_str()).unwrap_or(""),
                    "parameters": func.get("parameters").cloned().unwrap_or(serde_json::json!({"type": "object", "properties": {}})),
                }));
                continue;
            }
        }
        if tool.get("name").is_some() {
            result.push(tool.clone());
        }
    }
    result
}

pub fn chat_tool_choice_to_responses(tool_choice: &Value) -> Value {
    if let (Some(t), Some(func)) = (
        tool_choice.get("type").and_then(|t| t.as_str()),
        tool_choice.get("function"),
    )
        && t == "function"
        && let Some(name) = func.get("name").and_then(|n| n.as_str()) {
        return serde_json::json!({"type": "function", "name": name});
    }
    tool_choice.clone()
}

pub fn chat_to_responses_body(body: &Value, chatgpt_model: &str, service_tier: Option<&str>) -> Value {
    let mut input_items = Vec::new();

    if let Some(messages) = body.get("messages").and_then(|m| m.as_array()) {
        for message in messages {
            let role = message
                .get("role")
                .and_then(|r| r.as_str())
                .unwrap_or("user");
            let role = if role == "system" { "developer" } else { role };

            if role == "tool" {
                input_items.push(serde_json::json!({
                    "type": "function_call_output",
                    "call_id": message.get("tool_call_id").and_then(|v| v.as_str()).unwrap_or("unknown"),
                    "output": message.get("content").and_then(|v| v.as_str()).unwrap_or(""),
                }));
                continue;
            }

            let tool_calls = message.get("tool_calls").and_then(|tc| tc.as_array());

            if role == "assistant" && tool_calls.is_some() {
                let text = message
                    .get("content")
                    .and_then(|c| c.as_str())
                    .unwrap_or("");
                if !text.is_empty() {
                    input_items.push(serde_json::json!({
                        "type": "message",
                        "role": role,
                        "content": chat_to_responses_content(&Value::String(text.to_string()), true),
                    }));
                }
                if let Some(tcs) = tool_calls {
                    for tc in tcs {
                        let func = tc.get("function");
                        input_items.push(serde_json::json!({
                            "type": "function_call",
                            "call_id": tc.get("id").and_then(|v| v.as_str()).unwrap_or("unknown"),
                            "name": func.and_then(|f| f.get("name")).and_then(|n| n.as_str()).unwrap_or("unknown"),
                            "arguments": func.and_then(|f| f.get("arguments")).and_then(|a| a.as_str()).unwrap_or("{}"),
                        }));
                    }
                }
                continue;
            }

            let content = message.get("content").cloned().unwrap_or(Value::String(String::new()));
            input_items.push(serde_json::json!({
                "type": "message",
                "role": role,
                "content": chat_to_responses_content(&content, role == "assistant"),
            }));
        }
    }

    let mut response_body = serde_json::json!({
        "model": chatgpt_model,
        "input": input_items,
        "stream": true,
        "store": false,
        "reasoning": {
            "effort": body.get("reasoning_effort").and_then(|v| v.as_str()).unwrap_or("high"),
            "summary": "auto",
        },
        "text": {"verbosity": "medium"},
        "include": ["reasoning.encrypted_content"],
    });

    if let Some(st) = service_tier {
        response_body["service_tier"] = Value::String(st.to_string());
    }

    let tools = chat_tools_to_responses_tools(body.get("tools").unwrap_or(&Value::Null));
    if !tools.is_empty() {
        response_body["tools"] = Value::Array(tools);
    }

    if let Some(tc) = body.get("tool_choice") {
        response_body["tool_choice"] = chat_tool_choice_to_responses(tc);
    }

    response_body
}
