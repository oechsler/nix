# OpenCode Auto Router Configuration
#
# The OpenCode Auto Router gives OpenCode a single default model, `local/auto`.
# You use OpenCode normally; the router chooses a suitable backend for each request
# and reports the model at the end of the response.
#
# ## Request Flow
#
# User → OpenCode (local/auto) → Auto Router (127.0.0.1:4000) → Classifier (Ollama or LiteLLM)
#                                                                      ↓
# User ← OpenCode ← Auto Router ← LiteLLM (127.0.0.1:8000) or ChatGPT OAuth
#
# ## Providers
#
# - **Mistral API** — SOPS secret `opencode/mistral/api-key`, exposed as `MISTRAL_API_KEY`
# - **OpenCode Go** — SOPS secret `opencode/opencode-go/api-key`, exposed as `OPENCODE_GO_API_KEY`
# - **ChatGPT subscription** — OpenCode OAuth entry in `~/.local/share/opencode/auth.json`
# - **Local Ollama** — No external credential
#
# ## Model Families (escalation ladders)
#
# - Mistral: small → medium
# - DeepSeek: flash → pro
# - Qwen: 3.7-plus → 3.7-max → 3.8-max
# - GPT: luna → luna-fast → terra → terra-fast → sol → sol-fast
#
# ## Routing Policy
#
# - Trivial tasks → mistral-small (sparingly) or mistral-medium
# - Analysis/planning without tools → mistral-medium
# - Coding with tools → deepseek-v4-flash or qwen3.7-plus
# - Complex multi-step → deepseek-v4-pro or gpt-5.6-terra
# - Hardest problems → gpt-5.6-sol
#
# ## Fallback and Escalation
#
# - Backend fallback: network errors, rate limits, auth errors → walk fallback chain
# - Circuit breaker: exponential backoff (30s → 60s → 120s → 240s → 300s)
# - Session-quality banning: model fails to solve → 10min ban + escalate in family
# - Capability escalation: user says "didn't work" → next model in family ladder
#
# ## Operations
#
# systemctl --user status podman-opencode-router.service
# systemctl --user status podman-opencode-litellm.service
# systemctl --user status podman-opencode-ollama.service (local-classifier only)
# systemctl --user status opencode-router-sync-models.service (local-classifier only)
#
# curl http://127.0.0.1:4000/health
# curl http://127.0.0.1:8000/health
# curl http://127.0.0.1:11434/api/tags
#
# ## Source Layout
#
# Package implementation: modules/packages/opencode-router/
# - rust/ — Rust router implementation
# - nix/ — Nix modules (module.nix, router.nix, litellm.nix, services.nix, secrets.nix)
#
# This file: modules/home-manager/programs/opencode.nix
# - Imports the package module and sets model configuration
{
  config,
  lib,
  pkgs,
  features,
  ...
}:

