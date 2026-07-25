import unittest
from unittest.mock import AsyncMock, patch

import router


class RouterTest(unittest.TestCase):
    def setUp(self):
        router._provider_unavailable_until.clear()

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

    def test_terminal_stream_chunk_is_detected(self):
        line = 'data: {"choices":[{"finish_reason":"stop","delta":{}}]}'
        self.assertTrue(router._is_terminal_chunk(line))
        self.assertFalse(router._is_terminal_chunk("data: [DONE]"))

    def test_failed_attempt_escalates_previous_model(self):
        messages = [
            {"role": "assistant", "content": "An incomplete answer\n\n> **mistral-small**"},
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
            {"role": "assistant", "content": "Initial answer\n\n> **mistral-small**"},
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


class ChatCompletionsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        router._provider_unavailable_until.clear()

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
            patch.object(router, "_classify", AsyncMock(return_value="mistral-small")),
            patch.object(router, "_stream_to_backend", AsyncMock(return_value="ok")) as stream,
        ):
            self.assertEqual(await router.chat_completions(Request()), "ok")

        routed_body, candidates, notice_model, show_notice = stream.await_args.args
        self.assertIs(routed_body, body)
        self.assertEqual(candidates[0], "mistral-medium")
        self.assertEqual(notice_model, "mistral-small")
        self.assertTrue(show_notice)

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
