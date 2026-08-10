# OpenCode Auto Router - Rust Redesign

## Overview

Idiomatic Rust implementation shipped as a container image. Nix is the single source of truth for all configuration. Every aspect that is currently hardcoded (prompts, model descriptions, tiers, markers, escalation ladders) becomes configurable.

## Design Principles

1. **No Panics**: Production code never panics. All errors handled via `thiserror` + `Result<T>`.
2. **Fully Config-Driven**: Zero hardcoded model knowledge. Prompts, descriptions, tiers, markers, escalation ladders all in config.
3. **Container-First**: Ships as a static Rust binary in a minimal OCI image, distributable via any container registry (GHCR).
4. **Nix Orchestrates**: Nix generates all configs (router TOML, LiteLLM YAML, OpenCode client JSON) from one unified model definition and runs the pod.
5. **Future-Proof**: Adding a new model = adding one Nix attribute. No Rust recompilation needed for model changes.

---

## Single Configuration Interface

**Das wichtigste Design-Prinzip**: Es gibt **EINE zentrale Stelle** in Nix, wo man Modelle einträgt. Diese eine Definition konfiguriert automatisch:
- Auto-Router (TOML)
- LiteLLM (YAML)
- OpenCode Client (Modelle im Provider)

### Beispiel: Ein Modell eintragen

```nix
# In deiner NixOS/home-manager Konfiguration:
programs.opencode-auto-router = {
  enable = true;
  
  models = {
    deepseek-v4-flash = {
      description = "Fast coding model: bugs, refactors, multi-step changes. Very high quota.";
      family = "deepseek";
      provider = "litellm";
      tier = 2;
      litellmModel = "openai/deepseek-v4-flash";
      litellmApiBase = "https://opencode.ai/zen/go/v1";
      litellmApiKeyEnv = "OPENCODE_GO_API_KEY";
      fallbacks = [ "deepseek-v4-pro" "qwen3.7-plus" ];
      displayName = "DeepSeek V4 Flash";
    };
  };
};
```

### Was daraus generiert wird

Aus **dieser einen Definition** generiert Nix automatisch **drei Configs**:

#### 1. Auto-Router TOML (`router.toml`)
```toml
[models.deepseek-v4-flash]
description = "Fast coding model: bugs, refactors, multi-step changes. Very high quota."
family = "deepseek"
provider = "litellm"
litellm_model = "openai/deepseek-v4-flash"
litellm_api_base = "https://opencode.ai/zen/go/v1"
litellm_api_key_env = "OPENCODE_GO_API_KEY"
tier = 2
fallbacks = ["deepseek-v4-pro", "qwen3.7-plus"]
display_name = "DeepSeek V4 Flash"
```

#### 2. LiteLLM YAML (`litellm.yaml`)
```yaml
model_list:
  - model_name: deepseek-v4-flash
    litellm_params:
      model: openai/deepseek-v4-flash
      api_base: https://opencode.ai/zen/go/v1
      api_key: os.environ/OPENCODE_GO_API_KEY
```

#### 3. OpenCode Client (Provider-Modelle)
```json
{
  "provider": {
    "local": {
      "models": {
        "deepseek-v4-flash": {
          "name": "DeepSeek V4 Flash",
          "reasoning": true,
          "tool_call": true,
          "temperature": true,
          "limit": { "context": 128000, "output": 32768 }
        }
      }
    }
  }
}
```

### Vorteile

✅ **Keine Redundanz**: Modell-Information nur einmal eintragen  
✅ **Konsistenz**: Alle Configs sind immer synchron  
✅ **Einfach**: Neues Modell = ein Nix-Attribut  
✅ **Wartbar**: Änderungen an einem Ort wirken überall  
✅ **Flexibel**: Benutzer können eigene Modelle hinzufügen, ohne Router/LiteLLM/Client manuell zu konfigurieren

### Nix-Modul-Struktur

```
modules/packages/opencode-router/
├── flake.nix              # Sub-flake exposing package, image, and module
├── rust/                  # Rust source code
│   ├── Cargo.toml
│   ├── Cargo.lock
│   ├── config/            # Default configuration
│   ├── src/               # Router implementation
│   └── tests/             # Integration tests and fixtures
└── nix/                   # Nix modules
    ├── module.nix         # Unified options interface
    ├── router.nix         # Generates router.toml
    ├── litellm.nix        # Generates litellm.yaml
    ├── client.nix         # Configures OpenCode client
    ├── services.nix       # Podman container orchestration
    ├── secrets.nix        # SOPS secrets management
    └── package.nix        # Rust package and Docker image

modules/home-manager/programs/opencode-auto-router/
└── default.nix            # Thin interface that imports package module
```

**`nix/module.nix`** defines the unified interface:
```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.opencode-auto-router;
in
{
  imports = [
    ./router.nix
    ./litellm.nix
    ./client.nix
    ./services.nix
    ./secrets.nix
  ];

  options.programs.opencode-auto-router = {
    enable = lib.mkEnableOption "OpenCode Auto Router";
    
    # EINHEITLICHES INTERFACE - hier trägt man Modelle ein
    models = lib.mkOption {
      type = lib.types.attrsOf modelType;
      description = "Model definitions - drives router, litellm, and client config";
    };
    
    # Weitere Optionen...
    families = lib.mkOption { ... };
    prompts = lib.mkOption { ... };
    bans = lib.mkOption { ... };
    cache = lib.mkOption { ... };
  };

  config = lib.mkIf cfg.enable {
    # Alle Sub-Module lesen aus cfg.models
  };
}
```

**`config/router.nix`** generiert `router.toml`:
```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.opencode-auto-router;
  
  routerToml = pkgs.writeText "router.toml" (lib.generators.toTOML {} {
    models = lib.mapAttrs (name: model: {
      inherit (model) description family tier fallbacks;
      provider = model.provider;
      litellm_model = model.litellmModel;
      litellm_api_base = model.litellmApiBase;
      litellm_api_key_env = model.litellmApiKeyEnv;
      display_name = model.displayName;
    }) cfg.models;
    
    families = cfg.families;
    # ... weitere Config
  });
in
{
  config = lib.mkIf cfg.enable {
    # router.toml wird an Container übergeben
  };
}
```

**`config/litellm.nix`** generiert `litellm.yaml`:
```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.opencode-auto-router;
  
  # Nur Modelle mit provider = "litellm"
  litellmModels = lib.filterAttrs (n: m:
    m.provider == "litellm" && m.litellmModel != null
  ) cfg.models;
  
  litellmYaml = pkgs.writeText "litellm.yaml" (builtins.toJSON {
    model_list = lib.mapAttrsToList (name: model: {
      model_name = name;
      litellm_params = {
        model = model.litellmModel;
        api_key = "os.environ/${model.litellmApiKeyEnv}";
      } // lib.optionalAttrs (model.litellmApiBase != null) {
        api_base = model.litellmApiBase;
      };
    }) litellmModels;
    
    litellm_settings = { drop_params = true; request_timeout = 600; };
    general_settings = { master_key = "dummy"; };
  });
in
{
  config = lib.mkIf cfg.enable {
    # litellm.yaml wird an LiteLLM-Container übergeben
  };
}
```

