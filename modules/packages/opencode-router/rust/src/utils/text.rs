use serde_json::Value;

pub fn message_text(message: &Value) -> String {
    let content = message.get("content");
    let Some(content) = content else {
        return String::new();
    };
    match content {
        Value::String(s) => s.clone(),
        Value::Array(items) => {
            let mut parts = Vec::new();
            for item in items {
                if let Some(text) = item.get("text") {
                    parts.push(text.as_str().unwrap_or("").to_string());
                }
            }
            parts.join("\n")
        }
        other => other.to_string(),
    }
}

pub fn strip_model_notices(text: &str) -> String {
    text.lines()
        .filter(|line| !line.trim_start().starts_with('>'))
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_string()
}

pub fn strip_notices_from_history(messages: &[Value]) -> Vec<Value> {
    let mut cleaned = Vec::new();
    for message in messages {
        if message.get("role").and_then(|r| r.as_str()) != Some("assistant") {
            cleaned.push(message.clone());
            continue;
        }
        let content = message.get("content");
        let mut message = message.clone();
        if let Some(Value::String(content)) = content {
            let mut lines = content.lines();
            let mut skipped = 0usize;
            for line in lines.by_ref() {
                if line.starts_with('>') {
                    skipped += 1;
                } else if !line.trim().is_empty() {
                    break;
                } else {
                    skipped += 1;
                }
            }
            if skipped > 0 {
                let rest = content
                    .lines()
                    .skip(skipped)
                    .collect::<Vec<_>>()
                    .join("\n");
                message["content"] = Value::String(rest);
            }
        }
        cleaned.push(message);
    }
    cleaned
}

pub fn routing_context(messages: &[Value], max_messages: usize) -> String {
    let mut relevant = Vec::new();
    let start = messages.len().saturating_sub(max_messages);
    for message in messages.iter().skip(start) {
        let role = message
            .get("role")
            .and_then(|r| r.as_str())
            .unwrap_or("unknown");
        if !matches!(role, "user" | "assistant" | "system" | "developer") {
            continue;
        }
        let text = strip_model_notices(&message_text(message)).trim().to_string();
        if text.is_empty() {
            continue;
        }
        let text = if text.len() > 800 {
            format!("{}...", &text[..800])
        } else {
            text
        };
        relevant.push(format!("{}: {}", role, text));
    }
    relevant.join("\n\n")
}

pub fn truncate(text: &str, max_len: usize) -> String {
    if text.len() <= max_len {
        text.to_string()
    } else {
        format!("{}...", &text[..max_len])
    }
}
