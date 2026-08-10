use std::collections::HashMap;
use std::time::{Duration, Instant};

use reqwest::Client;
use serde_json::Value;

use crate::config::Config;
use crate::models::ModelRegistry;
use crate::state::SharedState;
use crate::utils::notice::build_models_section;
use crate::utils::tasks::analyze_tasks;
use crate::utils::text::routing_context;

const CLASSIFICATION_REASON_INSTRUCTION: &str = "IMPORTANT: The \"reason\" must describe THIS specific task in 2-6 words (user's language). Do NOT copy or paraphrase the model's description. Examples of good reasons: \"NixOS config lookup\", \"Simple greeting\", \"Complex multi-file refactor\", \"Math proof verification\".";

struct CacheEntry {
    expires: Instant,
    model: String,
    reason: String,
}

pub struct Classifier {
    client: Client,
    cache: HashMap<(u64, bool), CacheEntry>,
}

impl Default for Classifier {
    fn default() -> Self {
        Self::new()
    }
}

impl Classifier {
    pub fn new() -> Self {
        Self {
            client: Client::builder()
                .timeout(Duration::from_secs(8))
                .build()
                .expect("http client"),
            cache: HashMap::new(),
        }
    }

    pub fn cached_classify(&mut self, context: &str, has_tools: bool) -> Option<(String, String)> {
        let key = (hash_string(context), has_tools);
        let entry = self.cache.get(&key)?;
        if Instant::now() < entry.expires {
            return Some((entry.model.clone(), entry.reason.clone()));
        }
        self.cache.remove(&key);
        None
    }

    pub fn cache_classify(&mut self, context: &str, has_tools: bool, model: &str, reason: &str, ttl: Duration) {
        let key = (hash_string(context), has_tools);
        self.cache.insert(
            key,
            CacheEntry {
                expires: Instant::now() + ttl,
                model: model.to_string(),
                reason: reason.to_string(),
            },
        );
    }

    pub async fn classify(
        &mut self,
        config: &Config,
        registry: &ModelRegistry,
        state: &SharedState,
        messages: &[Value],
        has_tools: bool,
    ) -> (String, String) {
        let context = routing_context(messages, 4);
        if context.trim().is_empty() {
            return (registry.default_model.clone(), String::new());
        }

        let ttl = Duration::from_secs(config.classifier.cache_ttl_seconds);
        if let Some(cached) = self.cached_classify(&context, has_tools) {
            tracing::info!(
                model = cached.0,
                reason = cached.1,
                "classification cache hit"
            );
            return cached;
        }

        let prompt = self.build_classification_prompt(config, registry, state, &context, has_tools, messages).await;
        let timeout = Duration::from_secs(config.classifier.timeout_seconds);

        if !state.use_local_classifier {
            if let Some(result) = self
                .classify_cloud(config, registry, &prompt, timeout)
                .await
            {
                self.cache_classify(&context, has_tools, &result.0, &result.1, ttl);
                return result;
            }
            return (registry.default_model.clone(), String::new());
        }

        for model in &registry.classifier_models.clone() {
            if state.is_banned(model).await {
                tracing::info!(model = model, "skipping banned classifier model");
                continue;
            }
            if let Some(result) = self
                .classify_local(config, registry, model, &prompt, timeout)
                .await
            {
                self.cache_classify(&context, has_tools, &result.0, &result.1, ttl);
                return result;
            }
        }

        (registry.default_model.clone(), String::new())
    }

    async fn build_classification_prompt(
        &self,
        config: &Config,
        registry: &ModelRegistry,
        state: &SharedState,
        context: &str,
        has_tools: bool,
        messages: &[Value],
    ) -> String {
        let models_section = build_models_section(registry);

        let mut guidance_section = config.prompts.guidance.text.clone();
        for (model, guidance) in &config.prompts.model_guidance {
            if registry.models.contains_key(model) {
                guidance_section = guidance_section.replace(
                    &format!("- {}:", model),
                    &guidance.prompt_line,
                );
            }
        }

        let banned = state.banned_models().await;
        let banned_section = if banned.is_empty() {
            String::new()
        } else {
            let names: Vec<&String> = banned.keys().collect();
            let names: Vec<String> = names.iter().map(|s| (*s).clone()).collect();
            format!(
                "\nBanned/cooldown models (do NOT pick these; choose the best remaining option):\n- {}\n",
                names.join(", ")
            )
        };

        let task_info = analyze_tasks(messages);
        let task_section = if task_info.has_open_tasks {
            format!(
                "\n\nIMPORTANT: The conversation has {} open task(s) and {} completed task(s). Prefer stronger models to ensure task completion.",
                task_info.open_count, task_info.completed_count
            )
        } else {
            String::new()
        };

        let user_prompt = if config.prompts.classification.trim().is_empty() {
            format!(
                "Classify for OpenCode routing. Analyze the request below and pick the model that fits best.\n\n{}\n\nReturn exactly one line: model_id - reason\n\n{}\n\n{}\n{}\n\nContext (has_tools={}):\n{}",
                CLASSIFICATION_REASON_INSTRUCTION,
                models_section,
                guidance_section,
                banned_section,
                has_tools,
                context
            )
        } else {
            format!(
                "{}\n\n{}",
                CLASSIFICATION_REASON_INSTRUCTION,
                config
                    .prompts
                    .classification
                    .replace("{models_section}", &models_section)
                    .replace("{guidance_section}", &guidance_section)
                    .replace("{banned_section}", &banned_section)
                    .replace("{has_tools}", &has_tools.to_string())
                    .replace("{context}", context)
            )
        };

        format!(
            "{}{}\n\nDecision method: evaluate the complete task, estimate its complexity and required capability, then choose the best model by weighing the model matrix above. Use tiers as relative capability levels, not as rigid rules. Consider tools, ambiguity, reasoning depth, expected work size, latency, quota, and the cost of failure.",
            user_prompt,
            task_section
        )
    }

