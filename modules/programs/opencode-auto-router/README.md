# OpenCode Auto Router

The OpenCode Auto Router automatically selects the best AI model for your task. It provides OpenCode with a default model, `local/auto`, which uses a lightweight local Ollama model to classify each request and route it to the most suitable cloud backend.

This module is automatically enabled on development machines via `features.development.enable`.

Manual model selection is also available through the OpenCode provider:

- `local/mistral-small`
- `local/mistral-medium`
- `local/deepseek-v4-pro`
- `local/deepseek-v4-flash`
- `local/openai-luna`
- `local/openai-luna-fast`
- `local/openai-sol`
- `local/openai-sol-fast`
- `local/openai-terra`
- `local/openai-terra-fast`
- `local/qwen3.7-max`
- `local/qwen3.7-plus`
- `local/qwen3.6-plus`
- `local/qwen3:8b`

## Design Philosophy

The Auto Router is built on three core principles:

1. **Automatic Optimization**: Users should not need to think about which model to use. The system automatically selects the most cost-effective model that can handle the task competently.

2. **Cost Efficiency**: By routing simple tasks to cheaper models and reserving expensive models for complex work, we minimize costs without sacrificing quality.

3. **Reliability**: Automatic fallbacks ensure that if a model fails, the system gracefully degrades to the next best option without user intervention.

## Architecture

```text
OpenCode
  -> opencode-auto/auto at http://127.0.0.1:4000/v1
  -> opencode-auto-router container
  -> local qwen3:8b router model via Ollama
  -> selected cloud backend
```

The system consists of four main components:

- `opencode-ollama`: serves the local routing models (`qwen3:8b`, `llama3.2:3b`) on `127.0.0.1:11434`
- `opencode-litellm`: exposes cloud models through an OpenAI-compatible API on `127.0.0.1:8000`
- `opencode-auto-router`: exposes the single OpenCode-facing OpenAI-compatible API on `127.0.0.1:4000`
- `opencode-auto-router-pull-models.service`: pulls the configured Ollama models after Ollama starts

## How It Works

When you send a request to OpenCode:

1. The request is received by the auto-router at `http://127.0.0.1:4000/v1`
2. A local `qwen3:8b` model classifies the request to determine the task type
3. The router selects the most appropriate model based on:
   - Task complexity
   - Required capabilities
   - Cost efficiency
4. The request is forwarded to the selected cloud backend
5. You receive your answer from the optimal model

If a backend fails before sending the first response chunk (e.g., due to rate limits, context limits, or server errors), the router automatically tries fallback models and informs you in the chat:

```
deepseek-v4-pro → qwen3.7-plus
```

Streaming responses can only fallback before the first upstream chunk is sent.

## Available Models

The Auto Router supports the following models, grouped by provider:

### Mistral
- `mistral-small`: Cheapest option for simple tasks like chat, summaries, and translations
- `mistral-medium`: Better for architecture, reviews, analysis, and planning tasks

### DeepSeek
- `deepseek-v4-flash`: Fast and cost-effective for simple to medium coding tasks and quick fixes
- `deepseek-v4-pro`: Default choice for most coding, debugging, system administration, and tool-heavy work

### Qwen
- `qwen3.7-plus`: Good all-rounder for general development and debugging
- `qwen3.7-max`: Strong reasoning and coding capabilities for complex tasks and advanced problem solving
- `qwen3.6-plus`: Cost-effective option for architecture, reviews, analysis, and broad planning
- `qwen3:8b`: Local model available for testing and offline/privacy-critical tasks (not auto-routed)

### OpenAI
- `openai-luna`: General-purpose coding, editing, shell commands, daily development tasks
- `openai-luna-fast`: Fastest ChatGPT option for routine development at high throughput
- `openai-sol`: Strong model for complex debugging, refactoring, and tool-heavy development
- `openai-sol-fast`: Fast Sol variant for solid coding with quick turnaround
- `openai-terra`: Most capable model for the hardest agentic coding, critical bugs, ambiguous exploration, and high-stakes system administration
- `openai-terra-fast`: Faster Terra variant for urgent hard problems when latency matters

