import json
import logging
import os
import re
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
    "ROUTER_MODELS", "qwen3:8b"
).split(",")
DEFAULT_MODEL = os.environ.get("DEFAULT_MODEL", "qwen3.7-plus")
OPENCODE_AUTH_FILE = os.environ.get(
    "OPENCODE_AUTH_FILE", "/var/lib/opencode/auth.json"
)
CLASSIFIER_BACKEND = os.environ.get("CLASSIFIER_BACKEND", "local")
USE_LOCAL_CLASSIFIER = CLASSIFIER_BACKEND == "local"
# A neutral, cheap classifier model. Never let the classifier run on a model
# that is also a routing candidate: it would systematically pick itself.
CLOUD_CLASSIFIER_MODEL = os.environ.get(
    "CLOUD_CLASSIFIER_MODEL", "mistral-small"
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
            "Fast model for greetings, Q&A, titles, translation. "
            "Only for trivial tasks; skip for anything substantive."
        ),
        "family": "mistral",
        "fallbacks": ["mistral-medium"],
    },
    "mistral-medium": {
        "description": (
            "Strong model for architecture, design tradeoffs, reviews, planning, "
            "analysis. Capable with and without tools."
        ),
        "family": "mistral",
        "fallbacks": ["qwen3.7-plus", "deepseek-v4-flash"],
    },
    "deepseek-v4-flash": {
        "description": (
            "Fast coding model: bugs, refactors, multi-step changes, file edits, "
            "shell, NixOS, containers. Very high quota (158150 req/month)."
        ),
        "family": "deepseek",
        "fallbacks": ["deepseek-v4-pro", "qwen3.7-plus"],
    },
    "deepseek-v4-pro": {
        "description": (
            "Stronger DeepSeek for complex work: multi-step exploration, "
            "deep analysis with tools. 17150 req/month quota."
        ),
        "family": "deepseek",
        "fallbacks": ["qwen3.7-max", "gpt-5.6-terra"],
    },
    "gpt-5.6-terra": {
        "description": (
            "GPT for complex agentic coding and multi-step exploration. "
            "Strong reasoning and tool use."
        ),
        "family": "gpt",
        "chatgpt_model": "gpt-5.6-terra",
        "fallbacks": ["gpt-5.6-sol"],
    },
    "gpt-5.6-luna-openai": {
        "description": "Direct OpenAI fallback for the OpenCode Go Luna route. Never select automatically.",
        "family": "gpt",
        "chatgpt_model": "gpt-5.6-luna",
        "fallbacks": ["gpt-5.6-terra"],
        "hidden": True,
    },
    "gpt-5.6-sol": {
        "description": (
            "Top-tier GPT for hardest agentic work: ambiguous multi-step "
            "exploration, race conditions, high-stakes system administration, critical bugs. "
            "Strongest model available."
        ),
        "family": "gpt",
        "chatgpt_model": "gpt-5.6-sol",
        "fallbacks": ["qwen3.8-max"],
    },
    "gpt-5.6-luna": {
        "description": (
            "GPT entry tier via OpenCode Go. Good general-purpose model. "
            "10250 req/month quota."
        ),
        "family": "gpt",
        "fallbacks": ["gpt-5.6-luna-openai"],
    },
    "gpt-5.6-terra-fast": {
        "description": (
            "Faster Terra variant for complex tasks at higher throughput."
        ),
        "family": "gpt",
        "chatgpt_model": "gpt-5.6-terra",
        "service_tier": "priority",
        "fallbacks": ["gpt-5.6-sol-fast"],
    },
    "gpt-5.6-sol-fast": {
        "description": (
            "Fast top-tier GPT for hardest debugging when Terra insufficient."
        ),
        "family": "gpt",
        "chatgpt_model": "gpt-5.6-sol",
        "service_tier": "priority",
        "fallbacks": ["gpt-5.6-terra-fast"],
    },
    "gpt-5.6-luna-fast": {
        "description": (
            "Fast entry-tier GPT for simple-to-medium coding. Overflow model."
        ),
        "family": "gpt",
        "chatgpt_model": "gpt-5.6-luna",
        "service_tier": "priority",
        "fallbacks": ["qwen3.7-plus", "deepseek-v4-flash"],
    },
    "qwen3.7-plus": {
        "description": (
            "General development and broad refactors with tools. "
            "Solid coding model. 21600 req/month quota."
        ),
        "family": "qwen",
        "fallbacks": ["qwen3.7-max", "deepseek-v4-flash"],
    },
    "qwen3.8-max": {
        "description": (
            "Top Qwen reasoning model. Complex algorithmic analysis, math, "
            "deep design review. 810 req/month quota."
        ),
        "family": "qwen",
        "fallbacks": ["gpt-5.6-sol", "deepseek-v4-pro"],
    },
    "qwen3.7-max": {
        "description": (
            "Advanced reasoning, complex algorithmic analysis, math. "
            "1690 req/month quota."
        ),
        "family": "qwen",
        "fallbacks": ["qwen3.8-max", "gpt-5.6-terra"],
    },
    "qwen3:8b": {
        "description": (
            "Local Qwen3 8B on Ollama. Limited offline model for "
            "light tasks when privacy critical. Not for auto-routing."
        ),
        "family": "qwen",
        "fallbacks": ["mistral-small"],
    },
}

DIRECT_MODELS = set(MODEL_ROUTING)
MODEL_ALIASES = {
    "openai-luna-fast": "gpt-5.6-luna-fast",
    "openai-luna": "gpt-5.6-luna",
    "openai-sol-fast": "gpt-5.6-sol-fast",
    "openai-sol": "gpt-5.6-sol",
    "openai-terra-fast": "gpt-5.6-terra-fast",
    "openai-terra": "gpt-5.6-terra",
}
CHATGPT_MODELS = {
    m for m, cfg in MODEL_ROUTING.items() if "chatgpt_model" in cfg
}

MODEL_PROVIDERS = {
    "mistral-small": "mistral",
    "mistral-medium": "mistral",
    "deepseek-v4-flash": "opencode-go",
    "deepseek-v4-pro": "opencode-go",
    "gpt-5.6-luna": "opencode-go",
    "gpt-5.6-luna-openai": "openai",
    "qwen3.8-max": "opencode-go",
    "qwen3.7-plus": "opencode-go",
    "qwen3.7-max": "opencode-go",
    "qwen3:8b": "ollama",
    **{model: "chatgpt" for model in CHATGPT_MODELS},
}

