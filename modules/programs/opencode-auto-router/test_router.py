import unittest
from unittest.mock import AsyncMock, patch

import router


class RouterTest(unittest.TestCase):
    def test_fallback_chain_follows_all_configured_backends(self):
        self.assertEqual(
            router._fallback_chain("mistral-small"),
            ["mistral-small", "mistral-medium", "openai-terra", "openai-sol", "openai-luna", "openai-terra-fast", "openai-sol-fast", "openai-luna-fast", "deepseek-v4-flash"],
        )

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


if __name__ == "__main__":
    unittest.main()
