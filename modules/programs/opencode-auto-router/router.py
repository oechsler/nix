import json
import logging
import os
import time
from typing import Any

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse


app = FastAPI()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("opencode-auto-router")

LITELLM_URL = os.environ.get("LITELLM_URL", "http://127.0.0.1:8000/v1")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
ROUTER_MODEL = os.environ.get("ROUTER_MODEL", "qwen3:8b")
DEFAULT_MODEL = os.environ.get("DEFAULT_MODEL", "qwen3-fast")
OPENAI_CHATGPT_MODEL = os.environ.get("OPENAI_CHATGPT_MODEL", "gpt-5.5")
OPENCODE_AUTH_FILE = os.environ.get(
    "OPENCODE_AUTH_FILE", "/var/lib/opencode/auth.json"
)
OPENAI_TOKEN_URL = "https://auth.openai.com/oauth/token"
OPENAI_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
# ChatGPT subscription access uses the same backend path and headers as the
# OpenAI Codex CLI/OAuth flow. The routed model is OPENAI_CHATGPT_MODEL.
CHATGPT_RESPONSES_URL = "https://chatgpt.com/backend-api/codex/responses"
OPENAI_ACCOUNT_CLAIM = "https://api.openai.com/auth"

MODEL_DESCRIPTIONS = {
    "qwen3-fast": "Local Qwen3 14B. Use only when the user explicitly asks for local/private/offline handling and the task is simple.",
    "qwen3-deep": "Local Qwen3 32B. Use sparingly for complex local/private work where cloud is not acceptable; slower and may partially offload to CPU/RAM.",
    "mistral-medium": "Cloud model for architecture, reviews, analysis, product/design reasoning, and broad non-private planning.",
    "mistral-small": "Cloud model for cheap, fast utility tasks like greetings, summaries, titles, and simple non-sensitive questions.",
    "deepseek-v4-pro": "OpenCode Go DeepSeek V4 Pro cloud model. Default for normal OpenCode answers, coding, reasoning, system administration, and tool-heavy agent work.",
    "openai-chatgpt": "ChatGPT subscription model for the hardest coding, agentic, debugging, review, and refactoring work when cloud use is acceptable.",
}

DIRECT_MODELS = set(MODEL_DESCRIPTIONS)
MODEL_NOTICE_PREFIX = "Routed to"

