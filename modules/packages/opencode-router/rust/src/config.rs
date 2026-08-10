use std::collections::HashMap;
use std::path::Path;

use serde::Deserialize;

use crate::error::{Result, RouterError};

#[derive(Deserialize, Clone, Debug)]
pub struct ServerConfig {
    #[serde(default = "default_host")]
    pub host: String,
    #[serde(default = "default_port")]
    pub port: u16,
    #[serde(default = "default_log_level")]
    pub log_level: String,
}

fn default_host() -> String {
    "0.0.0.0".to_string()
}

fn default_port() -> u16 {
    4000
}

fn default_log_level() -> String {
    "info".to_string()
}

#[derive(Deserialize, Clone, Debug)]
pub struct ClassifierCloudConfig {
    #[serde(default = "default_cloud_classifier_model")]
    pub model: String,
    #[serde(default = "default_cloud_url")]
    pub url: String,
}

impl Default for ClassifierCloudConfig {
    fn default() -> Self {
        Self {
            model: default_cloud_classifier_model(),
            url: default_cloud_url(),
        }
    }
}

fn default_cloud_classifier_model() -> String {
    String::new()
}

fn default_cloud_url() -> String {
    "http://127.0.0.1:8000/v1".to_string()
}

#[derive(Deserialize, Clone, Debug)]
pub struct ClassifierLocalConfig {
    #[serde(default = "default_local_url")]
    pub url: String,
}

impl Default for ClassifierLocalConfig {
    fn default() -> Self {
        Self {
            url: default_local_url(),
        }
    }
}

fn default_local_url() -> String {
    "http://127.0.0.1:11434".to_string()
}

#[derive(Deserialize, Clone, Debug)]
pub struct ClassifierConfig {
    #[serde(default = "default_backend")]
    pub backend: String,
    #[serde(default = "default_classifier_model")]
    pub model: String,
    #[serde(default = "default_timeout_seconds")]
    pub timeout_seconds: u64,
    #[serde(default = "default_cache_ttl_seconds")]
    pub cache_ttl_seconds: u64,
    #[serde(default)]
    pub cloud: ClassifierCloudConfig,
    #[serde(default)]
    pub local: ClassifierLocalConfig,
}

fn default_backend() -> String {
    "local".to_string()
}

fn default_classifier_model() -> String {
    String::new()
}

fn default_timeout_seconds() -> u64 {
    8
}

fn default_cache_ttl_seconds() -> u64 {
    300
}

#[derive(Deserialize, Clone, Debug)]
pub struct ModelConfig {
    pub description: String,
    pub family: String,
    #[serde(default = "default_provider")]
    pub provider: String,
    #[serde(default = "default_tier")]
    pub tier: u8,
    #[serde(default)]
    pub fallbacks: Vec<String>,

    #[serde(default)]
    pub litellm_model: Option<String>,
    #[serde(default)]
    pub litellm_api_base: Option<String>,
    #[serde(default)]
    pub chatgpt_model: Option<String>,
    #[serde(default)]
    pub service_tier: Option<String>,

    #[serde(default)]
    pub hidden: Option<bool>,
    #[serde(default)]
    pub display_name: Option<String>,
}

fn default_provider() -> String {
    "litellm".to_string()
}

fn default_tier() -> u8 {
    2
}

#[derive(Deserialize, Clone, Debug)]
pub struct DefaultsConfig {
    #[serde(default = "default_default_model")]
    pub model: String,
    #[serde(default = "default_global_fallbacks")]
    pub global_fallbacks: Vec<String>,
    #[serde(default = "default_metadata_fallback_chain")]
    pub metadata_fallback_chain: Vec<String>,
}

fn default_default_model() -> String {
    String::new()
}

fn default_global_fallbacks() -> Vec<String> {
    Vec::new()
}

fn default_metadata_fallback_chain() -> Vec<String> {
    Vec::new()
}

#[derive(Deserialize, Clone, Debug)]
pub struct FamilyConfig {
    pub ladder: Vec<String>,
}

#[derive(Deserialize, Clone, Debug)]
pub struct ModelGuidanceConfig {
    pub prompt_line: String,
}

