{
  config,
  lib,
  pkgs,
  features,
  ...
}:

let
  cfg = config.programs.opencode-router;

  toModelEntry =
    name: model:
    {
      inherit (model)
        description
        family
        provider
        tier
        fallbacks
        hidden
        ;
    }
    // lib.optionalAttrs (model.backend.litellm.model != null) {
      litellm_model = model.backend.litellm.model;
    }
    // lib.optionalAttrs (model.backend.litellm.apiBase != null) {
      litellm_api_base = model.backend.litellm.apiBase;
    }
    // lib.optionalAttrs (model.backend.chatgpt.model != null) {
      chatgpt_model = model.backend.chatgpt.model;
    }
    // lib.optionalAttrs (model.backend.chatgpt.serviceTier != null) {
      service_tier = model.backend.chatgpt.serviceTier;
    }
    // lib.optionalAttrs (model.displayName != null) {
      display_name = model.displayName;
    };

  modelsToml = lib.mapAttrs toModelEntry cfg.models;

  aliases =
    lib.optionalAttrs (cfg.defaults.model != "") {
      auto = cfg.defaults.model;
    }
    // cfg.aliases;

  guidanceText = cfg.prompts.guidance;
  modelGuidance = lib.mapAttrs (model: line: {
    prompt_line = line;
  }) cfg.prompts.modelGuidance;

  routerToml = (pkgs.formats.toml { }).generate "router.toml" {
    server = {
      inherit (cfg) host port;
      log_level = cfg.logLevel;
    };

    classifier = {
      backend = cfg.classifier.backend;
      model = cfg.classifier.model;
      timeout_seconds = cfg.classifier.timeoutSeconds;
      cache_ttl_seconds = cfg.classifier.cacheTtlSeconds;
    };

    models = modelsToml;

    defaults = {
      model = cfg.defaults.model;
      global_fallbacks = cfg.defaults.globalFallbacks;
      metadata_fallback_chain = cfg.defaults.metadataFallbackChain;
    };

    inherit aliases;
    inherit (cfg) families;

    cross_family_escalation = cfg.crossFamilyEscalation;

    prompts = {
      classification = cfg.prompts.classification;
      guidance.text = guidanceText;
      model_guidance = modelGuidance;
    };

    markers = {
      retry = cfg.markers.retry;
      retry_patterns = cfg.markers.retryPatterns;
      metadata = cfg.markers.metadata;
      coding = cfg.markers.coding;
    };

    bans = {
      auth_seconds = cfg.bans.authSeconds;
      exhaustion_seconds = cfg.bans.exhaustionSeconds;
      session_quality_seconds = cfg.bans.sessionQualitySeconds;
    };

    performance = {
      success_weight = cfg.performance.successWeight;
      failure_weight = cfg.performance.failureWeight;
      reward_threshold = cfg.performance.rewardThreshold;
      decay_factor = cfg.performance.decayFactor;
      decay_interval_seconds = cfg.performance.decayIntervalSeconds;
    };

    circuit_breaker = {
      base_cooldown_seconds = cfg.circuitBreaker.baseCooldownSeconds;
      max_cooldown_seconds = cfg.circuitBreaker.maxCooldownSeconds;
    };

    cache = {
      enabled = cfg.cache.enabled;
      ttl_seconds = cfg.cache.ttlSeconds;
      pattern.enabled = cfg.cache.pattern.enabled;
      exact.enabled = cfg.cache.exact.enabled;
      similarity = {
        enabled = cfg.cache.similarity.enabled;
        threshold = cfg.cache.similarity.threshold;
        max_entries = cfg.cache.similarity.maxEntries;
      };
      llm.enabled = cfg.cache.llm.enabled;
    };

    agent_instruction.text = cfg.agentInstruction;

    notice = {
      enabled = cfg.notice.enabled;
      format = cfg.notice.format;
      redirect_format = cfg.notice.redirectFormat;
    };

    display_names = cfg.displayNames;

    chatgpt = {
      token_url = cfg.chatgpt.tokenUrl;
      client_id = cfg.chatgpt.clientId;
      responses_url = cfg.chatgpt.responsesUrl;
      account_claim_url = cfg.chatgpt.accountClaimUrl;
      auth_file = cfg.chatgpt.authFile;
    };
  };
in
{
  config =
    lib.mkIf (features.development.enable && features.development.opencode.enable && cfg.enable)
      {
        programs.opencode-router.routerConfigFile = lib.mkDefault routerToml;
      };
}
