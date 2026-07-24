import json
import logging
import os
import time
from typing import Any

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

app = FastAPI()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("opencode-auto-router")

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

LITELLM_URL = os.environ.get("LITELLM_URL", "http://127.0.0.1:8000/v1")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
ROUTER_MODELS = os.environ.get(
    "ROUTER_MODELS", "qwen3:8b,llama3.2:3b"
).split(",")
DEFAULT_MODEL = os.environ.get("DEFAULT_MODEL", "deepseek-v4-pro")
OPENAI_CHATGPT_MODEL = os.environ.get("OPENAI_CHATGPT_MODEL", "gpt-5.5")
OPENCODE_AUTH_FILE = os.environ.get(
    "OPENCODE_AUTH_FILE", "/var/lib/opencode/auth.json"
)

# ---------------------------------------------------------------------------
# Model routing configuration
#
# Each entry defines the model description (used in the classification prompt)
# and its fallback chain. The router picks the cheapest model suited to the
# task; if it fails, it walks the fallback chain before giving up.
# ---------------------------------------------------------------------------

MODEL_ROUTING = {
    "mistral-small": {
        "description": (
            "Mistral Vibe Code (EU, flat-rate €20/mo, SOFT fair-usage cap). "
            "Fast model for greetings, summaries, simple Q&A, titles, translation. "
            "PREFERRED for simple non-agentic tasks – NOT for tool-heavy workflows."
        ),
        "fallbacks": ["mistral-medium", "deepseek-v4-flash", "openai-chatgpt"],
    },
    "mistral-medium": {
        "description": (
            "Mistral Vibe Code (EU, flat-rate €20/mo, SOFT fair-usage cap). "
            "Strong model for architecture, design tradeoffs, reviews, planning, "
            "analysis. PREFERRED for EU sovereignty and reasoning-heavy tasks without tools."
        ),
        "fallbacks": ["openai-chatgpt", "deepseek-v4-flash", "qwen3.7-max"],
    },
    "deepseek-v4-flash": {
        "description": (
            "OpenCode Go DeepSeek V4 Flash (€10/mo, HARD cap: 31,650 req/5h). "
            "PRIMARY for coding and debugging with tools: file edits, shell commands, "
            "search, refactors, NixOS, containers. Largest Go quota – first choice "
            "for tool-based development work."
        ),
        "fallbacks": ["openai-chatgpt", "mistral-medium", "qwen3.7-plus"],
    },
    "deepseek-v4-pro": {
        "description": (
            "OpenCode Go DeepSeek V4 Pro (€10/mo, HARD cap: 3,450 req/5h). "
            "For the hardest problems when flash is insufficient. Limited quota."
        ),
        "fallbacks": ["openai-chatgpt", "qwen3.7-plus", "mistral-medium"],
    },
    "openai-chatgpt": {
        "description": (
            "ChatGPT Plus subscription (flat-rate €20/mo, SOFT extended-usage cap). "
            "Best for complex multi-step agentic workflows: deep exploration, "
            "ambiguous problems, high-stakes reviews, system administration. "
            "Use when Go quota is exhausted or task demands top-tier reasoning with tools."
        ),
        "fallbacks": ["deepseek-v4-flash", "mistral-medium", "qwen3.7-plus"],
    },
    "qwen3.7-plus": {
        "description": (
            "OpenCode Go Qwen3.7 Plus (€10/mo, HARD cap: 4,300 req/5h). "
            "Solid general-purpose coding model with tools. Good alternative "
            "when flash or ChatGPT are saturated."
        ),
        "fallbacks": ["openai-chatgpt", "deepseek-v4-flash", "mistral-medium"],
    },
    "qwen3.7-max": {
        "description": (
            "OpenCode Go Qwen3.7 Max (€10/mo, HARD cap: 950 req/5h). "
            "Specialist for advanced reasoning. Very tight quota – use only "
            "when mistral-medium is unavailable."
        ),
        "fallbacks": ["openai-chatgpt", "mistral-medium", "qwen3.7-plus"],
    },
    "qwen3.6-plus": {
        "description": (
            "OpenCode Go Qwen3.6 Plus (€10/mo). General-purpose coding. "
            "Use when other Go models are saturated."
        ),
        "fallbacks": ["qwen3.7-plus", "openai-chatgpt", "mistral-medium"],
    },
    "qwen3:8b": {
        "description": (
            "Local Qwen3 8B model on Ollama. Limited offline model for testing "
            "and light tasks when privacy is critical. Not for auto-routing."
        ),
        "fallbacks": ["mistral-small", "deepseek-v4-flash", "deepseek-v4-pro"],
    },
}

