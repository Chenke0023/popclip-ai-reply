#!/usr/bin/env python3
"""Fetch /models from an OpenAI-compatible endpoint and print one id per line.

Reads endpoint + api key from a body file produced by curl.
Usage: fetch_models.py <body_file>
"""
import json
import pathlib
import sys


def main(argv) -> int:
    if len(argv) < 2:
        print("fetch_models.py: missing body file", file=sys.stderr)
        return 1
    try:
        raw = pathlib.Path(argv[1]).read_text(encoding="utf-8", errors="replace").strip()
    except OSError as e:
        print(f"Read failed: {e}", file=sys.stderr)
        return 1
    if not raw:
        print("Empty response", file=sys.stderr)
        return 1

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"JSON parse error: {e}", file=sys.stderr)
        return 1

    if isinstance(data, dict) and "error" in data:
        err = data["error"]
        msg = err.get("message") if isinstance(err, dict) else str(err)
        print(f"API Error: {msg}", file=sys.stderr)
        return 1

    items = data.get("data") if isinstance(data, dict) else None
    if not isinstance(items, list):
        print("Unexpected response shape (no 'data' array)", file=sys.stderr)
        return 1

    ids = []
    for item in items:
        if isinstance(item, dict):
            mid = item.get("id")
            if isinstance(mid, str) and mid:
                ids.append(mid)

    if not ids:
        print("No models returned", file=sys.stderr)
        return 1

    ids.sort(key=str.lower)
    for mid in ids:
        print(mid)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
