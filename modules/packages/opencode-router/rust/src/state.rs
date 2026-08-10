use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;

use tokio::sync::RwLock;

use crate::backend::chatgpt::ChatGptBackend;
use crate::backend::litellm::LiteLlmBackend;
use crate::backend::ollama::OllamaBackend;
use crate::config::Config;

pub struct BanEntry {
    pub until: Instant,
    pub reason: String,
}

pub struct AppState {
    pub model_cooldown_until: HashMap<String, Instant>,
    pub model_bans: HashMap<String, BanEntry>,
    pub consecutive_routes: HashMap<String, usize>,
    pub consecutive_failures: HashMap<String, usize>,
    pub last_route_model: Option<String>,
    pub started_at: Instant,
}

pub struct SharedState {
    pub config: Config,
    pub use_local_classifier: bool,
    pub litellm_backend: LiteLlmBackend,
    pub chatgpt_backend: ChatGptBackend,
    pub ollama_backend: OllamaBackend,
    pub state: Arc<RwLock<AppState>>,
}

impl SharedState {
    pub fn new(
        config: Config,
        litellm_backend: LiteLlmBackend,
        chatgpt_backend: ChatGptBackend,
        ollama_backend: OllamaBackend,
    ) -> Self {
        let use_local_classifier = config.classifier.backend == "local";
        Self {
            config,
            use_local_classifier,
            litellm_backend,
            chatgpt_backend,
            ollama_backend,
            state: Arc::new(RwLock::new(AppState {
                model_cooldown_until: HashMap::new(),
                model_bans: HashMap::new(),
                consecutive_routes: HashMap::new(),
                consecutive_failures: HashMap::new(),
                last_route_model: None,
                started_at: Instant::now(),
            })),
        }
    }

    pub fn uptime(&self) -> std::time::Duration {
        self.state.try_read().map(|s| s.started_at.elapsed()).unwrap_or_default()
    }

    pub async fn ban_model(&self, model: &str, seconds: u64, reason: &str) {
        tracing::warn!(model = model, seconds = seconds, reason = reason, "model ban");
        let mut state = self.state.write().await;
        state.model_bans.insert(
            model.to_string(),
            BanEntry {
                until: Instant::now() + std::time::Duration::from_secs(seconds),
                reason: reason.to_string(),
            },
        );
    }

    pub async fn is_banned(&self, model: &str) -> bool {
        let now = Instant::now();
        let mut state = self.state.write().await;
        if let Some(entry) = state.model_bans.get(model) {
            if entry.until > now {
                return true;
            }
            state.model_bans.remove(model);
        }
        false
    }

    pub async fn banned_models(&self) -> HashMap<String, u64> {
        let now = Instant::now();
        let mut state = self.state.write().await;
        let mut result = HashMap::new();
        let expired: Vec<String> = state
            .model_bans
            .iter()
            .filter(|(_, e)| e.until <= now)
            .map(|(k, _)| k.clone())
            .collect();
        for key in expired {
            state.model_bans.remove(&key);
        }
        for (model, entry) in &state.model_bans {
            let remaining = entry.until.duration_since(now).as_secs();
            result.insert(model.clone(), remaining);
        }
        result
    }

    pub async fn banned_reasons(&self) -> HashMap<String, String> {
        let state = self.state.read().await;
        state
            .model_bans
            .iter()
            .map(|(k, v)| (k.clone(), v.reason.clone()))
            .collect()
    }

    pub fn cooldown_duration(&self, failures: usize) -> u64 {
        let base = self.config.circuit_breaker.base_cooldown_seconds;
        let max = self.config.circuit_breaker.max_cooldown_seconds;
        if failures == 0 {
            return base;
        }
        let duration = base.saturating_mul(2_u64.saturating_pow(failures as u32 - 1));
        duration.min(max)
    }

    pub async fn is_in_cooldown(&self, model: &str) -> bool {
        let now = Instant::now();
        let mut state = self.state.write().await;
        if let Some(&until) = state.model_cooldown_until.get(model) {
            if until <= now {
                state.model_cooldown_until.remove(model);
                return false;
            }
            return true;
        }
        false
    }

    pub async fn record_provider_failure(&self, model: &str, reason: &str, provider_wide: bool) {
        let key = if provider_wide {
            format!("provider:{}", self.provider_key(model))
        } else {
            model.to_string()
        };
        let mut state = self.state.write().await;
        let failures = state.consecutive_failures.entry(key.clone()).or_insert(0);
        *failures += 1;
        let failure_count = *failures;
        let duration = self.cooldown_duration(failure_count);

        let targets: Vec<String> = if provider_wide {
            self.provider_model_keys(model)
        } else {
            vec![model.to_string()]
        };

        let until = Instant::now() + std::time::Duration::from_secs(duration);
        for target in &targets {
            state.model_cooldown_until.insert(target.clone(), until);
        }

        tracing::warn!(
            model = model,
            seconds = duration,
            failures = failure_count,
            reason = reason,
            provider_wide = provider_wide,
            "model cooldown"
        );
    }

