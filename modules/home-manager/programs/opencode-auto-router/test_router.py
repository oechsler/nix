import unittest
from unittest.mock import AsyncMock, patch

import router


class RouterTest(unittest.TestCase):
    def setUp(self):
        router._model_cooldown_until.clear()
        router._model_ban_until.clear()
        router._model_ban_reason.clear()
        router._consecutive_routes.clear()
        router._consecutive_failures.clear()
        router._classification_cache.clear()
        router._last_route_model = None

    def test_fallback_chain_follows_all_configured_backends(self):
        self.assertEqual(
            router._fallback_chain("mistral-small"),
            [
                "mistral-small",
                "mistral-medium",
                "qwen3.7-plus",
                "deepseek-v4-flash",
                "qwen3.7-max",
                "deepseek-v4-pro",
                "qwen3.8-max",
                "gpt-5.6-terra",
                "gpt-5.6-sol",
                "gpt-5.6-luna-openai",
                "qwen3:8b",
            ],
        )

    def test_every_fallback_chain_ends_with_local_model(self):
        for model in router.DIRECT_MODELS:
            with self.subTest(model=model):
                chain = router._fallback_chain(model)
                self.assertIn("qwen3:8b", chain)
                providers = {router._provider(candidate) for candidate in chain}
                self.assertIn("mistral", providers)
                self.assertIn("opencode-go", providers)
                self.assertIn("ollama", providers)

    def test_cloud_classifier_hosts_exclude_ollama_fallbacks(self):
        with patch.object(router, "USE_LOCAL_CLASSIFIER", False):
            chain = router._fallback_chain("mistral-small")

        self.assertNotIn("qwen3:8b", chain)
        self.assertNotIn("ollama", {router._provider(model) for model in chain})

    def test_model_failure_isolates_opencode_go_model_cooldown(self):
        router._mark_provider_failure("deepseek-v4-flash", "test outage")
        self.assertFalse(router._provider_available("deepseek-v4-flash"))
        self.assertTrue(router._provider_available("deepseek-v4-pro"))
        self.assertTrue(router._provider_available("qwen3.7-plus"))
        self.assertTrue(router._provider_available("gpt-5.6-luna"))

        router._mark_provider_success("deepseek-v4-flash")
        self.assertTrue(router._provider_available("deepseek-v4-flash"))

    def test_repeated_model_failures_use_exponential_backoff(self):
        with patch.object(router, "_PROVIDER_COOLDOWN_BASE", 30):
            router._mark_provider_failure("deepseek-v4-flash", "first outage")
            self.assertFalse(router._provider_available("deepseek-v4-flash"))
            self.assertFalse(router._model_banned("deepseek-v4-flash"))

            router._mark_provider_failure("deepseek-v4-flash", "second outage")
            self.assertFalse(router._provider_available("deepseek-v4-flash"))
            self.assertFalse(router._model_banned("deepseek-v4-flash"))

    def test_provider_wide_failure_cooldowns_all_provider_models(self):
        router._mark_provider_failure(
            "deepseek-v4-flash", "network error", provider_wide=True
        )
        self.assertFalse(router._provider_available("deepseek-v4-flash"))
        self.assertFalse(router._provider_available("deepseek-v4-pro"))
        self.assertFalse(router._provider_available("qwen3.7-plus"))
        self.assertTrue(router._provider_available("mistral-small"))

    def test_auth_failure_creates_hard_ban(self):
        router._mark_provider_http_failure("deepseek-v4-flash", 401)
        self.assertTrue(router._model_banned("deepseek-v4-flash"))
        self.assertFalse(router._provider_available("qwen3.7-plus"))

    def test_rate_limit_failure_creates_temporary_ban(self):
        router._mark_provider_http_failure("deepseek-v4-flash", 429)
        self.assertTrue(router._model_banned("deepseek-v4-flash"))
        self.assertFalse(router._model_banned("deepseek-v4-pro"))
        self.assertFalse(router._model_banned("qwen3.7-plus"))

    def test_server_error_is_provider_wide(self):
        router._mark_provider_http_failure("deepseek-v4-flash", 503)
        self.assertFalse(router._provider_available("deepseek-v4-flash"))
        self.assertFalse(router._provider_available("qwen3.7-plus"))
        self.assertTrue(router._provider_available("mistral-small"))

    def test_rotation_ban_skipped_without_alternative(self):
        with patch.object(router, "MODEL_MAX_CONSECUTIVE", 2):
            router._ban_model("qwen3.7-max", 60, "pre-existing")
            router._ban_model("qwen3.8-max", 60, "pre-existing")
            router._record_route("qwen3.7-plus")
            router._record_route("qwen3.7-plus")

        self.assertFalse(router._model_banned("qwen3.7-plus"))

    def test_rotation_ban_applied_within_family_ladder(self):
        with patch.object(router, "MODEL_MAX_CONSECUTIVE", 2):
            router._record_route("deepseek-v4-flash")
            router._record_route("deepseek-v4-flash")

        self.assertTrue(router._model_banned("deepseek-v4-flash"))

    def test_route_rotation_bans_repeated_model(self):
        with patch.object(router, "MODEL_MAX_CONSECUTIVE", 2):
            router._record_route("deepseek-v4-flash")
            router._record_route("deepseek-v4-flash")

        self.assertTrue(router._model_banned("deepseek-v4-flash"))
        self.assertEqual(router._consecutive_routes["deepseek-v4-flash"], 0)

    def test_banned_models_are_visible_in_classifier_prompt(self):
        prompt = router._build_classification_prompt(
            "user: Fix the deployment", True, ["deepseek-v4-flash"]
        )

        self.assertIn("Banned/cooldown models", prompt)
        self.assertIn("deepseek-v4-flash", prompt)
        self.assertIn("do NOT pick these", prompt)

    def test_mistral_small_has_medium_as_its_first_real_fallback(self):
        self.assertEqual(
            router._fallback_chain("mistral-small")[:2],
            ["mistral-small", "mistral-medium"],
        )
        self.assertNotIn("mistral-small", router._fallback_chain("mistral-medium"))

    def test_notice_is_minimal_for_initial_route(self):
        self.assertEqual(
            router._model_notice_text("mistral-small", "mistral-small"),
            "> **Mistral Small**\n> Trivial Q&A / title",
        )

    def test_notice_shows_fallback_path(self):
        self.assertEqual(
            router._model_notice_text("mistral-medium", "mistral-small"),
            "> **Mistral Small → Mistral Medium**\n> Architecture & planning",
        )

    def test_notice_includes_classifier_reason_on_second_line(self):
        self.assertEqual(
            router._model_notice_text(
                "mistral-medium",
                "mistral-medium",
                "Weil die Aufgabe Architekturabwägungen erfordert.",
            ),
            "> **Mistral Medium**\n> Weil die Aufgabe Architekturabwägungen erfordert",
        )

    def test_classifier_choice_compacts_reason(self):
        self.assertEqual(
            router._parse_model_choice(
                "deepseek-v4-flash - Because this requires file edits and tests."
            ),
            ("deepseek-v4-flash", "Because this requires file edits and"),
        )

    def test_notice_shows_compact_reason_on_second_line(self):
        self.assertEqual(
            router._model_notice_text(
                "gpt-5.6-sol-fast", reason="Complex debugging and refactoring"
            ),
            "> **GPT-5.6 Sol Fast**\n> Complex debugging and refactoring",
        )

    def test_classifier_choice_requires_reason(self):
        self.assertIsNone(router._parse_model_choice("mistral-medium"))

    def test_classifier_choice_keeps_fast_suffix_in_model_id(self):
        self.assertEqual(
            router._parse_model_choice("gpt-5.6-sol-fast - Complex debugging"),
            ("gpt-5.6-sol-fast", "Complex debugging"),
        )

    def test_classifier_choice_repairs_legacy_fast_format(self):
        self.assertEqual(
            router._parse_model_choice("gpt-5.6-sol - fast - Complex debugging"),
            ("gpt-5.6-sol-fast", "Complex debugging"),
        )

    def test_classifier_choice_canonicalizes_legacy_gpt_alias(self):
        self.assertEqual(
            router._parse_model_choice("openai-sol - Complex debugging"),
            ("gpt-5.6-sol", "Complex debugging"),
        )

    def test_terminal_stream_chunk_is_detected(self):
        line = 'data: {"choices":[{"finish_reason":"stop","delta":{}}]}'
        self.assertTrue(router._is_terminal_chunk(line))
        self.assertFalse(router._is_terminal_chunk("data: [DONE]"))

    def test_agent_instruction_requires_end_to_end_completion(self):
        body = {"messages": [{"role": "user", "content": "Do all three tasks"}]}

        forwarded = router._add_agent_instruction(body, has_tools=True)

        instruction = forwarded["messages"][0]["content"]
        self.assertIn("one assignment and own it end to end", instruction)
        self.assertIn("Never stop after analysis", instruction)
        self.assertIn("all implementation, testing, linting, typechecking, and verification", instruction)
        self.assertIn("todo tool", instruction)
        self.assertEqual(body["messages"][0]["role"], "user")

    def test_agent_instruction_is_not_added_without_tools(self):
        body = {"messages": [{"role": "user", "content": "Explain this"}]}

        self.assertIs(router._add_agent_instruction(body, has_tools=False), body)

    def test_classifier_uses_approximate_matching_not_rigid_rules(self):
        prompt = router._build_classification_prompt("user: Do all five tasks", True)

        self.assertIn("Match approximately", prompt)
        self.assertIn("no rigid 1:1 mapping", prompt)

    def test_classifier_prompt_is_guidance_based(self):
        prompt = router._build_classification_prompt("user: Do all five tasks", True)

        self.assertNotIn("go-to starting point", prompt)
        self.assertNotIn("general recommendation", prompt)
        self.assertNotIn("DEFAULT to deepseek-v4-flash", prompt)
        self.assertIn("Guidance (not rules", prompt)
        self.assertIn("use your judgment", prompt)

    def test_strip_notices_from_history_removes_leading_block(self):
        messages = [
            {"role": "assistant", "content": "> **Qwen3.7 Plus**\n> General development\n\nHere is the answer."},
            {"role": "user", "content": "Thanks"},
        ]
        cleaned = router._strip_notices_from_history(messages)
        self.assertEqual(cleaned[0]["content"], "Here is the answer.")
        self.assertEqual(cleaned[1]["content"], "Thanks")

    def test_strip_notices_from_history_preserves_non_assistant_messages(self):
        messages = [
            {"role": "user", "content": "> This is a user quote"},
            {"role": "assistant", "content": "Normal answer"},
        ]
        cleaned = router._strip_notices_from_history(messages)
        self.assertEqual(cleaned[0]["content"], "> This is a user quote")
        self.assertEqual(cleaned[1]["content"], "Normal answer")

    def test_routing_context_strips_model_notices(self):
        messages = [
            {"role": "user", "content": "Help with coding"},
            {
                "role": "assistant",
                "content": "> **DeepSeek V4 Flash**\n> Coding, debugging\n\nHere is the fix.",
            },
            {"role": "user", "content": "Now check the tests"},
        ]
        context = router.routing_context(messages)

        self.assertNotIn("DeepSeek V4 Flash", context)
        self.assertNotIn("> **", context)
        self.assertIn("Here is the fix.", context)
        self.assertIn("Now check the tests", context)

    def test_failed_attempt_escalates_previous_model(self):
        messages = [
            {
                "role": "assistant",
                "content": "An incomplete answer\n\n> **mistral-small** - Because this was initially a simple request.",
            },
            {"role": "user", "content": "That did not work, please try again."},
        ]
        self.assertEqual(router._capability_escalation(messages), "mistral-medium")

    def test_fallback_notice_escalates_from_model_that_answered(self):
        messages = [
            {"role": "assistant", "content": "An incomplete answer\n\n> **mistral-small -> mistral-medium**"},
            {"role": "user", "content": "Das funktioniert nicht, versuche es nochmal."},
        ]
        self.assertEqual(router._capability_escalation(messages), "deepseek-v4-flash")

    def test_legacy_auto_notice_escalates_from_selected_model(self):
        messages = [
            {"role": "assistant", "content": "An incomplete answer\n\n> **auto -> mistral-small**"},
            {"role": "user", "content": "Das Modell bekommt es nicht hin."},
        ]
        self.assertEqual(router._capability_escalation(messages), "mistral-medium")

    def test_retry_detection_accepts_words_between_german_markers(self):
        messages = [
            {"role": "assistant", "content": "Incomplete\n\n> **mistral-small**"},
            {"role": "user", "content": "Das hat leider immer noch nicht funktioniert."},
        ]
        self.assertEqual(router._capability_escalation(messages), "mistral-medium")

    def test_model_lookup_skips_assistant_turn_without_notice(self):
        messages = [
            {"role": "assistant", "content": "> **mistral-small**\n> Simple request\n\nInitial answer"},
            {"role": "assistant", "content": "Intermediate tool call"},
            {"role": "user", "content": "That did not work."},
        ]
        self.assertEqual(router._capability_escalation(messages), "mistral-medium")

    def test_normal_follow_up_does_not_escalate(self):
        messages = [
            {"role": "assistant", "content": "The answer\n\n> **mistral-small**"},
            {"role": "user", "content": "Can you give me another example?"},
        ]
        self.assertIsNone(router._capability_escalation(messages))

    def test_escalation_does_not_downgrade_classifier_choice(self):
        self.assertEqual(
            router._more_capable_model("gpt-5.6-terra", "mistral-medium"),
            "gpt-5.6-terra",
        )

    def test_family_ladder_escalation_deepseek(self):
        messages = [
            {"role": "assistant", "content": "Incomplete\n\n> **deepseek-v4-flash**"},
            {"role": "user", "content": "That did not work, try again."},
        ]
        self.assertEqual(router._capability_escalation(messages), "deepseek-v4-pro")
        self.assertTrue(router._model_banned("deepseek-v4-flash"))

    def test_family_ladder_escalation_qwen(self):
        messages = [
            {"role": "assistant", "content": "Incomplete\n\n> **qwen3.7-plus**"},
            {"role": "user", "content": "That did not work, try again."},
        ]
        self.assertEqual(router._capability_escalation(messages), "qwen3.7-max")
        self.assertTrue(router._model_banned("qwen3.7-plus"))

    def test_family_ladder_escalation_gpt(self):
        messages = [
            {"role": "assistant", "content": "Incomplete\n\n> **gpt-5.6-luna**"},
            {"role": "user", "content": "That did not work, try again."},
        ]
        self.assertEqual(router._capability_escalation(messages), "gpt-5.6-luna-fast")
        self.assertTrue(router._model_banned("gpt-5.6-luna"))

    def test_session_quality_ban_applied_on_escalation(self):
        messages = [
            {"role": "assistant", "content": "Incomplete\n\n> **deepseek-v4-flash**"},
            {"role": "user", "content": "That did not work, try again."},
        ]
        router._capability_escalation(messages)
        self.assertTrue(router._model_banned("deepseek-v4-flash"))
        self.assertEqual(
            router._model_ban_reason["deepseek-v4-flash"],
            "user rejected result (session quality ban)",
        )

    def test_cross_family_escalation_when_family_exhausted(self):
        messages = [
            {"role": "assistant", "content": "Incomplete\n\n> **gpt-5.6-sol-fast**"},
            {"role": "user", "content": "That did not work, try again."},
        ]
        result = router._capability_escalation(messages)
        self.assertEqual(result, "gpt-5.6-sol")

    def test_chatgpt_request_preserves_requested_reasoning_effort(self):
        body = {"messages": [], "reasoning_effort": "medium"}

        converted = router._chat_to_responses_body(body, "gpt-5.6-sol")

        self.assertEqual(converted["reasoning"], {"effort": "medium", "summary": "auto"})

    def test_chatgpt_reasoning_summary_streams_as_reasoning_content(self):
        event = {
            "type": "response.reasoning_summary_text.delta",
            "response_id": "response-1",
            "delta": "Planning comprehensive checks",
        }

        chunk = router._chatgpt_text_chunk(event, "gpt-5.6-sol")

        self.assertEqual(
            chunk["choices"][0]["delta"],
            {"reasoning_content": "Planning comprehensive checks"},
        )

    def test_chatgpt_non_streaming_response_preserves_reasoning_summary(self):
        response = {
            "output": [
                {
                    "type": "reasoning",
                    "summary": [
                        {"type": "summary_text", "text": "Planning checks"}
                    ],
                },
                {
                    "type": "message",
                    "content": [{"type": "output_text", "text": "Finished"}],
                },
            ]
        }

        converted = router._responses_to_chat_completion(
            response, "gpt-5.6-sol", show_notice=False
        )

        message = converted["choices"][0]["message"]
        self.assertEqual(message["content"], "Finished")
        self.assertEqual(message["reasoning_content"], "Planning checks")

    def test_chatgpt_non_streaming_notice_precedes_response(self):
        response = {
            "output": [
                {
                    "type": "message",
                    "content": [{"type": "output_text", "text": "Finished"}],
                }
            ]
        }

        converted = router._responses_to_chat_completion(
            response,
            "gpt-5.6-sol-fast",
            original_model="auto",
            classification_reason="Complex debugging and refactoring",
        )

        content = converted["choices"][0]["message"]["content"]
        self.assertTrue(content.startswith("> **Auto → GPT-5.6 Sol Fast**\n> Complex debugging and refactoring\n\n"))
        self.assertTrue(content.endswith("Finished"))


class ChatCompletionsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        router._model_cooldown_until.clear()
        router._model_ban_until.clear()
        router._model_ban_reason.clear()
        router._consecutive_routes.clear()
        router._consecutive_failures.clear()
        router._classification_cache.clear()
        router._last_route_model = None

    async def test_cloud_classifier_uses_litellm(self):
        class Response:
            @staticmethod
            def raise_for_status():
                return None

            @staticmethod
            def json():
                return {
                    "choices": [
                        {
                            "message": {
                                "content": "mistral-medium - Architecture analysis"
                            }
                        }
                    ]
                }

        class Client:
            post = AsyncMock(return_value=Response())

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_args):
                return None

        with (
            patch.object(router, "USE_LOCAL_CLASSIFIER", False),
            patch.object(router.httpx, "AsyncClient", return_value=Client()),
        ):
            result = await router._classify(
                [{"role": "user", "content": "Compare two architectures"}],
                False,
            )

        self.assertEqual(
            result,
            (
                "mistral-medium",
                "Architecture analysis",
            ),
        )
        request = Client.post.await_args
        self.assertEqual(request.args[0], f"{router.LITELLM_URL}/chat/completions")
        self.assertEqual(
            request.kwargs["json"]["model"], router.CLOUD_CLASSIFIER_MODEL
        )

    async def test_cloud_classifier_failure_uses_default_model(self):
        class Client:
            post = AsyncMock(side_effect=router.httpx.ConnectError("offline"))

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_args):
                return None

        with (
            patch.object(router, "USE_LOCAL_CLASSIFIER", False),
            patch.object(router.httpx, "AsyncClient", return_value=Client()),
        ):
            result = await router._classify(
                [{"role": "user", "content": "Fix this code"}],
                True,
            )

        self.assertEqual(result, (router.DEFAULT_MODEL, ""))

    async def test_retry_routes_to_stronger_model_and_reports_path(self):
        body = {
            "model": "auto",
            "messages": [
                {"role": "assistant", "content": "Incomplete\n\n> **mistral-small**"},
                {"role": "user", "content": "That did not work. Try again."},
            ],
        }

        class Request:
            async def json(self):
                return body

        with (
            patch.object(
                router,
                "_classify",
                AsyncMock(
                    return_value=("mistral-small", "Simple request")
                ),
            ),
            patch.object(router, "_stream_to_backend", AsyncMock(return_value="ok")) as stream,
        ):
            self.assertEqual(await router.chat_completions(Request()), "ok")

        routed_body, candidates, notice_model, show_notice, reason = stream.await_args.args
        self.assertIs(routed_body, body)
        self.assertEqual(candidates[0], "mistral-medium")
        self.assertEqual(notice_model, "mistral-small")
        self.assertTrue(show_notice)
        self.assertEqual(reason, "")

    async def test_auto_route_forwards_classifier_reason(self):
        body = {
            "model": "auto",
            "messages": [{"role": "user", "content": "Compare two architectures"}],
        }

        class Request:
            async def json(self):
                return body

        reason = "Architectural tradeoffs"
        with (
            patch.object(
                router,
                "_classify",
                AsyncMock(return_value=("mistral-medium", reason)),
            ),
            patch.object(
                router, "_stream_to_backend", AsyncMock(return_value="ok")
            ) as stream,
        ):
            self.assertEqual(await router.chat_completions(Request()), "ok")

        self.assertEqual(stream.await_args.args[1][0], "mistral-medium")
        self.assertEqual(stream.await_args.args[2], "mistral-medium")
        self.assertEqual(stream.await_args.args[4], reason)

    async def test_coding_request_never_uses_mistral_small(self):
        body = {
            "model": "auto",
            "messages": [{"role": "user", "content": "Edit the config"}],
            "tools": [{"type": "function", "function": {"name": "bash"}}],
        }

        class Request:
            async def json(self):
                return body

        with (
            patch.object(
                router, "_classify", AsyncMock(return_value=("mistral-small", "Trivial"))
            ),
            patch.object(router, "_stream_to_backend", AsyncMock(return_value="ok")) as stream,
        ):
            self.assertEqual(await router.chat_completions(Request()), "ok")

        self.assertEqual(stream.await_args.args[1][0], "qwen3.7-plus")

    async def test_notice_suppressed_when_model_unchanged(self):
        body = {
            "model": "auto",
            "messages": [
                {"role": "assistant", "content": "Previous answer\n\n> **qwen3.7-plus**"},
                {"role": "user", "content": "Continue"},
            ],
        }

        class Request:
            async def json(self):
                return body

        with (
            patch.object(
                router, "_classify", AsyncMock(return_value=("qwen3.7-plus", "General dev"))
            ),
            patch.object(router, "_stream_to_backend", AsyncMock(return_value="ok")) as stream,
        ):
            await router.chat_completions(Request())

        _, _, _, show_notice, _ = stream.await_args.args
        self.assertFalse(show_notice)

    async def test_notice_shown_when_model_changes(self):
        body = {
            "model": "auto",
            "messages": [
                {"role": "assistant", "content": "Previous answer\n\n> **mistral-small**"},
                {"role": "user", "content": "Now do something harder"},
            ],
        }

        class Request:
            async def json(self):
                return body

        with (
            patch.object(
                router, "_classify", AsyncMock(return_value=("qwen3.7-plus", "Coding task"))
            ),
            patch.object(router, "_stream_to_backend", AsyncMock(return_value="ok")) as stream,
        ):
            await router.chat_completions(Request())

        _, _, _, show_notice, _ = stream.await_args.args
        self.assertTrue(show_notice)

    async def test_manual_model_skips_only_classification(self):
        body = {
            "model": "gpt-5.6-sol",
            "messages": [{"role": "user", "content": "Run all checks"}],
            "tools": [{"type": "function", "function": {"name": "bash"}}],
        }

        class Request:
            async def json(self):
                return body

        with (
            patch.object(router, "_classify", AsyncMock()) as classify,
            patch.object(
                router, "_stream_to_backend", AsyncMock(return_value="ok")
            ) as stream,
        ):
            self.assertEqual(await router.chat_completions(Request()), "ok")

        classify.assert_not_awaited()
        routed_body, candidates, notice_model, show_notice, reason = stream.await_args.args
        self.assertEqual(candidates[0], "gpt-5.6-sol")
        self.assertEqual(notice_model, "gpt-5.6-sol")
        self.assertFalse(show_notice)
        self.assertEqual(reason, "")
        self.assertIn(
            "one assignment and own it end to end",
            routed_body["messages"][0]["content"],
        )

    async def test_metadata_request_routes_to_mistral_small_without_classification(self):
        body = {
            "model": "auto",
            "messages": [
                {"role": "user", "content": "Generate a short title for this conversation"}
            ],
        }

        class Request:
            async def json(self):
                return body

        with (
            patch.object(router, "_classify", AsyncMock()) as classify,
            patch.object(
                router, "_stream_to_backend", AsyncMock(return_value="ok")
            ) as stream,
        ):
            self.assertEqual(await router.chat_completions(Request()), "ok")

        classify.assert_not_awaited()
        routed_body, candidates, notice_model, show_notice, reason = stream.await_args.args
        self.assertEqual(candidates[0], "mistral-small")
        self.assertEqual(notice_model, "mistral-small")
        self.assertFalse(show_notice)
        self.assertEqual(reason, "Titel/Summary")

    async def test_direct_title_request_keeps_cheap_fallback_chain(self):
        body = {
            "model": "mistral-small",
            "messages": [{"role": "user", "content": "Generate a short title"}],
        }

        class Request:
            async def json(self):
                return body

        with patch.object(
            router, "_stream_to_backend", AsyncMock(return_value="ok")
        ) as stream:
            self.assertEqual(await router.chat_completions(Request()), "ok")

        self.assertEqual(stream.await_args.args[1], router._metadata_fallback_chain())

    async def test_model_outage_tries_sibling_model_then_fails_over(self):
        class Response:
            is_success = False
            status_code = 429

            @staticmethod
            def json():
                return {"error": "rate limit exceeded"}

            text = "rate limit exceeded"

        class Client:
            post = AsyncMock(return_value=Response())

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_args):
                return None

        chatgpt = AsyncMock(return_value="chatgpt fallback")
        with (
            patch.object(router.httpx, "AsyncClient", return_value=Client()),
            patch.object(router, "_stream_chatgpt", chatgpt),
        ):
            result = await router._stream_to_backend(
                body={"stream": False},
                candidates=["mistral-small", "mistral-medium", "gpt-5.6-luna-openai"],
                original_model="mistral-small",
            )

        self.assertEqual(result, "chatgpt fallback")
        self.assertEqual(Client.post.await_count, 1)
        chatgpt.assert_awaited_once()

    async def test_server_error_skips_whole_provider_before_failing_over(self):
        class Response:
            is_success = False
            status_code = 503

            @staticmethod
            def json():
                return {"error": "provider unavailable"}

            text = "provider unavailable"

        class Client:
            post = AsyncMock(return_value=Response())

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_args):
                return None

        chatgpt = AsyncMock(return_value="chatgpt fallback")
        with (
            patch.object(router.httpx, "AsyncClient", return_value=Client()),
            patch.object(router, "_stream_chatgpt", chatgpt),
        ):
            result = await router._stream_to_backend(
                body={"stream": False},
                candidates=["mistral-small", "mistral-medium", "gpt-5.6-luna-openai"],
                original_model="mistral-small",
            )

        self.assertEqual(result, "chatgpt fallback")
        self.assertEqual(Client.post.await_count, 1)
        chatgpt.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