DIRECT_MODELS = set(MODEL_ROUTING)

# ---------------------------------------------------------------------------
# ChatGPT / OpenAI OAuth
#
# ChatGPT subscription traffic uses the same backend path and OAuth flow as
# the OpenAI Codex CLI. The routed model is OPENAI_CHATGPT_MODEL.
# ---------------------------------------------------------------------------

OPENAI_TOKEN_URL = "https://auth.openai.com/oauth/token"
OPENAI_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
CHATGPT_RESPONSES_URL = "https://chatgpt.com/backend-api/codex/responses"
OPENAI_ACCOUNT_CLAIM = "https://api.openai.com/auth"

# ---------------------------------------------------------------------------
# Message helpers
# ---------------------------------------------------------------------------


def message_text(message: dict[str, Any]) -> str:
    content = message.get("content", "")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(str(item.get("text", "")))
        return "\n".join(parts)
    return str(content)


def routing_context(messages: list[dict[str, Any]]) -> str:
    """Last few conversation turns, truncated, for the classification prompt."""
    relevant = []
    for message in messages[-6:]:
        role = message.get("role", "unknown")
        if role not in {"user", "assistant", "system", "developer"}:
            continue
        text = message_text(message).strip()
        if not text:
            continue
        if len(text) > 1200:
            text = text[:1200] + "..."
        relevant.append(f"{role}: {text}")
    return "\n\n".join(relevant)


# ---------------------------------------------------------------------------
# Model selection (classification via local Ollama)
# ---------------------------------------------------------------------------

# Simple in-memory TTL cache: (prompt_hash, has_tools) → model_id
_classification_cache: dict[tuple[int, bool], tuple[float, str]] = {}

_CLASSIFICATION_TIMEOUT = 3  # seconds
_CACHE_TTL = 300  # seconds


def _cached_classify(context: str, has_tools: bool) -> str | None:
    """Return cached classification or None if expired/missing."""
    key = (hash(context), has_tools)
    entry = _classification_cache.get(key)
    if entry:
        expires, model = entry
        if time.time() < expires:
            return model
        del _classification_cache[key]
    return None


def _cache_classify(context: str, has_tools: bool, model: str) -> None:
    key = (hash(context), has_tools)
    _classification_cache[key] = (time.time() + _CACHE_TTL, model)