    pub async fn record_provider_http_failure(&self, model: &str, status_code: u16) {
        let base = self.config.circuit_breaker.base_cooldown_seconds;
        if status_code == 401 || status_code == 403 {
            let reason = format!("HTTP {} (auth)", status_code);
            self.ban_model(model, self.config.bans.auth_seconds, &reason).await;
            let mut state = self.state.write().await;
            for target in self.provider_model_keys(model) {
                state
                    .model_cooldown_until
                    .insert(target, Instant::now() + std::time::Duration::from_secs(base));
            }
            return;
        }
        if status_code == 429 {
            let reason = format!("HTTP {} (quota exhausted)", status_code);
            self.ban_model(model, self.config.bans.exhaustion_seconds, &reason).await;
            let mut state = self.state.write().await;
            for target in self.provider_model_keys(model) {
                state
                    .model_cooldown_until
                    .insert(target, Instant::now() + std::time::Duration::from_secs(base));
            }
            return;
        }
        if status_code >= 500 || [408, 425].contains(&status_code) {
            self.record_provider_failure(model, &format!("HTTP {}", status_code), true).await;
        }
    }

    pub async fn record_success(&self, model: &str) {
        let mut state = self.state.write().await;
        state.model_cooldown_until.remove(model);
        state.model_bans.remove(model);
        state.consecutive_failures.remove(model);
        let provider_key = format!("provider:{}", self.provider_key(model));
        state.consecutive_failures.remove(&provider_key);
    }

    pub async fn record_failure(&self, model: &str) {
        self.record_provider_failure(model, "backend failure", false).await;
    }

    pub async fn record_route(&self, model: &str, max_consecutive: usize, rotation_ban_seconds: u64) {
        let mut state = self.state.write().await;
        if state.last_route_model.as_deref() != Some(model) {
            for count in state.consecutive_routes.values_mut() {
                *count = 0;
            }
            state.last_route_model = Some(model.to_string());
        }
        let count = state.consecutive_routes.entry(model.to_string()).or_insert(0);
        *count += 1;
        let current_count = *count;
        if current_count >= max_consecutive {
            let has_alternative = self.has_banned_alternative_locked(&state, model).await;
            if has_alternative {
                let reason = format!("served {} consecutive requests (load balancing)", current_count);
                drop(state);
                self.ban_model(model, rotation_ban_seconds, &reason).await;
            } else {
                tracing::info!(model = model, "rotation threshold reached but no alternative");
            }
            let mut state = self.state.write().await;
            if let Some(count) = state.consecutive_routes.get_mut(model) {
                *count = 0;
            }
        }
    }

    async fn has_banned_alternative_locked(&self, state: &AppState, model: &str) -> bool {
        let family = self
            .config
            .models
            .get(model)
            .map(|m| m.family.clone());
        let Some(family) = family else {
            return false;
        };
        let now = Instant::now();
        if let Some(ladder) = self.config.families.get(&family) {
            for candidate in &ladder.ladder {
                if candidate != model {
                    let is_banned = state.model_bans.get(candidate).is_some_and(|e| e.until > now);
                    if !is_banned {
                        return true;
                    }
                }
            }
        }
        false
    }

    pub async fn degraded_providers(&self) -> HashMap<String, u64> {
        let now = Instant::now();
        let mut state = self.state.write().await;
        let mut result = HashMap::new();
        let expired: Vec<String> = state
            .model_cooldown_until
            .iter()
            .filter(|(_, until)| **until <= now)
            .map(|(k, _)| k.clone())
            .collect();
        for key in expired {
            state.model_cooldown_until.remove(&key);
        }
        for (model, until) in &state.model_cooldown_until {
            let remaining = until.duration_since(now).as_secs();
            result.insert(model.clone(), remaining);
        }
        result
    }

    fn provider_key(&self, model: &str) -> String {
        self.config
            .models
            .get(model)
            .map(|m| {
                if let Some(ref api_base) = m.litellm_api_base {
                    api_base.clone()
                } else if m.provider == "chatgpt" {
                    "chatgpt".to_string()
                } else if m.provider == "ollama" {
                    "ollama".to_string()
                } else {
                    m.provider.clone()
                }
            })
            .unwrap_or_else(|| "unknown".to_string())
    }

    fn provider_model_keys(&self, model: &str) -> Vec<String> {
        let key = self.provider_key(model);
        self.config
            .models
            .iter()
            .filter(|(_, m)| {
                if let Some(ref api_base) = m.litellm_api_base {
                    *api_base == key
                } else if m.provider == "chatgpt" {
                    key == "chatgpt"
                } else if m.provider == "ollama" {
                    key == "ollama"
                } else {
                    m.provider == key
                }
            })
            .map(|(n, _)| n.clone())
            .collect()
    }
}
