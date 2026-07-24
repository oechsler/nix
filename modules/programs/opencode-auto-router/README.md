# OpenCode Auto Router

The OpenCode Auto Router is a smart system that automatically selects the best AI model for your task. It provides OpenCode with a default model, `local/auto`, which uses a lightweight local Ollama model to classify each request and route it to the most suitable cloud backend.

This module is automatically enabled on development machines via `features.development.enable`.

You can also manually select a model through the OpenCode provider:

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

## How It Works

Think of the Auto Router as a **smart traffic director** for your AI requests. Here is what happens when you ask OpenCode a question:

1. **You send a request** (e.g., "Debug this Python code" or "Explain NixOS to me").
2. **The router receives it** at `http://127.0.0.1:4000/v1`.
3. **A local AI model (`qwen3:8b`)** analyzes your request to understand what kind of task it is.
4. **The router picks the best model** for that task, balancing capability and cost.
5. **Your request is sent** to the selected cloud model.
6. **You get your answer** from the most suitable AI.

If the selected model fails (e.g., due to rate limits or errors), the router **automatically tries a fallback model** and lets you know with a message like `Routed to: original -> fallback`.

## Model Selection Explained

The Auto Router selects models based on **two key factors**:

1. **Task Type**: What kind of task are you asking for?
2. **Cost vs. Capability**: What is the minimum capability needed to solve the task well?

### Model Capability Matrix

| Model | Best For | Cost | Speed | Capability |
|-------|----------|------|-------|------------|
| `mistral-small` | Simple chat, summaries, translations | $ | ⚡⚡⚡⚡⚡ | Low |
| `deepseek-v4-flash` | Quick fixes, simple coding tasks | $$ | ⚡⚡⚡⚡ | Medium |
| `deepseek-v4-pro` | **Default choice** for most tasks | $$$ | ⚡⚡⚡ | High |
| `qwen3.7-plus` | General development, debugging | $$$ | ⚡⚡ | Medium-High |
| `qwen3.7-max` | Complex tasks, refactoring | $$$$ | ⚡⚡ | High |
| `qwen3.6-plus` | Architecture, reviews, planning | $$$$ | ⚡⚡ | High |
| `mistral-medium` | Architecture, reviews, planning | $$$$ | ⚡⚡ | High |
| `openai-terra` | **Highest capability** for critical tasks | $$$$$ | ⚡ | Very High |
| `openai-sol` | Complex debugging, refactoring | $$$$$ | ⚡ | High |
| `openai-luna` | General-purpose coding | $$$$$ | ⚡ | Medium |

### When to Use Which Model

- **Simple questions?** → `mistral-small` (cheapest, fast)
- **Quick code fixes?** → `deepseek-v4-flash` (fast and cheap)
- **Most coding tasks?** → `deepseek-v4-pro` (default, good balance)
- **General development?** → `qwen3.7-plus` (good all-rounder)
- **Complex refactoring?** → `qwen3.7-max` (strong reasoning)
- **Architecture decisions?** → `qwen3.6-plus` or `mistral-medium`
- **Critical bugs?** → `openai-terra` (most capable)

> 💡 **Pro Tip**: The Auto Router **always picks the cheapest model that can do the job well**. You don't need to worry about selecting the right model yourself!

## Architecture

```mermaid
graph TD
    A[Your Request] -->|e.g. "Debug this code"| B[OpenCode]
    B -->|Sends to| C[Auto Router
    http://127.0.0.1:4000/v1]
    C --> D[Local Classifier
    qwen3:8b via Ollama]
    D -->|"This is a debugging task"| C
    C --> E[Selects Best Model
    e.g. deepseek-v4-pro]
    E --> F[Cloud Backend
    via LiteLLM]
    F -->|Response| B
    B -->|Answer| A
```

## Available Backends

| Model | Description | Use Case |
|-------|-------------|----------|
| `mistral-small` | Mistral cloud model via LiteLLM | Cheap/simple tasks (greetings, summaries, translations) |
| `deepseek-v4-flash` | OpenCode Go DeepSeek V4 Flash | Simple to medium coding tasks, quick fixes |
| `deepseek-v4-pro` | OpenCode Go DeepSeek V4 Pro | Default model for most coding, debugging, and system tasks |
| `qwen3.7-plus` | OpenCode Go Qwen3.7 Plus | General development and debugging |
| `qwen3.7-max` | OpenCode Go Qwen3.7 Max | Complex tasks, refactoring, advanced problem solving |
| `qwen3.6-plus` | OpenCode Go Qwen3.6 Plus | Architecture, reviews, analysis, planning |
| `mistral-medium` | Mistral cloud model via LiteLLM | Architecture, reviews, analysis, planning |
| `qwen3:8b` | Local Qwen3 8B via Ollama | Testing, offline use, privacy-critical tasks (not auto-routed) |
| `openai-terra` | ChatGPT 5.6 Terra | Hardest agentic coding, critical bugs, high-stakes tasks |
| `openai-sol` | ChatGPT 5.6 Sol | Complex debugging, refactoring, tool-heavy development |
| `openai-luna` | ChatGPT 5.6 Luna | General-purpose coding, daily development tasks |
| `openai-terra-fast` | ChatGPT 5.6 Terra Fast | Urgent high-stakes tasks with priority tier |
| `openai-sol-fast` | ChatGPT 5.6 Sol Fast | Fast Sol variant for quick turnaround |
| `openai-luna-fast` | ChatGPT 5.6 Luna Fast | Fastest ChatGPT option for routine development |

## Auto-Routing Logic

The router optimizes for the cheapest model that can complete the task effectively:

- Simple chat, summaries, short explanations → `mistral-small`
- Simple to medium coding, quick fixes → `deepseek-v4-flash`
- Most coding, debugging, system tasks → `deepseek-v4-pro`
- General development, debugging → `qwen3.7-plus`
- Complex tasks, refactoring → `qwen3.7-max`
- Architecture, reviews, planning → `qwen3.6-plus` or `mistral-medium`
- Hardest, riskiest tasks → `openai-terra`

Local `qwen3:8b` is used primarily for classification but is available for manual selection.

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