PRIVATE_TERMS = (
    "local",
    "lokal",
    "private",
    "privat",
    "offline",
    "no cloud",
    "keine cloud",
    "nicht in die cloud",
    "sensitive",
    "sensibel",
)
HARD_TERMS = (
    "refactor",
    "refactoring",
    "large change",
    "many files",
    "architecture",
    "debug",
    "bug",
    "security",
    "performance",
    "review",
    "migration",
    "deploy",
    "deployment",
    "kubernetes",
    "k8s",
    "docker",
    "podman",
    "nixos",
    "flake",
    "network",
    "firewall",
    "service",
    "systemd",
    "logs",
    "database",
    "postgres",
    "mysql",
    "redis",
    "komplex",
    "schwierig",
    "bereitstell",
    "dienst",
    "netzwerk",
    "datenbank",
    "architektur",
    "fehlersuche",
    "fehlersuch",
    "sicherheits",
    "leistung",
    "performanz",
    "protokoll",
    "protokolle",
    "mehrere dateien",
    "viele dateien",
    "größer",
    "groesser",
    "umfangreich",
)
CODING_AGENT_TERMS = (
    "agent",
    "tool",
    "tools",
    "inspect",
    "check",
    "look up",
    "find out",
    "implement",
    "edit",
    "fix",
    "build",
    "test",
    "run",
    "code",
    "coding",
    "patch",
    "diagnose",
    "troubleshoot",
    "configure",
    "config",
    "install",
    "upgrade",
    "update",
    "start",
    "stop",
    "restart",
    "status",
    "log",
    "logs",
    "journal",
    "systemctl",
    "journalctl",
    "nix",
    "nixos",
    "home-manager",
    "flake",
    "package",
    "dependency",
    "dependencies",
    "container",
    "docker",
    "podman",
    "compose",
    "kubernetes",
    "k8s",
    "helm",
    "network",
    "dns",
    "firewall",
    "port",
    "process",
    "disk",
    "mount",
    "memory",
    "cpu",
    "gpu",
    "driver",
    "linux",
    "database",
    "sql",
    "migration",
    "schema",
    "backup",
    "restore",
    "permission",
    "permissions",
    "secret",
    "env",
    "environment",
    "ci",
    "pipeline",
    "workflow",
    "github actions",
    "lint",
    "format",
    "compile",
    "build error",
    "stacktrace",
    "traceback",
    "exception",
    "file",
    "files",
    "repo",
    "repository",
    "workspace",
    "computer",
    "machine",
    "pc",
    "system",
    "kernel",
    "terminal",
    "command",
    "dienst",
    "dienste",
    "log",
    "logs",
    "konfig",
    "konfiguration",
    "installier",
    "aktualisier",
    "starte",
    "stoppe",
    "neustart",
    "status",
    "paket",
    "abhängigkeit",
    "abhaengigkeit",
    "container",
    "netzwerk",
    "port",
    "prozess",
    "platte",
    "speicher",
    "treiber",
    "datenbank",
    "migration",
    "backup",
    "berechtigung",
    "secret",
    "umgebung",
    "fehler",
    "stacktrace",
    "kompilier",
    "baue",
    "teste",
    "entwickel",
    "änder",
    "aender",
    "ändere",
    "aendere",
    "anpass",
    "umbau",
    "umbauen",
    "erstell",
    "erzeuge",
    "leg an",
    "lösche",
    "loesche",
    "entfern",
    "verschieb",
    "benenn",
    "öffne",
    "oeffne",
    "lies",
    "lese",
    "zeig",
    "anzeigen",
    "ausgeben",
    "ausführen",
    "ausfuehren",
    "führ aus",
    "fuehr aus",
    "kommando",
    "shell",
    "terminal",
    "konsole",
    "arbeitsbereich",
    "projekt",
    "quellcode",
    "codebasis",
    "modul",
    "funktion",
    "klasse",
    "skript",
    "skripte",
    "programm",
    "programmier",
    "entwicklungs",
    "abhängigkeiten",
    "abhaengigkeiten",
    "pakete",
    "dienste",
    "einheit",
    "units",
    "systemdienst",
    "journal",
    "protokoll",
    "protokolle",
    "fehlersuche",
    "diagnose",
    "untersuch",
    "analysier",
    "debugg",
    "beheb",
    "behebe",
    "reproduzier",
    "nachstell",
    "prüfe",
    "pruefe",
    "validier",
    "verifizier",
    "deploy",
    "bereitstell",
    "ausroll",
    "containerisierung",
    "kubernetes",
    "helm",
    "datenbank",
    "tabelle",
    "schema",
    "sicherung",
    "wiederherstell",
    "geheimnis",
    "geheimnisse",
    "umgebungsvariable",
    "umgebungsvariablen",
    "rechte",
    "berechtigungen",
    "zugriff",
    "benutzer",
    "gruppe",
    "gruppen",
    "firewall",
    "dns",
    "schnittstelle",
    "laufwerk",
    "mount",
    "einhängen",
    "einhaengen",
    "speicherplatz",
    "arbeitsspeicher",
    "prozessor",
    "grafikkarte",
    "kernel",
    "linux",
    "implementier",
    "bearbeite",
    "reparier",
    "raussuch",
    "herausfind",
    "finde heraus",
    "schau nach",
    "prüf",
    "pruef",
    "guck",
    "such",
    "datei",
    "dateien",
    "rechner",
    "maschine",
    "befehl",
)


def last_user_text(messages: list[dict[str, Any]]) -> str:
    for message in reversed(messages):
        if message.get("role") != "user":
            continue

        content = message.get("content", "")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts = []
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text":
                    parts.append(str(item.get("text", "")))
            return "\n".join(parts)
    return ""


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


def all_request_text(messages: list[dict[str, Any]]) -> str:
    return "\n".join(message_text(message) for message in messages).lower()


def contains_any(text: str, terms: tuple[str, ...]) -> bool:
    return any(term in text for term in terms)


def heuristic_model(messages: list[dict[str, Any]], has_tools: bool) -> str | None:
    user_text = last_user_text(messages).lower()
    # Only the user can request local/private/offline handling. OpenCode system
    # prompts commonly mention local files/tools and must not trigger local models.
    wants_private = contains_any(user_text, PRIVATE_TERMS)
    hard = contains_any(user_text, HARD_TERMS)

    if wants_private:
        return "qwen3-deep" if hard else "qwen3-fast"

    high_stakes = any(
        term in user_text
        for term in (
            "high-stakes",
            "production",
            "prod",
            "security incident",
            "data loss",
            "datenverlust",
            "produktiv",
            "sicherheit",
            "produktionssystem",
            "prod-system",
            "kritisch",
            "notfall",
            "incident",
            "ausfall",
        )
    )
    if hard and high_stakes:
        return "openai-chatgpt"

    return None


