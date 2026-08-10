use serde_json::Value;

pub struct TaskInfo {
    pub open_count: usize,
    pub completed_count: usize,
    pub has_open_tasks: bool,
}

pub fn analyze_tasks(messages: &[Value]) -> TaskInfo {
    let mut open_count = 0;
    let mut completed_count = 0;

    for message in messages {
        let role = message.get("role").and_then(|r| r.as_str()).unwrap_or("");
        if role != "assistant" && role != "user" {
            continue;
        }

        let content = message.get("content");
        let text = match content {
            Some(Value::String(s)) => s.clone(),
            Some(Value::Array(items)) => {
                let mut parts = Vec::new();
                for item in items {
                    if let Some(text) = item.get("text")
                        && let Some(t) = text.as_str() {
                        parts.push(t);
                    }
                }
                parts.join("\n")
            }
            _ => continue,
        };

        let info = analyze_text(&text);
        open_count += info.open_count;
        completed_count += info.completed_count;
    }

    TaskInfo {
        open_count,
        completed_count,
        has_open_tasks: open_count > 0,
    }
}

fn analyze_text(text: &str) -> TaskInfo {
    let mut open_count = 0;
    let mut completed_count = 0;

    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("- [ ]") || trimmed.starts_with("* [ ]") {
            open_count += 1;
        } else if trimmed.starts_with("- [x]") || trimmed.starts_with("* [x]") {
            completed_count += 1;
        }
    }

    TaskInfo {
        open_count,
        completed_count,
        has_open_tasks: open_count > 0,
    }
}
