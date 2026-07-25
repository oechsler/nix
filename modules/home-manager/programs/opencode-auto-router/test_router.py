import unittest
from unittest.mock import AsyncMock, patch

import router


class RouterTest(unittest.TestCase):
    def setUp(self):
        router._provider_unavailable_until.clear()
        router._classification_cache.clear()

    def test_fallback_chain_follows_all_configured_backends(self):
        self.assertEqual(
            router._fallback_chain("mistral-small"),
            ["mistral-small", "mistral-medium", "openai-terra", "openai-sol", "openai-luna", "openai-terra-fast", "openai-sol-fast", "openai-luna-fast", "deepseek-v4-flash", "qwen3:8b"],
        )

    def test_every_fallback_chain_ends_with_local_model(self):
        for model in router.DIRECT_MODELS:
            with self.subTest(model=model):
                chain = router._fallback_chain(model)
                self.assertIn("qwen3:8b", chain)
                self.assertEqual(
                    {router._provider(candidate) for candidate in chain},
                    {"mistral", "opencode-go", "chatgpt", "ollama"},
                )

    def test_cloud_classifier_hosts_exclude_ollama_fallbacks(self):
        with patch.object(router, "USE_LOCAL_CLASSIFIER", False):
            chain = router._fallback_chain("mistral-small")

        self.assertNotIn("qwen3:8b", chain)
        self.assertNotIn("ollama", {router._provider(model) for model in chain})

    def test_provider_failure_temporarily_disables_all_provider_models(self):
        router._mark_provider_failure("mistral-small", "test outage")
        self.assertFalse(router._provider_available("mistral-small"))
        self.assertFalse(router._provider_available("mistral-medium"))
        self.assertTrue(router._provider_available("openai-luna"))

        router._mark_provider_success("mistral-medium")
        self.assertTrue(router._provider_available("mistral-small"))

    def test_notice_is_minimal_for_initial_route(self):
        self.assertEqual(router._model_notice_text("mistral-small", "mistral-small"), "> **mistral-small**")

    def test_notice_shows_fallback_path(self):
        self.assertEqual(
            router._model_notice_text("mistral-medium", "mistral-small"),
            "> **mistral-small -> mistral-medium**",
        )

    def test_notice_includes_classifier_reason_on_second_line(self):
        self.assertEqual(
            router._model_notice_text(
                "mistral-medium",
                "mistral-medium",
                "Weil die Aufgabe Architekturabwägungen erfordert.",
            ),
            "> **mistral-medium**\n> Weil die Aufgabe Architekturabwägungen erfordert",
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
                "openai-sol-fast", reason="Complex debugging and refactoring"
            ),
            "> **openai-sol-fast**\n> Complex debugging and refactoring",
        )

    def test_classifier_choice_requires_reason(self):
        self.assertIsNone(router._parse_model_choice("mistral-medium"))

    def test_terminal_stream_chunk_is_detected(self):
        line = 'data: {"choices":[{"finish_reason":"stop","delta":{}}]}'
        self.assertTrue(router._is_terminal_chunk(line))
        self.assertFalse(router._is_terminal_chunk("data: [DONE]"))

    def test_agent_instruction_requires_end_to_end_completion(self):
        body = {"messages": [{"role": "user", "content": "Do all three tasks"}]}

        forwarded = router._add_agent_instruction(body, has_tools=True)

        instruction = forwarded["messages"][0]["content"]
        self.assertIn("keep working until all of them are completed", instruction)
        self.assertIn("Do not stop after analysis, after one subtask", instruction)
        self.assertIn("implementation and verification", instruction)
        self.assertIn("todo tool", instruction)
        self.assertEqual(body["messages"][0]["role"], "user")

    def test_agent_instruction_is_not_added_without_tools(self):
        body = {"messages": [{"role": "user", "content": "Explain this"}]}

        self.assertIs(router._add_agent_instruction(body, has_tools=False), body)

    def test_classifier_treats_multiple_deliverables_as_complex_agentic(self):
        prompt = router._build_classification_prompt("user: Do all five tasks", True)

        self.assertIn("Requests with several deliverables", prompt)
        self.assertIn("explicitly asks the agent to continue until completion", prompt)

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
        self.assertEqual(router._capability_escalation(messages), "openai-terra")

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
            router._more_capable_model("openai-terra", "mistral-medium"),
            "openai-terra",
        )

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
            response, "openai-sol", show_notice=False
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
            "openai-sol-fast",
            original_model="auto",
            classification_reason="Complex debugging and refactoring",
        )

        content = converted["choices"][0]["message"]["content"]
        self.assertTrue(content.startswith("> **auto -> openai-sol-fast**\n> Complex debugging and refactoring\n\n"))
        self.assertTrue(content.endswith("Finished"))


class ChatCompletionsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        router._provider_unavailable_until.clear()
        router._classification_cache.clear()

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

    async def test_manual_model_skips_only_classification(self):
        body = {
            "model": "openai-sol",
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
        self.assertEqual(candidates[0], "openai-sol")
        self.assertEqual(notice_model, "openai-sol")
        self.assertFalse(show_notice)
        self.assertEqual(reason, "")
        self.assertIn(
            "keep working until all of them are completed",
            routed_body["messages"][0]["content"],
        )

    async def test_provider_outage_skips_sibling_model_and_fails_over(self):
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
                candidates=["mistral-small", "mistral-medium", "openai-luna"],
                original_model="mistral-small",
            )

        self.assertEqual(result, "chatgpt fallback")
        self.assertEqual(Client.post.await_count, 1)
        chatgpt.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