def routing_context(messages: list[dict[str, Any]]) -> str:
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


def parse_model_choice(text: str) -> str | None:
    cleaned = text.strip().lower()
    for model in MODEL_DESCRIPTIONS:
        if model in cleaned:
            return model
    return None


def model_notice(model: str) -> str:
    return f"[{MODEL_NOTICE_PREFIX}: {model}]\n\n"


def chat_completion_chunk(model: str, content: str) -> dict[str, Any]:
    return {
        "id": "opencode-auto-router-notice",
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": model,
        "choices": [
            {"index": 0, "delta": {"content": content}, "finish_reason": None}
        ],
    }


def add_agent_instruction(body: dict[str, Any], has_tools: bool) -> dict[str, Any]:
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


async def choose_model(messages: list[dict[str, Any]], has_tools: bool = False) -> str:
    heuristic = heuristic_model(messages, has_tools)
    if heuristic:
        return heuristic

    context = routing_context(messages)
    if not context.strip():
        return DEFAULT_MODEL

    prompt = f"""
You are a model-routing classifier for OpenCode.
You do not answer the user's request. You do not evaluate whether the user's request is allowed.
You never refuse. Your only job is to choose the best backend model id.
Choose the cheapest model that is likely to complete the task well. Optimize for quality per cost,
not for showing variety and not for always choosing the strongest model.

Available backends:
{json.dumps(MODEL_DESCRIPTIONS, indent=2)}

Do not choose qwen3-fast or qwen3-deep unless the user explicitly asks for local/private/offline handling.
Choose qwen3-deep only when the user asks to stay local/private/offline AND the request needs
careful reasoning, non-trivial code changes, debugging, architecture, refactors, security review,
performance analysis, or many files.
Choose qwen3-fast only when the user asks to stay local/private/offline and the request is simple.
Requests in English or German to inspect, change, debug, configure, install, build,
test, deploy, administer, or troubleshoot the current computer, system, terminal,
workspace, repository, files, installed software, kernel, services, logs, containers,
Kubernetes, NixOS, networks, databases, CI, permissions, secrets, or command output
are tool-heavy agent work.

Cost/complexity routing policy:
- Choose mistral-small for greetings, simple Q&A, rewriting, summaries, classification,
  translation, short explanations, and other low-risk non-agentic tasks.
- Choose deepseek-v4-pro for most OpenCode agent work: coding, file edits, shell/system
  inspection, debugging, build/test failures, NixOS/admin tasks, containers, services,
  logs, and medium-complexity reasoning. This is the default best price/performance model.
- Choose mistral-medium for broad architecture, design tradeoffs, reviews, product/planning,
  analysis-heavy tasks, or when communication quality matters more than tool use.
- Choose openai-chatgpt only when the task is unusually hard, ambiguous, multi-step,
  risky, high-stakes, or likely to fail on cheaper models.

Choose openai-chatgpt only for the hardest coding-agent tasks, risky broad refactors,
very difficult bugs, high-stakes reviews, or ambiguous multi-step work when the user did not ask
for local/private handling and cheaper models are less likely to succeed.

If a task is complex and privacy is not requested, prefer deepseek-v4-pro for coding,
mistral-medium for architecture/review/analysis, and openai-chatgpt only for the hardest cases.
Do not choose qwen3-fast or qwen3-deep for non-private work unless the user asks to stay local.

Tools available to the final model: {has_tools}

Return exactly one model id and nothing else.

Conversation context:
{context}
""".strip()

    try:
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                f"{OLLAMA_URL}/api/generate",
                json={
                    "model": ROUTER_MODEL,
                    "prompt": prompt,
                    "stream": False,
                    "options": {"temperature": 0},
                },
            )
            response.raise_for_status()
            choice = parse_model_choice(response.json().get("response", ""))
    except Exception:
        return DEFAULT_MODEL

    return choice if choice else DEFAULT_MODEL


def decode_jwt_payload(token: str) -> dict[str, Any]:
    try:
        import base64

        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload.encode()).decode())
    except Exception:
        return {}


def load_openai_auth() -> dict[str, Any] | None:
    try:
        with open(OPENCODE_AUTH_FILE, encoding="utf-8") as handle:
            auth = json.load(handle).get("openai")
        return auth if isinstance(auth, dict) and auth.get("type") == "oauth" else None
    except Exception:
        return None


