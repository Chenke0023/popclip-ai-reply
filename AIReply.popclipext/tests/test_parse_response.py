#!/usr/bin/env python3
"""Tests for parse_response.py."""
import json
import os
import tempfile
import unittest

from lib.parse_response import main as parse_main


def _body_file(content: str) -> str:
    tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False)
    tmp.write(content)
    tmp.close()
    return tmp.name


class TestParseResponse(unittest.TestCase):
    def test_success(self):
        body = json.dumps({"choices": [{"message": {"content": "Hello"}}]})
        path = _body_file(body)
        try:
            self.assertEqual(parse_main(["prog", "200", path]), 0)
        finally:
            os.unlink(path)

    def test_empty_choices(self):
        body = json.dumps({"choices": []})
        path = _body_file(body)
        try:
            self.assertEqual(parse_main(["prog", "200", path]), 1)
        finally:
            os.unlink(path)

    def test_no_choices_key(self):
        body = json.dumps({"data": []})
        path = _body_file(body)
        try:
            self.assertEqual(parse_main(["prog", "200", path]), 1)
        finally:
            os.unlink(path)

    def test_http_401(self):
        body = json.dumps({"error": {"message": "Unauthorized"}})
        path = _body_file(body)
        try:
            self.assertEqual(parse_main(["prog", "401", path]), 1)
        finally:
            os.unlink(path)

    def test_http_403(self):
        path = _body_file("{}")
        try:
            self.assertEqual(parse_main(["prog", "403", path]), 1)
        finally:
            os.unlink(path)

    def test_http_429(self):
        path = _body_file("{}")
        try:
            self.assertEqual(parse_main(["prog", "429", path]), 1)
        finally:
            os.unlink(path)

    def test_http_5xx(self):
        path = _body_file("{}")
        try:
            self.assertEqual(parse_main(["prog", "500", path]), 1)
        finally:
            os.unlink(path)

    def test_non_json_response(self):
        body = "<html>gateway error</html>"
        path = _body_file(body)
        try:
            self.assertEqual(parse_main(["prog", "200", path]), 1)
        finally:
            os.unlink(path)

    def test_bom_prefix(self):
        body = "﻿" + json.dumps(
            {"choices": [{"message": {"content": "ok"}}]}
        )
        path = _body_file(body)
        try:
            self.assertEqual(parse_main(["prog", "200", path]), 0)
        finally:
            os.unlink(path)

    def test_gateway_junk_around_json(self):
        body = 'pre\n{"choices":[{"message":{"content":"ok"}}]}\npost'
        path = _body_file(body)
        try:
            self.assertEqual(parse_main(["prog", "200", path]), 0)
        finally:
            os.unlink(path)

    def test_empty_body(self):
        path = _body_file("")
        try:
            self.assertEqual(parse_main(["prog", "200", path]), 1)
        finally:
            os.unlink(path)

    def test_missing_args(self):
        self.assertEqual(parse_main(["prog"]), 1)
        self.assertEqual(parse_main(["prog", "200"]), 1)

    def test_missing_content_key(self):
        body = json.dumps({"choices": [{"message": {}}]})
        path = _body_file(body)
        try:
            self.assertEqual(parse_main(["prog", "200", path]), 1)
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main()