**`config/client.nix`** generiert OpenCode Client-Modelle:
```nix
{ config, lib, ... }:

let
  cfg = config.programs.opencode-auto-router;
  
  # Nur nicht-hidden Modelle
  clientModels = lib.mapAttrs (name: model: {
    name = model.displayName or name;
    reasoning = true;
    interleaved.field = "reasoning_content";
    tool_call = true;
    temperature = true;
    limit = { context = 128000; output = 32768; };
  }) (lib.filterAttrs (n: m: !m.hidden) cfg.models);
in
{
  config = lib.mkIf cfg.enable {
    programs.opencode.settings.provider.local.models = clientModels;
  };
}
```

### Workflow: Neues Modell hinzufügen

**Vorher** (3 Dateien manuell bearbeiten):
1. `router.py` → `MODEL_ROUTING` dict aktualisieren
2. `litellm.yaml` → Model-Eintrag hinzufügen
3. `client.nix` → Model im Provider registrieren

**Nachher** (1 Stelle):
```nix
programs.opencode-auto-router.models.gemini-2.5-pro = {
  description = "Google's strongest reasoning model.";
  family = "gemini";
  provider = "litellm";
  tier = 4;
  litellmModel = "gemini/gemini-2.5-pro";
  litellmApiKeyEnv = "GEMINI_API_KEY";
  fallbacks = [ "qwen3.8-max" "gpt-5.6-sol" ];
  displayName = "Gemini 2.5 Pro";
};
```

**Fertig.** Router, LiteLLM und Client sind automatisch konfiguriert.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Nix Configuration                                │
│                                                                         │
│  programs.opencode-auto-router = {                                     │
│    models = { ... };        # Single source of truth                   │
│    families = { ... };      # Escalation ladders                       │
│    prompts = { ... };       # Classification prompt template           │
│    markers = { ... };       # Retry/coding/metadata markers            │
│    tiers = { ... };         # Capability levels                        │
│    bans = { ... };          # Timing configuration                     │
│  };                                                                     │
└────────────────────────────────────────────────────────────────────────┘
                    │                    │                    │
                    ▼                    ▼                    ▼
        ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
        │  router.toml      │ │  litellm.yaml     │ │  OpenCode client  │
        │  (Router config)  │ │  (LiteLLM config) │ │  (client.nix)     │
        └───────────────────┘ └───────────────────┘ └───────────────────┘
                    │                    │                    │
                    ▼                    ▼                    ▼
        ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
        │  Auto Router      │ │  LiteLLM          │ │  OpenCode         │
        │  (Rust container) │ │  (container)      │ │  (Node.js)        │
        │  ghcr.io/...      │ │  ghcr.io/berriai  │ │                   │
        └───────────────────┘ └───────────────────┘ └───────────────────┘
                    │                    │
                    └────────┬───────────┘
                             ▼
                    ┌───────────────────┐
                    │  Ollama           │
                    │  (container, opt) │
                    └───────────────────┘
```

---

## Container Image

### Multi-Stage Build

```dockerfile
# Stage 1: Build
FROM rust:1.85-alpine AS builder
RUN apk add --no-cache musl-dev
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
RUN cargo fetch
COPY src ./src
RUN cargo build --release --target x86_64-unknown-linux-musl

# Stage 2: Runtime
FROM scratch
COPY --from=builder /build/target/x86_64-unknown-linux-musl/release/opencode-router /opencode-router
COPY config/default.toml /etc/opencode-router/default.toml
EXPOSE 4000
ENTRYPOINT ["/opencode-router"]
```

The image is ~15MB (static binary + default config). Published to `ghcr.io/<org>/opencode-router:<version>`.

### Nix Image Build (alternative)

For Nix users, the image can also be built via `dockerTools`:

```nix
routerImage = pkgs.dockerTools.buildLayeredImage {
  name = "opencode-router";
  tag = "latest";
  contents = [
    (pkgs.callPackage ./rust-package.nix {})
  ];
  config = {
    Cmd = ["/bin/opencode-router" "--config" "/etc/opencode-router/config.toml"];
    ExposedPorts = { "4000/tcp" = {}; };
  };
};
```

### Standalone Distribution

Without Nix, users can run:

```bash
podman run -d \
  --name opencode-router \
  -p 4000:4000 \
  -v ./router.toml:/etc/opencode-router/config.toml:ro \
  -v ~/.local/share/opencode/auth.json:/var/lib/opencode/auth.json:ro \
  ghcr.io/<org>/opencode-router:latest
```

---

## Configuration Schema

The router reads a single TOML file. All sections are optional and fall back to built-in defaults.

### Full Config

```toml
[server]
host = "0.0.0.0"
port = 4000
log_level = "info"

[classifier]
backend = "local"                    # "local" | "cloud"
model = "qwen3:8b"                   # Local Ollama model for classification
timeout_seconds = 8
cache_ttl_seconds = 300

[classifier.cloud]
model = "mistral-small"              # Model used when backend = "cloud"
url = "http://127.0.0.1:8000/v1"     # LiteLLM endpoint

[classifier.local]
url = "http://127.0.0.1:11434"       # Ollama endpoint

# ─── Models ──────────────────────────────────────────────────────────────────
# Each model entry defines everything the router needs to know.
# The `description` is injected into the classification prompt verbatim.
# `provider` determines which backend handles requests.
# `fallbacks` is the ordered fallback chain.
# `tier` is the capability level (1 = trivial, 5 = strongest).

[models.mistral-small]
description = "Fast model for greetings, Q&A, titles, translation. Only for trivial tasks; skip for anything substantive."
family = "mistral"
provider = "litellm"
litellm_model = "mistral/mistral-small-latest"
tier = 1
fallbacks = ["mistral-medium"]

[models.mistral-medium]
description = "Strong model for architecture, design tradeoffs, reviews, planning, analysis. Capable with and without tools."
family = "mistral"
provider = "litellm"
litellm_model = "mistral/mistral-medium-latest"
tier = 2
fallbacks = ["qwen3.7-plus", "deepseek-v4-flash"]

[models.deepseek-v4-flash]
description = "Fast coding model: bugs, refactors, multi-step changes, file edits, shell, NixOS, containers. Very high quota (158150 req/month)."
family = "deepseek"
provider = "litellm"
litellm_model = "openai/deepseek-v4-flash"
litellm_api_base = "https://opencode.ai/zen/go/v1"
litellm_api_key_env = "OPENCODE_GO_API_KEY"
tier = 2
fallbacks = ["deepseek-v4-pro", "qwen3.7-plus"]

[models.deepseek-v4-pro]
description = "Stronger DeepSeek for complex work: multi-step exploration, deep analysis with tools. 17150 req/month quota."
family = "deepseek"
provider = "litellm"
litellm_model = "openai/deepseek-v4-pro"
litellm_api_base = "https://opencode.ai/zen/go/v1"
litellm_api_key_env = "OPENCODE_GO_API_KEY"
tier = 3
fallbacks = ["qwen3.7-max", "gpt-5.6-terra"]

[models.gpt-5.6-terra]
description = "GPT for complex agentic coding and multi-step exploration. Strong reasoning and tool use."
family = "gpt"
provider = "chatgpt"
chatgpt_model = "gpt-5.6-terra"
tier = 3
fallbacks = ["gpt-5.6-sol"]

[models.gpt-5.6-luna]
description = "GPT entry tier via OpenCode Go. Good general-purpose model. 10250 req/month quota."
family = "gpt"
provider = "litellm"
litellm_model = "openai/gpt-5.6-luna"
litellm_api_base = "https://opencode.ai/zen/go/v1"
litellm_api_key_env = "OPENCODE_GO_API_KEY"
tier = 2
fallbacks = ["gpt-5.6-luna-openai"]

