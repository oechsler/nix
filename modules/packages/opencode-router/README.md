# OpenCode Router

The OpenCode Router gives OpenCode a single default model, `local/auto`. You use OpenCode normally; the router chooses a suitable backend for each request and reports the model at the end of the response.

The router is enabled whenever `features.development.opencode.enable` is enabled. Set `features.development.opencode.classifier` to `local` for Ollama classification or `cloud` for classification through a small cloud model without running Ollama.

## Architecture

```
User → OpenCode (local/auto) → Router (127.0.0.1:4000) → Classifier (Ollama or LiteLLM)
                                    ↓
User ← OpenCode ← Router ← LiteLLM (127.0.0.1:8000) or ChatGPT OAuth
```

The router is a Rust binary that runs as a systemd user service inside a Podman pod. It exposes an OpenAI-compatible `/v1/chat/completions` endpoint. On each request, it classifies the task, selects a backend, forwards the request, and streams the response back.

### Components

- **`opencode-router`** at `127.0.0.1:4000` — Classification, backend selection, ChatGPT OAuth, fallback, and response metadata
- **`opencode-litellm`** at `127.0.0.1:8000` — OpenAI-compatible adapter for Mistral and OpenCode Go
- **`opencode-ollama`** at `127.0.0.1:11434` — Optional local classifier and offline model runtime
- **`opencode-router-sync-models.service`** — On local-classifier hosts, pulls configured Ollama models and removes stale ones

The containers run rootless in one Podman pod (`opencode-router`) and communicate through localhost. Cloud-classifier hosts run only LiteLLM and the router; local-classifier hosts additionally run Ollama.

## Endpoints

The router exposes an OpenAI-compatible API:

- **`POST /v1/chat/completions`** — Main endpoint. Accepts OpenAI chat completions format, returns streaming or non-streaming responses with `local/auto` as the model.
- **`GET /v1/models`** — Lists available models (including `local/auto` and any manually selectable models).
- **`GET /health`** — Returns router health status, including circuit breaker state and cache statistics.

## Usage

### Activation

Enable the router in your host configuration:

```nix
features.development.opencode.enable = true;
features.development.opencode.classifier = "local"; # or "cloud"
```

This activates the router, LiteLLM, and (for `local` classifier) Ollama as systemd user services.

### Module Options

The home-manager module exposes extensive options under `programs.opencode-router`:

**Core settings:**

- `enable` — Enable the router
- `host` — Bind address (default: `0.0.0.0`)
- `port` — Bind port (default: `4000`)
- `logLevel` — Log level: `trace`, `debug`, `info`, `warn`, `error` (default: `info`)
- `image` — OCI image name (default: `opencode-router:latest`)
- `imagePackage` — Built OCI image derivation (set by the package)

**Classifier:**

- `classifier.backend` — `local` (Ollama) or `cloud` (LiteLLM)
- `classifier.model` — Local classifier model (default: `qwen3:8b`)
- `classifier.timeoutSeconds` — Classification timeout (default: `8`)
- `classifier.cacheTtlSeconds` — Classification cache TTL (default: `300`)

**Models:**

- `models` — Attribute set of model definitions. Each model has:
  - `description` — Model description for classification prompt
  - `family` — Model family for escalation ladder
  - `provider` — Backend provider: `litellm`, `chatgpt`, or `ollama`
  - `tier` — Capability tier (1=trivial, 10=strongest)
  - `fallbacks` — Ordered fallback chain
  - `litellmModel` — LiteLLM model identifier (for `litellm` provider)
  - `apiKeyEnv` — Environment variable for API key (e.g., `MISTRAL_API_KEY`)
  - `chatgptModel` — ChatGPT model identifier (for `chatgpt` provider)
  - `hidden` — Hide from client model list
  - `displayName` — Human-readable display name

**Families and escalation:**

- `families` — Attribute set of model families with `ladder` (list of model IDs from weakest to strongest)
- `crossFamilyEscalation` — Map of model ID to next model ID for cross-family escalation
- `defaults.model` — Default model when classification fails
- `defaults.globalFallbacks` — Safety net appended to every fallback chain
- `defaults.metadataFallbackChain` — Cheap-only chain for title/summary generation

**Prompts:**

- `prompts.classification` — Classification prompt template
- `prompts.guidance` — General guidance text
- `prompts.modelGuidance` — Per-model guidance lines (attribute set)

**Markers:**

- `markers.retry` — Retry detection patterns (literal strings)
- `markers.retryPatterns` — Retry detection regex patterns
- `markers.metadata` — Metadata request patterns
- `markers.coding` — Coding request patterns

**Bans:**

- `bans.authSeconds` — Ban duration on auth errors (default: `600`)
- `bans.exhaustionSeconds` — Ban duration on quota exhaustion (default: `900`)
- `bans.sessionQualitySeconds` — Ban duration on user rejection (default: `600`)

**Performance:**

- `performance.successWeight` — Points per successful request (default: `1.0`)
- `performance.failureWeight` — Points deducted per failure (default: `-2.0`)
- `performance.rewardThreshold` — Successes before priority (default: `5`)
- `performance.decayFactor` — Score decay factor (default: `0.95`)
- `performance.decayIntervalSeconds` — Decay interval (default: `300`)

**Circuit breaker:**

- `circuitBreaker.baseCooldownSeconds` — Base cooldown (default: `30`)
- `circuitBreaker.maxCooldownSeconds` — Max cooldown (default: `300`)

**Cache:**