#[derive(Deserialize, Clone, Debug, Default)]
pub struct GuidanceConfig {
    #[serde(default)]
    pub text: String,
}

#[derive(Deserialize, Clone, Debug, Default)]
pub struct PromptsConfig {
    #[serde(default)]
    pub classification: String,
    #[serde(default)]
    pub guidance: GuidanceConfig,
    #[serde(default)]
    pub model_guidance: HashMap<String, ModelGuidanceConfig>,
}

#[derive(Deserialize, Clone, Debug, Default)]
pub struct MarkersConfig {
    #[serde(default)]
    pub retry: Vec<String>,
    #[serde(default)]
    pub retry_patterns: Vec<String>,
    #[serde(default)]
    pub metadata: Vec<String>,
    #[serde(default)]
    pub coding: Vec<String>,
}

#[derive(Deserialize, Clone, Debug)]
pub struct BansConfig {
    #[serde(default = "default_auth_seconds")]
    pub auth_seconds: u64,
    #[serde(default = "default_exhaustion_seconds")]
    pub exhaustion_seconds: u64,
    #[serde(default = "default_session_quality_seconds")]
    pub session_quality_seconds: u64,
}

impl Default for BansConfig {
    fn default() -> Self {
        Self {
            auth_seconds: default_auth_seconds(),
            exhaustion_seconds: default_exhaustion_seconds(),
            session_quality_seconds: default_session_quality_seconds(),
        }
    }
}

fn default_auth_seconds() -> u64 {
    600
}

fn default_exhaustion_seconds() -> u64 {
    900
}

fn default_session_quality_seconds() -> u64 {
    600
}

#[derive(Deserialize, Clone, Debug)]
pub struct PerformanceConfig {
    #[serde(default = "default_success_weight")]
    pub success_weight: f64,
    #[serde(default = "default_failure_weight")]
    pub failure_weight: f64,
    #[serde(default = "default_reward_threshold")]
    pub reward_threshold: f64,
    #[serde(default = "default_decay_factor")]
    pub decay_factor: f64,
    #[serde(default = "default_decay_interval_seconds")]
    pub decay_interval_seconds: u64,
}

impl Default for PerformanceConfig {
    fn default() -> Self {
        Self {
            success_weight: default_success_weight(),
            failure_weight: default_failure_weight(),
            reward_threshold: default_reward_threshold(),
            decay_factor: default_decay_factor(),
            decay_interval_seconds: default_decay_interval_seconds(),
        }
    }
}

fn default_success_weight() -> f64 {
    1.0
}

fn default_failure_weight() -> f64 {
    -2.0
}

fn default_reward_threshold() -> f64 {
    5.0
}

fn default_decay_factor() -> f64 {
    0.95
}

fn default_decay_interval_seconds() -> u64 {
    300
}

#[derive(Deserialize, Clone, Debug)]
pub struct CircuitBreakerConfig {
    #[serde(default = "default_base_cooldown_seconds")]
    pub base_cooldown_seconds: u64,
    #[serde(default = "default_max_cooldown_seconds")]
    pub max_cooldown_seconds: u64,
}

impl Default for CircuitBreakerConfig {
    fn default() -> Self {
        Self {
            base_cooldown_seconds: default_base_cooldown_seconds(),
            max_cooldown_seconds: default_max_cooldown_seconds(),
        }
    }
}

fn default_base_cooldown_seconds() -> u64 {
    30
}

fn default_max_cooldown_seconds() -> u64 {
    300
}

#[derive(Deserialize, Clone, Debug, Default)]
pub struct AgentInstructionConfig {
    #[serde(default)]
    pub text: String,
}

#[derive(Deserialize, Clone, Debug)]
pub struct NoticeConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_notice_format")]
    pub format: String,
    #[serde(default = "default_redirect_format")]
    pub redirect_format: String,
}

impl Default for NoticeConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            format: default_notice_format(),
            redirect_format: default_redirect_format(),
        }
    }
}

fn default_notice_format() -> String {
    "> **{display_name}**\n> {reason}".to_string()
}