MODEL_DISPLAY_NAMES = {
    "auto": "Auto",
    "mistral-small": "Mistral Small",
    "mistral-medium": "Mistral Medium",
    "deepseek-v4-flash": "DeepSeek V4 Flash",
    "deepseek-v4-pro": "DeepSeek V4 Pro",
    "gpt-5.6-luna-fast": "GPT-5.6 Luna Fast",
    "gpt-5.6-luna": "GPT-5.6 Luna",
    "gpt-5.6-sol-fast": "GPT-5.6 Sol Fast",
    "gpt-5.6-sol": "GPT-5.6 Sol",
    "gpt-5.6-terra-fast": "GPT-5.6 Terra Fast",
    "gpt-5.6-terra": "GPT-5.6 Terra",
    "qwen3.8-max": "Qwen3.8 Max",
    "qwen3.7-plus": "Qwen3.7 Plus",
    "qwen3.7-max": "Qwen3.7 Max",
    "qwen3:8b": "Qwen3 8B (Local)",
}

# Ensure every route covers all available providers. The local model is
# filtered out when this host is configured without Ollama.
GLOBAL_FALLBACKS = [
    # Small is only an entry route for trivial requests, never a generic
    # fallback for substantive work or for mistral-medium.
    "mistral-medium",
    "deepseek-v4-flash",
    "gpt-5.6-luna-openai",
    "qwen3:8b",
]

# ---------------------------------------------------------------------------
# Availability circuit breaker
#
# Failures are handled with exponential backoff instead of hard bans so the
# router heals itself: a transient outage (LiteLLM restart, one bad request)
# cools down for a short time, and the cooldown grows only while the provider
# keeps failing. Successful requests reset the backoff.
#
# Failure classes:
# - Infra failures (network errors, 5xx): applied provider-wide, since every
#   model on that provider shares the outage.
# - Rate limits (429) and transient statuses (408, 425): model-specific, the
#   quota belongs to the individual model.
# - Auth failures (401, 403): hard bans until the credentials are fixed, since
#   they do not clear on their own.
#
# Load-balancing rotation: a model that served MODEL_MAX_CONSECUTIVE requests
# in a row is banned for MODEL_ROTATION_BAN_SECONDS, but only while an equally
# capable alternative is available, so the router never dead-ends into a
# configuration where every good model is banned at once.
# ---------------------------------------------------------------------------

_PROVIDER_COOLDOWN_BASE = int(os.environ.get("PROVIDER_COOLDOWN_BASE_SECONDS", "30"))
_PROVIDER_COOLDOWN_MAX = int(os.environ.get("PROVIDER_COOLDOWN_MAX_SECONDS", "300"))
_AUTH_BAN_SECONDS = int(os.environ.get("AUTH_BAN_SECONDS", "600"))
_EXHAUSTION_BAN_SECONDS = int(os.environ.get("EXHAUSTION_BAN_SECONDS", "900"))
_SESSION_QUALITY_BAN_SECONDS = int(os.environ.get("SESSION_QUALITY_BAN_SECONDS", "600"))
MODEL_ROTATION_BAN_SECONDS = int(
    os.environ.get("MODEL_ROTATION_BAN_SECONDS", "120")
)
MODEL_MAX_CONSECUTIVE = int(os.environ.get("MODEL_MAX_CONSECUTIVE", "15"))
_PROVIDER_FAILURE_STATUSES = {408, 425, 429}
_model_cooldown_until: dict[str, float] = {}
_model_ban_until: dict[str, float] = {}
_model_ban_reason: dict[str, str] = {}
_consecutive_routes: dict[str, int] = {}
_consecutive_failures: dict[str, int] = {}
_last_route_model: str | None = None

# ---------------------------------------------------------------------------
# ChatGPT / OpenAI OAuth
#
# ChatGPT subscription traffic uses the same backend path and OAuth flow as
# the OpenAI Codex CLI. The routed model name comes from the chatgpt_model
# field in MODEL_ROUTING.
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


def _strip_model_notices(text: str) -> str:
    """Remove opencode model-notice blockquotes ("> **Model**" tag lines).

    The notices annotate which model answered last. If they leak into the
    classification context they prime the classifier, which then keeps picking
    the same model ("flash answered -> pick flash again" loop).
    """
    return "\n".join(
        line for line in text.splitlines() if not line.startswith(">")
    ).strip()


