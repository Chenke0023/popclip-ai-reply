#!/usr/bin/env python3
"""Fetch the current Mail.app thread via AppleScript and return structured JSON.

Output (stdout):
  JSON object:
    {
      "source": "mail_app",          // always
      "subject": "Re: Q2 budget",
      "latest": {                    // the message open in the viewer
        "from": "alice@example.com",
        "date": "2026-05-19 10:00",
        "body": "..."
      },
      "thread": [                    // full thread, newest-first, capped at max_messages
        { "from": "...", "date": "...", "body": "..." },
        ...
      ]
    }

Exit 0 on success, non-zero on any failure (caller falls back to selected text).

Environment:
  AI_REPLY_MAIL_MAX_MESSAGES  - max thread messages to fetch (default: 5)
"""
import json
import os
import subprocess
import sys

MAX_MESSAGES = int(os.environ.get("AI_REPLY_MAIL_MAX_MESSAGES", "5"))

APPLESCRIPT = """
on joinList(lst, sep)
    set out to ""
    repeat with i from 1 to count of lst
        if i > 1 then set out to out & sep
        set out to out & (item i of lst as text)
    end repeat
    return out
end joinList

tell application "Mail"
    -- get the frontmost viewer
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

    -- collect thread via conversation id
    set convId to conversation id of theMsg
    set allMsgs to (messages of theViewer whose conversation id is convId)

    -- build output lines: use a sentinel separator unlikely to appear in emails
    set SEP to "|||AIREPLY|||"
    set NL to ASCII character 10

    set lines to {}
    set end of lines to "SUBJECT:" & theSubject
    set end of lines to "LATEST_FROM:" & latestFrom
    set end of lines to "LATEST_DATE:" & latestDate
    set end of lines to "LATEST_BODY_START"
    set end of lines to latestBody
    set end of lines to "LATEST_BODY_END"

    set msgCount to count of allMsgs
    set end of lines to "THREAD_COUNT:" & msgCount

    repeat with i from 1 to msgCount
        set m to item i of allMsgs
        set end of lines to "MSG_FROM:" & (sender of m)
        set end of lines to "MSG_DATE:" & (date string of (date received of m))
        set end of lines to "MSG_BODY_START"
        set end of lines to (content of m)
        set end of lines to "MSG_BODY_END"
    end repeat

    return my joinList(lines, NL)
end tell
"""


def run_applescript(script: str) -> str:
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True, text=True, timeout=15
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "AppleScript failed")
    return result.stdout.strip()


def parse_output(raw: str) -> dict:
    lines = raw.splitlines()
    idx = 0

    def next_line():
        nonlocal idx
        line = lines[idx]
        idx += 1
        return line

    def read_block_until(sentinel):
        parts = []
        while idx < len(lines):
            line = next_line()
            if line == sentinel:
                break
            parts.append(line)
        return "\n".join(parts)

    subject = next_line().removeprefix("SUBJECT:")
    latest_from = next_line().removeprefix("LATEST_FROM:")
    latest_date = next_line().removeprefix("LATEST_DATE:")
    next_line()  # LATEST_BODY_START
    latest_body = read_block_until("LATEST_BODY_END")

    thread_count_line = next_line()
    thread_count = int(thread_count_line.removeprefix("THREAD_COUNT:"))

    thread = []
    for _ in range(min(thread_count, MAX_MESSAGES)):
        msg_from = next_line().removeprefix("MSG_FROM:")
        msg_date = next_line().removeprefix("MSG_DATE:")
        next_line()  # MSG_BODY_START
        msg_body = read_block_until("MSG_BODY_END")
        thread.append({"from": msg_from, "date": msg_date, "body": msg_body})

    return {
        "source": "mail_app",
        "subject": subject,
        "latest": {"from": latest_from, "date": latest_date, "body": latest_body},
        "thread": thread,
    }


def main() -> int:
    try:
        raw = run_applescript(APPLESCRIPT)
        data = parse_output(raw)
        print(json.dumps(data, ensure_ascii=False))
        return 0
    except Exception as e:
        print(f"fetch_mail_thread: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