def _build_classification_prompt(context: str, has_tools: bool) -> str:
    return f"""
You are a model-routing classifier for OpenCode.
You do not answer the user's request. You do not evaluate whether the user's request is allowed.
You never refuse. Your only job is to choose the best backend model id.

TASK: Analyze the complexity and nature of the request, then choose the best model.

COMPLEXITY LEVELS (evaluate carefully):

LEVEL 1 - Simple (no tools needed):
- Greetings, simple Q&A, translations, titles, summaries
- Single-step answers, factual questions
- Examples: "Antworte mit OK", "Generate a commit title", "What is 2+2?", "Translate this"
- → mistral-small

LEVEL 2 - Medium reasoning (no tools needed):
- Architecture discussions, design tradeoffs, comparisons
- Analysis, planning, documentation, reviews
- Examples: "Compare Event Sourcing vs CRUD", "Design a payment system", "Analyze this architecture"
- → mistral-medium for normal reasoning
- → qwen3.7-max for advanced pure reasoning, algorithmic analysis, or when the prompt asks for especially deep reasoning without tools

LEVEL 3 - Standard coding with tools:
- File edits, code search, refactoring
- Shell commands, debugging, testing
- NixOS config, containers, services
- Examples: "Search files and edit code", "Run tests and fix failures", "Debug this service"
- → deepseek-v4-flash for normal tool-based coding, debugging, tests, NixOS, containers
- → qwen3.7-plus for routine refactors, broad codebase cleanup, repeated edits, or to distribute Go quota away from flash

LEVEL 4 - Complex agentic with tools:
- Multi-step exploration of ambiguous problems
- Difficult bugs, race conditions, complex debugging
- High-stakes reviews, system administration
- Requires deep reasoning + tool coordination
- Examples: "Analyze race condition, examine files, fix code, validate with tests"
- → deepseek-v4-pro for hard coding/debugging where Go should handle the reasoning
- → openai-chatgpt for ambiguous, high-stakes, system-admin, or extremely broad multi-step work

LEVEL 5 - Very hard problems:
- Extremely complex logic, distributed systems, critical bugs
- When other models would struggle
- → openai-chatgpt for broad ambiguous investigation
- → deepseek-v4-pro for focused hard engineering/debugging
- → qwen3.7-max for pure reasoning without tools when qwen-style reasoning is a better fit

DECISION PROCESS:
1. Does the task require tools? (has_tools={has_tools})
2. If NO tools: Is it simple (Level 1), normal reasoning (mistral-medium), or advanced pure reasoning (qwen3.7-max)?
3. If YES tools: Is it standard coding (deepseek-v4-flash), broad routine refactor (qwen3.7-plus), hard focused debugging (deepseek-v4-pro), or broad ambiguous/high-stakes agentic work (openai-chatgpt)?
4. Choose the model that matches the level.

HARD ROUTING CONSTRAINTS:
- If has_tools=True and the task mentions logs, services, containers, production, ambiguous failures, broad investigation, or system administration → openai-chatgpt
- If has_tools=True, do not choose qwen3.7-max unless the request is primarily advanced reasoning and not broad tool coordination
- qwen3.7-max is mainly for advanced pure reasoning without tools

IMPORTANT:
- All subscriptions are flat-rate, no per-token costs
- Go models have hard 5h quotas but large capacity (Flash: 31k, Pro: 3.45k, Plus: 4.3k, Max: 950)
- Mistral/ChatGPT have soft monthly caps, use freely
- Use multiple Go models intentionally: flash for normal tools, qwen3.7-plus for routine/broad edits, deepseek-v4-pro for hard focused debugging, qwen3.7-max for advanced pure reasoning
- Reserve ChatGPT for broad ambiguous or high-stakes multi-step agentic tasks

Available backends:
{json.dumps({m: cfg["description"] for m, cfg in MODEL_ROUTING.items()}, indent=2)}

Return exactly one model id and nothing else.

Conversation context:
{context}
""".strip()


def _parse_model_choice(text: str) -> str | None:
    cleaned = text.strip().lower()
    for model in DIRECT_MODELS:
        if model in cleaned:
            # Never return a classifier model as the backend
            if model in ROUTER_MODELS:
                continue
            return model
    return None


async def _classify(messages: list[dict[str, Any]], has_tools: bool) -> str:
    """Ask the local Ollama router models which cloud backend to use.

    Uses in-memory cache to skip classification for repeated prompts.
    Falls back to DEFAULT_MODEL after _CLASSIFICATION_TIMEOUT seconds.
    """
    context = routing_context(messages)
    if not context.strip():
        return DEFAULT_MODEL

    cached = _cached_classify(context, has_tools)
    if cached:
        logger.info("classification cache hit model=%s", cached)
        return cached

    prompt = _build_classification_prompt(context, has_tools)

    for model in ROUTER_MODELS:
        try:
            async with httpx.AsyncClient(timeout=_CLASSIFICATION_TIMEOUT) as client:
                response = await client.post(
                    f"{OLLAMA_URL}/api/generate",
                    json={
                        "model": model,
                        "prompt": prompt,
                        "stream": False,
                        "options": {"temperature": 0},
                    },
                )
                response.raise_for_status()
                choice = _parse_model_choice(response.json().get("response", ""))
                if choice:
                    _cache_classify(context, has_tools, choice)
                    return choice
        except Exception:
            continue

    # All classifiers failed or timed out
    return DEFAULT_MODEL