[models.gpt-5.6-sol]
description = "Top-tier GPT for hardest agentic work: ambiguous multi-step exploration, race conditions, high-stakes system administration, critical bugs. Strongest model available."
family = "gpt"
provider = "chatgpt"
chatgpt_model = "gpt-5.6-sol"
tier = 5
fallbacks = ["qwen3.8-max"]

[models.gpt-5.6-terra-fast]
description = "Faster Terra variant for complex tasks at higher throughput."
family = "gpt"
provider = "chatgpt"
chatgpt_model = "gpt-5.6-terra"
service_tier = "priority"
tier = 3
fallbacks = ["gpt-5.6-sol-fast"]

[models.gpt-5.6-sol-fast]
description = "Fast top-tier GPT for hardest debugging when Terra insufficient."
family = "gpt"
provider = "chatgpt"
chatgpt_model = "gpt-5.6-sol"
service_tier = "priority"
tier = 4
fallbacks = ["gpt-5.6-terra-fast"]

[models.gpt-5.6-luna-fast]
description = "Fast entry-tier GPT for simple-to-medium coding. Overflow model."
family = "gpt"
provider = "chatgpt"
chatgpt_model = "gpt-5.6-luna"
service_tier = "priority"
tier = 2
fallbacks = ["qwen3.7-plus", "deepseek-v4-flash"]

[models.gpt-5.6-luna-openai]
description = "Direct OpenAI fallback for the OpenCode Go Luna route. Never select automatically."
family = "gpt"
provider = "chatgpt"
chatgpt_model = "gpt-5.6-luna"
hidden = true
tier = 2
fallbacks = ["gpt-5.6-terra"]

[models.qwen3.7-plus]
description = "General development and broad refactors with tools. Solid coding model. 21600 req/month quota."
family = "qwen"
provider = "litellm"
litellm_model = "openai/qwen3.7-plus"
litellm_api_base = "https://opencode.ai/zen/go/v1"
litellm_api_key_env = "OPENCODE_GO_API_KEY"
tier = 2
fallbacks = ["qwen3.7-max", "deepseek-v4-flash"]

[models.qwen3.7-max]
description = "Advanced reasoning, complex algorithmic analysis, math. 1690 req/month quota."
family = "qwen"
provider = "litellm"
litellm_model = "openai/qwen3.7-max"
litellm_api_base = "https://opencode.ai/zen/go/v1"
litellm_api_key_env = "OPENCODE_GO_API_KEY"
tier = 3
fallbacks = ["qwen3.8-max", "gpt-5.6-terra"]

[models.qwen3.8-max]
description = "Top Qwen reasoning model. Complex algorithmic analysis, math, deep design review. 810 req/month quota."
family = "qwen"
provider = "litellm"
litellm_model = "openai/qwen3.8-max"
litellm_api_base = "https://opencode.ai/zen/go/v1"
litellm_api_key_env = "OPENCODE_GO_API_KEY"
tier = 4
fallbacks = ["gpt-5.6-sol", "deepseek-v4-pro"]

[models."qwen3:8b"]
description = "Local Qwen3 8B on Ollama. Limited offline model for light tasks when privacy critical. Not for auto-routing."
family = "qwen"
provider = "ollama"
tier = 1
fallbacks = ["mistral-small"]

# ─── Defaults ────────────────────────────────────────────────────────────────

[defaults]
model = "qwen3.7-plus"               # Default when classification fails
global_fallbacks = [                  # Safety net appended to every chain
  "mistral-medium",
  "deepseek-v4-flash",
  "gpt-5.6-luna-openai",
  "qwen3:8b",
]
metadata_fallback_chain = [           # Cheap-only chain for title/summary
  "mistral-small",
  "mistral-medium",
  "deepseek-v4-flash",
  "gpt-5.6-luna-fast",
]

# ─── Aliases ─────────────────────────────────────────────────────────────────
# Map client-facing names to canonical model IDs.

[aliases]
"openai-luna-fast" = "gpt-5.6-luna-fast"
"openai-luna" = "gpt-5.6-luna"
"openai-sol-fast" = "gpt-5.6-sol-fast"
"openai-sol" = "gpt-5.6-sol"
"openai-terra-fast" = "gpt-5.6-terra-fast"
"openai-terra" = "gpt-5.6-terra"

# ─── Families ────────────────────────────────────────────────────────────────
# Escalation ladders within a model family. Ordered from weakest to strongest.
# Used for: family escalation on retry, load-balancing alternatives.

[families.mistral]
ladder = ["mistral-small", "mistral-medium"]

[families.deepseek]
ladder = ["deepseek-v4-flash", "deepseek-v4-pro"]

[families.qwen]
ladder = ["qwen3.7-plus", "qwen3.7-max", "qwen3.8-max"]

[families.gpt]
ladder = ["gpt-5.6-luna", "gpt-5.6-luna-fast", "gpt-5.6-terra", "gpt-5.6-terra-fast", "gpt-5.6-sol", "gpt-5.6-sol-fast"]

# ─── Prompts ─────────────────────────────────────────────────────────────────
# All prompt text is configurable. Variables available in templates:
#   {models_section}  - rendered model list (from descriptions)
#   {banned_section}  - currently banned models
#   {context}         - truncated conversation context
#   {has_tools}       - "true" / "false"

[prompts]
classification = """
Classify for OpenCode routing. Match approximately based on the task – no rigid 1:1 mapping. Think about what model fits best for THIS specific request. Return: model_id - reason (2-6 words in user's language).

{models_section}

{guidance_section}
{banned_section}

Context (has_tools={has_tools}):
{context}
"""

[prompts.guidance]
text = """
Guidance (not rules – use your judgment):
- Consider: capability needs, tool usage, quota availability, and how hard the task really is.
- For coding with tools, prefer DeepSeek Flash or Qwen Plus as cost-effective choices; escalate to stronger models when the task demands more reasoning or the cheaper model would fail.
- Math, algorithmics, proofs → Qwen Max models or GPT.
- Architecture/planning/design discussions → Mistral Medium or GPT.
- Never use mistral-small for coding, debugging, shell, NixOS, file edits, or substantive requests, even without tools.
- When in doubt between two models, choose the cheaper/faster one.
- Prefer -fast variants for simple, latency-sensitive overflow.
"""

# Per-model guidance injected into the models_section
# This overrides auto-generated guidance from descriptions
[prompts.model_guidance."mistral-small"]
prompt_line = "- mistral-small: trivial – greetings, simple Q&A, titles, translations, one-line answers. No tools needed."

[prompts.model_guidance."deepseek-v4-flash"]
prompt_line = "- deepseek-v4-flash: fast coding with tools – file edits, shell, tests, small-to-medium features. High quota, cheap. Good default for most coding."

# ─── Markers ─────────────────────────────────────────────────────────────────
# Text patterns used for request classification and retry detection.
# All are lowercase matched against the conversation context.

[markers]
retry = [
  "did not work",
  "didn't work",
  "does not work",
  "doesn't work",
  "still wrong",
  "not fixed",
  "didn't fix",
  "not what i asked",
  "try again",
  "previous answer",
  "other model",
  "cannot handle",
  "can't handle",
  "hat nicht funktioniert",
  "funktioniert nicht",
  "klappt nicht",
  "immer noch falsch",
  "nicht gefixt",
  "nicht geschafft",
  "nicht mehr schafft",
  "bekommt nicht hin",
  "nicht hin",
  "nicht was ich",
  "nochmal",
  "anderes modell",
  "andere modell",
  "vorherige antwort",
  "schafft es nicht",
  "schafft das nicht",
  "nicht nur die doku",
  "nicht nur die dokumentation",
]