fn default_redirect_format() -> String {
    "> **{original_display} → {display_name}**\n> {reason}".to_string()
}

#[derive(Deserialize, Clone, Debug)]
pub struct CachePatternConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
}

impl Default for CachePatternConfig {
    fn default() -> Self {
        Self {
            enabled: default_true(),
        }
    }
}

#[derive(Deserialize, Clone, Debug)]
pub struct CacheExactConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
}

impl Default for CacheExactConfig {
    fn default() -> Self {
        Self {
            enabled: default_true(),
        }
    }
}

#[derive(Deserialize, Clone, Debug)]
pub struct CacheSimilarityConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_similarity_threshold")]
    pub threshold: f64,
    #[serde(default = "default_max_entries")]
    pub max_entries: usize,
}

impl Default for CacheSimilarityConfig {
    fn default() -> Self {
        Self {
            enabled: default_true(),
            threshold: default_similarity_threshold(),
            max_entries: default_max_entries(),
        }
    }
}

fn default_similarity_threshold() -> f64 {
    0.85
}

fn default_max_entries() -> usize {
    1000
}

#[derive(Deserialize, Clone, Debug)]
pub struct CacheLlmConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
}

impl Default for CacheLlmConfig {
    fn default() -> Self {
        Self {
            enabled: default_true(),
        }
    }
}

fn default_true() -> bool {
    true
}

#[derive(Deserialize, Clone, Debug)]
pub struct CacheConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_cache_ttl")]
    pub ttl_seconds: u64,
    #[serde(default)]
    pub pattern: CachePatternConfig,
    #[serde(default)]
    pub exact: CacheExactConfig,
    #[serde(default)]
    pub similarity: CacheSimilarityConfig,
    #[serde(default)]
    pub llm: CacheLlmConfig,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            enabled: default_true(),
            ttl_seconds: default_cache_ttl(),
            pattern: CachePatternConfig::default(),
            exact: CacheExactConfig::default(),
            similarity: CacheSimilarityConfig::default(),
            llm: CacheLlmConfig::default(),
        }
    }
}

fn default_cache_ttl() -> u64 {
    300
}

#[derive(Deserialize, Clone, Debug)]
pub struct ChatGptConfig {
    #[serde(default = "default_token_url")]
    pub token_url: String,
    #[serde(default = "default_client_id")]
    pub client_id: String,
    #[serde(default = "default_responses_url")]
    pub responses_url: String,
    #[serde(default = "default_account_claim_url")]
    pub account_claim_url: String,
    #[serde(default = "default_auth_file")]
    pub auth_file: String,
}

impl Default for ChatGptConfig {
    fn default() -> Self {
        Self {
            token_url: default_token_url(),
            client_id: default_client_id(),
            responses_url: default_responses_url(),
            account_claim_url: default_account_claim_url(),
            auth_file: default_auth_file(),
        }
    }
}

fn default_token_url() -> String {
    "https://auth.openai.com/oauth/token".to_string()
}

fn default_client_id() -> String {
    "app_EMoamEEZ73f0CkXaXp7hrann".to_string()
}

fn default_responses_url() -> String {
    "https://chatgpt.com/backend-api/codex/responses".to_string()
}

fn default_account_claim_url() -> String {
    "https://api.openai.com/auth".to_string()
}

fn default_auth_file() -> String {
    "/var/lib/opencode/auth.json".to_string()
}

#[derive(Deserialize, Clone, Debug)]
pub struct Config {
    #[serde(default = "default_server")]
    pub server: ServerConfig,
    #[serde(default = "default_classifier")]
    pub classifier: ClassifierConfig,
    #[serde(default)]
    pub models: HashMap<String, ModelConfig>,
    #[serde(default = "default_defaults")]
    pub defaults: DefaultsConfig,
    #[serde(default)]
    pub aliases: HashMap<String, String>,
    #[serde(default)]
    pub families: HashMap<String, FamilyConfig>,
    #[serde(default)]
    pub prompts: PromptsConfig,
    #[serde(default)]
    pub markers: MarkersConfig,
    #[serde(default)]
    pub bans: BansConfig,
    #[serde(default)]
    pub performance: PerformanceConfig,
    #[serde(default)]
    pub circuit_breaker: CircuitBreakerConfig,
    #[serde(default)]
    pub agent_instruction: AgentInstructionConfig,
    #[serde(default)]
    pub notice: NoticeConfig,
    #[serde(default)]
    pub display_names: HashMap<String, String>,
    #[serde(default)]
    pub chatgpt: ChatGptConfig,
    #[serde(default)]
    pub cache: CacheConfig,
    #[serde(default = "default_cross_family_escalation")]
    pub cross_family_escalation: HashMap<String, String>,
}