# ---------------------------------------------------------------------------
# Metadata request detection
#
# opencode occasionally sends title/summary generation requests with no tools.
# We detect these and suppress the [Routed to: …] notice so the result is
# clean (just the title/summary text).
# ---------------------------------------------------------------------------

_TITLE_SUMMARY_MARKERS = {
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
}


def _is_metadata_request(messages: list[dict[str, Any]], has_tools: bool) -> bool:
    if has_tools:
        return False
    text = routing_context(messages).lower()
    return any(marker in text for marker in _TITLE_SUMMARY_MARKERS)


# ---------------------------------------------------------------------------
# Fallback chain
# ---------------------------------------------------------------------------


def _fallback_chain(model: str) -> list[str]:
    candidates = [model] + MODEL_ROUTING.get(model, {}).get("fallbacks", [])
    seen = set()
    result = []
    for candidate in candidates:
        if candidate in DIRECT_MODELS and candidate not in seen:
            result.append(candidate)
            seen.add(candidate)
    return result or [model]


# ---------------------------------------------------------------------------
# Response helpers
# ---------------------------------------------------------------------------


def _model_notice(model: str, original_model: str | None = None) -> str:
    return ""

def _model_notice_text(model: str, original_model: str | None = None) -> str:
    if original_model and original_model != model:
        return f"[{original_model} -> {model}]"
    return f"[{model}]"


def _notice_chunk(model: str, content: str) -> dict[str, Any]:
    return {
        "id": "opencode-auto-router-notice",
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": model,
        "choices": [
            {"index": 0, "delta": {"content": content}, "finish_reason": None}
        ],
    }


def _error_text(response: httpx.Response) -> str:
    try:
        return response.text
    except Exception:
        return ""


def _add_agent_instruction(body: dict[str, Any], has_tools: bool) -> dict[str, Any]:
    """Prepend a system instruction when the model has tools (agent mode)."""
    if not has_tools:
        return body

    forwarded = dict(body)
    messages = list(forwarded.get("messages", []))
    messages.insert(
        0,
        {
            "role": "system",
            "content": (
                "You are running inside OpenCode as an agent with tools. "
                "When the user asks you to inspect the computer, workspace, files, "
                "repository, services, logs, or command output, use the provided tools "
                "instead of saying you cannot access the system."
            ),
        },
    )
    forwarded["messages"] = messages
    return forwarded


# ---------------------------------------------------------------------------
# ChatGPT / Responses API format conversion
# ---------------------------------------------------------------------------


def _chat_to_responses_content(
    content: Any, assistant: bool = False
) -> list[dict[str, str]]:
    item_type = "output_text" if assistant else "input_text"
    if isinstance(content, str):
        return [{"type": item_type, "text": content}]
    if isinstance(content, list):
        result = []
        for part in content:
            if isinstance(part, dict) and part.get("type") == "text":
                result.append({"type": item_type, "text": str(part.get("text", ""))})
        return result
    return [{"type": item_type, "text": str(content)}]


def _chat_tools_to_responses_tools(tools: Any) -> list[dict[str, Any]]:
    if not isinstance(tools, list):
        return []

    result = []
    for tool in tools:
        if not isinstance(tool, dict):
            continue
        if tool.get("type") == "function" and isinstance(tool.get("function"), dict):
            func = tool["function"]
            name = func.get("name")
            if not name:
                continue
            result.append({
                "type": "function",
                "name": name,
                "description": func.get("description", ""),
                "parameters": func.get(
                    "parameters", {"type": "object", "properties": {}}
                ),
            })
            continue
        if tool.get("name"):
            result.append(tool)
    return result


def _chat_tool_choice_to_responses_tool_choice(tool_choice: Any) -> Any:
    if isinstance(tool_choice, dict) and tool_choice.get("type") == "function":
        function = tool_choice.get("function")
        if isinstance(function, dict) and function.get("name"):
            return {"type": "function", "name": function["name"]}
    return tool_choice


