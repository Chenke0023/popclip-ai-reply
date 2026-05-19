#!/usr/bin/env python3
"""Load an API-key pool from either a JSON file or a JSON string.

Order:
  1. If $AI_REPLY_POOL_FILE points to a readable file, parse that.
  2. Else parse the JSON string passed on stdin.

Output: space-separated "api_key|endpoint" pairs on stdout.
Exit code 0 on success (or empty pool), 1 on parse error.
"""
import json
import os
import pathlib
import sys


def _normalize(pool) -> list[str]:
    if not isinstance(pool, list):
        return []
    pairs = []
    for item in pool:
        if not isinstance(item, dict):
            continue
        api_key = (item.get("api_key") or "").strip()
        endpoint = (item.get("endpoint") or "").strip().rstrip("/")
        if api_key and endpoint:
            pairs.append(f"{api_key}|{endpoint}")
    return pairs


def main() -> int:
    pool_file = (os.environ.get("AI_REPLY_POOL_FILE") or "").strip()
    raw = ""

    if pool_file:
        expanded = os.path.expanduser(pool_file)
        try:
            raw = pathlib.Path(expanded).read_text(encoding="utf-8").strip()
        except OSError:
            raw = ""

    if not raw:
        raw = sys.stdin.read().strip()

    if not raw:
        return 0

    try:
        pool = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"pool parse error: {e}", file=sys.stderr)
        return 1

    pairs = _normalize(pool)
    print(" ".join(pairs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
