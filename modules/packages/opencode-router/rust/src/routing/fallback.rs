use crate::models::ModelRegistry;
use crate::state::SharedState;

pub fn fallback_chain(
    model: &str,
    registry: &ModelRegistry,
    state: &SharedState,
) -> Vec<String> {
    let mut result: Vec<String> = Vec::new();
    let mut queue: Vec<String> = vec![model.to_string()];

    while let Some(candidate) = queue.pop() {
        if !registry.is_direct_model(&candidate) || result.contains(&candidate) {
            continue;
        }
        result.push(candidate.clone());
        if let Some(m) = registry.models.get(&candidate) {
            for fb in &m.fallbacks {
                if !result.contains(fb) {
                    queue.push(fb.clone());
                }
            }
        }
    }

    for fb in &registry.global_fallbacks {
        if !result.contains(fb) {
            result.push(fb.clone());
        }
    }

    if !state.use_local_classifier {
        result.retain(|c| {
            registry
                .models
                .get(c)
                .is_some_and(|m| m.provider != "ollama")
        });
    }

    if result.is_empty() {
        vec![model.to_string()]
    } else {
        result
    }
}

pub fn metadata_fallback_chain(registry: &ModelRegistry, state: &SharedState) -> Vec<String> {
    let mut result = registry.metadata_fallback_chain.clone();
    if state.use_local_classifier {
        let local_model = &state.config.classifier.model;
        if !result.contains(local_model) {
            result.push(local_model.clone());
        }
    }
    result
}