retry_patterns = [
  '\\bhat\\b.*\\bnicht funktioniert\\b',
  '\\bbekommt\\b.*\\bnicht hin\\b',
  '\\bschafft\\b.*\\bnicht(?: mehr)?\\b',
]

metadata = [
  "generate a title",
  "generate title",
  "short title",
  "concise title",
  "session title",
  "conversation title",
  "title for this",
  "summarize this conversation",
  "conversation summary",
  "session summary",
  "titel für",
  "titel fuer",
  "kurzer titel",
  "kurzen titel",
  "zusammenfassung der konversation",
  "zusammenfassung dieser konversation",
]

coding = [
  "code", "coding", "implement", "implementation", "debug", "bug",
  "refactor", "test", "script", "shell", "nix", "nixos",
  "python", "javascript", "typescript",
  "konfiguration", "programmier", "fehler", "debuggen",
  "implementieren", "refactoren",
]

# ─── Model Performance & Bans ────────────────────────────────────────────────
# Models are REWARDED for success, not punished for working well.
# Only ban on actual failures: auth errors, quota exhaustion, user rejection.

[bans]
auth_seconds = 600                      # Hard ban on 401/403 (credentials broken)
exhaustion_seconds = 900                # Ban on 429 (quota exhausted)
session_quality_seconds = 600           # Ban when user rejects result (didn't work, try again)

[performance]
success_weight = 1.0                    # Points per successful request
failure_weight = -2.0                   # Points deducted per failure
reward_threshold = 5                    # After N successes, model gets priority
decay_factor = 0.95                     # Score decays over time (prevents stale preferences)
decay_interval_seconds = 300            # Apply decay every 5 minutes

# Models with high scores are preferred for similar requests
# This creates a feedback loop: good models get more work, bad models get banned

[circuit_breaker]
base_cooldown_seconds = 30
max_cooldown_seconds = 300

# ─── Smart Caching ───────────────────────────────────────────────────────────
# Multi-level cache to minimize expensive LLM classification calls.
# Goal: 90%+ cache hit rate to reduce Ollama/GPU load.

[cache]
enabled = true
ttl_seconds = 300                       # Base TTL for all cache levels

[cache.pattern]
enabled = true                          # Regex-based classification for obvious cases
# Examples: "hello" → mistral-small, "fix bug" → deepseek-v4-flash
# Zero LLM cost, instant response

[cache.exact]
enabled = true                          # Exact message hash → model
# Same conversation = same model (no re-classification)

[cache.similarity]
enabled = true                          # N-gram similarity matching
threshold = 0.85                        # 85% similarity = cache hit
max_entries = 1000                      # LRU cache size
# Similar requests reuse cached classification

[cache.llm]
enabled = true                          # LLM classification (fallback)
# Only called when pattern/exact/similarity all miss
# This is the expensive path (Ollama/GPU cost)

# ─── Agent Instruction ───────────────────────────────────────────────────────
# Prepended as a system message when the model has tools.

[agent_instruction]
text = """
You are running inside OpenCode as an agent with tools. Treat the user's complete request as one assignment and own it end to end. Identify every deliverable, constraint, and acceptance condition first. Inspect files and implement every requested change. For 3+ substantive steps, use the todo tool when available: create a todo list and keep it updated after each tool result. Continue through all implementation, testing, linting, typechecking, and verification. Never stop after analysis, after one subtask, or after a partial fix. Before answering, verify each deliverable against the original request and run the strongest applicable checks. Only return a final answer when complete or when blocked. If blocked, complete every unblocked part first and state the blocker and remaining action. CRITICAL RULE: NEVER generate model-routing annotations (like '> **DeepSeek V4 Flash**', '> **GPT-5.6 Sol**', '> Coding & shell commands') or any model IDs in your responses. The auto-router system injects those automatically. You must not prefix, suffix, or embed any routing information.
"""

# ─── Notice Format ───────────────────────────────────────────────────────────
# How the router annotates responses with model information.

[notice]
format = "> **{display_name}**\n> {reason}"
redirect_format = "> **{original_display} → {display_name}**\n> {reason}"

# ─── Display Names ───────────────────────────────────────────────────────────

[display_names]
auto = "Auto"
mistral-small = "Mistral Small"
mistral-medium = "Mistral Medium"
deepseek-v4-flash = "DeepSeek V4 Flash"
deepseek-v4-pro = "DeepSeek V4 Pro"
gpt-5.6-luna-fast = "GPT-5.6 Luna Fast"
gpt-5.6-luna = "GPT-5.6 Luna"
gpt-5.6-sol-fast = "GPT-5.6 Sol Fast"
gpt-5.6-sol = "GPT-5.6 Sol"
gpt-5.6-terra-fast = "GPT-5.6 Terra Fast"
gpt-5.6-terra = "GPT-5.6 Terra"
qwen3.8-max = "Qwen3.8 Max"
qwen3.7-plus = "Qwen3.7 Plus"
qwen3.7-max = "Qwen3.7 Max"
"qwen3:8b" = "Qwen3 8B (Local)"

# ─── ChatGPT OAuth ──────────────────────────────────────────────────────────

[chatgpt]
token_url = "https://auth.openai.com/oauth/token"
client_id = "app_EMoamEEZ73f0CkXaXp7hrann"
responses_url = "https://chatgpt.com/backend-api/codex/responses"
account_claim_url = "https://api.openai.com/auth"
auth_file = "/var/lib/opencode/auth.json"
```

---

## Rust Project Structure

```
modules/packages/opencode-router/rust/
├── Cargo.toml
├── Cargo.lock
├── config/
│   └── default.toml                 # Built-in defaults (same as above)
├── src/
│   ├── main.rs                      # Entry point: parse CLI, load config, start server
│   ├── lib.rs                       # Library root
│   ├── config.rs                    # Config types + TOML deserialization + validation
│   ├── error.rs                     # Unified error types (thiserror)
│   ├── state.rs                     # Shared state: bans, cooldowns, rotation, cache
│   ├── models.rs                    # Model registry, lookup, aliases, providers
│   ├── routing/
│   │   ├── mod.rs                   # Main routing logic: classify → escalate → fallback
│   │   ├── classifier.rs            # Classification prompt building + parsing
│   │   ├── fallback.rs              # BFS fallback chain walker
│   │   ├── escalation.rs            # Capability + family escalation
│   │   └── circuit_breaker.rs       # Exponential backoff, cooldowns
│   ├── handlers/
│   │   ├── mod.rs                   # Axum router
│   │   ├── chat.rs                  # POST /v1/chat/completions
│   │   ├── health.rs                # GET /health
│   │   └── models.rs                # GET /v1/models
│   ├── backend/
│   │   ├── mod.rs                   # Backend trait + dispatch
│   │   ├── litellm.rs               # LiteLLM HTTP client (streaming + non-streaming)
│   │   ├── chatgpt.rs               # ChatGPT Responses API client
│   │   └── ollama.rs                # Ollama HTTP client
│   ├── auth/
│   │   ├── mod.rs
│   │   └── openai.rs                # OAuth token load/refresh/save
│   ├── transform/
│   │   ├── mod.rs
│   │   ├── chat_to_responses.rs     # Chat API → Responses API conversion
│   │   └── responses_to_chat.rs     # Responses API → Chat API conversion
│   └── utils/
│       ├── mod.rs
│       ├── notice.rs                # Notice formatting + stripping
│       └── text.rs                  # Message text extraction, context truncation
└── tests/
    └── fixtures/
        └── test_config.toml         # Test fixture for integration tests
