#!/usr/bin/env python3
"""Parse an HTTP response body and either print the reply content or
print a structured error message and exit non-zero.

Usage: parse_response.py <http_status> <body_file>

Stdout (success): the assistant's text content
Exit code 0 on success, 1 on any error (with a human-readable line on stdout).
"""
import json
import pathlib
import sys


def _load(path: str):
    try:
        raw = pathlib.Path(path).read_text(encoding="utf-8", errors="replace").strip()
    except OSError as e:
        return None, f"Failed to read response body file. {e}"
    if not raw:
        return None, "Empty response body."
    if raw.startswith("﻿"):
        raw = raw[1:]
    try:
        return json.loads(raw), None
    except json.JSONDecodeError as e:
        # Try to recover an embedded JSON object (some gateways prepend/append junk).
        start = raw.find("{")
        end = raw.rfind("}")
        if start != -1 and end > start:
            try:
                return json.loads(raw[start:end + 1]), None
            except json.JSONDecodeError as e2:
                return None, f"Failed to parse JSON response. {e}; recovery: {e2}"
        return None, f"Failed to parse JSON response. {e}"


def _format_error(data) -> str:
    err = data.get("error") if isinstance(data, dict) else None
    if isinstance(err, dict):
        return err.get("message") or json.dumps(err, ensure_ascii=False)
    if err:
        return str(err)
    return "Unknown API error"


def main(argv) -> int:
    if len(argv) < 3:
        print("parse_response.py: missing arguments")
        return 1
    status = argv[1]
    body_path = argv[2]

    data, err = _load(body_path)

    if status != "200":
        # Prefer a structured error if present, otherwise fall back to HTTP status.
        if isinstance(data, dict) and "error" in data:
            print("API Error: " + _format_error(data))
        elif err:
            print(f"HTTP {status}: {err}")
        else:
            print(f"HTTP {status}")
        return 1

    if err:
        print(err)
        return 1

    if isinstance(data, dict) and "error" in data:
        print("API Error: " + _format_error(data))
        return 1

    try:
        choices = data.get("choices") if isinstance(data, dict) else None
        if choices and len(choices) > 0:
            content = choices[0]["message"]["content"]
            sys.stdout.write(content)
            return 0
        print("No 'choices' in API response.")
        return 1
    except (KeyError, TypeError) as e:
        print(f"Unexpected response format. {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