let
  cfg = config.programs.opencode-router;

  models = {
    "mistral-small" = {
      description = "Fast model for greetings, Q&A, titles, translation. Only for trivial tasks; skip for anything substantive.";
      family = "mistral";
      provider = "litellm";
      tier = 1;
      fallbacks = [ "mistral-medium" ];
      backend.litellm = {
        model = "mistral/mistral-small-latest";
        apiKeyEnv = "MISTRAL_API_KEY";
      };
      displayName = "Mistral Small";
    };

    "mistral-medium" = {
      description = "Strong model for architecture, design tradeoffs, reviews, planning, analysis. Capable with and without tools.";
      family = "mistral";
      provider = "litellm";
      tier = 2;
      fallbacks = [
        "qwen3.7-plus"
        "deepseek-v4-flash"
      ];
      backend.litellm = {
        model = "mistral/mistral-medium-latest";
        apiKeyEnv = "MISTRAL_API_KEY";
      };
      displayName = "Mistral Medium";
    };

    "deepseek-v4-flash" = {
      description = "Fast coding model: bugs, refactors, multi-step changes, file edits, shell, NixOS, containers. Very high quota (158150 req/month).";
      family = "deepseek";
      provider = "litellm";
      tier = 2;
      fallbacks = [
        "deepseek-v4-pro"
        "qwen3.7-plus"
      ];
      backend.litellm = {
        model = "openai/deepseek-v4-flash";
        apiBase = "https://opencode.ai/zen/go/v1";
        apiKeyEnv = "OPENCODE_GO_API_KEY";
      };
      displayName = "DeepSeek V4 Flash";
    };

    "deepseek-v4-pro" = {
      description = "Stronger DeepSeek for complex work: multi-step exploration, deep analysis with tools. 17150 req/month quota.";
      family = "deepseek";
      provider = "litellm";
      tier = 3;
      fallbacks = [
        "qwen3.7-max"
        "gpt-5.6-terra"
      ];
      backend.litellm = {
        model = "openai/deepseek-v4-pro";
        apiBase = "https://opencode.ai/zen/go/v1";
        apiKeyEnv = "OPENCODE_GO_API_KEY";
      };
      displayName = "DeepSeek V4 Pro";
    };

    "gpt-5.6-terra" = {
      description = "GPT for complex agentic coding and multi-step exploration. Strong reasoning and tool use.";
      family = "gpt";
      provider = "chatgpt";
      tier = 3;
      fallbacks = [ "gpt-5.6-sol" ];
      backend.chatgpt.model = "gpt-5.6-terra";
      displayName = "GPT-5.6 Terra";
    };

    "gpt-5.6-luna" = {
      description = "GPT entry tier via OpenCode Go. Good general-purpose model. 10250 req/month quota.";
      family = "gpt";
      provider = "litellm";
      tier = 2;
      fallbacks = [ "gpt-5.6-luna-openai" ];
      backend.litellm = {
        model = "openai/gpt-5.6-luna";
        apiBase = "https://opencode.ai/zen/go/v1";
        apiKeyEnv = "OPENCODE_GO_API_KEY";
      };
      displayName = "GPT-5.6 Luna";
    };

    "gpt-5.6-sol" = {
      description = "Top-tier GPT for hardest agentic work: ambiguous multi-step exploration, race conditions, high-stakes system administration, critical bugs. Strongest model available.";
      family = "gpt";
      provider = "chatgpt";
      tier = 5;
      fallbacks = [ "qwen3.8-max" ];
      backend.chatgpt.model = "gpt-5.6-sol";
      displayName = "GPT-5.6 Sol";
    };

    "gpt-5.6-terra-fast" = {
      description = "Faster Terra variant for complex tasks at higher throughput.";
      family = "gpt";
      provider = "chatgpt";
      tier = 3;
      fallbacks = [ "gpt-5.6-sol-fast" ];
      backend.chatgpt = {
        model = "gpt-5.6-terra";
        serviceTier = "priority";
      };
      displayName = "GPT-5.6 Terra Fast";
    };

    "gpt-5.6-sol-fast" = {
      description = "Fast top-tier GPT for hardest debugging when Terra insufficient.";
      family = "gpt";
      provider = "chatgpt";
      tier = 4;
      fallbacks = [ "gpt-5.6-terra-fast" ];
      backend.chatgpt = {
        model = "gpt-5.6-sol";
        serviceTier = "priority";
      };
      displayName = "GPT-5.6 Sol Fast";
    };

    "gpt-5.6-luna-fast" = {
      description = "Fast entry-tier GPT for simple-to-medium coding. Overflow model.";
      family = "gpt";
      provider = "chatgpt";
      tier = 2;
      fallbacks = [
        "qwen3.7-plus"
        "deepseek-v4-flash"
      ];
      backend.chatgpt = {
        model = "gpt-5.6-luna";
        serviceTier = "priority";
      };
      displayName = "GPT-5.6 Luna Fast";
    };

    "gpt-5.6-luna-openai" = {
      description = "Direct OpenAI fallback for the OpenCode Go Luna route. Never select automatically.";
      family = "gpt";
      provider = "chatgpt";
      tier = 2;
      fallbacks = [ "gpt-5.6-terra" ];
      backend.chatgpt.model = "gpt-5.6-luna";
      hidden = true;
      displayName = "GPT-5.6 Luna (OpenAI)";
    };

    "qwen3.7-plus" = {
      description = "General development and broad refactors with tools. Solid coding model. 21600 req/month quota.";
      family = "qwen";
      provider = "litellm";
      tier = 2;
      fallbacks = [
        "qwen3.7-max"
        "deepseek-v4-flash"
      ];
      backend.litellm = {
        model = "openai/qwen3.7-plus";
        apiBase = "https://opencode.ai/zen/go/v1";
        apiKeyEnv = "OPENCODE_GO_API_KEY";
      };
      displayName = "Qwen3.7 Plus";
    };

    "qwen3.7-max" = {
      description = "Advanced reasoning, complex algorithmic analysis, math. 1690 req/month quota.";
      family = "qwen";
      provider = "litellm";
      tier = 3;
      fallbacks = [
        "qwen3.8-max"
        "gpt-5.6-terra"
      ];
      backend.litellm = {
        model = "openai/qwen3.7-max";
        apiBase = "https://opencode.ai/zen/go/v1";
        apiKeyEnv = "OPENCODE_GO_API_KEY";
      };
      displayName = "Qwen3.7 Max";
    };

    "qwen3.8-max" = {
      description = "Top Qwen reasoning model. Complex algorithmic analysis, math, deep design review. 810 req/month quota.";
      family = "qwen";
      provider = "litellm";
      tier = 4;
      fallbacks = [
        "gpt-5.6-sol"
        "deepseek-v4-pro"
      ];
      backend.litellm = {
        model = "openai/qwen3.8-max";
        apiBase = "https://opencode.ai/zen/go/v1";
        apiKeyEnv = "OPENCODE_GO_API_KEY";
      };
      displayName = "Qwen3.8 Max";
    };

    "qwen3:8b" = {
      description = "Local Qwen3 8B on Ollama. Limited offline model for light tasks when privacy critical. Not for auto-routing.";
      family = "qwen";
      provider = "ollama";
      tier = 1;
      fallbacks = [ "mistral-small" ];
      displayName = "Qwen3 8B (Local)";
    };
  };

  aliases = {
    "openai-luna-fast" = "gpt-5.6-luna-fast";
    "openai-luna" = "gpt-5.6-luna";
    "openai-sol-fast" = "gpt-5.6-sol-fast";
    "openai-sol" = "gpt-5.6-sol";
    "openai-terra-fast" = "gpt-5.6-terra-fast";
    "openai-terra" = "gpt-5.6-terra";
  };

  families = {
    "mistral".ladder = [
      "mistral-small"
      "mistral-medium"
    ];
    "deepseek".ladder = [
      "deepseek-v4-flash"
      "deepseek-v4-pro"
    ];
    "qwen".ladder = [
      "qwen3.7-plus"
      "qwen3.7-max"
      "qwen3.8-max"
    ];
    "gpt".ladder = [
      "gpt-5.6-luna"
      "gpt-5.6-luna-fast"
      "gpt-5.6-terra"
      "gpt-5.6-terra-fast"
      "gpt-5.6-sol"
      "gpt-5.6-sol-fast"
    ];
  };

  crossFamilyEscalation = {
    "mistral-small" = "mistral-medium";
    "mistral-medium" = "deepseek-v4-flash";
    "deepseek-v4-flash" = "deepseek-v4-pro";
    "deepseek-v4-pro" = "qwen3.7-max";
    "qwen3.7-plus" = "qwen3.7-max";
    "qwen3.7-max" = "qwen3.8-max";
    "qwen3.8-max" = "gpt-5.6-terra";
    "gpt-5.6-luna" = "gpt-5.6-terra";
    "gpt-5.6-luna-fast" = "gpt-5.6-terra-fast";
    "gpt-5.6-terra" = "gpt-5.6-sol";
    "gpt-5.6-terra-fast" = "gpt-5.6-sol-fast";
    "gpt-5.6-sol" = "gpt-5.6-sol-fast";
    "gpt-5.6-sol-fast" = "gpt-5.6-terra-fast";
  };

  prompts = {
    guidance = ''
      Guidance (not rules – use your judgment):
      - Consider: capability needs, tool usage, quota availability, and how hard the task really is.
      - For coding with tools, prefer DeepSeek Flash or Qwen Plus as cost-effective choices; escalate to stronger models when the task demands more reasoning or the cheaper model would fail.
      - Math, algorithmics, proofs → Qwen Max models or GPT.
      - Architecture/planning/design discussions → Mistral Medium or GPT.
      - Never use mistral-small for coding, debugging, shell, NixOS, file edits, or substantive requests, even without tools.
      - When in doubt between two models, choose the cheaper/faster one.
      - Prefer -fast variants for simple, latency-sensitive overflow.
    '';

    modelGuidance = {
      "mistral-small" =
        "- mistral-small: trivial – greetings, simple Q&A, titles, translations, one-line answers. No tools needed.";
      "deepseek-v4-flash" =
        "- deepseek-v4-flash: fast coding with tools – file edits, shell, tests, small-to-medium features. High quota, cheap. Good default for most coding.";
    };
  };

  markers = {
    retry = [
      "did not work"
      "didn't work"
      "does not work"
      "doesn't work"
      "still wrong"
      "not fixed"
      "didn't fix"
      "not what i asked"
      "try again"
      "previous answer"
      "other model"
      "cannot handle"
      "can't handle"
      "hat nicht funktioniert"
      "funktioniert nicht"
      "klappt nicht"
      "immer noch falsch"
      "nicht gefixt"
      "nicht geschafft"
      "nicht mehr schafft"
      "bekommt nicht hin"
      "nicht hin"
      "nicht was ich"
      "nochmal"
      "anderes modell"
      "andere modell"
      "vorherige antwort"
      "schafft es nicht"
      "schafft das nicht"
      "nicht nur die doku"
      "nicht nur die dokumentation"
    ];

    retryPatterns = [
      "\\bhat\\b.*\\bnicht funktioniert\\b"
      "\\bbekommt\\b.*\\bnicht hin\\b"
      "\\bschafft\\b.*\\bnicht(?: mehr)?\\b"
    ];

    metadata = [
      "generate a title"
      "generate title"
      "short title"
      "concise title"
      "session title"
      "conversation title"
      "title for this"
      "summarize this conversation"
      "conversation summary"
      "session summary"
      "titel für"
      "titel fuer"
      "kurzer titel"
      "kurzen titel"
      "zusammenfassung der konversation"
      "zusammenfassung dieser konversation"
    ];

    coding = [
      "code"
      "coding"
      "implement"
      "implementation"
      "debug"
      "bug"
      "refactor"
      "test"
      "script"
      "shell"
      "nix"
      "nixos"
      "python"
      "javascript"
      "typescript"
      "konfiguration"
      "programmier"
      "fehler"
      "debuggen"
      "implementieren"
      "refactoren"
    ];
  };

  displayNames = {
    "auto" = "Auto";
    "mistral-small" = "Mistral Small";
    "mistral-medium" = "Mistral Medium";
    "deepseek-v4-flash" = "DeepSeek V4 Flash";
    "deepseek-v4-pro" = "DeepSeek V4 Pro";
    "gpt-5.6-luna-fast" = "GPT-5.6 Luna Fast";
    "gpt-5.6-luna" = "GPT-5.6 Luna";
    "gpt-5.6-sol-fast" = "GPT-5.6 Sol Fast";
    "gpt-5.6-sol" = "GPT-5.6 Sol";
    "gpt-5.6-terra-fast" = "GPT-5.6 Terra Fast";
    "gpt-5.6-terra" = "GPT-5.6 Terra";
    "qwen3.8-max" = "Qwen3.8 Max";
    "qwen3.7-plus" = "Qwen3.7 Plus";
    "qwen3.7-max" = "Qwen3.7 Max";
    "qwen3:8b" = "Qwen3 8B (Local)";
  };

  chatgpt = {
    tokenUrl = "https://auth.openai.com/oauth/token";
    clientId = "app_EMoamEEZ73f0CkXaXp7hrann";
    responsesUrl = "https://chatgpt.com/backend-api/codex/responses";
    accountClaimUrl = "https://api.openai.com/auth";
    authFile = "/var/lib/opencode/auth.json";
  };

  ollamaModels = [ "qwen3:8b" ];

  classifier = {
    backend = "local";
    model = "qwen3:8b";
    timeoutSeconds = 8;
    cacheTtlSeconds = 300;
  };

  defaults = {
    model = "qwen3.7-plus";
    globalFallbacks = [
      "mistral-medium"
      "deepseek-v4-flash"
      "gpt-5.6-luna-openai"
      "qwen3:8b"
    ];
    metadataFallbackChain = [
      "mistral-small"
      "mistral-medium"
      "deepseek-v4-flash"
      "gpt-5.6-luna-fast"
    ];
  };

  bans = {
    authSeconds = 600;
    exhaustionSeconds = 900;
    sessionQualitySeconds = 600;
  };

  performance = {
    successWeight = 1.0;
    failureWeight = -2.0;
    rewardThreshold = 5;
    decayFactor = 0.95;
    decayIntervalSeconds = 300;
  };

  circuitBreaker = {
    baseCooldownSeconds = 30;
    maxCooldownSeconds = 300;
  };

  cache = {
    enabled = true;
    ttlSeconds = 300;
    pattern.enabled = true;
    exact.enabled = true;
    similarity = {
      enabled = true;
      threshold = 0.85;
      maxEntries = 1000;
    };
    llm.enabled = true;
  };

  notice = {
    format = "> **{display_name}**\n> {reason}";
    redirectFormat = "> **{original_display} → {display_name}**\n> {reason}";
  };

  litellmApiKeys = {
    MISTRAL_API_KEY = "opencode/mistral/api-key";
    OPENCODE_GO_API_KEY = "opencode/opencode-go/api-key";
  };
in
{
  imports = [
    ../../packages/opencode-router/nix/module.nix
  ];

  config = lib.mkIf (features.development.enable && features.development.opencode.enable) {
    programs.opencode-router = {
      enable = true;
      inherit
        models
        aliases
        families
        crossFamilyEscalation
        prompts
        markers
        displayNames
        chatgpt
        ollamaModels
        classifier
        defaults
        bans
        performance
        circuitBreaker
        cache
        notice
        litellmApiKeys
        ;
    };
  };
}
