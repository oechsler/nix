use regex::Regex;
use serde_json::Value;

use crate::config::Config;
use crate::models::ModelRegistry;
use crate::state::SharedState;
use crate::utils::text::{message_text, routing_context};

pub async fn capability_escalation(
    messages: &[Value],
    registry: &ModelRegistry,
    state: &SharedState,
) -> Option<String> {
    let latest_user = messages
        .iter()
        .rev()
        .find(|m| m.get("role").and_then(|r| r.as_str()) == Some("user"))
        .map(|m| message_text(m).to_lowercase())
        .unwrap_or_default();

    let is_retry = is_retry_request(&latest_user, &state.config.markers);
    if !is_retry {
        return None;
    }

    let formatter = crate::utils::notice::NoticeFormatter::new(&state.config, registry);
    let previous_model = formatter.last_routed_model(messages, registry)?;

    if let Some(family_next) = get_family_escalation(&previous_model, registry)
        && !state.is_banned(&family_next).await {
        state
            .ban_model(
                &previous_model,
                state.config.bans.session_quality_seconds,
                "user rejected result (session quality ban)",
            )
            .await;
        tracing::info!(
            model = previous_model,
            escalated = family_next,
            "family escalation"
        );
        return Some(family_next);
    }

    if let Some(cross_family) = get_cross_family_escalation(&previous_model, &state.config) {
        state
            .ban_model(
                &previous_model,
                state.config.bans.session_quality_seconds,
                "user rejected result (session quality ban)",
            )
            .await;
        tracing::info!(
            model = previous_model,
            escalated = cross_family,
            "cross-family escalation"
        );
        return Some(cross_family);
    }

    None
}

fn get_family_escalation(model: &str, registry: &ModelRegistry) -> Option<String> {
    let family = registry.family_for(model)?;
    let ladder = registry.family_ladder(family)?;
    let current_index = ladder.iter().position(|m| m == model)?;
    if current_index < ladder.len() - 1 {
        Some(ladder[current_index + 1].clone())
    } else {
        None
    }
}

fn get_cross_family_escalation(model: &str, config: &Config) -> Option<String> {
    config.cross_family_escalation.get(model).cloned()
}

pub fn capability_level(config: &Config, model: &str) -> u8 {
    config.models.get(model).map(|m| m.tier).unwrap_or(0)
}

pub fn more_capable_model(config: &Config, classified: &str, escalation: &str) -> String {
    if capability_level(config, classified) >= capability_level(config, escalation) {
        classified.to_string()
    } else {
        escalation.to_string()
    }
}

fn is_retry_request(text: &str, markers: &crate::config::MarkersConfig) -> bool {
    if markers.retry.iter().any(|m| text.contains(m)) {
        return true;
    }
    for pattern_str in &markers.retry_patterns {
        if let Ok(pattern) = Regex::new(pattern_str)
            && pattern.is_match(text) {
            return true;
        }
    }
    false
}

pub fn is_metadata_request(
    messages: &[Value],
    has_tools: bool,
    markers: &crate::config::MarkersConfig,
) -> bool {
    if has_tools {
        return false;
    }
    let text = routing_context(messages, 4).to_lowercase();
    markers.metadata.iter().any(|m| text.contains(m))
}

pub fn is_coding_request(
    messages: &[Value],
    has_tools: bool,
    markers: &crate::config::MarkersConfig,
) -> bool {
    if has_tools {
        return true;
    }
    let text = routing_context(messages, 4).to_lowercase();
    markers.coding.iter().any(|m| text.contains(m))
}