fn default_server() -> ServerConfig {
    ServerConfig {
        host: default_host(),
        port: default_port(),
        log_level: default_log_level(),
    }
}

fn default_classifier() -> ClassifierConfig {
    ClassifierConfig {
        backend: default_backend(),
        model: default_classifier_model(),
        timeout_seconds: default_timeout_seconds(),
        cache_ttl_seconds: default_cache_ttl_seconds(),
        cloud: ClassifierCloudConfig::default(),
        local: ClassifierLocalConfig::default(),
    }
}

fn default_defaults() -> DefaultsConfig {
    DefaultsConfig {
        model: default_default_model(),
        global_fallbacks: default_global_fallbacks(),
        metadata_fallback_chain: default_metadata_fallback_chain(),
    }
}

fn default_cross_family_escalation() -> HashMap<String, String> {
    HashMap::new()
}

pub fn load_config(path: &Path) -> Result<Config> {
    let content = std::fs::read_to_string(path)?;
    let config: Config = toml::from_str(&content)?;
    validate_config(&config)?;
    Ok(config)
}

pub fn load_default_config() -> Result<Config> {
    let default_toml = include_str!("../config/default.toml");
    let config: Config = toml::from_str(default_toml)?;
    Ok(config)
}

fn validate_config(config: &Config) -> Result<()> {
    for (name, model) in &config.models {
        if model.tier == 0 || model.tier > 10 {
            return Err(RouterError::Config(format!(
                "model {} has invalid tier {}, must be 1-10",
                name, model.tier
            )));
        }
        match model.provider.as_str() {
            "litellm" | "chatgpt" | "ollama" => {}
            other => {
                return Err(RouterError::Config(format!(
                    "model {} has unknown provider {}",
                    name, other
                )));
            }
        }
        for fallback in &model.fallbacks {
            if !config.models.contains_key(fallback) {
                return Err(RouterError::Config(format!(
                    "model {} references unknown fallback {}",
                    name, fallback
                )));
            }
        }
    }

    for (alias, target) in &config.aliases {
        if !config.models.contains_key(target) {
            return Err(RouterError::Config(format!(
                "alias {} points to unknown model {}",
                alias, target
            )));
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_load_default_config() {
        let config = load_default_config().expect("should load default config");
        assert!(!config.models.is_empty());
    }

    #[test]
    fn test_invalid_tier_rejected() {
        let mut config = load_default_config().unwrap();
        config
            .models
            .insert(
                "bad".to_string(),
                ModelConfig {
                    description: "test".to_string(),
                    family: "test".to_string(),
                    provider: "litellm".to_string(),
                    tier: 0,
                    fallbacks: vec![],
                    litellm_model: None,
                    litellm_api_base: None,
                    chatgpt_model: None,
                    service_tier: None,
                    hidden: None,
                    display_name: None,
                },
            );
        assert!(validate_config(&config).is_err());
    }

    #[test]
    fn test_unknown_provider_rejected() {
        let mut config = load_default_config().unwrap();
        config
            .models
            .insert(
                "bad".to_string(),
                ModelConfig {
                    description: "test".to_string(),
                    family: "test".to_string(),
                    provider: "unknown".to_string(),
                    tier: 2,
                    fallbacks: vec![],
                    litellm_model: None,
                    litellm_api_base: None,
                    chatgpt_model: None,
                    service_tier: None,
                    hidden: None,
                    display_name: None,
                },
            );
        assert!(validate_config(&config).is_err());
    }
}
