#!/usr/bin/env python3
"""Tests for load_pool.py."""
import io
import os
import sys
import tempfile
import unittest

from lib.load_pool import main as pool_main, _normalize


class TestNormalize(unittest.TestCase):
    def test_valid_pool(self):
        pool = [
            {"api_key": "sk-a", "endpoint": "https://api.openai.com/v1"},
            {"api_key": "sk-b", "endpoint": "https://api.deepseek.com/v1/"},
        ]
        result = _normalize(pool)
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0], "sk-a|https://api.openai.com/v1")
        self.assertEqual(result[1], "sk-b|https://api.deepseek.com/v1")

    def test_missing_fields(self):
        pool = [
            {"api_key": "", "endpoint": "https://a.com/v1"},
            {"api_key": "sk-b", "endpoint": ""},
            {"api_key": "sk-c", "endpoint": "https://c.com/v1"},
        ]
        result = _normalize(pool)
        self.assertEqual(result, ["sk-c|https://c.com/v1"])

    def test_not_a_list(self):
        self.assertEqual(_normalize({"key": "val"}), [])
        self.assertEqual(_normalize("string"), [])

    def test_non_dict_items(self):
        pool = [{"api_key": "sk-a", "endpoint": "https://a.com/v1"}, "bad"]
        result = _normalize(pool)
        self.assertEqual(result, ["sk-a|https://a.com/v1"])


class TestLoadPoolMain(unittest.TestCase):
    def test_stdin_json(self):
        old_stdin = sys.stdin
        try:
            sys.stdin = io.StringIO(
                '[{"api_key":"sk-x","endpoint":"https://x.com/v1"}]'
            )
            old_stdout = sys.stdout
            sys.stdout = io.StringIO()
            try:
                self.assertEqual(pool_main(), 0)
                self.assertIn("sk-x|https://x.com/v1", sys.stdout.getvalue())
            finally:
                sys.stdout = old_stdout
        finally:
            sys.stdin = old_stdin

    def test_empty_stdin(self):
        old_stdin = sys.stdin
        try:
            sys.stdin = io.StringIO("")
            self.assertEqual(pool_main(), 0)
        finally:
            sys.stdin = old_stdin

    def test_invalid_json(self):
        old_stdin = sys.stdin
        try:
            sys.stdin = io.StringIO("not json")
            self.assertEqual(pool_main(), 1)
        finally:
            sys.stdin = old_stdin

    def test_file_env(self):
        pool_json = '[{"api_key":"sk-f","endpoint":"https://f.com/v1"}]'
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write(pool_json)
            f.flush()
            old_env = os.environ.get("AI_REPLY_POOL_FILE")
            os.environ["AI_REPLY_POOL_FILE"] = f.name
            try:
                old_stdout = sys.stdout
                sys.stdout = io.StringIO()
                try:
                    self.assertEqual(pool_main(), 0)
                    self.assertIn("sk-f|https://f.com/v1", sys.stdout.getvalue())
                finally:
                    sys.stdout = old_stdout
            finally:
                if old_env is not None:
                    os.environ["AI_REPLY_POOL_FILE"] = old_env
                else:
                    del os.environ["AI_REPLY_POOL_FILE"]
                os.unlink(f.name)

    def test_nonexistent_file(self):
        old_env = os.environ.get("AI_REPLY_POOL_FILE")
        os.environ["AI_REPLY_POOL_FILE"] = "/tmp/does_not_exist_12345.json"
        try:
            old_stdin = sys.stdin
            sys.stdin = io.StringIO("")
            try:
                self.assertEqual(pool_main(), 0)
            finally:
                sys.stdin = old_stdin
        finally:
            if old_env is not None:
                os.environ["AI_REPLY_POOL_FILE"] = old_env
            else:
                del os.environ["AI_REPLY_POOL_FILE"]


if __name__ == "__main__":
    unittest.main()