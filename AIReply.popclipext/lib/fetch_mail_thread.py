#!/usr/bin/env python3
"""Fetch the current Mail.app thread via AppleScript and return structured JSON.

Output (stdout):
  JSON object:
    {
      "source": "mail_app",
      "subject": "Re: Q2 budget",
      "latest": {
        "from": "alice@example.com",
        "date": "2026-05-19 10:00",
        "body": "..."
      },
      "thread": [
        { "from": "...", "date": "...", "body": "..." },
        ...
      ]
    }

Exit 0 on success, non-zero on failure (caller falls back to selected text).

Environment:
  AI_REPLY_MAIL_MAX_MESSAGES  - max thread messages to fetch (default: 5)
"""
import base64
import json
import os
import subprocess
import sys
import uuid

MAX_MESSAGES = min(int(os.environ.get("AI_REPLY_MAIL_MAX_MESSAGES", "5")), 20)

# A random separator per invocation — eliminates collision risk with
# email body content (unlike fixed sentinel strings such as |||AIREPLY|||).
SEP = uuid.uuid4().hex

APPLESCRIPT_TEMPLATE = """\
on joinList(lst, sep)
    set out to ""
    repeat with i from 1 to count of lst
        if i > 1 then set out to out & sep
        set out to out & (item i of lst as text)
    end repeat
    return out
end joinList

tell application "Mail"
    if (count of message viewers) is 0 then
        error "No Mail viewer open"
    end if
    set theViewer to message viewer 1
    if (count of selected messages of theViewer) is 0 then
        error "No message selected"
    end if
    set theMsg to item 1 of (selected messages of theViewer)

    set theSubject to subject of theMsg
    set latestFrom to sender of theMsg
    set latestDate to (date string of (date received of theMsg))
    set latestBody to content of theMsg

    set convId to conversation id of theMsg
    set allMsgs to (messages of theViewer whose conversation id is convId)
    set msgCount to count of allMsgs

    set SEP to "__SEP_PLACEHOLDER__"
    set NL to ASCII character 10

    set lines to {}
    set end of lines to "SUBJECT:" & theSubject
    set end of lines to "LATEST_FROM:" & latestFrom
    set end of lines to "LATEST_DATE:" & latestDate
    set end of lines to "LATEST_BODY_B64:" & (do shell script "printf %s " & quoted form of latestBody & " | base64 -b 0")
    set end of lines to "THREAD_COUNT:" & msgCount

    -- Only extract bodies for the most recent MAX_MESSAGES messages.
    -- Pulling content for hundreds of thread messages cripples Mail.app.
    set startIndex to 1
    if msgCount > __MAX_PLACEHOLDER__ then set startIndex to msgCount - __MAX_PLACEHOLDER__ + 1

    repeat with i from startIndex to msgCount
        set m to item i of allMsgs
        set end of lines to SEP & (sender of m)
        set end of lines to SEP & (date string of (date received of m))
        set end of lines to SEP & (do shell script "printf %s " & quoted form of (content of m) & " | base64 -b 0")
    end repeat

    return my joinList(lines, NL)
end tell
""".replace("__SEP_PLACEHOLDER__", SEP).replace("__MAX_PLACEHOLDER__", str(MAX_MESSAGES))


def run_applescript(script: str) -> str:
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True, text=True, timeout=15
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "AppleScript failed")
    return result.stdout.strip()


def b64decode(s: str) -> str:
    """Decode a base64 string, tolerant of whitespace."""
    try:
        return base64.b64decode(s.strip()).decode("utf-8", errors="replace")
    except Exception:
        return s  # fallback: return raw text


class ParseError(RuntimeError):
    """Raised when AppleScript output is malformed or incomplete."""


def _require_prefix(line: str, prefix: str) -> str:
    if not line.startswith(prefix):
        raise ParseError(f"Expected line to start with {prefix!r}, got: {line!r}")
    return line[len(prefix):]


def parse_output(raw: str) -> dict:
    lines = raw.splitlines()
    idx = 0

    def next_line(expected_prefix: str = "") -> str:
        nonlocal idx
        if idx >= len(lines):
            raise ParseError(
                f"Unexpected end of output (needed prefix {expected_prefix!r})"
            )
        line = lines[idx]
        idx += 1
        return line

    try:
        subject = _require_prefix(next_line("SUBJECT:"), "SUBJECT:")
        latest_from = _require_prefix(next_line("LATEST_FROM:"), "LATEST_FROM:")
        latest_date = _require_prefix(next_line("LATEST_DATE:"), "LATEST_DATE:")
        latest_body = b64decode(
            _require_prefix(next_line("LATEST_BODY_B64:"), "LATEST_BODY_B64:")
        )

        thread_count_line = _require_prefix(
            next_line("THREAD_COUNT:"), "THREAD_COUNT:"
        )
        try:
            thread_count = int(thread_count_line)
        except ValueError as exc:
            raise ParseError(f"Invalid THREAD_COUNT value: {thread_count_line!r}") from exc

        thread = []
        for _ in range(thread_count):
            if idx >= len(lines):
                break
            line = next_line(f"thread entry (SEP={SEP})")
            if not line.startswith(SEP):
                continue
            msg_from = line[len(SEP):]
            msg_date = next_line("thread date")[len(SEP):]
            msg_body = b64decode(next_line("thread body")[len(SEP):])
            thread.append({"from": msg_from, "date": msg_date, "body": msg_body})
    except ParseError:
        raise
    except Exception as exc:
        raise ParseError(f"Failed to parse AppleScript output: {exc}") from exc

    # Trim to max in case AppleScript sent more (shouldn't happen but safe).
    thread = thread[-MAX_MESSAGES:] if len(thread) > MAX_MESSAGES else thread

    return {
        "source": "mail_app",
        "subject": subject,
        "latest": {"from": latest_from, "date": latest_date, "body": latest_body},
        "thread": thread,
    }


def main() -> int:
    try:
        raw = run_applescript(APPLESCRIPT_TEMPLATE)
        data = parse_output(raw)
        print(json.dumps(data, ensure_ascii=False))
        return 0
    except Exception as e:
        print(f"fetch_mail_thread: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())