# OpenCode Auto Router

The OpenCode Auto Router gives OpenCode a single default model, `local/auto`. You use OpenCode normally; the router chooses a suitable backend for each request and reports the model at the end of the response.

The module is enabled on development machines through `features.development.enable`.

## Why It Exists

Different models are useful for different work. A small model is sufficient for a translation, while a difficult debugging session benefits from a stronger agentic model. Selecting models manually for every request is distracting and wastes provider capacity.

The router therefore follows three design choices:

1. Use a local classifier so routing decisions do not require another cloud request.
2. Choose the least expensive model expected to complete the task well.
3. Keep provider failures and inadequate answers recoverable without hiding which model was used.

You can still select any model manually when you need predictable behavior.

## Request Flow

```mermaid
flowchart LR
    user["User"] --> opencode["OpenCode<br/>local/auto"]
    opencode --> router["Auto Router<br/>127.0.0.1:4000"]
    router --> classifier["Local classifier<br/>Ollama"]
    classifier --> router
    router --> litellm["LiteLLM<br/>Mistral and OpenCode Go"]
    router --> chatgpt["ChatGPT backend<br/>OpenAI OAuth"]
    litellm --> router
    chatgpt --> router
    router --> opencode
```

For an automatic request:

1. OpenCode sends the conversation and available tools to the router.
2. Ollama classifies the task locally. `llama3.2:3b` is tried first and `qwen3:8b` is its classifier fallback.
3. The router selects a backend based on task complexity, tool use, model capability, and subscription limits.
4. LiteLLM normalizes Mistral and OpenCode Go behind one local OpenAI-compatible API. ChatGPT subscription models are called directly because they use a different OAuth API.
5. The router streams the answer back to OpenCode.

## Model Selection

Models are listed once below in the approximate order of work they are intended to handle. The local classifier uses the complete conversation, not only the latest sentence.

| Model | Provider | Intended use |
| --- | --- | --- |
| `mistral-small` | Mistral | Chat, translation, summaries, titles, and simple questions without tools |
| `mistral-medium` | Mistral | Architecture, planning, reviews, and analysis without tools |
| `deepseek-v4-flash` | OpenCode Go | Default for routine coding, debugging, shell work, tests, and file edits |
| `deepseek-v4-pro` | OpenCode Go | Difficult focused engineering and debugging |
| `qwen3.7-plus` | OpenCode Go | General development, broad edits, and an alternative to DeepSeek Flash |
| `qwen3.7-max` | OpenCode Go | Advanced reasoning without broad tool coordination |
| `qwen3.6-plus` | OpenCode Go | General coding when other OpenCode Go models are unavailable |
| `openai-luna` / `openai-luna-fast` | ChatGPT | Daily agentic development; `fast` uses the priority service tier |
| `openai-sol` / `openai-sol-fast` | ChatGPT | Complex debugging, refactoring, and multi-step tool use |
| `openai-terra` / `openai-terra-fast` | ChatGPT | Ambiguous, critical, or high-stakes work; Terra is the strongest tier |
| `qwen3:8b` | Local Ollama | Manual offline or privacy-sensitive work; not selected as an answer model by auto-routing |

The broad routing policy is:

- Simple, non-agentic requests use Mistral Small.
- Analysis and design without tools use Mistral Medium.
- Routine work with tools uses DeepSeek Flash, Qwen Plus, or Luna.
- Difficult multi-step work uses DeepSeek Pro or Sol.
- The hardest or highest-risk work uses Terra.

## Retries and Fallbacks

The router handles two different failure modes.

**Backend fallback** applies when a provider fails before the first response chunk, for example because of a rate limit, missing authentication, a context limit, or an upstream server error. The router follows the configured fallback chain until a backend accepts the request. Once streaming has started, it cannot replace that response.

**Capability escalation** applies when a backend returned an answer but the user says that the attempt failed or asks it to try again. On the next turn, the router reads the model recorded on the previous response and moves to the next capability tier. This is separate from provider availability fallback and prevents a failed task from repeatedly returning to the same small model.

Every automatic response ends with one minimal routing line:

```text
mistral-small
```

If a backend fallback or capability escalation occurred, the line shows the path:

```text
mistral-small -> mistral-medium
```

There is intentionally no label or prefix so routing metadata stays secondary to the conversation. OpenCode title and summary requests suppress this line entirely.

## Providers and Authentication

LiteLLM is not an AI provider. It is the local compatibility layer at `127.0.0.1:8000` that gives the router one OpenAI-compatible endpoint for Mistral and OpenCode Go.

| Provider | Models | Credential source |
| --- | --- | --- |
| Mistral API | Mistral Small and Medium | SOPS secret `opencode/mistral/api-key`, exposed to LiteLLM as `MISTRAL_API_KEY` |
| OpenCode Go | DeepSeek and Qwen cloud models | SOPS secret `opencode/opencode-go/api-key`, exposed to LiteLLM as `OPENCODE_GO_API_KEY` |
| ChatGPT subscription | Luna, Sol, Terra, and fast variants | OpenCode OAuth entry in `~/.local/share/opencode/auth.json` |
| Local Ollama | Classifier models and manual `qwen3:8b` | No external credential |

The SOPS secrets are rendered into a systemd-managed environment file and passed only to the LiteLLM container. They are not stored in `litellm.yaml`.

ChatGPT authentication works differently. OpenCode creates the OAuth entry through its OpenAI authentication plugin. The host file `~/.local/share/opencode/auth.json` is mounted into the router container as `/var/lib/opencode/auth.json`. The router reads the `openai` OAuth entry, refreshes expired access tokens with its refresh token, and writes refreshed credentials back to the same mounted file. It then calls the ChatGPT Codex backend directly with the account ID from the OAuth data.

## Manual Selection

Select `local/auto` for normal use. To bypass classification and automatic fallback, choose a specific `local/<model>` entry in OpenCode, for example `local/openai-terra` or `local/qwen3:8b`.

## Components

| Component | Address | Responsibility |
| --- | --- | --- |
| `opencode-auto-router` | `127.0.0.1:4000` | Classification, backend selection, ChatGPT OAuth, fallback, and response metadata |
| `opencode-litellm` | `127.0.0.1:8000` | OpenAI-compatible adapter for Mistral and OpenCode Go |
| `opencode-ollama` | `127.0.0.1:11434` | Local classifier and offline model runtime |
| `opencode-auto-router-sync-models.service` | n/a | Pulls configured Ollama models and removes stale ones |

All three containers run rootless in one Podman pod and communicate through localhost.

## Operations

The services are user services:

```bash
systemctl --user status podman-opencode-ollama.service
systemctl --user status podman-opencode-litellm.service
systemctl --user status podman-opencode-auto-router.service
systemctl --user status opencode-auto-router-sync-models.service
```

Check the local endpoints:

```bash
curl http://127.0.0.1:11434/api/tags
curl http://127.0.0.1:4000/health
```

After changing the module, rebuild the Home Manager configuration and restart OpenCode. OpenCode loads provider configuration only at startup.
