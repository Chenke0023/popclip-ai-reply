#!/usr/bin/env python3
"""Tests for build_payload.py."""
import json
import os
import sys
import unittest
from io import StringIO

# Ensure lib/ is on path so we can import build_payload
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from build_payload import main as build_main, STYLE_INSTRUCTIONS, _truthy


class TestTruthy(unittest.TestCase):
    def test_truthy_values(self):
        for v in ("1", "true", "yes", "on", "TRUE", " True "):
            self.assertTrue(_truthy(v), f"expected {v!r} to be truthy")

    def test_falsy_values(self):
        for v in ("", "0", "false", "no", "off", "maybe", None):
            self.assertFalse(_truthy(v), f"expected {v!r} to be falsy")


class TestBuildPayloadMain(unittest.TestCase):
    def setUp(self):
        self._old_env = dict(os.environ)
        self._clear_env()

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self._old_env)

    def _clear_env(self):
        for key in list(os.environ.keys()):
            if key.startswith("AI_REPLY_"):
                del os.environ[key]

    def _capture(self):
        self.stdout = StringIO()
        self.stderr = StringIO()
        self._old_stdout = sys.stdout
        self._old_stderr = sys.stderr
        sys.stdout = self.stdout
        sys.stderr = self.stderr

    def _restore_stdio(self):
        sys.stdout = self._old_stdout
        sys.stderr = self._old_stderr

    def test_basic_payload(self):
        os.environ["AI_REPLY_INPUT_TEXT"] = "Hello, how are you?"
        os.environ["AI_REPLY_MODEL"] = "gpt-4o"
        self._capture()
        try:
            rc = build_main()
        finally:
            self._restore_stdio()
        self.assertEqual(rc, 0)
        payload = json.loads(self.stdout.getvalue())
        self.assertEqual(payload["model"], "gpt-4o")
        self.assertEqual(payload["temperature"], 0.4)
        self.assertEqual(len(payload["messages"]), 2)
        self.assertEqual(payload["messages"][0]["role"], "system")
        self.assertIn("Email content:", payload["messages"][1]["content"])
        self.assertIn("Hello, how are you?", payload["messages"][1]["content"])

    def test_followup_payload(self):
        os.environ["AI_REPLY_INPUT_TEXT"] = "Meeting at 3pm?"
        os.environ["AI_REPLY_DRAFT_REPLY"] = "Sure, see you then."
        os.environ["AI_REPLY_FOLLOWUP_PROMPT"] = "Make it shorter"
        os.environ["AI_REPLY_MODEL"] = "gpt-4o"
        self._capture()
        try:
            rc = build_main()
        finally:
            self._restore_stdio()
        self.assertEqual(rc, 0)
        payload = json.loads(self.stdout.getvalue())
        content = payload["messages"][1]["content"]
        self.assertIn("Current draft reply:", content)
        self.assertIn("Follow-up request:", content)
        self.assertIn("Rewrite the draft reply", content)

    def test_mail_thread_injection(self):
        thread = {
            "source": "mail_app",
            "subject": "Re: Budget",
            "latest": {"from": "a@b.com", "date": "2026-05-20", "body": "Latest body"},
            "thread": [
                {"from": "c@d.com", "date": "2026-05-19", "body": "First message"},
                {"from": "e@f.com", "date": "2026-05-20", "body": "Latest body"},
            ],
        }
        os.environ["AI_REPLY_INPUT_TEXT"] = "Latest body"
        os.environ["AI_REPLY_MAIL_THREAD_JSON"] = json.dumps(thread)
        os.environ["AI_REPLY_MODEL"] = "gpt-4o"
        self._capture()
        try:
            rc = build_main()
        finally:
            self._restore_stdio()
        self.assertEqual(rc, 0)
        payload = json.loads(self.stdout.getvalue())
        content = payload["messages"][1]["content"]
        self.assertIn("Email subject: Re: Budget", content)
        self.assertIn("Previous messages in this thread", content)
        self.assertIn("First message", content)
        # Latest body should be deduplicated (not in thread history)
        self.assertEqual(content.count("Latest body"), 1)

    def test_custom_system_prompt(self):
        os.environ["AI_REPLY_INPUT_TEXT"] = "Hi"
        os.environ["AI_REPLY_SYSTEM_PROMPT"] = "Custom prompt"
        os.environ["AI_REPLY_MODEL"] = "gpt-4o"
        self._capture()
        try:
            rc = build_main()
        finally:
            self._restore_stdio()
        self.assertEqual(rc, 0)
        payload = json.loads(self.stdout.getvalue())
        self.assertEqual(payload["messages"][0]["content"], "Custom prompt")

    def test_temperature_parsing(self):
        os.environ["AI_REPLY_INPUT_TEXT"] = "Hi"
        os.environ["AI_REPLY_TEMPERATURE_RAW"] = "0.9"
        os.environ["AI_REPLY_MODEL"] = "gpt-4o"
        self._capture()
        try:
            rc = build_main()
        finally:
            self._restore_stdio()
        payload = json.loads(self.stdout.getvalue())
        self.assertEqual(payload["temperature"], 0.9)

    def test_invalid_temperature_fallback(self):
        os.environ["AI_REPLY_INPUT_TEXT"] = "Hi"
        os.environ["AI_REPLY_TEMPERATURE_RAW"] = "hot"
        os.environ["AI_REPLY_MODEL"] = "gpt-4o"
        self._capture()
        try:
            rc = build_main()
        finally:
            self._restore_stdio()
        payload = json.loads(self.stdout.getvalue())
        self.assertEqual(payload["temperature"], 0.4)

    def test_user_and_runtime_prompts(self):
        os.environ["AI_REPLY_INPUT_TEXT"] = "Hi"
        os.environ["AI_REPLY_USER_PROMPT"] = "Always sign off with 'Best'"
        os.environ["AI_REPLY_RUNTIME_PROMPT"] = "Also mention the deadline"
        os.environ["AI_REPLY_MODEL"] = "gpt-4o"
        self._capture()
        try:
            rc = build_main()
        finally:
            self._restore_stdio()
        payload = json.loads(self.stdout.getvalue())
        content = payload["messages"][1]["content"]
        self.assertIn("User instructions:", content)
        self.assertIn("Always sign off with 'Best'", content)
        self.assertIn("Additional user requirements:", content)
        self.assertIn("Also mention the deadline", content)

    def test_auto_language_false(self):
        os.environ["AI_REPLY_INPUT_TEXT"] = "Bonjour"
        os.environ["AI_REPLY_AUTO_LANGUAGE"] = "false"
        os.environ["AI_REPLY_MODEL"] = "gpt-4o"
        self._capture()
        try:
            rc = build_main()
        finally:
            self._restore_stdio()
        payload = json.loads(self.stdout.getvalue())
        system = payload["messages"][0]["content"]
        self.assertNotIn("same language", system)

    def test_invalid_reply_style_fallback(self):
        os.environ["AI_REPLY_INPUT_TEXT"] = "Hi"
        os.environ["AI_REPLY_STYLE"] = "sassy"
        os.environ["AI_REPLY_MODEL"] = "gpt-4o"
        self._capture()
        try:
            rc = build_main()
        finally:
            self._restore_stdio()
        payload = json.loads(self.stdout.getvalue())
        system = payload["messages"][0]["content"]
        self.assertIn(STYLE_INSTRUCTIONS["professional"], system)


if __name__ == "__main__":
    unittest.main()
