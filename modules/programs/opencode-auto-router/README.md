# OpenCode Auto Router

This module gives OpenCode one default model, `local/auto`. A small local Ollama model classifies each request, then the router sends the actual answer request to a cloud backend.

It is enabled automatically on development machines via `features.development.enable`.

Manual model selection is also available through the same OpenCode provider:

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

## Architecture

```text
OpenCode
  -> opencode-auto/auto at http://127.0.0.1:4000/v1
  -> opencode-auto-router container
  -> local qwen3:8b router model via Ollama
  -> selected cloud backend
```

Backends currently available to the router:

- `mistral-small`: Mistral cloud model through LiteLLM, intended for cheap/simple cloud work such as greetings and summaries.
- `deepseek-v4-flash`: OpenCode Go DeepSeek V4 Flash cloud model. Fast and cost-effective for simple to medium coding tasks.
- `deepseek-v4-pro`: OpenCode Go DeepSeek V4 Pro cloud model, intended as the default auto-routed answer model for OpenCode, coding, system administration, debugging, reasoning, and tool-heavy work.
- `qwen3.7-plus`: OpenCode Go Qwen3.7 Plus cloud model. Good coding performance for general development and debugging.
- `qwen3.7-max`: OpenCode Go Qwen3.7 Max cloud model. Strong reasoning and coding capabilities for complex tasks and advanced problem solving.
- `qwen3.6-plus`: OpenCode Go Qwen3.6 Plus cloud model. Cost-effective option for architecture, reviews, analysis, and broad non-private planning.
- `mistral-medium`: Mistral cloud model through LiteLLM, intended for architecture, reviews, analysis, and broad planning.
- `qwen3:8b`: Local Qwen3 8B model running on Ollama. Available for manual selection as `local/qwen3:8b`. Useful for testing and offline/privacy-critical tasks. Slower and less capable than cloud models; not selected by auto-routing.
- `openai-terra`: ChatGPT 5.6 Terra – most capable model for the hardest agentic coding, critical bugs, ambiguous exploration, and high-stakes system administration.
- `openai-sol`: ChatGPT 5.6 Sol – strong model for complex debugging, refactoring, and tool-heavy development with moderate reasoning demands.
- `openai-luna`: ChatGPT 5.6 Luna – general-purpose coding, editing, shell commands, daily development tasks.
- `openai-terra-fast`: ChatGPT 5.6 Terra Fast – faster Terra variant for urgent hard problems when latency matters.
- `openai-sol-fast`: ChatGPT 5.6 Sol Fast – fast Sol variant for solid coding with quick turnaround.
- `openai-luna-fast`: ChatGPT 5.6 Luna Fast – fastest ChatGPT option for routine development at high throughput.

Auto-routing optimizes for the cheapest model that is likely to complete the task well:

- Simple chat, summaries, short explanations, translation, and low-risk non-agentic tasks go to `mistral-small`.
- Simple to medium coding tasks, quick fixes, and straightforward reasoning go to `deepseek-v4-flash`.
- Most coding, OpenCode agent, shell/system inspection, debugging, NixOS/admin, container, service, log, build, and test work goes to `deepseek-v4-pro`.
- General development, debugging, and medium-complexity coding tasks go to `qwen3.7-plus`.
- Complex tasks, refactoring, and advanced problem solving go to `qwen3.7-max`.
- Architecture, reviews, analysis, and broad non-private planning go to `qwen3.6-plus`.
- Broad architecture, design tradeoffs, reviews, planning, and analysis-heavy work goes to `mistral-medium`.
- The hardest, riskiest, most ambiguous, or high-stakes work goes to `openai-terra`.
- Local Qwen is used primarily for classification, but is also available as a manually-selectable answer model for testing and offline use.

If a backend fails before the response starts, the router tries fallback models automatically.
Examples: rate limits, context-limit errors, temporary backend failures, missing ChatGPT auth,
or upstream 5xx responses. Streaming responses can only fallback before the first upstream
chunk is sent. Fallbacks are shown in-chat as `Routed to: original -> fallback`.

## Components

- `opencode-ollama`: serves the local routing models (`qwen3:8b`, `llama3.2:3b`) on `127.0.0.1:11434`.
- `opencode-litellm`: exposes cloud models through an OpenAI-compatible API on `127.0.0.1:8000`.
- `opencode-auto-router`: exposes the single OpenCode-facing OpenAI-compatible API on `127.0.0.1:4000`.
- `opencode-auto-router-pull-models.service`: pulls the configured Ollama models after Ollama starts.

## ChatGPT Subscription Auth

OpenCode itself authenticates ChatGPT/OpenAI through `opencode-openai-codex-auth`. The auto-router reuses the resulting `~/.local/share/opencode/auth.json` OAuth tokens and refreshes them when needed.

The ChatGPT backend endpoint still contains `codex` in the URL because that is the official Codex CLI/OAuth backend path used by the existing OpenCode plugin. The actual model name sent to the API is configured per routing entry via the `chatgpt_model` field (e.g. `terra`, `sol`, `luna` with `-fast` variants).

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
