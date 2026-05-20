#!/usr/bin/env python3
"""Tests for write_pool.py."""
import json
import os
import tempfile
import unittest

from lib.write_pool import parse_pool_lines, write_pool


class TestParsePoolLines(unittest.TestCase):
    def test_mixed_formats(self):
        result = parse_pool_lines(
            "sk-a\nsk-b|https://b.example/v1/\n# ignored\n\n",
            "https://default.example/v1/",
        )
        self.assertEqual(
            result,
            [
                {"api_key": "sk-a", "endpoint": "https://default.example/v1"},
                {"api_key": "sk-b", "endpoint": "https://b.example/v1"},
            ],
        )

    def test_triple_quotes_are_data(self):
        result = parse_pool_lines("sk-'''-still-data", "https://default.example/v1")
        self.assertEqual(result[0]["api_key"], "sk-'''-still-data")

    def test_drops_incomplete_entries(self):
        result = parse_pool_lines("|https://missing-key.example\nsk-ok|", "")
        self.assertEqual(result, [])


class TestWritePool(unittest.TestCase):
    def test_writes_json_and_chmods_600(self):
        with tempfile.NamedTemporaryFile(mode="w", delete=False) as input_file:
            input_file.write("sk-a\n")
            input_file.flush()
        with tempfile.TemporaryDirectory() as temp_dir:
            output_file = os.path.join(temp_dir, "pool.json")
            try:
                self.assertEqual(
                    write_pool(input_file.name, "https://default.example/v1", output_file),
                    1,
                )
                with open(output_file, encoding="utf-8") as file:
                    data = json.load(file)
                self.assertEqual(data[0]["api_key"], "sk-a")
                self.assertEqual(oct(os.stat(output_file).st_mode & 0o777), "0o600")
            finally:
                os.unlink(input_file.name)


if __name__ == "__main__":
    unittest.main()