def _chat_to_responses_body(body: dict[str, Any]) -> dict[str, Any]:
    input_items = []
    for message in body.get("messages", []):
        role = message.get("role", "user")
        if role == "system":
            role = "developer"
        if role == "tool":
            input_items.append({
                "type": "function_call_output",
                "call_id": message.get("tool_call_id", "unknown"),
                "output": message.get("content", ""),
            })
            continue
        # Convert assistant tool_calls to function_call items
        tool_calls = message.get("tool_calls")
        if role == "assistant" and tool_calls:
            text = message.get("content") or ""
            if text:
                input_items.append({
                    "type": "message",
                    "role": role,
                    "content": _chat_to_responses_content(text, assistant=True),
                })
            for tc in tool_calls:
                fn = tc.get("function", {})
                input_items.append({
                    "type": "function_call",
                    "call_id": tc.get("id", "unknown"),
                    "name": fn.get("name", "unknown"),
                    "arguments": fn.get("arguments", "{}"),
                })
            continue
        input_items.append({
            "type": "message",
            "role": role,
            "content": _chat_to_responses_content(
                message.get("content", ""), assistant=role == "assistant"
            ),
        })

    response_body: dict[str, Any] = {
        "model": OPENAI_CHATGPT_MODEL,
        "input": input_items,
        "stream": True,
        "store": False,
        "reasoning": {"effort": "high", "summary": "auto"},
        "text": {"verbosity": "medium"},
        "include": ["reasoning.encrypted_content"],
    }
    tools = _chat_tools_to_responses_tools(body.get("tools"))
    if tools:
        response_body["tools"] = tools
    if body.get("tool_choice"):
        response_body["tool_choice"] = _chat_tool_choice_to_responses_tool_choice(
            body["tool_choice"]
        )
    return response_body


# ---------------------------------------------------------------------------
# ChatGPT / Responses API → chat completion format (non-streaming fallback)
# ---------------------------------------------------------------------------


def _responses_to_chat_completion(
    response: dict[str, Any],
    routed_model: str,
    original_model: str | None = None,
    show_notice: bool = True,
) -> dict[str, Any]:
    text_parts = []
    tool_calls = []
    for item in response.get("output", []):
        if item.get("type") == "message":
            for content in item.get("content", []):
                if content.get("type") in {"output_text", "text"}:
                    text_parts.append(content.get("text", ""))
        if item.get("type") == "function_call":
            tool_calls.append({
                "id": item.get("call_id") or item.get("id"),
                "type": "function",
                "function": {
                    "name": item.get("name"),
                    "arguments": item.get("arguments", "{}"),
                },
            })

    content = "".join(text_parts)
    if show_notice:
        content += "\n\n" + _model_notice_text(routed_model, original_model)
    message: dict[str, Any] = {
        "role": "assistant",
        "content": content,
    }
    if tool_calls:
        message["tool_calls"] = tool_calls

    return {
        "id": response.get("id", "chatgpt-response"),
        "object": "chat.completion",
        "created": int(time.time()),
        "model": response.get("model", OPENAI_CHATGPT_MODEL),
        "choices": [{"index": 0, "message": message, "finish_reason": "stop"}],
    }


# ---------------------------------------------------------------------------
# ChatGPT OAuth helpers
# ---------------------------------------------------------------------------


def _decode_jwt_payload(token: str) -> dict[str, Any]:
    try:
        import base64

        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload.encode()).decode())
    except Exception:
        return {}


def _load_openai_auth() -> dict[str, Any] | None:
    try:
        with open(OPENCODE_AUTH_FILE, encoding="utf-8") as handle:
            auth = json.load(handle).get("openai")
        return auth if isinstance(auth, dict) and auth.get("type") == "oauth" else None
    except Exception:
        return None


def _save_openai_auth(auth: dict[str, Any]) -> None:
    try:
        with open(OPENCODE_AUTH_FILE, encoding="utf-8") as handle:
            data = json.load(handle)
        data["openai"] = auth
        with open(OPENCODE_AUTH_FILE, "w", encoding="utf-8") as handle:
            json.dump(data, handle)
    except Exception:
        pass


