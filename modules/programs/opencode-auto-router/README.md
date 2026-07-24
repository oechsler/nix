# OpenCode Auto Router

This module provides OpenCode with a default model, `local/auto`. A lightweight local Ollama model classifies each request and routes it to the most suitable cloud backend.

It is enabled automatically on development machines via `features.development.enable`.

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

## Overview

The auto router acts as an intelligent intermediary between OpenCode and various AI models. It:

- Analyzes your request to determine the task type.
- Selects the most cost-effective model capable of handling the task.
- Routes the request to the appropriate backend.
- Handles fallbacks if the primary model fails.

This ensures optimal performance and cost efficiency for all types of tasks.

## Architecture

```
OpenCode
  -> opencode-auto/auto at http://127.0.0.1:4000/v1
  -> opencode-auto-router container
  -> local qwen3:8b router model via Ollama
  -> selected cloud backend
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