- `cache.enabled` — Enable caching (default: `true`)
- `cache.ttlSeconds` — Cache TTL (default: `300`)
- `cache.pattern.enabled` — Regex-based classification cache (default: `true`)
- `cache.exact.enabled` — Exact message hash matching (default: `true`)
- `cache.similarity.enabled` — N-gram similarity matching (default: `true`)
- `cache.similarity.threshold` — Similarity threshold (default: `0.85`)
- `cache.similarity.maxEntries` — LRU cache size (default: `1000`)
- `cache.llm.enabled` — LLM classification cache (default: `true`)

**Notice:**

- `notice.format` — Notice format (default: `"> **{display_name}**\n> {reason}"`)
- `notice.redirectFormat` — Redirect notice format (default: `"> **{original_display} → {display_name}**\n> {reason}"`)

**ChatGPT OAuth:**

- `chatgpt.tokenUrl` — OAuth token URL
- `chatgpt.clientId` — OAuth client ID
- `chatgpt.responsesUrl` — Responses API URL
- `chatgpt.accountClaimUrl` — Account claim URL
- `chatgpt.authFile` — Auth file path (default: `/var/lib/opencode/auth.json`)

**Ollama:**

- `ollamaModels` — Models to pull into Ollama

**API keys:**

- `litellmApiKeys` — API keys for LiteLLM providers (env-var-name → sops-secret-path)

Example:

```nix
litellmApiKeys = {
  MISTRAL_API_KEY = "opencode/mistral/api-key";
  OPENCODE_GO_API_KEY = "opencode/opencode-go/api-key";
};
```

**Generated files:**

- `routerConfigFile` — Generated `router.toml` path (internal)
- `litellmConfigFile` — Generated `litellm.yaml` path (internal)

### Manual Model Selection

Select `local/auto` for normal use. A specific `local/<model>` entry, for example `local/gpt-5.6-terra`, bypasses classification and capability escalation but retains reasoning display, tool support, persistence instructions, and availability fallback. Local-classifier hosts additionally expose `local/qwen3:8b`.

## Operations

The services are user services:

```bash
systemctl --user status podman-opencode-ollama.service
systemctl --user status podman-opencode-litellm.service
systemctl --user status podman-opencode-router.service
systemctl --user status opencode-router-sync-models.service
```

The Ollama and model-sync services exist only on local-classifier hosts.

Check the local endpoints:

```bash
curl http://127.0.0.1:11434/api/tags
curl http://127.0.0.1:4000/health
```

After changing the module, rebuild the Home Manager configuration and restart OpenCode. OpenCode loads provider configuration only at startup.

## Development

### Build the package

```bash
nix build .#packages.x86_64-linux.default
```

### Build the OCI image

```bash
nix build .#packages.x86_64-linux.image
```

### Development shell

```bash
nix develop .#devShells.x86_64-linux.default
```

Provides: `rustc`, `cargo`, `cargo-watch`, `rustfmt`, `clippy`.

### Run tests

```bash
cd modules/packages/opencode-router/rust && cargo test
```

### Run the router locally

```bash
cd modules/packages/opencode-router/rust
OPENCODER_CONFIG=config/default.toml cargo run
```

The router reads the config from `$OPENCODER_CONFIG` (default: `/etc/opencode-router/config.toml`) and listens on `127.0.0.1:4000` by default.

## Source Layout

```
modules/packages/opencode-router/
├── flake.nix              # Sub-flake: package, OCI image, home-manager module
├── README.md              # This file
├── rust/                  # Rust router implementation
│   ├── Cargo.toml
│   ├── Cargo.lock
│   ├── config/
│   │   └── default.toml   # Default router configuration (routing prompt, fallbacks)
│   ├── src/
│   │   ├── main.rs        # Entry point: Axum server, CLI config loading
│   │   ├── lib.rs         # Library root
│   │   ├── config.rs      # Configuration types (router.toml schema)
│   │   ├── error.rs       # Error types and HTTP error mapping
│   │   ├── models.rs      # Shared data models (request/response types)
│   │   ├── state.rs       # Application state (circuit breaker, cache, bans)
│   │   ├── auth/
│   │   │   └── openai.rs  # ChatGPT OAuth token refresh and management
│   │   ├── backend/
│   │   │   ├── chatgpt.rs # ChatGPT Responses API client
│   │   │   ├── litellm.rs # LiteLLM OpenAI-compatible client
│   │   │   └── ollama.rs  # Local Ollama client
│   │   ├── handlers/
│   │   │   ├── chat.rs    # /v1/chat/completions endpoint
│   │   │   ├── health.rs  # /health endpoint
│   │   │   └── models.rs  # /v1/models endpoint
│   │   ├── routing/
│   │   │   ├── classifier.rs  # Classification prompt and parsing
│   │   │   ├── escalation.rs  # Capability escalation logic
│   │   │   └── fallback.rs    # Backend fallback chain walker
│   │   ├── transform/
│   │   │   ├── chat_to_responses.rs     # ChatGPT → Responses API adapter
│   │   │   └── responses_to_chat.rs     # Responses API → Chat adapter
│   │   └── utils/
│   │       ├── notice.rs  # Routing notice injection/stripping
│   │       ├── tasks.rs   # Title/summary request detection
│   │       └── text.rs    # Text truncation and helpers
│   └── tests/             # Integration tests and fixtures
└── nix/                   # Nix packaging and configuration
    ├── module.nix         # Unified home-manager options interface
    ├── router.nix         # Generates router.toml from Nix options
    ├── litellm.nix        # Generates litellm.yaml from Nix options
    ├── client.nix         # Configures OpenCode client (config.json, auth.json)
    ├── services.nix       # Podman container orchestration (pod + services)
    ├── secrets.nix        # SOPS secrets management for API keys
    └── package.nix        # Rust package build and OCI image
```

The home-manager module at `modules/home-manager/programs/opencode.nix` is a thin interface that imports the package module and sets model configuration.

Feature options remain in `modules/system/features.nix`, and individual hosts select the classifier in their host configuration.