    async fn classify_cloud(
        &mut self,
        config: &Config,
        _registry: &ModelRegistry,
        prompt: &str,
        timeout: Duration,
    ) -> Option<(String, String)> {
        let url = format!("{}/chat/completions", config.classifier.cloud.url);
        let body = serde_json::json!({
            "model": config.classifier.cloud.model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0,
            "max_tokens": 128,
            "stream": false,
        });
        let response = self
            .client
            .post(&url)
            .header("Authorization", "Bearer dummy")
            .timeout(timeout)
            .json(&body)
            .send()
            .await
            .ok()?;
        if !response.status().is_success() {
            return None;
        }
        let json: Value = response.json().await.ok()?;
        let content = json["choices"][0]["message"]["content"].as_str()?;
        parse_model_choice(content, _registry)
    }

    async fn classify_local(
        &mut self,
        config: &Config,
        registry: &ModelRegistry,
        model: &str,
        prompt: &str,
        timeout: Duration,
    ) -> Option<(String, String)> {
        let url = format!("{}/api/generate", config.classifier.local.url);
        let body = serde_json::json!({
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": {"temperature": 0},
        });
        let response = self
            .client
            .post(&url)
            .timeout(timeout)
            .json(&body)
            .send()
            .await
            .ok()?;
        if !response.status().is_success() {
            return None;
        }
        let json: Value = response.json().await.ok()?;
        let text = json["response"].as_str()?;
        parse_model_choice(text, registry)
    }
}

pub fn parse_model_choice(text: &str, registry: &ModelRegistry) -> Option<(String, String)> {
    let cleaned = text.trim().trim_matches('`').trim_matches('"').trim_matches('\'');

    let mut all_models: Vec<String> = registry
        .models
        .keys()
        .chain(registry.aliases.keys())
        .cloned()
        .collect();
    all_models.sort_by_key(|m| std::cmp::Reverse(m.len()));

    let fast_prefix_re = regex::Regex::new(r"(?i)^[-–—]?\s*fast\s*[-–—:]\s*").ok()?;
    let fast_match_re = regex::Regex::new(r"(?i)^fast\s*[-–—:]\s*(.+)$").ok()?;

    for model in &all_models {
        if registry.is_classifier_model(model) {
            continue;
        }
        let escaped = regex::escape(model);
        let pattern = format!(
            r"(?is)^\s*\**{}\**\s*(?:-|–|—|:)\s*(.+)$",
            escaped
        );
        let re = regex::Regex::new(&pattern).ok()?;
        let caps = re.captures(cleaned)?;
        let mut reason_text = caps.get(1)?.as_str().trim().to_string();

        let canonical = registry.resolve_alias(model);

        if let Some(model_info) = registry.models.get(&canonical) {
            let desc_words: Vec<&str> = model_info.description.split_whitespace().take(6).collect();
            let reason_words: Vec<&str> = reason_text.split_whitespace().take(6).collect();
            if desc_words == reason_words {
                reason_text = String::new();
            }
        }

        if canonical.ends_with("-fast") {
            reason_text = fast_prefix_re.replace(&reason_text, "").to_string();
        } else {
            if let Some(fm) = fast_match_re.captures(&reason_text) {
                let fast_model = format!("{}-fast", canonical);
                if registry.is_direct_model(&fast_model) {
                    return Some((fast_model, compact_reason(fm.get(1)?.as_str())));
                }
            }
        }

        return Some((canonical, compact_reason(&reason_text)));
    }
    None
}

fn compact_reason(reason: &str) -> String {
    let trimmed = reason.trim().trim_matches('`').trim_matches('"').trim_matches('\'').trim_matches('*').trim();
    let words: Vec<&str> = trimmed.split_whitespace().collect();
    let words = words[..words.len().min(6)].to_vec();
    let joined = words.join(" ");
    joined
        .trim_end_matches(['.', ',', ';', ':', '!', '?'])
        .to_string()
}

fn hash_string(s: &str) -> u64 {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    let mut hasher = DefaultHasher::new();
    s.hash(&mut hasher);
    hasher.finish()
}