```

---

## Error Handling

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum RouterError {
    #[error("config: {0}")]
    Config(String),

    #[error("model not found: {0}")]
    ModelNotFound(String),

    #[error("backend unavailable: {provider}: {detail}")]
    BackendUnavailable { provider: String, detail: String },

    #[error("classification failed: {0}")]
    ClassificationFailed(String),

    #[error("auth error: {0}")]
    Auth(String),

    #[error("http: {0}")]
    Http(#[from] reqwest::Error),

    #[error("json: {0}")]
    Json(#[from] serde_json::Error),

    #[error("io: {0}")]
    Io(#[from] std::io::Error),

    #[error("toml: {0}")]
    Toml(#[from] toml::de::Error),

    #[error("timeout: {0}")]
    Timeout(String),
}

pub type Result<T> = std::result::Result<T, RouterError>;
```

All handlers catch `RouterError` and return appropriate HTTP responses. No `unwrap()`, `expect()`, or `panic!()` in production code.

---

## Core Types

```rust
#[derive(Deserialize, Clone)]
pub struct ModelConfig {
    pub description: String,
    pub family: String,
    pub provider: Provider,
    pub tier: u8,
    pub fallbacks: Vec<String>,

    // Provider-specific
    pub litellm_model: Option<String>,
    pub litellm_api_base: Option<String>,
    pub litellm_api_key_env: Option<String>,
    pub chatgpt_model: Option<String>,
    pub service_tier: Option<String>,

    // Metadata
    pub hidden: Option<bool>,
    pub display_name: Option<String>,
}

#[derive(Deserialize, Clone)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    Litellm,
    Chatgpt,
    Ollama,
}

#[derive(Deserialize)]
pub struct FamilyConfig {
    pub ladder: Vec<String>,
}

#[derive(Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub classifier: ClassifierConfig,
    pub models: HashMap<String, ModelConfig>,
    pub defaults: DefaultsConfig,
    pub aliases: HashMap<String, String>,
    pub families: HashMap<String, FamilyConfig>,
    pub prompts: PromptsConfig,
    pub markers: MarkersConfig,
    pub bans: BansConfig,
    pub circuit_breaker: CircuitBreakerConfig,
    pub agent_instruction: AgentInstructionConfig,
    pub notice: NoticeConfig,
    pub display_names: HashMap<String, String>,
    pub chatgpt: ChatGptConfig,
}
```

---

## Nix Module Design

### Unified Module Interface

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.opencode-auto-router;

  # ─── Model Type ────────────────────────────────────────────────────
  modelType = lib.types.submodule {
    options = {
      description = lib.mkOption { type = lib.types.str; };
      family = lib.mkOption { type = lib.types.str; };
      provider = lib.mkOption {
        type = lib.types.enum [ "litellm" "chatgpt" "ollama" ];
      };
      tier = lib.mkOption { type = lib.types.ints.between 1 10; };
      fallbacks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };

      # LiteLLM routing
      litellmModel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      litellmApiBase = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      litellmApiKeyEnv = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      # ChatGPT routing
      chatgptModel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      serviceTier = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      # Metadata
      hidden = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      displayName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
    };
  };

  # ─── Generate router.toml ──────────────────────────────────────────
  routerToml = pkgs.writeText "router.toml" (lib.generators.toTOML {} {
    server = { inherit (cfg) host; port = cfg.port; log_level = cfg.logLevel; };
    # ... (all sections from cfg)
  });

  # ─── Generate litellm.yaml ─────────────────────────────────────────
  litellmModels = lib.filterAttrs (n: m:
    m.provider == "litellm" && m.litellmModel != null
  ) cfg.models;

  litellmYaml = pkgs.writeText "litellm.yaml" (builtins.toJSON {
    model_list = lib.mapAttrsToList (name: model: {
      model_name = name;
      litellm_params = {
        model = model.litellmModel;
        api_key = "os.environ/${model.litellmApiKeyEnv}";
      } // lib.optionalAttrs (model.litellmApiBase != null) {
        api_base = model.litellmApiBase;
      };
    }) litellmModels;
    litellm_settings = { drop_params = true; request_timeout = 600; };
    general_settings = { master_key = "dummy"; };
  });

  # ─── Generate OpenCode client models ───────────────────────────────
  clientModels = lib.mapAttrs (name: model: {
    name = model.displayName or (lib.toUpper (builtins.substring 0 1 name) + builtins.substring 1 (builtins.stringLength name) name);
    reasoning = true;
    interleaved.field = "reasoning_content";
    tool_call = true;
    temperature = true;
    limit = { context = 128000; output = 32768; };
  }) (lib.filterAttrs (n: m: !m.hidden) cfg.models);
in
{
  options.programs.opencode-auto-router = {
    enable = lib.mkEnableOption "OpenCode Auto Router";

    host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
    port = lib.mkOption { type = lib.types.port; default = 4000; };
    logLevel = lib.mkOption {
      type = lib.types.enum [ "trace" "debug" "info" "warn" "error" ];
      default = "info";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/<org>/opencode-router:latest";
      description = "OCI image for the auto-router";
    };

    classifier = {
      backend = lib.mkOption {
        type = lib.types.enum [ "local" "cloud" ];
        default = "local";
      };
      model = lib.mkOption { type = lib.types.str; default = "qwen3:8b"; };
    };

    models = lib.mkOption {
      type = lib.types.attrsOf modelType;
      default = { /* all default models from above */ };
    };

    families = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.ladder = lib.mkOption { type = lib.types.listOf lib.types.str; };
      });
      default = {
        mistral.ladder = [ "mistral-small" "mistral-medium" ];
        deepseek.ladder = [ "deepseek-v4-flash" "deepseek-v4-pro" ];
        qwen.ladder = [ "qwen3.7-plus" "qwen3.7-max" "qwen3.8-max" ];
        gpt.ladder = [ "gpt-5.6-luna" "gpt-5.6-luna-fast" "gpt-5.6-terra" "gpt-5.6-terra-fast" "gpt-5.6-sol" "gpt-5.6-sol-fast" ];
      };
    };

    prompts = {
      classification = lib.mkOption { type = lib.types.str; default = "/* default */"; };
      guidance = lib.mkOption { type = lib.types.str; default = "/* default */"; };
      modelGuidance = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
      };
    };

    markers = {
      retry = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ /* ... */ ]; };
      metadata = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ /* ... */ ]; };
      coding = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ /* ... */ ]; };
    };

    bans = {
      authSeconds = lib.mkOption { type = lib.types.int; default = 600; };
      exhaustionSeconds = lib.mkOption { type = lib.types.int; default = 900; };
      sessionQualitySeconds = lib.mkOption { type = lib.types.int; default = 600; };
    };

    performance = {
      successWeight = lib.mkOption { type = lib.types.float; default = 1.0; };
      failureWeight = lib.mkOption { type = lib.types.float; default = -2.0; };
      rewardThreshold = lib.mkOption { type = lib.types.int; default = 5; };
      decayFactor = lib.mkOption { type = lib.types.float; default = 0.95; };
      decayIntervalSeconds = lib.mkOption { type = lib.types.int; default = 300; };
    };

    cache = {
      enabled = lib.mkOption { type = lib.types.bool; default = true; };
      ttlSeconds = lib.mkOption { type = lib.types.int; default = 300; };
      
      pattern = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
      };
      exact = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
      };
      similarity = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
        threshold = lib.mkOption { type = lib.types.float; default = 0.85; };
        maxEntries = lib.mkOption { type = lib.types.int; default = 1000; };
      };
      llm = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Generate configs, run pod with containers
    # (services.nix replacement)
  };
}
```

### Adding a New Model

With the config-driven design, adding a new model requires **zero Rust changes**:

```nix
# In user's NixOS/home-manager config:
programs.opencode-auto-router.models.gemini-2.5-pro = {
  description = "Google's strongest reasoning model for complex analysis.";
  family = "gemini";
  provider = "litellm";
  tier = 4;
  litellmModel = "gemini/gemini-2.5-pro";
  litellmApiKeyEnv = "GEMINI_API_KEY";
  fallbacks = [ "qwen3.8-max" "gpt-5.6-sol" ];
};

