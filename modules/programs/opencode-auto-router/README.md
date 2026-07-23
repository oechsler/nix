# OpenCode Auto Router

This module gives OpenCode one default model, `local/auto`, and routes each request to a local or cloud backend automatically.

It is enabled automatically on development machines via `features.development.enable`.

Manual model selection is also available through the same OpenCode provider:

- `local/qwen3-fast`
- `local/qwen3-deep`
- `local/mistral-medium`
- `local/deepseek-v4-pro`
- `local/openai-chatgpt`

## Architecture

```text
OpenCode
  -> opencode-auto/auto at http://127.0.0.1:4000/v1
  -> opencode-auto-router container
  -> local qwen3:8b router model via Ollama
  -> selected backend
```

Backends currently available to the router:

- `qwen3-fast`: local Ollama model through LiteLLM, used by auto-routing only when local/private/offline handling is explicitly requested and the task is simple.
- `qwen3-deep`: larger local Ollama model through LiteLLM, used by auto-routing only for harder local/private/offline work.
- `mistral-small`: Mistral cloud model through LiteLLM, intended for cheap/simple cloud work such as greetings and summaries.
- `mistral-medium`: Mistral cloud model through LiteLLM, intended for architecture, reviews, analysis, and broad planning.
- `deepseek-v4-pro`: OpenCode Go cloud model through LiteLLM, intended as the default auto-routed answer model for OpenCode, coding, system administration, debugging, reasoning, and tool-heavy work.
- `openai-chatgpt`: ChatGPT subscription model through the ChatGPT OAuth backend, reserved for the hardest agentic coding work, risky broad refactors, difficult bugs, and high-stakes reviews.

Auto-routing optimizes for the cheapest model that is likely to complete the task well:

- Simple chat, summaries, short explanations, translation, and low-risk non-agentic tasks go to `mistral-small`.
- Most coding, OpenCode agent, shell/system inspection, debugging, NixOS/admin, container, service, log, build, and test work goes to `deepseek-v4-pro`.
- Broad architecture, design tradeoffs, reviews, planning, and analysis-heavy work goes to `mistral-medium`.
- The hardest, riskiest, most ambiguous, or high-stakes work goes to `openai-chatgpt`.
- Local Qwen models are used by auto-routing only when the user explicitly asks for local/private/offline handling.

## Components

- `opencode-ollama`: serves local models and the routing model on `127.0.0.1:11434`.
- `opencode-litellm`: exposes local Ollama and Mistral models through an OpenAI-compatible API on `127.0.0.1:8000`.
- `opencode-auto-router`: exposes the single OpenCode-facing OpenAI-compatible API on `127.0.0.1:4000`.
- `opencode-auto-router-pull-models.service`: pulls the configured Ollama models after Ollama starts.

## ChatGPT Subscription Auth

OpenCode itself authenticates ChatGPT/OpenAI through `opencode-openai-codex-auth`. The auto-router reuses the resulting `~/.local/share/opencode/auth.json` OAuth tokens and refreshes them when needed.

The ChatGPT backend endpoint still contains `codex` in the URL because that is the official Codex CLI/OAuth backend path used by the existing OpenCode plugin. The configured model is `gpt-5.5` via `OPENAI_CHATGPT_MODEL`, not a Codex-only model.

## Operations

Check services:

```bash
systemctl status podman-opencode-ollama.service
systemctl status podman-opencode-litellm.service
systemctl status podman-opencode-auto-router.service
systemctl status opencode-auto-router-pull-models.service
```

Check endpoints:

```bash
curl http://127.0.0.1:11434/api/tags
curl http://127.0.0.1:4000/health
```

OpenCode must be restarted after config changes because it loads configuration only at startup.