## Routing Logic

The router uses the following decision tree for model selection:

- Simple chat, summaries, translations → `mistral-small`
- Simple to medium coding, quick fixes → `deepseek-v4-flash`
- Most coding, debugging, system tasks → `deepseek-v4-pro`
- General development, debugging → `qwen3.7-plus`
- Complex tasks, refactoring → `qwen3.7-max`
- Architecture, reviews, planning → `qwen3.6-plus` or `mistral-medium`
- Hardest, riskiest tasks → `openai-terra`

## Providers and Authentication

The Auto Router connects to the following AI providers:

### OpenCode Go
We use OpenCode Go as our primary provider for most cloud models. This service provides access to:
- DeepSeek models (`deepseek-v4-flash`, `deepseek-v4-pro`)
- Qwen models (`qwen3.7-plus`, `qwen3.7-max`, `qwen3.6-plus`)
- OpenAI models (`openai-luna`, `openai-sol`, `openai-terra` and their fast variants)

Authentication for OpenCode Go models is handled automatically through the OpenCode infrastructure.

### Mistral
Mistral models (`mistral-small`, `mistral-medium`) are accessed through LiteLLM, which serves as our local proxy to aggregate all backend connections. LiteLLM handles authentication via API keys configured in its configuration.

### Local Models
The `qwen3:8b` model runs locally via Ollama and requires no external authentication. It is used primarily for request classification.

### OpenAI/ChatGPT
OpenCode authenticates with ChatGPT/OpenAI through `opencode-openai-codex-auth`. The auto-router reuses the OAuth tokens stored in `~/.local/share/opencode/auth.json` and refreshes them when needed.

The ChatGPT backend endpoint contains `codex` in the URL as it uses the official Codex CLI/OAuth backend path. Model slugs are:

- `gpt-5.6-terra`
- `gpt-5.6-sol`
- `gpt-5.6-luna`

Fast variants use `service_tier: priority`.

## Fallback Mechanism

If a backend fails before sending the first response chunk (e.g., due to rate limits, context limits, or server errors), the router automatically tries fallback models. Fallbacks are shown in-chat as:

```
Routed to: original -> fallback
```

Streaming responses can only fallback before the first upstream chunk is sent.

## Components

| Component | Port | Description |
|-----------|------|-------------|
| `opencode-ollama` | 11434 | Serves local routing models (`qwen3:8b`, `llama3.2:3b`) |
| `opencode-litellm` | 8000 | Exposes cloud models via OpenAI-compatible API |
| `opencode-auto-router` | 4000 | Single OpenCode-facing OpenAI-compatible API |
| `opencode-auto-router-pull-models.service` | – | Pulls configured Ollama models after Ollama starts |

## ChatGPT Subscription Auth

OpenCode authenticates with ChatGPT/OpenAI via `opencode-openai-codex-auth`. The auto-router reuses the OAuth tokens stored in `~/.local/share/opencode/auth.json` and refreshes them as needed.

The ChatGPT backend endpoint contains `codex` in the URL as it uses the official Codex CLI/OAuth backend path. Model slugs are:

- `gpt-5.6-terra`
- `gpt-5.6-sol`
- `gpt-5.6-luna`

Fast variants use `service_tier: priority`.

## Operations

### Check Services

```bash
systemctl status podman-opencode-ollama.service
systemctl status podman-opencode-litellm.service
systemctl status podman-opencode-auto-router.service
systemctl status opencode-auto-router-pull-models.service
```

### Check Endpoints

```bash
curl http://127.0.0.1:11434/api/tags
curl http://127.0.0.1:4000/health
```

### Restart OpenCode

OpenCode must be restarted after configuration changes as it loads configuration only at startup.