programs.opencode-auto-router.families.gemini.ladder = [
  "gemini-2.5-flash" "gemini-2.5-pro"
];
```

This single addition auto-generates:
- Router TOML entry (classification prompt, routing, fallbacks)
- LiteLLM YAML entry (model_name + litellm_params)
- OpenCode client model entry (display name, limits, provider)

---

## Implementation Plan

### Phase 1: Foundation (Day 1-2)
1. `Cargo.toml` with dependencies
2. `config.rs` - all config types, TOML deserialization, validation
3. `error.rs` - unified error types
4. `default.toml` - built-in defaults

### Phase 2: Model Registry & State (Day 3-4)
1. `models.rs` - registry, lookup, aliases, provider dispatch
2. `state.rs` - performance scores, bans, cooldowns (all in one `Arc<RwLock<State>>`)
   - Reward/penalty system (success_weight, failure_weight)
   - Score decay over time
   - Ban logic (only for failures, not success)
   - Multi-level cache (pattern, exact, similarity, llm)

### Phase 3: Routing Logic (Day 5-7)
1. `routing/classifier.rs` - prompt building from config, parsing, multi-level cache
2. `routing/fallback.rs` - BFS fallback chain
3. `routing/escalation.rs` - family + cross-family escalation from config
4. `routing/circuit_breaker.rs` - exponential backoff
5. `routing/performance.rs` - score-based model selection

### Phase 4: HTTP Layer (Day 8-10)
1. `main.rs` - Axum server, CLI arg parsing, config loading
2. `handlers/health.rs` - GET /health
3. `handlers/models.rs` - GET /v1/models
4. `handlers/chat.rs` - POST /v1/chat/completions (the main endpoint)

### Phase 5: Backends (Day 11-15)
1. `backend/litellm.rs` - streaming + non-streaming LiteLLM client
2. `backend/ollama.rs` - Ollama classification client
3. `backend/chatgpt.rs` - ChatGPT Responses API streaming + non-streaming
4. `auth/openai.rs` - OAuth token management
5. `transform/` - Chat ↔ Responses API conversion

### Phase 6: Notice & Agent Instructions (Day 16-17)
1. `utils/notice.rs` - formatting, stripping, chunk injection
2. `utils/text.rs` - message text extraction, context building
3. Agent instruction injection from config

### Phase 7: Container & Nix (Day 18-20)
1. `Dockerfile` - multi-stage static build
2. Nix `default.nix` - Rust package build
3. Nix module - config generation + Podman pod orchestration
4. Replace `services.nix` with new module

### Phase 8: Testing & Polish (Day 21-28)
1. Unit tests (75+ tests) - all modules
2. Integration tests (30+ tests) - HTTP endpoints with mock backends
3. Behavioral tests (30+ tests) - ban/reward logic, cache behavior
4. Property-based tests - fuzzing for edge cases
5. Performance benchmarks - cache hit rate, latency
6. Coverage report (>90% target)
7. `clippy`, `cargo fmt`, `cargo doc`
8. Update `README.md`

---

## Testing Strategy

### Test Categories

#### 1. Unit Tests (per module)

**`config.rs`**
```rust
#[cfg(test)]
mod tests {
    #[test]
    fn test_load_valid_config() { /* Parse complete TOML */ }
    
    #[test]
    fn test_missing_optional_fields_use_defaults() { /* Verify defaults */ }
    
    #[test]
    fn test_invalid_tier_rejected() { /* tier: 0 or 11 → error */ }
    
    #[test]
    fn test_model_references_valid() { /* fallbacks point to existing models */ }
    
    #[test]
    fn test_family_ladder_consistency() { /* All models in families exist */ }
    
    #[test]
    fn test_provider_specific_fields() { /* litellm_model for litellm provider */ }
}
```

**`models.rs`**
```rust
#[test]
fn test_model_lookup_by_name() { /* Find model in registry */ }

#[test]
fn test_alias_resolution() { /* "openai-luna" → "gpt-5.6-luna" */ }

#[test]
fn test_hidden_models_excluded_from_list() { /* /v1/models filters hidden */ }

#[test]
fn test_provider_dispatch() { /* Correct backend for each provider */ }
```

**`state.rs`**
```rust
#[test]
fn test_ban_expires_after_timeout() { /* Time-based expiration */ }

#[test]
fn test_success_increments_score() { /* Reward logic */ }

#[test]
fn test_failure_decrements_score() { /* Penalty logic */ }

#[test]
fn test_score_decay_over_time() { /* Exponential decay */ }

#[test]
fn test_high_score_models_preferred() { /* Priority selection */ }

#[test]
fn test_concurrent_state_access() { /* Arc<RwLock> safety */ }
```

**`routing/fallback.rs`**
```rust
#[test]
fn test_bfs_fallback_walk() { /* All fallbacks visited in order */ }

#[test]
fn test_global_fallbacks_appended() { /* Safety net always included */ }

#[test]
fn test_banned_models_skipped() { /* Fallback chain respects bans */ }

#[test]
fn test_circular_fallback_prevented() { /* No infinite loops */ }

#[test]
fn test_metadata_fallback_chain() { /* Cheap-only chain for titles */ }
```

**`routing/escalation.rs`**
```rust
#[test]
fn test_family_escalation_next_step() { /* mistral-small → mistral-medium */ }

#[test]
fn test_family_escalation_at_top() { /* No escalation beyond ladder end */ }

#[test]
fn test_cross_family_escalation() { /* Fallback when family exhausted */ }

#[test]
fn test_retry_detection_english() { /* "didn't work" markers */ }

#[test]
fn test_retry_detection_german() { /* "hat nicht funktioniert" markers */ }

#[test]
fn test_retry_regex_patterns() { /* Complex regex matching */ }
```

**`routing/circuit_breaker.rs`**
```rust
#[test]
fn test_exponential_backoff() { /* 30s → 60s → 120s → ... */ }

#[test]
fn test_max_cooldown_cap() { /* Never exceeds max_cooldown_seconds */ }

#[test]
fn test_success_resets_cooldown() { /* Back to base after success */ }

#[test]
fn test_provider_wide_vs_model_specific() { /* 5xx vs 429 handling */ }
```

**`routing/classifier.rs`**
```rust
#[test]
fn test_prompt_template_rendering() { /* Variables substituted */ }

#[test]
fn test_model_guidance_injection() { /* Custom prompt_line used */ }

#[test]
fn test_banned_models_in_prompt() { /* Banned section populated */ }

