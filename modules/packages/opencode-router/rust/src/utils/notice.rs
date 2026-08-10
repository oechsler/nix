use crate::config::Config;
use crate::models::ModelRegistry;
use crate::utils::text::{message_text, routing_context, strip_notices_from_history};

pub struct NoticeFormatter {
    pub format: String,
    pub redirect_format: String,
}

impl NoticeFormatter {
    pub fn new(config: &Config, _registry: &ModelRegistry) -> Self {
        Self {
            format: config.notice.format.clone(),
            redirect_format: config.notice.redirect_format.clone(),
        }
    }

    pub fn compact_reason(&self, reason: &str) -> String {
        let trimmed = reason
            .trim()
            .trim_matches('`')
            .trim_matches('"')
            .trim_matches('\'')
            .trim_matches('*')
            .trim();
        let words: Vec<&str> = trimmed.split_whitespace().collect();
        let words = words[..words.len().min(6)].to_vec();
        let joined = words.join(" ");
        joined
            .trim_end_matches(['.', ',', ';', ':', '!', '?'])
            .to_string()
    }

    pub fn model_notice_text(
        &self,
        model: &str,
        registry: &ModelRegistry,
        original_model: Option<&str>,
        reason: &str,
    ) -> String {
        let display_name = registry.display_name(model);
        let mut compact_reason = self.compact_reason(reason);
        if compact_reason.is_empty() {
            compact_reason = "Auto-routed".to_string();
        }
        if let Some(original) = original_model
            && original != model {
            let original_display = registry.display_name(original);
            return self
                .redirect_format
                .replace("{original_display}", &original_display)
                .replace("{display_name}", &display_name)
                .replace("{reason}", &compact_reason);
        }
        self.format
            .replace("{display_name}", &display_name)
            .replace("{reason}", &compact_reason)
    }

    pub fn notice_chunk(&self, model: &str, content: &str) -> serde_json::Value {
        serde_json::json!({
            "id": "opencode-auto-router-notice",
            "object": "chat.completion.chunk",
            "created": chrono_now(),
            "model": model,
            "choices": [{"index": 0, "delta": {"content": content}, "finish_reason": null}],
        })
    }

    pub fn last_routed_model(
        &self,
        messages: &[serde_json::Value],
        registry: &ModelRegistry,
    ) -> Option<String> {
        let all_models: Vec<String> = registry
            .models
            .keys()
            .cloned()
            .chain(registry.aliases.keys().cloned())
            .collect();
        let model_pattern = all_models.join("|");
        let model_pattern = regex::escape(&model_pattern);
        let notice_pattern = regex::Regex::new(&format!(
            r"(?i)^>\s+\*\*(auto|{})(?:\s+(?:->|→)\s+({}))?\*\*(?:\s+-\s+.+)?$",
            model_pattern, model_pattern
        ))
        .ok()?;

        for message in messages.iter().rev() {
            if message.get("role").and_then(|r| r.as_str()) != Some("assistant") {
                continue;
            }
            let text = message_text(message);
            for line in text.lines().map(|l| l.trim()).filter(|l| !l.is_empty()) {
                if let Some(caps) = notice_pattern.captures(line) {
                    let model = caps.get(2).or_else(|| caps.get(1)).map(|m| m.as_str())?;
                    return Some(registry.resolve_alias(model));
                }
            }
        }
        None
    }

    pub fn is_terminal_chunk(&self, line: &str) -> bool {
        if !line.starts_with("data: ") || line.starts_with("data: [DONE]") {
            return false;
        }
        let parsed: Result<serde_json::Value, _> = serde_json::from_str(&line[6..]);
        let Ok(chunk) = parsed else {
            return false;
        };
        chunk["choices"]
            .as_array()
            .unwrap_or(&vec![])
            .iter()
            .any(|choice| choice.get("finish_reason").is_some())
    }
}

fn chrono_now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub fn build_models_section(registry: &ModelRegistry) -> String {
    let mut sections = Vec::new();
    for (name, model) in &registry.models {
        if registry.is_classifier_model(name) {
            continue;
        }
        let mut line = format!(
            "- {} [tier {}, family {}, provider {}]: {}",
            name, model.tier, model.family, model.provider, model.description
        );
        if model.provider == "chatgpt" && name.contains("fast") {
            line.push_str(" (fast variant)");
        }
        sections.push(line);
    }
    sections.join("\n")
}

pub fn strip_notices(messages: &[serde_json::Value]) -> Vec<serde_json::Value> {
    strip_notices_from_history(messages)
}

pub fn build_context(messages: &[serde_json::Value], max_messages: usize) -> String {
    routing_context(messages, max_messages)
}

pub fn clean_text(text: &str) -> String {
    crate::utils::text::strip_model_notices(text)
}
