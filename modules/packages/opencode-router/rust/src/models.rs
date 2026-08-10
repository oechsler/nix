use std::collections::HashMap;

use crate::config::Config;

pub struct ModelEntry {
    pub id: String,
    pub object: &'static str,
    pub created: u64,
    pub owned_by: String,
}

pub struct ModelRegistry {
    pub models: HashMap<String, crate::config::ModelConfig>,
    pub aliases: HashMap<String, String>,
    pub display_names: HashMap<String, String>,
    pub default_model: String,
    pub global_fallbacks: Vec<String>,
    pub metadata_fallback_chain: Vec<String>,
    pub families: HashMap<String, Vec<String>>,
    pub classifier_models: Vec<String>,
}

impl ModelRegistry {
    pub fn from_config(config: &Config) -> Self {
        let classifier_models = config
            .classifier
            .model
            .split(',')
            .map(|s| s.trim().to_string())
            .collect();

        Self {
            models: config.models.clone(),
            aliases: config.aliases.clone(),
            display_names: config.display_names.clone(),
            default_model: config.defaults.model.clone(),
            global_fallbacks: config.defaults.global_fallbacks.clone(),
            metadata_fallback_chain: config.defaults.metadata_fallback_chain.clone(),
            families: config
                .families
                .iter()
                .map(|(k, v)| (k.clone(), v.ladder.clone()))
                .collect(),
            classifier_models,
        }
    }

    pub fn resolve_model(&self, name: &str) -> Option<String> {
        if let Some(target) = self.aliases.get(name)
            && self.models.contains_key(target) {
            return Some(target.clone());
        }
        if self.models.contains_key(name) {
            return Some(name.to_string());
        }
        None
    }

    pub fn resolve_alias(&self, name: &str) -> String {
        self.aliases
            .get(name)
            .cloned()
            .unwrap_or_else(|| name.to_string())
    }

    pub fn is_direct_model(&self, name: &str) -> bool {
        self.models.contains_key(name)
    }

    pub fn is_chatgpt_model(&self, name: &str) -> bool {
        self.models
            .get(name)
            .is_some_and(|m| m.chatgpt_model.is_some())
    }

    pub fn is_ollama_model(&self, name: &str) -> bool {
        self.models
            .get(name)
            .is_some_and(|m| m.provider == "ollama")
    }

    pub fn is_classifier_model(&self, name: &str) -> bool {
        self.classifier_models.iter().any(|m| m == name)
    }

    pub fn is_hidden(&self, name: &str) -> bool {
        self.models.get(name).is_some_and(|m| m.hidden.unwrap_or(false))
    }

    pub fn display_name(&self, name: &str) -> String {
        self.display_names
            .get(name)
            .cloned()
            .unwrap_or_else(|| name.to_string())
    }

    pub fn provider(&self, name: &str) -> String {
        self.models
            .get(name)
            .map(|m| m.provider.clone())
            .unwrap_or_else(|| "unknown".to_string())
    }

    pub fn provider_models(&self, provider: &str) -> Vec<String> {
        self.models
            .iter()
            .filter(|(_, m)| m.provider == provider)
            .map(|(n, _)| n.clone())
            .collect()
    }

    pub fn family_ladder(&self, family: &str) -> Option<&Vec<String>> {
        self.families.get(family)
    }

    pub fn family_for(&self, model: &str) -> Option<&str> {
        self.models.get(model).map(|m| m.family.as_str())
    }

    pub fn tier_for(&self, model: &str) -> u8 {
        self.models.get(model).map(|m| m.tier).unwrap_or(0)
    }

    pub fn visible_models(&self, use_local_classifier: bool) -> Vec<String> {
        self.models
            .keys()
            .filter(|name| {
                let m = &self.models[*name];
                if m.hidden.unwrap_or(false) {
                    return false;
                }
                if self.is_classifier_model(name) {
                    return false;
                }
                if !use_local_classifier && m.provider == "ollama" {
                    return false;
                }
                true
            })
            .cloned()
            .collect()
    }

    pub fn list_visible_models(&self, use_local_classifier: bool) -> Vec<ModelEntry> {
        self.visible_models(use_local_classifier)
            .into_iter()
            .map(|name| {
                let owned_by = self.provider(&name);
                ModelEntry {
                    id: name,
                    object: "model",
                    created: 0,
                    owned_by,
                }
            })
            .collect()
    }
}