#[test]
fn test_parse_model_choice_valid() { /* "mistral-small - reason" */ }

#[test]
fn test_parse_model_choice_with_aliases() { /* Handle aliases */ }

#[test]
fn test_parse_model_choice_fast_variant() { /* "fast" prefix handling */ }

#[test]
fn test_compact_reason() { /* Truncate to 6 words */ }
```

**`utils/notice.rs`**
```rust
#[test]
fn test_notice_formatting() { /* "> **Model**\n> reason" */ }

#[test]
fn test_redirect_formatting() { /* "> **Original → Target**" */ }

#[test]
fn test_strip_notices_from_history() { /* Remove "> **Model**" lines */ }

#[test]
fn test_strip_model_notices_from_context() { /* Clean classification context */ }
```

**`utils/text.rs`**
```rust
#[test]
fn test_message_text_string() { /* Simple string content */ }

#[test]
fn test_message_text_array() { /* Array of text parts */ }

#[test]
fn test_routing_context_truncation() { /* Last 4 messages, 800 chars each */ }

#[test]
fn test_metadata_request_detection() { /* Title/summary markers */ }

#[test]
fn test_coding_request_detection() { /* Coding markers */ }
```

#### 2. Integration Tests (HTTP endpoints)

**`tests/integration.rs`**
```rust
use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;

