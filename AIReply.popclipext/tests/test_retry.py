#!/usr/bin/env python3
"""Tests for retry.py."""
import json
import os
import tempfile
import time
import unittest
from datetime import datetime, timezone

from lib.retry import (
    _mask_key,
    backoff_sleep,
    is_key_healthy,
    mark_key_unhealthy,
    parse_retry_after,
    skip_unhealthy_keys,
)


class TestMaskKey(unittest.TestCase):
    def test_short_key(self):
        self.assertEqual(_mask_key("sk-ab"), "sk-a***")

    def test_long_key(self):
        self.assertEqual(_mask_key("sk-abcdefghijklmnopqrstuvwxyz"), "sk-abcde***wxyz")

    def test_already_masked(self):
        self.assertEqual(_mask_key("sk-abc***"), "sk-abc***")

    def test_exactly_12(self):
        self.assertEqual(_mask_key("sk-1234567890"), "sk-12345***7890")


class TestParseRetryAfter(unittest.TestCase):
    def test_integer_seconds(self):
        headers = "HTTP/1.1 429 Too Many Requests\nRetry-After: 120\n"
        self.assertEqual(parse_retry_after(headers), 120.0)

    def test_http_date(self):
        # Use a fixed future date far enough ahead to avoid timing issues
        from datetime import timedelta
        future = datetime.now(timezone.utc) + timedelta(minutes=5)
        future = future.replace(second=0, microsecond=0)
        date_str = future.strftime("%a, %d %b %Y %H:%M:%S GMT")
        headers = f"Retry-After: {date_str}"
        result = parse_retry_after(headers)
        # Allow a wide window because parsedate_to_datetime may not preserve tz exactly
        self.assertTrue(240 <= result <= 320, f"Expected ~300, got {result}")

    def test_case_insensitive(self):
        headers = "retry-after: 30"
        self.assertEqual(parse_retry_after(headers), 30.0)

    def test_missing(self):
        self.assertEqual(parse_retry_after("Content-Type: application/json"), 0.0)

    def test_malformed_date_fallback(self):
        headers = "Retry-After: not-a-date"
        self.assertEqual(parse_retry_after(headers), 5.0)


class TestBackoffSleep(unittest.TestCase):
    def test_backoff_values(self):
        self.assertEqual(backoff_sleep(1, base=0.5, max_wait=4.0), 0.5)
        self.assertEqual(backoff_sleep(2, base=0.5, max_wait=4.0), 1.0)
        self.assertEqual(backoff_sleep(3, base=0.5, max_wait=4.0), 2.0)
        self.assertEqual(backoff_sleep(4, base=0.5, max_wait=4.0), 4.0)
        self.assertEqual(backoff_sleep(10, base=0.5, max_wait=4.0), 4.0)


class TestKeyHealth(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.health_file = os.path.join(self.tmpdir.name, "health.json")
        os.environ["AI_REPLY_KEY_HEALTH_FILE"] = self.health_file

    def tearDown(self):
        self.tmpdir.cleanup()
        del os.environ["AI_REPLY_KEY_HEALTH_FILE"]

    def test_mark_and_check(self):
        mark_key_unhealthy("sk-abc***", "rate_limited", cooldown_seconds=1)
        self.assertFalse(is_key_healthy("sk-abc***"))
        time.sleep(2)
        self.assertTrue(is_key_healthy("sk-abc***"))

    def test_missing_file_is_healthy(self):
        self.assertTrue(is_key_healthy("sk-any***"))

    def test_file_permissions(self):
        mark_key_unhealthy("sk-abc***", "test", cooldown_seconds=60)
        mode = os.stat(self.health_file).st_mode & 0o777
        self.assertEqual(mode, 0o600)


class TestSkipUnhealthyKeys(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.health_file = os.path.join(self.tmpdir.name, "health.json")
        os.environ["AI_REPLY_KEY_HEALTH_FILE"] = self.health_file

    def tearDown(self):
        self.tmpdir.cleanup()
        del os.environ["AI_REPLY_KEY_HEALTH_FILE"]

    def test_all_healthy(self):
        pairs = "sk-a|https://a.com/v1 sk-b|https://b.com/v1"
        self.assertEqual(skip_unhealthy_keys(pairs), pairs)

    def test_skips_unhealthy(self):
        mark_key_unhealthy(_mask_key("sk-bad"), "rate_limited", cooldown_seconds=60)
        pairs = "sk-ok|https://a.com/v1 sk-bad|https://b.com/v1"
        result = skip_unhealthy_keys(pairs)
        self.assertEqual(result, "sk-ok|https://a.com/v1")

    def test_fallback_when_all_unhealthy(self):
        mark_key_unhealthy(_mask_key("sk-a"), "rate_limited", cooldown_seconds=60)
        mark_key_unhealthy(_mask_key("sk-b"), "rate_limited", cooldown_seconds=60)
        pairs = "sk-a|https://a.com/v1 sk-b|https://b.com/v1"
        result = skip_unhealthy_keys(pairs)
        self.assertEqual(result, pairs)

    def test_empty_input(self):
        self.assertEqual(skip_unhealthy_keys(""), "")
        self.assertEqual(skip_unhealthy_keys("   "), "   ")


if __name__ == "__main__":
    unittest.main()