def save_openai_auth(auth: dict[str, Any]) -> None:
    try:
        with open(OPENCODE_AUTH_FILE, encoding="utf-8") as handle:
            data = json.load(handle)
        data["openai"] = auth
        with open(OPENCODE_AUTH_FILE, "w", encoding="utf-8") as handle:
            json.dump(data, handle)
    except Exception:
        pass


async def get_openai_auth() -> tuple[dict[str, Any], str] | None:
    auth = load_openai_auth()
    if not auth:
        return None

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
        auth.update(
            {
                "access": tokens["access_token"],
                "refresh": tokens["refresh_token"],
                "expires": int(time.time() * 1000) + int(tokens["expires_in"]) * 1000,
            }
        )
        save_openai_auth(auth)

    account_id = auth.get("accountId")
    if not account_id:
        account_id = decode_jwt_payload(auth.get("access", "")).get(
            OPENAI_ACCOUNT_CLAIM, {}
        ).get("chatgpt_account_id")
    return (auth, account_id) if account_id else None


def chat_content_to_responses_content(content: Any, assistant: bool = False) -> list[dict[str, str]]:
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


def chat_tools_to_responses_tools(tools: Any) -> list[dict[str, Any]]:
    if not isinstance(tools, list):
        return []

    result = []
    for tool in tools:
        if not isinstance(tool, dict):
            continue
        if tool.get("type") == "function" and isinstance(tool.get("function"), dict):
            function = tool["function"]
            name = function.get("name")
            if not name:
                continue
            converted = {
                "type": "function",
                "name": name,
                "description": function.get("description", ""),
                "parameters": function.get("parameters", {"type": "object", "properties": {}}),
            }
            result.append(converted)
            continue
        if tool.get("name"):
            result.append(tool)
    return result


def chat_tool_choice_to_responses_tool_choice(tool_choice: Any) -> Any:
    if isinstance(tool_choice, dict) and tool_choice.get("type") == "function":
        function = tool_choice.get("function")
        if isinstance(function, dict) and function.get("name"):
            return {"type": "function", "name": function["name"]}
    return tool_choice


def chat_to_responses_body(body: dict[str, Any]) -> dict[str, Any]:
    input_items = []
    for message in body.get("messages", []):
        role = message.get("role", "user")
        if role == "system":
            role = "developer"
        if role == "tool":
            input_items.append(
                {
                    "type": "function_call_output",
                    "call_id": message.get("tool_call_id", "unknown"),
                    "output": message.get("content", ""),
                }
            )
            continue
        input_items.append(
            {
                "type": "message",
                "role": role,
                "content": chat_content_to_responses_content(
                    message.get("content", ""), assistant=role == "assistant"
                ),
            }
        )

    response_body: dict[str, Any] = {
        "model": OPENAI_CHATGPT_MODEL,
        "input": input_items,
        "stream": True,
        "store": False,
        "reasoning": {"effort": "high", "summary": "auto"},
        "text": {"verbosity": "medium"},
        "include": ["reasoning.encrypted_content"],
    }
    tools = chat_tools_to_responses_tools(body.get("tools"))
    if tools:
        response_body["tools"] = tools
    if body.get("tool_choice"):
        response_body["tool_choice"] = chat_tool_choice_to_responses_tool_choice(
            body["tool_choice"]
        )
    return response_body