#[tokio::test]
async fn test_health_endpoint() {
    let app = create_test_app();
    let response = app
        .oneshot(Request::builder().uri("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    
    assert_eq!(response.status(), StatusCode::OK);
    let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
    let health: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(health["status"], "ok");
}

#[tokio::test]
async fn test_models_endpoint() {
    let app = create_test_app();
    let response = app
        .oneshot(Request::builder().uri("/v1/models").body(Body::empty()).unwrap())
        .await
        .unwrap();
    
    assert_eq!(response.status(), StatusCode::OK);
    let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
    let models: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(models["data"].as_array().unwrap().len() > 0);
    assert!(!models["data"].as_array().unwrap().iter().any(|m| m["id"] == "gpt-5.6-luna-openai")); // hidden
}

#[tokio::test]
async fn test_chat_completions_with_mock_backend() {
    // Mock LiteLLM server
    let mock_server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .respond_with(ResponseTemplate::new(200)
            .set_body_json(serde_json::json!({
                "choices": [{"message": {"content": "Hello!"}}]
            })))
        .mount(&mock_server)
        .await;
    
    let app = create_test_app_with_backend(mock_server.uri());
    let response = app
        .oneshot(Request::builder()
            .method("POST")
            .uri("/v1/chat/completions")
            .header("content-type", "application/json")
            .body(Body::from(serde_json::to_string(&serde_json::json!({
                "model": "auto",
                "messages": [{"role": "user", "content": "Hello"}]
            })).unwrap()))
            .unwrap())
        .await
        .unwrap();
    
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_fallback_on_backend_failure() {
    // First backend fails, second succeeds
    let mock_server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .respond_with(ResponseTemplate::new(500))
        .up_to_n_times(1)
        .mount(&mock_server)
        .await;
    
    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .respond_with(ResponseTemplate::new(200)
            .set_body_json(serde_json::json!({
                "choices": [{"message": {"content": "Fallback worked!"}}]
            })))
        .mount(&mock_server)
        .await;
    
    let app = create_test_app_with_backend(mock_server.uri());
    let response = app
        .oneshot(Request::builder()
            .method("POST")
            .uri("/v1/chat/completions")
            .header("content-type", "application/json")
            .body(Body::from(serde_json::to_string(&serde_json::json!({
                "model": "auto",
                "messages": [{"role": "user", "content": "Test fallback"}]
            })).unwrap()))
            .unwrap())
        .await
        .unwrap();
    
    assert_eq!(response.status(), StatusCode::OK);
    let body = hyper::body::to_bytes(response.into_body()).await.unwrap();
    assert!(String::from_utf8_lossy(&body).contains("Fallback worked!"));
}

#[tokio::test]
async fn test_streaming_response() {
    let mock_server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .respond_with(ResponseTemplate::new(200)
            .set_body_string("data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n\
                              data: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n\
                              data: [DONE]\n\n"))
        .mount(&mock_server)
        .await;
    
    let app = create_test_app_with_backend(mock_server.uri());
    let response = app
        .oneshot(Request::builder()
            .method("POST")
            .uri("/v1/chat/completions")
            .header("content-type", "application/json")
            .body(Body::from(serde_json::to_string(&serde_json::json!({
                "model": "auto",
                "stream": true,
                "messages": [{"role": "user", "content": "Stream test"}]
            })).unwrap()))
            .unwrap())
        .await
        .unwrap();
    
    assert_eq!(response.headers()["content-type"], "text/event-stream");
}
```

#### 3. Behavioral Tests (Ban/Reward Logic)

**`tests/behavioral.rs`**
```rust
#[tokio::test]
async fn test_successful_model_not_banned() {
    let mut state = AppState::new(test_config());
    
    // Simulate 20 successful requests
    for _ in 0..20 {
        state.record_success("deepseek-v4-flash");
    }
    
    // Model should NOT be banned (old logic would ban after 15)
    assert!(!state.is_banned("deepseek-v4-flash"));
    assert!(state.get_score("deepseek-v4-flash") > 10.0);
}

#[tokio::test]
async fn test_user_rejection_bans_model() {
    let mut state = AppState::new(test_config());
    
    // Simulate user saying "didn't work"
    state.record_session_quality_ban("mistral-small", "user rejected result");
    
    assert!(state.is_banned("mistral-small"));
    assert!(state.get_ban_reason("mistral-small").contains("user rejected"));
}

#[tokio::test]
async fn test_quota_exhaustion_bans_model() {
    let mut state = AppState::new(test_config());
    
    // Simulate 429 response
    state.record_http_failure("qwen3.8-max", 429);
    
    assert!(state.is_banned("qwen3.8-max"));
    assert!(state.get_ban_reason("qwen3.8-max").contains("quota"));
}

#[tokio::test]
async fn test_auth_failure_bans_model() {
    let mut state = AppState::new(test_config());
    
    // Simulate 401 response
    state.record_http_failure("gpt-5.6-terra", 401);
    
    assert!(state.is_banned("gpt-5.6-terra"));
    assert!(state.get_ban_reason("gpt-5.6-terra").contains("auth"));
}

#[tokio::test]
async fn test_high_score_models_preferred_in_routing() {
    let mut state = AppState::new(test_config());
    
    // Give deepseek-v4-flash high score
    for _ in 0..10 {
        state.record_success("deepseek-v4-flash");
    }
    
    // Route similar request
    let chosen = state.select_model_for_classification("fix bug in code", true);
    
    // Should prefer high-score model
    assert_eq!(chosen, "deepseek-v4-flash");
}

#[tokio::test]
async fn test_score_decay_over_time() {
    let mut state = AppState::new(test_config());
    
    // Give model high score
    for _ in 0..10 {
        state.record_success("qwen3.7-plus");
    }
    
    let initial_score = state.get_score("qwen3.7-plus");
    
    // Advance time by 5 minutes (decay interval)
    state.advance_time(Duration::from_secs(300));
    state.apply_decay();
    
    let decayed_score = state.get_score("qwen3.7-plus");
    assert!(decayed_score < initial_score);
    assert!(decayed_score > initial_score * 0.9); // ~5% decay
}
```

#### 4. Cache Tests

**`tests/cache.rs`**
```rust
#[tokio::test]
async fn test_pattern_cache_hit() {
    let mut cache = ClassificationCache::new(test_config());
    
    // "hello" should match pattern → mistral-small
    let result = cache.classify("hello", false).await;
    assert_eq!(result.model, "mistral-small");
    assert_eq!(result.source, "pattern"); // No LLM call
}

#[tokio::test]
async fn test_exact_cache_hit() {
    let mut cache = ClassificationCache::new(test_config());
    
    // First call (LLM)
    let result1 = cache.classify("fix bug in main.rs", true).await;
    assert_eq!(result1.source, "llm");
    
    // Second call (cache)
    let result2 = cache.classify("fix bug in main.rs", true).await;
    assert_eq!(result2.model, result1.model);
    assert_eq!(result2.source, "exact"); // Cache hit
}

#[tokio::test]
async fn test_similarity_cache_hit() {
    let mut cache = ClassificationCache::new(test_config());
    
    // First call
    let result1 = cache.classify("implement feature X", true).await;
    
    // Similar request (85%+ similarity)
    let result2 = cache.classify("implement feature Y", true).await;
    assert_eq!(result2.model, result1.model);
    assert_eq!(result2.source, "similarity");
}

#[tokio::test]
async fn test_cache_ttl_expiration() {
    let mut cache = ClassificationCache::new(test_config());
    
    // Populate cache
    cache.classify("test", false).await;
    
    // Advance time beyond TTL
    cache.advance_time(Duration::from_secs(301));
    
    // Should miss cache
    let result = cache.classify("test", false).await;
    assert_eq!(result.source, "llm");
}

#[tokio::test]
async fn test_cache_hit_rate() {
    let mut cache = ClassificationCache::new(test_config());
    
    let requests = vec![
        ("hello", false),
        ("fix bug", true),
        ("implement feature", true),
        ("hello", false), // Repeat
        ("fix bug", true), // Repeat
        ("write tests", true),
        ("hello", false), // Repeat
    ];
    
    let mut hits = 0;
    for (text, has_tools) in requests {
        let result = cache.classify(text, has_tools).await;
        if result.source != "llm" {
            hits += 1;
        }
    }
    
    let hit_rate = hits as f64 / requests.len() as f64;
    assert!(hit_rate > 0.4); // At least 40% cache hit rate
}
```

#### 5. Property-Based Tests (Fuzzing)

**`tests/properties.rs`**
```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn test_fallback_chain_no_infinite_loop(
        models in prop::collection::vec(any::<String>(), 1..10)
    ) {
        let config = generate_test_config_with_models(&models);
        let chain = build_fallback_chain("test-model", &config);
        
        // Chain must terminate
        assert!(chain.len() <= models.len() * 2);
    }
    
    #[test]
    fn test_ban_expires_deterministically(
        seconds in 1..1000u64
    ) {
        let mut state = AppState::new(test_config());
        state.ban_model("test", Duration::from_secs(seconds), "test");
        
        // Advance time past ban
        state.advance_time(Duration::from_secs(seconds + 1));
        
        assert!(!state.is_banned("test"));
    }
    
    #[test]
    fn test_score_never_negative(
        successes in 0..100u32,
        failures in 0..100u32
    ) {
        let mut state = AppState::new(test_config());
        
        for _ in 0..successes {
            state.record_success("test");
        }
        for _ in 0..failures {
            state.record_failure("test");
        }
        
        assert!(state.get_score("test") >= 0.0);
    }
    
    #[test]
    fn test_config_parsing_idempotent(
        config_str in any_config_string()
    ) {
        let config1 = parse_config(&config_str);
        let config2 = parse_config(&config_str);
        
        assert_eq!(config1.is_ok(), config2.is_ok());
    }
}
```

#### 6. Performance Tests

**`tests/performance.rs`**
```rust
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn benchmark_classification_cache(c: &mut Criterion) {
    let mut cache = ClassificationCache::new(test_config());
    
    c.bench_function("classify_with_cache", |b| {
        b.iter(|| {
            black_box(async {
                cache.classify("fix bug in code", true).await
            })
        })
    });
}

fn benchmark_fallback_chain(c: &mut Criterion) {
    let config = test_config();
    
    c.bench_function("build_fallback_chain", |b| {
        b.iter(|| {
            black_box(build_fallback_chain("deepseek-v4-flash", &config))
        })
    });
}

criterion_group!(benches, benchmark_classification_cache, benchmark_fallback_chain);
criterion_main!(benches);
```

### Test Coverage Goals

| Component | Unit Tests | Integration Tests | Behavioral Tests | Target Coverage |
|-----------|------------|-------------------|------------------|-----------------|
| Config | 10+ | - | - | 95% |
| Models | 8+ | - | - | 90% |
| State | 15+ | - | 10+ | 95% |
| Routing | 20+ | 5+ | 15+ | 90% |
| Cache | 10+ | - | 5+ | 95% |
| Handlers | - | 10+ | - | 85% |
| Backends | - | 15+ | - | 80% |
| Utils | 12+ | - | - | 90% |
| **Total** | **75+** | **30+** | **30+** | **>90%** |

### Test Execution

```bash
# Run all tests
cargo test

# Run with coverage
cargo tarpaulin --out Html

# Run benchmarks
cargo bench

# Run property-based tests (longer)
cargo test --release -- --ignored

# Run integration tests with mock server
cargo test --test integration

# Run behavioral tests
cargo test --test behavioral
```

### Continuous Integration

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable
      
      - name: Run tests
        run: cargo test --all-features
      
      - name: Check formatting
        run: cargo fmt -- --check
      
      - name: Run clippy
        run: cargo clippy -- -D warnings
      
      - name: Check coverage
        run: |
          cargo install cargo-tarpaulin
          cargo tarpaulin --out Xml
          # Upload to codecov.io
```

---

## Dependencies

```toml
[dependencies]
axum = { version = "0.8", features = ["macros"] }
tokio = { version = "1", features = ["full"] }
reqwest = { version = "0.12", features = ["json", "stream", "rustls-tls"], default-features = false }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
toml = "0.8"
thiserror = "2"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
jsonwebtoken = "9"
regex = "1"
chrono = "0.4"
tower = "0.5"
tower-http = { version = "0.6", features = ["cors", "trace"] }
futures = "0.3"
tokio-stream = "0.1"
base64 = "0.22"

[dev-dependencies]
tokio-test = "0.4"
mockall = "0.13"
wiremock = "0.6"
proptest = "1.5"
criterion = { version = "0.5", features = ["html_reports"] }
test-log = "0.2"
pretty_assertions = "1.4"

[[bench]]
name = "cache_bench"
harness = false
```

---

## Key Differences from Python

| Aspect | Python (current) | Rust (new) |
|--------|------------------|------------|
| Model knowledge | Hardcoded in `MODEL_ROUTING` | Config file, hot-reloadable |
| Prompts | Hardcoded string in function | Config template with variables |
| Markers | Hardcoded sets/tuples | Config lists |
| Tiers/escalation | Hardcoded dicts | Config families + tiers |
| Runtime | Python + uvicorn in container | Static binary in scratch container |
| Image size | ~500MB (Python runtime) | ~15MB (static binary) |
| Error handling | Exceptions, some swallowed | `thiserror` + `Result<T>`, no panics |
| Concurrency | asyncio event loop | Tokio runtime, fine-grained async |
| Config reload | Restart required | SIGHUP or file watcher (future) |
| Distribution | Nix only (Python source) | OCI image (any container runtime) |
