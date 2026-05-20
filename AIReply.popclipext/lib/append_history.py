#!/usr/bin/env python3
"""Append a successful generation to history.jsonl.

Reads from env vars to avoid argv length issues with long emails/replies.
"""
import datetime as dt
import json
import os
import pathlib
import sys


def main() -> int:
    history_path = os.environ.get("AI_REPLY_HISTORY_PATH")
    if not history_path:
        return 0
    record = {
        "ts": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "model": os.environ.get("AI_REPLY_MODEL", ""),
        "style": os.environ.get("AI_REPLY_STYLE", ""),
        "language": os.environ.get("AI_REPLY_DETECTED_LANGUAGE", ""),
        "input": os.environ.get("AI_REPLY_INPUT_TEXT", ""),
        "runtime_prompt": os.environ.get("AI_REPLY_RUNTIME_PROMPT", ""),
        "reply": os.environ.get("AI_REPLY_FINAL_REPLY", ""),
    }
    try:
        path = pathlib.Path(history_path).expanduser()
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
        os.chmod(path, 0o600)
    except OSError as e:
        print(f"history write failed: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