def _strip_notices_from_history(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Remove router notice blockquotes from assistant messages in history.

    The router prepends a notice block ("> **Model**\\n> reason") to every
    streamed response. Models start imitating it once it appears in the
    conversation history, producing repeated stacked notices. Strip the
    notices before forwarding history to a backend so the pattern never
    appears in model context.
    """
    cleaned = []
    for message in messages:
        if message.get("role") != "assistant":
            cleaned.append(message)
            continue
        content = message.get("content", "")
        if isinstance(content, str) and content.startswith(">"):
            lines = content.splitlines()
            i = 0
            while i < len(lines) and lines[i].startswith(">"):
                i += 1
            while i < len(lines) and not lines[i].strip():
                i += 1
            content = "\n".join(lines[i:])
        cleaned.append({**message, "content": content})
    return cleaned


def routing_context(messages: list[dict[str, Any]]) -> str:
    """Last few conversation turns, truncated, for the classification prompt."""
    relevant = []
    for message in messages[-4:]:
        role = message.get("role", "unknown")
        if role not in {"user", "assistant", "system", "developer"}:
            continue
        text = _strip_model_notices(message_text(message)).strip()
        if not text:
            continue
        if len(text) > 800:
            text = text[:800] + "..."
        relevant.append(f"{role}: {text}")
    return "\n\n".join(relevant)


# ---------------------------------------------------------------------------
# Model selection
# ---------------------------------------------------------------------------

# Simple in-memory TTL cache: (prompt_hash, has_tools) → (model_id, reason)
_classification_cache: dict[tuple[int, bool], tuple[float, str, str]] = {}

_CLASSIFICATION_TIMEOUT = 8  # seconds
_CACHE_TTL = 300  # seconds


def _cached_classify(context: str, has_tools: bool) -> tuple[str, str] | None:
    """Return cached classification (model, reason) or None if expired/missing."""
    key = (hash(context), has_tools)
    entry = _classification_cache.get(key)
    if entry:
        expires, model, reason = entry
        if time.time() < expires:
            return (model, reason)
        del _classification_cache[key]
    return None


def _cache_classify(context: str, has_tools: bool, model: str, reason: str = "") -> None:
    key = (hash(context), has_tools)
    _classification_cache[key] = (time.time() + _CACHE_TTL, model, reason)


def _build_classification_prompt(
    context: str, has_tools: bool, banned_models: list[str] | None = None
) -> str:
    banned_section = ""
    if banned_models:
        banned_section = f"""
Banned/cooldown models (do NOT pick these; choose the best remaining option):
- {", ".join(sorted(banned_models))}
"""
    return f"""
Classify for OpenCode routing. Match approximately based on the task – no rigid 1:1 mapping. Think about what model fits best for THIS specific request. Return: model_id - reason (2-6 words in user's language).

Available models (each with strengths, quotas, and costs – you decide the best fit):
- mistral-small: trivial – greetings, simple Q&A, titles, translations, one-line answers. No tools needed.
- mistral-medium: analysis, architecture, design tradeoffs, planning, reviews, design discussions.
- deepseek-v4-flash: fast coding with tools – file edits, shell, tests, small-to-medium features. High quota, cheap. Good default for most coding.
- qwen3.7-plus: broad multi-file refactors, large-scale changes. Good balance of quality and speed.
- deepseek-v4-pro: deep multi-step exploration, complex debugging with many files.
- qwen3.7-max: advanced reasoning, math, algorithmic analysis.
- qwen3.8-max: deepest reasoning, proofs, formal methods.
- gpt-5.6-luna-fast / gpt-5.6-luna: overflow when DeepSeek/Qwen saturated; strong general purpose.
- gpt-5.6-terra / gpt-5.6-sol: hardest problems – ambiguous production issues, critical bugs, high-stakes system work.
- qwen3:8b (local): only for offline/privacy-critical light tasks.

Guidance (not rules – use your judgment):
- Consider: capability needs, tool usage, quota availability, and how hard the task really is.
- For coding with tools, prefer DeepSeek Flash or Qwen Plus as cost-effective choices; escalate to stronger models when the task demands more reasoning or the cheaper model would fail.
- Math, algorithmics, proofs → Qwen Max models or GPT.
- Architecture/planning/design discussions → Mistral Medium or GPT.
- Never use mistral-small for coding, debugging, shell, NixOS, file edits, or substantive requests, even without tools.
- When in doubt between two models, choose the cheaper/faster one.
- Prefer -fast variants for simple, latency-sensitive overflow.{banned_section}
Approximate quotas (req/month): deepseek-v4-flash:158150, deepseek-v4-pro:17150, qwen3.7-plus:21600, qwen3.7-max:1690, qwen3.8-max:810, gpt-5.6-luna:10250.

Context (has_tools={has_tools}):
{context}
""".strip()


def _compact_reason(reason: str) -> str:
    words = " ".join(reason.strip().strip("`\"'* ").split()).split()
    return " ".join(words[:6]).rstrip(".,;:!?")


def _parse_model_choice(text: str) -> tuple[str, str] | None:
    """Parse ``model_id - reason`` while tolerating common model formatting."""
    cleaned = text.strip().strip("`\"'")
    for model in sorted(DIRECT_MODELS | set(MODEL_ALIASES), key=len, reverse=True):
        if model in ROUTER_MODELS:
            continue
        match = re.match(
            rf"^\s*\**{re.escape(model)}\**\s*(?:-|–|—|:)\s*(.+)$",
            cleaned,
            flags=re.IGNORECASE | re.DOTALL,
        )
        if not match:
            continue
        canonical_model = MODEL_ALIASES.get(model, model)
        reason_text = match.group(1).strip()
        if canonical_model.endswith("-fast"):
            reason_text = re.sub(r"^[-–—]?\s*fast\s*[-–—:]\s*", "", reason_text, flags=re.IGNORECASE)
        else:
            fast_match = re.match(r"^fast\s*[-–—:]\s*(.+)$", reason_text, flags=re.IGNORECASE)
            if fast_match:
                fast_model = f"{canonical_model}-fast"
                if fast_model in DIRECT_MODELS:
                    canonical_model = fast_model
                    reason_text = fast_match.group(1)
        reason = _compact_reason(reason_text)
        if reason:
            return (canonical_model, reason)
    return None


async def _classify(messages: list[dict[str, Any]], has_tools: bool) -> tuple[str, str]:
    """Ask the classifier which cloud backend to use.

    Uses local Ollama models when configured, otherwise a small model through
    the existing LiteLLM gateway.
    Uses in-memory cache to skip classification for repeated prompts.
    Falls back to DEFAULT_MODEL after _CLASSIFICATION_TIMEOUT seconds.
    Returns (model_id, reason) tuple.
    """
    context = routing_context(messages)
    if not context.strip():
        return (DEFAULT_MODEL, "")

    cached = _cached_classify(context, has_tools)
    if cached:
        logger.info("classification cache hit model=%s reason=%s", cached[0], cached[1])
        return cached

    prompt = _build_classification_prompt(context, has_tools, list(_banned_models()))

    if not USE_LOCAL_CLASSIFIER:
        try:
            async with httpx.AsyncClient(timeout=_CLASSIFICATION_TIMEOUT) as client:
                response = await client.post(
                    f"{LITELLM_URL}/chat/completions",
                    headers={"Authorization": "Bearer dummy"},
                    json={
                        "model": CLOUD_CLASSIFIER_MODEL,
                        "messages": [{"role": "user", "content": prompt}],
                        "temperature": 0,
                        "max_tokens": 128,  # Increased for reason
                        "stream": False,
                    },
                )
                response.raise_for_status()
                content = response.json()["choices"][0]["message"]["content"]
                choice = _parse_model_choice(str(content))
                if choice:
                    model, reason = choice
                    _cache_classify(context, has_tools, model, reason)
                    return (model, reason)
                logger.warning(
                    "cloud classifier returned unknown model content=%s", content
                )
        except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError) as exc:
            logger.warning("cloud classification failed: %s", exc)
        return (DEFAULT_MODEL, "")

    for model in ROUTER_MODELS:
        if _model_banned(model):
            logger.info("skipping banned classifier model=%s", model)
            continue
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
                    classified_model, reason = choice
                    _cache_classify(context, has_tools, classified_model, reason)
                    return (classified_model, reason)
                logger.warning(
                    "local classifier returned unknown model content=%s",
                    response.json().get("response", ""),
                )
        except Exception:
            continue

    # All classifiers failed or timed out
    return (DEFAULT_MODEL, "")


# ---------------------------------------------------------------------------
# Metadata request detection
#
# opencode occasionally sends title/summary generation requests with no tools.
# We detect these and suppress the model notice so the result is clean.
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

_CODING_MARKERS = (
    "code",
    "coding",
    "implement",
    "implementation",
    "debug",
    "bug",
    "refactor",
    "test",
    "script",
    "shell",
    "nix",
    "nixos",
    "python",
    "javascript",
    "typescript",
    "konfiguration",
    "programmier",
    "fehler",
    "debuggen",
    "implementieren",
    "refactoren",
)


def _is_metadata_request(messages: list[dict[str, Any]], has_tools: bool) -> bool:
    if has_tools:
        return False
    text = routing_context(messages).lower()
    return any(marker in text for marker in _TITLE_SUMMARY_MARKERS)


def _is_coding_request(messages: list[dict[str, Any]], has_tools: bool) -> bool:
    if has_tools:
        return True
    text = routing_context(messages).lower()
    return any(marker in text for marker in _CODING_MARKERS)


# ---------------------------------------------------------------------------
# Fallback chain
# ---------------------------------------------------------------------------


# Backend fallbacks handle availability failures. Capability escalation is
# separate: it moves a retry to a stronger model after an inadequate answer.
FAMILY_ESCALATION_LADDERS = {
    "mistral": ["mistral-small", "mistral-medium"],
    "deepseek": ["deepseek-v4-flash", "deepseek-v4-pro"],
    "qwen": ["qwen3.7-plus", "qwen3.7-max", "qwen3.8-max"],
    "gpt": ["gpt-5.6-luna", "gpt-5.6-luna-fast", "gpt-5.6-terra", "gpt-5.6-terra-fast", "gpt-5.6-sol", "gpt-5.6-sol-fast"],
}


def _get_family_escalation(model: str) -> str | None:
    """Get the next model in the family escalation ladder."""
    model_info = MODEL_ROUTING.get(model, {})
    family = model_info.get("family")
    if not family:
        return None
    
    ladder = FAMILY_ESCALATION_LADDERS.get(family, [])
    if not ladder:
        return None
    
    try:
        current_index = ladder.index(model)
        if current_index < len(ladder) - 1:
            return ladder[current_index + 1]
    except ValueError:
        pass
    
    return None


CAPABILITY_ESCALATION = {
    "mistral-small": "mistral-medium",
    "mistral-medium": "deepseek-v4-flash",
    "deepseek-v4-flash": "deepseek-v4-pro",
    "deepseek-v4-pro": "qwen3.7-max",
    "qwen3.7-plus": "qwen3.7-max",
    "qwen3.7-max": "qwen3.8-max",
    "qwen3.8-max": "gpt-5.6-terra",
    "gpt-5.6-luna": "gpt-5.6-terra",
    "gpt-5.6-luna-fast": "gpt-5.6-terra-fast",
    "gpt-5.6-terra": "gpt-5.6-sol",
    "gpt-5.6-terra-fast": "gpt-5.6-sol-fast",
    "gpt-5.6-sol": "gpt-5.6-sol-fast",
    "gpt-5.6-sol-fast": "gpt-5.6-sol",
}

CAPABILITY_LEVEL = {
    "mistral-small": 1,
    "deepseek-v4-flash": 2,
    "mistral-medium": 2,
    "gpt-5.6-luna-fast": 2,
    "gpt-5.6-luna": 2,
    "qwen3.7-plus": 2,
    "gpt-5.6-terra-fast": 3,
    "gpt-5.6-terra": 3,
    "deepseek-v4-pro": 3,
    "qwen3.7-max": 3,
    "gpt-5.6-sol-fast": 4,
    "qwen3.8-max": 4,
    "gpt-5.6-sol": 5,
}

_RETRY_MARKERS = (
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
)

_RETRY_PATTERNS = (
    re.compile(r"\bhat\b.*\bnicht funktioniert\b"),
    re.compile(r"\bbekommt\b.*\bnicht hin\b"),
    re.compile(r"\bschafft\b.*\bnicht(?: mehr)?\b"),
)


def _last_routed_model(messages: list[dict[str, Any]]) -> str | None:
    """Read the model from the final routing line of the last assistant turn."""
    model_pattern = "|".join(
        sorted(
            (re.escape(model) for model in DIRECT_MODELS | set(MODEL_ALIASES)),
            key=len,
            reverse=True,
        )
    )
    notice_pattern = re.compile(
        rf"^>\s+\*\*(auto|{model_pattern})(?:\s+(?:->|→)\s+({model_pattern}))?\*\*(?:\s+-\s+.+)?$"
    )
    for message in reversed(messages):
        if message.get("role") != "assistant":
            continue
        lines = [line.strip() for line in message_text(message).splitlines() if line.strip()]
        for line in lines:
            match = notice_pattern.fullmatch(line)
            if match:
                model = match.group(2) or match.group(1)
                return MODEL_ALIASES.get(model, model)
    return None


def _capability_escalation(messages: list[dict[str, Any]]) -> str | None:
    """Return a stronger model when the user rejects the previous result.
    
    First tries the family ladder (next step in same family), then falls back
    to cross-family escalation. Bans the previous model for the session.
    """
    latest_user = next(
        (
            message_text(message).lower()
            for message in reversed(messages)
            if message.get("role") == "user"
        ),
        "",
    )
    if not any(marker in latest_user for marker in _RETRY_MARKERS) and not any(
        pattern.search(latest_user) for pattern in _RETRY_PATTERNS
    ):
        return None
    previous_model = _last_routed_model(messages)
    if not previous_model:
        return None
    
    family_next = _get_family_escalation(previous_model)
    if family_next and not _model_banned(family_next):
        _ban_model(previous_model, _SESSION_QUALITY_BAN_SECONDS, "user rejected result (session quality ban)")
        logger.info("family escalation model=%s -> model=%s", previous_model, family_next)
        return family_next
    
    cross_family = CAPABILITY_ESCALATION.get(previous_model)
    if cross_family:
        _ban_model(previous_model, _SESSION_QUALITY_BAN_SECONDS, "user rejected result (session quality ban)")
        logger.info("cross-family escalation model=%s -> model=%s", previous_model, cross_family)
        return cross_family
    
    return None


def _more_capable_model(classified_model: str, escalation_model: str) -> str:
    """Keep a classifier choice when it is already at least as capable."""
    if CAPABILITY_LEVEL.get(classified_model, 0) >= CAPABILITY_LEVEL.get(
        escalation_model, 0
    ):
        return classified_model
    return escalation_model


def _fallback_chain(model: str) -> list[str]:
    """Breadth-first walk of all configured fallbacks (not just the first)."""
    result: list[str] = []
    queue: list[str] = [model]
    while queue:
        candidate = queue.pop(0)
        if candidate not in DIRECT_MODELS or candidate in result:
            continue
        result.append(candidate)
        queue.extend(MODEL_ROUTING.get(candidate, {}).get("fallbacks", []))
    for fallback in GLOBAL_FALLBACKS:
        if fallback not in result:
            result.append(fallback)
    if not USE_LOCAL_CLASSIFIER:
        result = [candidate for candidate in result if _provider(candidate) != "ollama"]
    return result or [model]


METADATA_FALLBACK_CHAIN = [
    "mistral-small",
    "mistral-medium",
    "deepseek-v4-flash",
    "gpt-5.6-luna-fast",
]


def _metadata_fallback_chain() -> list[str]:
    """Cheap-only fallback chain for title/summary requests."""
    result = list(METADATA_FALLBACK_CHAIN)
    if USE_LOCAL_CLASSIFIER and "qwen3:8b" not in result:
        result.append("qwen3:8b")
    return result


def _provider(model: str) -> str:
    return MODEL_PROVIDERS.get(model, model)


def _provider_models(model: str) -> list[str]:
    provider = _provider(model)
    return [m for m, p in MODEL_PROVIDERS.items() if p == provider]


def _cooldown_duration(failures: int) -> int:
    return min(
        _PROVIDER_COOLDOWN_BASE * (2 ** (failures - 1)),
        _PROVIDER_COOLDOWN_MAX,
    )


def _provider_available(model: str) -> bool:
    unavailable_until = _model_cooldown_until.get(model, 0)
    if unavailable_until <= time.monotonic():
        _model_cooldown_until.pop(model, None)
        return True
    return False


def _mark_provider_failure(
    model: str, reason: str, provider_wide: bool = False
) -> None:
    key = f"provider:{_provider(model)}" if provider_wide else model
    failures = _consecutive_failures.get(key, 0) + 1
    _consecutive_failures[key] = failures
    duration = _cooldown_duration(failures)
    targets = _provider_models(model) if provider_wide else [model]
    for target in targets:
        _model_cooldown_until[target] = time.monotonic() + duration
    logger.warning(
        "model cooldown model=%s seconds=%s failures=%s reason=%s provider_wide=%s",
        model,
        duration,
        failures,
        reason,
        provider_wide,
    )


def _mark_provider_http_failure(model: str, status_code: int) -> None:
    if status_code in (401, 403):
        reason = f"HTTP {status_code} (auth)"
        _ban_model(model, _AUTH_BAN_SECONDS, reason)
        for target in _provider_models(model):
            _model_cooldown_until[target] = time.monotonic() + _PROVIDER_COOLDOWN_BASE
        return
    if status_code == 429:
        reason = f"HTTP {status_code} (quota exhausted)"
        _ban_model(model, _EXHAUSTION_BAN_SECONDS, reason)
        for target in _provider_models(model):
            _model_cooldown_until[target] = time.monotonic() + _PROVIDER_COOLDOWN_BASE
        return
    if status_code >= 500 or status_code in _PROVIDER_FAILURE_STATUSES:
        _mark_provider_failure(model, f"HTTP {status_code}", provider_wide=True)


def _mark_provider_success(model: str) -> None:
    _model_cooldown_until.pop(model, None)
    _model_ban_until.pop(model, None)
    _model_ban_reason.pop(model, None)
    _consecutive_failures.pop(model, None)
    _consecutive_failures.pop(f"provider:{_provider(model)}", None)


def _ban_model(model: str, seconds: int, reason: str) -> None:
    _model_ban_until[model] = time.monotonic() + seconds
    _model_ban_reason[model] = reason
    logger.warning(
        "model ban model=%s seconds=%s reason=%s", model, seconds, reason
    )


def _model_banned(model: str) -> bool:
    ban_until = _model_ban_until.get(model, 0)
    if ban_until <= time.monotonic():
        _model_ban_until.pop(model, None)
        _model_ban_reason.pop(model, None)
        return False
    return True


def _banned_models() -> dict[str, int]:
    """Currently banned models with remaining seconds (expired ones dropped)."""
    now = time.monotonic()
    banned = {}
    for model, ban_until in list(_model_ban_until.items()):
        remaining = int(ban_until - now)
        if remaining > 0:
            banned[model] = remaining
        else:
            _model_ban_until.pop(model, None)
            _model_ban_reason.pop(model, None)
    return banned


def _record_route(model: str) -> None:
    """Track consecutive routing and ban a model when it dominates the load."""
    global _last_route_model
    if _last_route_model != model:
        for other in list(_consecutive_routes):
            _consecutive_routes[other] = 0
        _last_route_model = model
    _consecutive_routes.setdefault(model, 0)
    _consecutive_routes[model] += 1
    if _consecutive_routes[model] >= MODEL_MAX_CONSECUTIVE:
        if _banned_alternative(model):
            _ban_model(
                model,
                MODEL_ROTATION_BAN_SECONDS,
                f"served {_consecutive_routes[model]} consecutive requests (load balancing)",
            )
        else:
            logger.info(
                "rotation threshold reached but no alternative for model=%s",
                model,
            )
        _consecutive_routes[model] = 0


def _banned_alternative(model: str) -> str | None:
    """Return an equally capable sibling for a banned model, if available.
    Uses family ladders to find alternatives."""
    model_info = MODEL_ROUTING.get(model, {})
    family = model_info.get("family")
    
    if family:
        ladder = FAMILY_ESCALATION_LADDERS.get(family, [])
        if ladder:
            for candidate in ladder:
                if candidate != model and not _model_banned(candidate):
                    return candidate
    
    return None


def _degraded_providers() -> dict[str, int]:
    now = time.monotonic()
    degraded = {}
    for model, unavailable_until in list(_model_cooldown_until.items()):
        remaining = int(unavailable_until - now)
        if remaining > 0:
            degraded[model] = remaining
        else:
            _model_cooldown_until.pop(model, None)
    return degraded


# ---------------------------------------------------------------------------
# Response helpers
# ---------------------------------------------------------------------------


_FALLBACK_REASONS: dict[str, str] = {
    "mistral-small": "Trivial Q&A / title",
    "mistral-medium": "Architecture & planning",
    "deepseek-v4-flash": "Coding, debugging, refactors",
    "deepseek-v4-pro": "Exceptional complexity",
    "gpt-5.6-luna-fast": "Quick overflow",
    "gpt-5.6-luna": "General overflow",
    "gpt-5.6-terra-fast": "Complex overflow",
    "gpt-5.6-terra": "Highest complexity",
    "gpt-5.6-sol-fast": "Critical fixes",
    "gpt-5.6-sol": "Hardest problems",
    "qwen3.7-plus": "General development",
    "qwen3.8-max": "Deepest reasoning",
    "qwen3.7-max": "Advanced reasoning",
}

def _model_notice_text(
    model: str, original_model: str | None = None, reason: str = ""
) -> str:
    display_name = MODEL_DISPLAY_NAMES.get(model, model)
    if original_model and original_model != model:
        original_display = MODEL_DISPLAY_NAMES.get(original_model, original_model)
        model_line = f"> **{original_display} → {display_name}**"
    else:
        model_line = f"> **{display_name}**"
    compact_reason = _compact_reason(reason)
    if not compact_reason:
        compact_reason = _FALLBACK_REASONS.get(model, "Auto-routed")
    return f"{model_line}\n> {compact_reason}"


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


def _is_terminal_chunk(line: str) -> bool:
    if not line.startswith("data: ") or line.startswith("data: [DONE]"):
        return False
    try:
        chunk = json.loads(line[6:])
    except Exception:
        return False
    return any(
        choice.get("finish_reason") is not None
        for choice in chunk.get("choices", [])
    )


def _error_text(response: httpx.Response) -> str:
    try:
        return response.text
    except Exception:
        return ""


def _add_agent_instruction(body: dict[str, Any], has_tools: bool) -> dict[str, Any]:
    """Prepend persistence instructions when the model has tools."""
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
                "Treat the user's complete request as one assignment and own it end to end. "
                "Identify every deliverable, constraint, and acceptance condition first. "
                "Inspect files and implement every requested change. "
                "For 3+ substantive steps, use the todo tool when available: "
                "create a todo list and keep it updated after each tool result. "
                "Continue through all implementation, testing, linting, typechecking, and verification. "
                "Never stop after analysis, after one subtask, or after a partial fix. "
                "Before answering, verify each deliverable against the original request "
                "and run the strongest applicable checks. "
                "Only return a final answer when complete or when blocked. "
                "If blocked, complete every unblocked part first and state the blocker and remaining action. "
                "CRITICAL RULE: NEVER generate model-routing annotations "
                "(like '> **DeepSeek V4 Flash**', '> **GPT-5.6 Sol**', '> Coding & "
                "shell commands') or any model IDs in your responses. "
                "The auto-router system injects those automatically. "
                "You must not prefix, suffix, or embed any routing information."
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


def _chat_to_responses_body(
    body: dict[str, Any], chatgpt_model: str, service_tier: str | None = None
) -> dict[str, Any]:
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
        "model": chatgpt_model,
        "input": input_items,
        "stream": True,
        "store": False,
        "reasoning": {
            "effort": body.get("reasoning_effort", "high"),
            "summary": "auto",
        },
        "text": {"verbosity": "medium"},
        "include": ["reasoning.encrypted_content"],
    }
    if service_tier:
        response_body["service_tier"] = service_tier
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
    classification_reason: str = "",
) -> dict[str, Any]:
    text_parts = []
    reasoning_parts = []
    tool_calls = []
    for item in response.get("output", []):
        if item.get("type") == "message":
            for content in item.get("content", []):
                if content.get("type") in {"output_text", "text"}:
                    text_parts.append(content.get("text", ""))
        if item.get("type") == "reasoning":
            for summary in item.get("summary", []):
                if summary.get("type") in {"summary_text", "text"}:
                    reasoning_parts.append(summary.get("text", ""))
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
        content = _model_notice_text(
            routed_model, original_model, classification_reason
        ) + "\n\n" + content
    message: dict[str, Any] = {
        "role": "assistant",
        "content": content,
    }
    if tool_calls:
        message["tool_calls"] = tool_calls
    if reasoning_parts:
        message["reasoning_content"] = "".join(reasoning_parts)

    return {
        "id": response.get("id", "chatgpt-response"),
        "object": "chat.completion",
        "created": int(time.time()),
        "model": response.get("model", routed_model),
        "choices": [{"index": 0, "message": message, "finish_reason": "stop"}],
    }


def _chatgpt_text_chunk(event: dict[str, Any], model: str) -> dict[str, Any] | None:
    event_type = event.get("type")
    if event_type in {"response.output_text.delta", "response.text.delta"}:
        delta = {"content": event.get("delta", "")}
    elif event_type in {
        "response.reasoning.delta",
        "response.reasoning_text.delta",
        "response.reasoning_summary_text.delta",
    }:
        delta = {"reasoning_content": event.get("delta", "")}
    else:
        return None

    return {
        "id": event.get("response_id", "chatgpt-response"),
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": model,
        "choices": [{"index": 0, "delta": delta, "finish_reason": None}],
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
    classification_reason: str = "",
):
    try:
        auth_info = await _get_openai_auth()
    except Exception as exc:
        _mark_provider_http_failure(routed_model, 401)
        if fallback_models:
            return await _stream_to_backend(
                body,
                fallback_models,
                original_model or routed_model,
                show_notice,
                classification_reason,
            )
        return JSONResponse(
            {"error": "OpenAI OAuth refresh failed", "details": str(exc)},
            status_code=502,
        )
    if not auth_info:
        _mark_provider_http_failure(routed_model, 401)
        if fallback_models:
            return await _stream_to_backend(
                body,
                fallback_models,
                original_model or routed_model,
                show_notice,
                classification_reason,
            )
        return JSONResponse(
            {"error": "OpenAI OAuth auth not found. Run opencode auth login for openai."},
            status_code=401,
        )

    auth, account_id = auth_info
    model_config = MODEL_ROUTING[routed_model]
    request_body = _chat_to_responses_body(
        body,
        model_config["chatgpt_model"],
        model_config.get("service_tier"),
    )
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
            body,
            request_body,
            headers,
            routed_model,
            fallback_models,
            original_model,
            show_notice,
            classification_reason,
        )

    client = httpx.AsyncClient(timeout=httpx.Timeout(30.0, read=600.0))
    upstream = client.stream(
        "POST", CHATGPT_RESPONSES_URL, json=request_body, headers=headers
    )
    try:
        response = await upstream.__aenter__()
    except httpx.HTTPError as exc:
        await client.aclose()
        _mark_provider_failure(routed_model, f"network error: {exc}", provider_wide=True)
        if fallback_models:
            return await _stream_to_backend(
                body,
                fallback_models,
                original_model or routed_model,
                show_notice,
                classification_reason,
            )
        return JSONResponse(
            {"error": "ChatGPT upstream unavailable", "details": str(exc)},
            status_code=502,
        )
    if not response.is_success:
        error_body = (await response.aread()).decode(errors="replace")
        logger.warning(
            "chatgpt upstream failed status=%s body=%s",
            response.status_code,
            error_body,
        )
        _mark_provider_http_failure(routed_model, response.status_code)
        await upstream.__aexit__(None, None, None)
        await client.aclose()
        if fallback_models:
            return await _stream_to_backend(
                body,
                fallback_models,
                original_model or routed_model,
                show_notice,
                classification_reason,
            )
        return JSONResponse(
            {"error": "ChatGPT upstream failed", "details": error_body},
            status_code=response.status_code,
        )

    _mark_provider_success(routed_model)

    async def _iter_chatgpt_sse():
        had_tool_calls = False
        pending_fc_name: str | None = None
        pending_fc_call_id: str | None = None
        fc_index = 0
        if show_notice or original_model != routed_model:
            notice_content = _model_notice_text(
                routed_model, original_model, classification_reason
            ) + "\n\n"
            yield f"data: {json.dumps(_notice_chunk(request_body['model'], notice_content))}\n\n"
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
                chunk = _chatgpt_text_chunk(event, request_body["model"])
                if chunk:
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
        except httpx.HTTPError as exc:
            _mark_provider_failure(routed_model, f"stream interrupted: {exc}")
            raise
        finally:
            await upstream.__aexit__(None, None, None)
            await client.aclose()

    return StreamingResponse(
        _iter_chatgpt_sse(),
        status_code=response.status_code,
        media_type="text/event-stream",
    )


async def _chatgpt_non_streaming(
    chat_body: dict[str, Any],
    request_body: dict[str, Any],
    headers: dict[str, str],
    routed_model: str,
    fallback_models: list[str] | None,
    original_model: str | None,
    show_notice: bool,
    classification_reason: str,
):
    try:
        async with httpx.AsyncClient(timeout=600) as client:
            response = await client.post(
                CHATGPT_RESPONSES_URL, json=request_body, headers=headers
            )
    except httpx.HTTPError as exc:
        _mark_provider_failure(routed_model, f"network error: {exc}", provider_wide=True)
        if fallback_models:
            return await _stream_to_backend(
                body=chat_body,
                candidates=fallback_models,
                original_model=original_model or routed_model,
                show_notice=show_notice,
                classification_reason=classification_reason,
            )
        return JSONResponse(
            {"error": "ChatGPT upstream unavailable", "details": str(exc)},
            status_code=502,
        )

    if not response.is_success:
        _mark_provider_http_failure(routed_model, response.status_code)
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
            return await _stream_to_backend(
                body=chat_body,
                candidates=fallback_models,
                original_model=original_model or routed_model,
                show_notice=show_notice,
                classification_reason=classification_reason,
            )
        return JSONResponse(payload, status_code=response.status_code)

    _mark_provider_success(routed_model)

    final_response = None
    text_parts = []
    reasoning_parts = []
    tool_calls = []
    pending_fc_name: str | None = None
    pending_fc_call_id: str | None = None
    for line in response.text.splitlines():
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
                pending_fc_call_id = item.get("call_id")
        if event_type in {"response.output_text.delta", "response.text.delta"}:
            text_parts.append(event.get("delta", ""))
        if event_type in {
            "response.reasoning.delta",
            "response.reasoning_text.delta",
            "response.reasoning_summary_text.delta",
        }:
            reasoning_parts.append(event.get("delta", ""))
        if event_type == "response.function_call_arguments.done":
            tool_calls.append({
                "type": "function_call",
                "call_id": pending_fc_call_id or f"call_{int(time.time())}",
                "name": pending_fc_name or "unknown",
                "arguments": event.get("arguments", ""),
            })
            pending_fc_name = None
            pending_fc_call_id = None
        if event_type in {"response.done", "response.completed"}:
            final_response = event.get("response")
    if not final_response:
        _mark_provider_failure(routed_model, "no final response")
        _ban_model(routed_model, _SESSION_QUALITY_BAN_SECONDS, "no final response (session quality ban)")
        if fallback_models:
            return await _stream_to_backend(
                body=chat_body,
                candidates=fallback_models,
                original_model=original_model or routed_model,
                show_notice=show_notice,
                classification_reason=classification_reason,
            )
        return JSONResponse({"error": "No final Codex response"}, status_code=502)
    if not final_response.get("output"):
        output = []
        if text_parts:
            output.append({
                "type": "message",
                "content": [{"type": "output_text", "text": "".join(text_parts)}],
            })
        if reasoning_parts:
            output.append({
                "type": "reasoning",
                "summary": [
                    {"type": "summary_text", "text": "".join(reasoning_parts)}
                ],
            })
        output.extend(tool_calls)
        final_response = dict(final_response)
        final_response["output"] = output
    return JSONResponse(
        _responses_to_chat_completion(
            final_response,
            routed_model,
            original_model,
            show_notice or original_model != routed_model,
            classification_reason,
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
    classification_reason: str = "",
):
    """Try each candidate in order. Stream on first successful backend."""
    headers = {"Authorization": "Bearer dummy"}
    stream = bool(body.get("stream"))
    last_status = 502
    last_error: dict[str, Any] = {"error": "No backend candidates available"}

    for index, candidate in enumerate(candidates):
        remaining = candidates[index + 1 :]
        if not _provider_available(candidate) or _model_banned(candidate):
            logger.info(
                "skipping unavailable or banned provider=%s model=%s",
                _provider(candidate),
                candidate,
            )
            continue
        if candidate in CHATGPT_MODELS:
            return await _stream_chatgpt(
                body,
                candidate,
                remaining,
                original_model,
                show_notice,
                classification_reason,
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
            try:
                response = await upstream.__aenter__()
            except httpx.HTTPError as exc:
                await client.aclose()
                _mark_provider_failure(candidate, f"network error: {exc}", provider_wide=True)
                last_error = {
                    "error": "Backend unavailable",
                    "model": candidate,
                    "details": str(exc),
                }
                continue
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
                _mark_provider_http_failure(candidate, response.status_code)
                await upstream.__aexit__(None, None, None)
                await client.aclose()
                continue

            _mark_provider_success(candidate)

            async def _iter_litellm_stream(model: str = candidate):
                try:
                    if show_notice or model != original_model:
                        notice_content = _model_notice_text(
                            model, original_model, classification_reason
                        ) + "\n\n"
                        yield f"data: {json.dumps(_notice_chunk(model, notice_content))}\n\n"
                    async for line in response.aiter_lines():
                        yield line + "\n"
                except httpx.HTTPError as exc:
                    _mark_provider_failure(model, f"stream interrupted: {exc}")
                    raise
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
        try:
            async with httpx.AsyncClient(timeout=600) as client:
                response = await client.post(
                    f"{LITELLM_URL}/chat/completions",
                    json=forwarded,
                    headers=headers,
                )
        except httpx.HTTPError as exc:
            _mark_provider_failure(candidate, f"network error: {exc}", provider_wide=True)
            last_error = {
                "error": "Backend unavailable",
                "model": candidate,
                "details": str(exc),
            }
            continue

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
            _mark_provider_http_failure(candidate, response.status_code)
            continue

        _mark_provider_success(candidate)
        try:
            payload = response.json()
        except ValueError as exc:
            _mark_provider_failure(candidate, f"invalid JSON response: {exc}")
            last_error = {
                "error": "Backend returned an invalid response",
                "model": candidate,
                "details": str(exc),
            }
            continue
        for choice in payload.get("choices", []):
            message = choice.get("message")
            if isinstance(message, dict):
                content = str(message.get("content", ""))
                if show_notice or candidate != original_model:
                    content = _model_notice_text(
                        candidate, original_model, classification_reason
                    ) + "\n\n" + content
                message["content"] = content
        return JSONResponse(payload, status_code=response.status_code)

    return JSONResponse(last_error, status_code=last_status)


# ---------------------------------------------------------------------------
# FastAPI endpoints
# ---------------------------------------------------------------------------


@app.get("/health")
async def health() -> dict[str, Any]:
    degraded = _degraded_providers()
    banned = _banned_models()
    return {
        "status": "degraded" if degraded or banned else "ok",
        "classifier_backend": CLASSIFIER_BACKEND,
        "model_cooldowns": degraded,
        "model_bans": {
            model: {
                "seconds": remaining,
                "reason": _model_ban_reason.get(model, ""),
            }
            for model, remaining in banned.items()
        },
        "consecutive_routes": dict(_consecutive_routes),
        "consecutive_failures": dict(_consecutive_failures),
    }


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
    for model_id, cfg in MODEL_ROUTING.items():
        if model_id in ROUTER_MODELS:
            continue
        if cfg.get("hidden"):
            continue
        if not USE_LOCAL_CLASSIFIER and _provider(model_id) == "ollama":
            continue
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

    requested_model = MODEL_ALIASES.get(str(body.get("model", "auto")), str(body.get("model", "auto")))
    has_tools = bool(body.get("tools"))
    is_metadata = _is_metadata_request(messages, has_tools)

    # If the client already picked a specific model, use it directly.
    # Title/summary requests go to the cheap model without classification.
    # Otherwise classify the request through the configured classifier.
    if requested_model in DIRECT_MODELS:
        target_model = requested_model
        classification_reason = ""
    elif is_metadata:
        target_model = "mistral-small"
        classification_reason = "Titel/Summary"
    else:
        target_model, classification_reason = await _classify(messages, has_tools)

    # Small is intentionally limited to non-agentic requests. Do not let a
    # classifier mistake a tool-enabled task for trivial Q&A.
    if not is_metadata and target_model == "mistral-small" and _is_coding_request(
        messages, has_tools
    ):
        target_model = "qwen3.7-plus"
        classification_reason = "Coding-Aufgabe braucht Coding-Modell"

    if _model_banned(target_model):
        alternative = _banned_alternative(target_model)
        if alternative:
            logger.info(
                "replacing banned classified model=%s with alternative=%s",
                target_model,
                alternative,
            )
            target_model = alternative
            classification_reason = "Load balancing"

    escalation_model = (
        None
        if requested_model in DIRECT_MODELS
        else _capability_escalation(messages)
    )
    notice_model = target_model
    if escalation_model:
        previous_model = _last_routed_model(messages)
        escalated_target = _more_capable_model(target_model, escalation_model)
        logger.info(
            "capability escalation classified_model=%s escalated_model=%s",
            target_model,
            escalated_target,
        )
        if escalated_target != target_model:
            classification_reason = ""
        target_model = escalated_target
        notice_model = previous_model or target_model

    logger.info(
        "routing requested_model=%s target_model=%s has_tools=%s messages=%s reason=%s",
        requested_model,
        target_model,
        has_tools,
        len(messages),
        classification_reason,
    )

    last_model = _last_routed_model(messages)
    show_notice = (
        not is_metadata
        and requested_model not in DIRECT_MODELS
        and last_model != target_model
    )
    body["messages"] = _strip_notices_from_history(body.get("messages", []))
    body = _add_agent_instruction(body, has_tools)
    _record_route(target_model)
    candidates = (
        _metadata_fallback_chain()
        if is_metadata
        else _fallback_chain(target_model)
    )

    logger.info(
        "fallback chain target_model=%s candidates=%s",
        target_model,
        candidates,
    )

    return await _stream_to_backend(
        body, candidates, notice_model, show_notice, classification_reason
    )