async def _get_openai_auth() -> tuple[dict[str, Any], str] | None:
    """Return (auth_dict, account_id) or None if auth is unavailable."""
    auth = _load_openai_auth()
    if not auth:
        return None

    # Refresh if token expires within 60 seconds
    if int(auth.get("expires", 0)) <= int(time.time() * 1000) + 60_000:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(
                OPENAI_TOKEN_URL,
                data={
                    "grant_type": "refresh_token",
                    "refresh_token": auth.get("refresh", ""),
                    "client_id": OPENAI_CLIENT_ID,
                },
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
            response.raise_for_status()
            tokens = response.json()
        auth.update({
            "access": tokens["access_token"],
            "refresh": tokens["refresh_token"],
            "expires": int(time.time() * 1000) + int(tokens["expires_in"]) * 1000,
        })
        _save_openai_auth(auth)

    account_id = auth.get("accountId")
    if not account_id:
        account_id = (
            _decode_jwt_payload(auth.get("access", ""))
            .get(OPENAI_ACCOUNT_CLAIM, {})
            .get("chatgpt_account_id")
        )
    return (auth, account_id) if account_id else None


# ---------------------------------------------------------------------------
# ChatGPT streaming backend
# ---------------------------------------------------------------------------


async def _stream_chatgpt(
    body: dict[str, Any],
    routed_model: str,
    fallback_models: list[str] | None = None,
    original_model: str | None = None,
    show_notice: bool = True,
):
    auth_info = await _get_openai_auth()
    if not auth_info:
        if fallback_models:
            return await _stream_to_backend(
                body, fallback_models, routed_model, show_notice
            )
        return JSONResponse(
            {"error": "OpenAI OAuth auth not found. Run opencode auth login for openai."},
            status_code=401,
        )

    auth, account_id = auth_info
    request_body = _chat_to_responses_body(body)
    headers = {
        "Authorization": f"Bearer {auth['access']}",
        "chatgpt-account-id": account_id,
        "OpenAI-Beta": "responses=experimental",
        "originator": "codex_cli_rs",
        "accept": "text/event-stream",
        "content-type": "application/json",
    }

    if not body.get("stream"):
        return await _chatgpt_non_streaming(
            request_body, headers, routed_model, fallback_models, original_model, show_notice
        )

    client = httpx.AsyncClient(timeout=httpx.Timeout(30.0, read=600.0))
    upstream = client.stream(
        "POST", CHATGPT_RESPONSES_URL, json=request_body, headers=headers
    )
    response = await upstream.__aenter__()
    if not response.is_success:
        error_body = (await response.aread()).decode(errors="replace")
        logger.warning(
            "chatgpt upstream failed status=%s body=%s",
            response.status_code,
            error_body,
        )
        await upstream.__aexit__(None, None, None)
        await client.aclose()
        if fallback_models:
            return await _stream_to_backend(
                body, fallback_models, routed_model, show_notice
            )
        return JSONResponse(
            {"error": "ChatGPT upstream failed", "details": error_body},
            status_code=response.status_code,
        )

    async def _iter_chatgpt_sse():
        had_tool_calls = False
        pending_fc_name: str | None = None
        pending_fc_call_id: str | None = None
        fc_index = 0
        try:
            async for line in response.aiter_lines():
                if not line.startswith("data: "):
                    continue
                try:
                    event = json.loads(line[6:])
                except Exception:
                    continue
                event_type = event.get("type")
                if event_type == "response.output_item.added":
                    item = event.get("item", {})
                    if item.get("type") == "function_call":
                        pending_fc_name = item.get("name", "")
                        pending_fc_call_id = item.get("call_id", f"call_{int(time.time())}")
                if event_type in {"response.output_text.delta", "response.text.delta"}:
                    delta = event.get("delta", "")
                    chunk = {
                        "id": event.get("response_id", "chatgpt-response"),
                        "object": "chat.completion.chunk",
                        "created": int(time.time()),
                        "model": request_body["model"],
                        "choices": [
                            {
                                "index": 0,
                                "delta": {"content": delta},
                                "finish_reason": None,
                            }
                        ],
                    }
                    yield f"data: {json.dumps(chunk)}\n\n"
                if event_type == "response.function_call_arguments.done":
                    had_tool_calls = True
                    call_id = pending_fc_call_id or f"call_{int(time.time())}"
                    name = pending_fc_name or "unknown"
                    args = event.get("arguments", "")
                    chunk = {
                        "id": event.get("response_id", "chatgpt-response"),
                        "object": "chat.completion.chunk",
                        "created": int(time.time()),
                        "model": request_body["model"],
                        "choices": [
                            {
                                "index": fc_index,
                                "delta": {
                                    "tool_calls": [
                                        {
                                            "index": fc_index,
                                            "id": call_id,
                                            "type": "function",
                                            "function": {
                                                "name": name,
                                                "arguments": args,
                                            },
                                        }
                                    ]
                                },
                                "finish_reason": None,
                            }
                        ],
                    }
                    fc_index += 1
                    pending_fc_name = None
                    pending_fc_call_id = None
                    yield f"data: {json.dumps(chunk)}\n\n"
                if event_type in {"response.done", "response.completed"}:
                    response_id = event.get("response", {}).get("id", "chatgpt-response")
                    if show_notice:
                        yield f"data: {json.dumps(_notice_chunk(routed_model, '\n\n' + _model_notice_text(routed_model, original_model)))}\n\n"
                    done = {
                        "id": response_id,
                        "object": "chat.completion.chunk",
                        "created": int(time.time()),
                        "model": request_body["model"],
                        "choices": [
                            {"index": 0, "delta": {}, "finish_reason": "tool_calls" if had_tool_calls else "stop"}
                        ],
                    }
                    yield f"data: {json.dumps(done)}\n\n"
                    yield "data: [DONE]\n\n"
        finally:
            await upstream.__aexit__(None, None, None)
            await client.aclose()

    return StreamingResponse(
        _iter_chatgpt_sse(),
        status_code=response.status_code,
        media_type="text/event-stream",
    )


async def _chatgpt_non_streaming(
    request_body: dict[str, Any],
    headers: dict[str, str],
    routed_model: str,
    fallback_models: list[str] | None,
    original_model: str | None,
    show_notice: bool,
):
    async with httpx.AsyncClient(timeout=600) as client:
        response = await client.post(
            CHATGPT_RESPONSES_URL, json=request_body, headers=headers
        )
        if not response.is_success:
            logger.warning(
                "chatgpt upstream failed status=%s body=%s",
                response.status_code,
                response.text,
            )
            try:
                payload = response.json()
            except Exception:
                payload = {"error": "ChatGPT upstream failed", "details": response.text}
            if fallback_models:
                return await _stream_to_backend(body=request_body, candidates=fallback_models, original_model=routed_model)
            return JSONResponse(payload, status_code=response.status_code)

        final_response = None
        for line in response.text.splitlines():
            if not line.startswith("data: "):
                continue
            try:
                event = json.loads(line[6:])
            except Exception:
                continue
            if event.get("type") in {"response.done", "response.completed"}:
                final_response = event.get("response")
        if not final_response:
            return JSONResponse({"error": "No final Codex response"}, status_code=502)
        return JSONResponse(
            _responses_to_chat_completion(
                final_response, routed_model, original_model, show_notice
            )
        )


# ---------------------------------------------------------------------------
# LiteLLM backend (Mistral, DeepSeek via OpenCode Go)
# ---------------------------------------------------------------------------


async def _stream_to_backend(
    body: dict[str, Any],
    candidates: list[str],
    original_model: str,
    show_notice: bool = True,
):
    """Try each candidate in order. Stream on first success, fallback on failure."""
    headers = {"Authorization": "Bearer dummy"}
    stream = bool(body.get("stream"))
    last_status = 502
    last_error: dict[str, Any] = {"error": "No backend candidates available"}

    for index, candidate in enumerate(candidates):
        remaining = candidates[index + 1 :]
        if candidate == "openai-chatgpt":
            return await _stream_chatgpt(
                body, candidate, remaining, original_model, show_notice
            )

        forwarded = dict(body)
        forwarded["model"] = candidate

        if stream:
            client = httpx.AsyncClient(timeout=httpx.Timeout(30.0, read=600.0))
            upstream = client.stream(
                "POST",
                f"{LITELLM_URL}/chat/completions",
                json=forwarded,
                headers=headers,
            )
            response = await upstream.__aenter__()
            if not response.is_success:
                body_text = (await response.aread()).decode(errors="replace")
                logger.warning(
                    "backend failed model=%s status=%s body=%s",
                    candidate,
                    response.status_code,
                    body_text,
                )
                last_status = response.status_code
                last_error = {
                    "error": "Backend failed",
                    "model": candidate,
                    "details": body_text,
                }
                await upstream.__aexit__(None, None, None)
                await client.aclose()
                continue

            async def _iter_litellm_stream(model: str = candidate):
                try:
                    async for line in response.aiter_lines():
                        if line.startswith("data: [DONE]"):
                            if show_notice:
                                yield f"data: {json.dumps(_notice_chunk(model, '\n\n' + _model_notice_text(model, original_model)))}\n\n"
                            yield "data: [DONE]\n\n"
                        else:
                            yield line + "\n"
                finally:
                    await upstream.__aexit__(None, None, None)
                    await client.aclose()

            return StreamingResponse(
                _iter_litellm_stream(),
                status_code=response.status_code,
                media_type=response.headers.get(
                    "content-type", "text/event-stream"
                ),
            )

        # Non-streaming path
        async with httpx.AsyncClient(timeout=600) as client:
            response = await client.post(
                f"{LITELLM_URL}/chat/completions",
                json=forwarded,
                headers=headers,
            )

        if not response.is_success:
            body_text = _error_text(response)
            logger.warning(
                "backend failed model=%s status=%s body=%s",
                candidate,
                response.status_code,
                body_text,
            )
            last_status = response.status_code
            last_error = {
                "error": "Backend failed",
                "model": candidate,
                "details": body_text,
            }
            continue

        payload = response.json()
        for choice in payload.get("choices", []):
            message = choice.get("message")
            if isinstance(message, dict):
                content = str(message.get("content", ""))
                if show_notice:
                    content += "\n\n" + _model_notice_text(candidate, original_model)
                message["content"] = content
        return JSONResponse(payload, status_code=response.status_code)

    return JSONResponse(last_error, status_code=last_status)


# ---------------------------------------------------------------------------
# FastAPI endpoints
# ---------------------------------------------------------------------------


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/models")
async def models() -> dict[str, Any]:
    data = [
        {
            "id": "auto",
            "object": "model",
            "created": 0,
            "owned_by": "opencode-auto-router",
        }
    ]
    for model_id in MODEL_ROUTING:
        if model_id not in ROUTER_MODELS:
            data.append({
                "id": model_id,
                "object": "model",
                "created": 0,
                "owned_by": "opencode-auto-router",
            })
    return {"object": "list", "data": data}


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    body = await request.json()
    messages = body.get("messages", [])
    if not isinstance(messages, list):
        return JSONResponse({"error": "messages must be a list"}, status_code=400)

    requested_model = str(body.get("model", "auto"))
    has_tools = bool(body.get("tools"))

    # If the client already picked a specific model, use it directly.
    # Otherwise classify the request through the local Ollama router.
    target_model = (
        requested_model
        if requested_model in DIRECT_MODELS
        else await _classify(messages, has_tools)
    )

    logger.info(
        "routing requested_model=%s target_model=%s has_tools=%s messages=%s",
        requested_model,
        target_model,
        has_tools,
        len(messages),
    )

    show_notice = (
        not _is_metadata_request(messages, has_tools)
        and requested_model not in DIRECT_MODELS
    )
    body = _add_agent_instruction(body, has_tools)
    candidates = (
        [target_model]
        if requested_model in DIRECT_MODELS
        else _fallback_chain(target_model)
    )

    logger.info(
        "fallback chain target_model=%s candidates=%s",
        target_model,
        candidates,
    )

    return await _stream_to_backend(body, candidates, target_model, show_notice)
