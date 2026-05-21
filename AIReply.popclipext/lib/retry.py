#!/usr/bin/env python3
"""Exponential backoff, Retry-After parsing, and key health tracking.

Used by reply.zsh / dialog.zsh for retry decisions and by the
API pool driver to avoid repeatedly hitting broken or rate-limited keys.
"""
import json
import os
import pathlib
import re
import time
from datetime import datetime, timezone


def _health_file() -> str:
    """Return the path to the key-health JSON file.

    Evaluated at call time so that tests can mutate the env var
    and see the new path immediately.
    """
    return os.path.expanduser(
        os.environ.get("AI_REPLY_KEY_HEALTH_FILE",
                       "~/Library/Logs/AIReplyPopClip/key_health.json")
    )


def parse_retry_after(headers_text: str) -> float:
    """Extract Retry-After seconds from HTTP headers (case-insensitive).
    Supports both integer seconds and HTTP-date formats. Returns 0 when absent.
    """
    for line in headers_text.splitlines():
        m = re.match(r"(?i)^retry-after:\s*(.+)$", line.strip())
        if m:
            val = m.group(1).strip()
            if val.isdigit():
                return float(val)
            # HTTP-date — parse and diff from now.
            try:
                from email.utils import parsedate_to_datetime
                dt = parsedate_to_datetime(val)
                delta = (dt - datetime.now(timezone.utc)).total_seconds()
                return max(0.0, delta)
            except (ValueError, TypeError, ImportError):
                return 5.0  # conservative default
    return 0.0


def backoff_sleep(attempt: int, base: float = 0.5, max_wait: float = 4.0) -> float:
    """Return seconds to sleep for attempt N (1-indexed), cap at max_wait."""
    wait = min(base * (2 ** (attempt - 1)), max_wait)
    time.sleep(wait)
    return wait


def mark_key_unhealthy(api_key_masked: str, reason: str, cooldown_seconds: int = 60):
    """Persist a cooldown_until timestamp for a masked key."""
    health_file = _health_file()
    try:
        pathlib.Path(health_file).parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        return

    health = {}
    try:
        raw = pathlib.Path(health_file).read_text(encoding="utf-8")
        health = json.loads(raw) if raw.strip() else {}
    except (OSError, json.JSONDecodeError):
        health = {}

    cooldown_until = int(time.time()) + cooldown_seconds
    health[api_key_masked] = {
        "cooldown_until": cooldown_until,
        "reason": reason,
        "updated": datetime.now(timezone.utc).isoformat(),
    }

    try:
        # Use os.open with O_CREAT and mode 0o600 to avoid TOCTOU race condition
        fd = os.open(health_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(health, f, indent=2)
    except OSError:
        pass


def is_key_healthy(api_key_masked: str) -> bool:
    """Check whether a key is past its cooldown."""
    health_file = _health_file()
    try:
        health = json.loads(pathlib.Path(health_file).read_text(encoding="utf-8"))
        entry = health.get(api_key_masked)
        if entry and isinstance(entry, dict):
            return int(time.time()) > entry.get("cooldown_until", 0)
    except (OSError, json.JSONDecodeError):
        pass
    return True


def skip_unhealthy_keys(pairs: str) -> str:
    """Given space-separated 'api_key|endpoint' entries, return only the
    healthy ones (in their original order)."""
    if not pairs.strip():
        return pairs
    healthy = []
    for p in pairs.strip().split():
        key = p.split("|", 1)[0]
        masked = _mask_key(key)
        if is_key_healthy(masked):
            healthy.append(p)
    return " ".join(healthy) if healthy else pairs  # fallback to all if none healthy


def _mask_key(api_key: str) -> str:
    """Return masked key for safe logging and health-file lookup.

    The mask format is stable regardless of key length so that callers
    who already have a masked key (e.g. reply.zsh passing ${k:0:8}***)
    can use it directly, while callers with the full key get the same
    result after masking.
    """
    # If the caller already passed a masked key (contains ***), return as-is.
    if "***" in api_key:
        return api_key
    if len(api_key) <= 12:
        return api_key[:4] + "***"
    return api_key[:8] + "***" + api_key[-4:]


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: retry.py <command> [args...]", file=sys.stderr)
        print("  parse-retry-after <headers_file>", file=sys.stderr)
        print("  mark-unhealthy <masked_key> <reason> [cooldown_seconds]", file=sys.stderr)
        print("  is-healthy <masked_key>", file=sys.stderr)
        print("  skip-unhealthy <pool_string>", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "parse-retry-after":
        path = sys.argv[2] if len(sys.argv) > 2 else ""
        text = pathlib.Path(path).read_text(encoding="utf-8", errors="replace") if path else ""
        print(int(parse_retry_after(text)))

    elif cmd == "mark-unhealthy":
        key = sys.argv[2] if len(sys.argv) > 2 else ""
        reason = sys.argv[3] if len(sys.argv) > 3 else "unknown"
        cooldown = int(sys.argv[4]) if len(sys.argv) > 4 else 60
        mark_key_unhealthy(key, reason, cooldown)
        print("ok")

    elif cmd == "is-healthy":
        key = sys.argv[2] if len(sys.argv) > 2 else ""
        print("true" if is_key_healthy(key) else "false")

    elif cmd == "skip-unhealthy":
        pairs = sys.argv[2] if len(sys.argv) > 2 else ""
        print(skip_unhealthy_keys(pairs))