def chat_completion_from_responses_response(
    response: dict[str, Any], routed_model: str
) -> dict[str, Any]:
    text_parts = []
    tool_calls = []
    for item in response.get("output", []):
        if item.get("type") == "message":
            for content in item.get("content", []):
                if content.get("type") in {"output_text", "text"}:
                    text_parts.append(content.get("text", ""))
        if item.get("type") == "function_call":
            tool_calls.append(
                {
                    "id": item.get("call_id") or item.get("id"),
                    "type": "function",
                    "function": {
                        "name": item.get("name"),
                        "arguments": item.get("arguments", "{}"),
                    },
                }
            )

    message: dict[str, Any] = {
        "role": "assistant",
        "content": model_notice(routed_model) + "".join(text_parts),
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


async def openai_chatgpt_response(body: dict[str, Any], routed_model: str):
    auth_info = await get_openai_auth()
    if not auth_info:
        return JSONResponse(
            {"error": "OpenAI OAuth auth not found. Run opencode auth login for openai."},
            status_code=401,
        )

    auth, account_id = auth_info
    request_body = chat_to_responses_body(body)
    headers = {
        "Authorization": f"Bearer {auth['access']}",
        "chatgpt-account-id": account_id,
        "OpenAI-Beta": "responses=experimental",
        "originator": "codex_cli_rs",
        "accept": "text/event-stream",
        "content-type": "application/json",
    }

    if body.get("stream"):
        client = httpx.AsyncClient(timeout=None)
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
            return JSONResponse(
                {"error": "ChatGPT upstream failed", "details": error_body},
                status_code=response.status_code,
            )

        async def iter_chat_sse():
            try:
                yield f"data: {json.dumps(chat_completion_chunk(routed_model, model_notice(routed_model)))}\n\n"
                async for line in response.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    raw = line[6:]
                    try:
                        event = json.loads(raw)
                    except Exception:
                        continue
                    event_type = event.get("type")
                    if event_type in {"response.output_text.delta", "response.text.delta"}:
                        delta = event.get("delta", "")
                        chunk = {
                            "id": event.get("response_id", "chatgpt-response"),
                            "object": "chat.completion.chunk",
                            "created": int(time.time()),
                            "model": request_body["model"],
                            "choices": [
                                {"index": 0, "delta": {"content": delta}, "finish_reason": None}
                            ],
                        }
                        yield f"data: {json.dumps(chunk)}\n\n"
                    if event_type in {"response.done", "response.completed"}:
                        done = {
                            "id": event.get("response", {}).get("id", "chatgpt-response"),
                            "object": "chat.completion.chunk",
                            "created": int(time.time()),
                            "model": request_body["model"],
                            "choices": [
                                {"index": 0, "delta": {}, "finish_reason": "stop"}
                            ],
                        }
                        yield f"data: {json.dumps(done)}\n\n"
                        yield "data: [DONE]\n\n"
            finally:
                await upstream.__aexit__(None, None, None)
                await client.aclose()

        return StreamingResponse(
            iter_chat_sse(),
            status_code=response.status_code,
            media_type="text/event-stream",
        )

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
        return JSONResponse(chat_completion_from_responses_response(final_response, routed_model))


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/models")
async def models() -> dict[str, Any]:
    return {
        "object": "list",
        "data": [
            {
                "id": "auto",
                "object": "model",
                "created": 0,
                "owned_by": "opencode-auto-router",
            }
        ],
    }


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    body = await request.json()
    messages = body.get("messages", [])
    if not isinstance(messages, list):
        return JSONResponse({"error": "messages must be a list"}, status_code=400)

    requested_model = str(body.get("model", "auto"))
    has_tools = bool(body.get("tools"))
    target_model = (
        requested_model
        if requested_model in DIRECT_MODELS
        else await choose_model(messages, has_tools)
    )
    logger.info(
        "routing requested_model=%s target_model=%s has_tools=%s messages=%s",
        requested_model,
        target_model,
        has_tools,
        len(messages),
    )
    body = add_agent_instruction(body, has_tools)
    if target_model == "openai-chatgpt":
        return await openai_chatgpt_response(body, target_model)

    forwarded = dict(body)
    forwarded["model"] = target_model

    headers = {"Authorization": "Bearer dummy"}
    stream = bool(forwarded.get("stream"))

    if stream:
        client = httpx.AsyncClient(timeout=None)
        upstream = client.stream(
            "POST",
            f"{LITELLM_URL}/chat/completions",
            json=forwarded,
            headers=headers,
        )
        response = await upstream.__aenter__()

        async def iter_bytes():
            try:
                yield f"data: {json.dumps(chat_completion_chunk(target_model, model_notice(target_model)))}\n\n".encode()
                async for chunk in response.aiter_bytes():
                    yield chunk
            finally:
                await upstream.__aexit__(None, None, None)
                await client.aclose()

        return StreamingResponse(
            iter_bytes(),
            status_code=response.status_code,
            media_type=response.headers.get("content-type", "text/event-stream"),
        )

    async with httpx.AsyncClient(timeout=600) as client:
        response = await client.post(
            f"{LITELLM_URL}/chat/completions",
            json=forwarded,
            headers=headers,
        )
    payload = response.json()
    if response.is_success:
        for choice in payload.get("choices", []):
            message = choice.get("message")
            if isinstance(message, dict):
                message["content"] = model_notice(target_model) + str(
                    message.get("content", "")
                )
    return JSONResponse(payload, status_code=response.status_code)
