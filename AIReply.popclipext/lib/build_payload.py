#!/usr/bin/env python3
"""Build the OpenAI-compatible chat-completions payload from env vars.

Reads:
  AI_REPLY_INPUT_TEXT         - the original email selection
  AI_REPLY_USER_PROMPT        - user-configured prompt (rare; from settings)
  AI_REPLY_RUNTIME_PROMPT     - extra instruction the user typed in the dialog
  AI_REPLY_SYSTEM_PROMPT      - override system prompt (optional)
  AI_REPLY_MODEL              - model id
  AI_REPLY_TEMPERATURE_RAW    - temperature as string
  AI_REPLY_AUTO_LANGUAGE      - "true" to instruct same-language reply
  AI_REPLY_STYLE              - professional|friendly|concise
  AI_REPLY_DRAFT_REPLY        - previous draft (for Follow Up)
  AI_REPLY_FOLLOWUP_PROMPT    - follow-up instruction (for Follow Up)
  AI_REPLY_MAIL_THREAD_JSON   - JSON from fetch_mail_thread.py (optional)

Writes:
  stdout: payload JSON
  stderr: DETECTED_LANGUAGE=<name>
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from detect_language import detect

STYLE_INSTRUCTIONS = {
    "professional": "Use a formal, professional tone. Be respectful and business-appropriate.",
    "friendly": "Use a warm, friendly tone. Be approachable and conversational while remaining professional.",
    "concise": "Be brief and to the point. Use short sentences and get straight to the message.",
}


def _truthy(s: str) -> bool:
    return (s or "").strip().lower() in ("1", "true", "yes", "on")


def main() -> int:
    email = os.environ.get("AI_REPLY_INPUT_TEXT", "")
    user_prompt = (os.environ.get("AI_REPLY_USER_PROMPT") or "").strip()
    runtime_prompt = (os.environ.get("AI_REPLY_RUNTIME_PROMPT") or "").strip()
    system_prompt = (os.environ.get("AI_REPLY_SYSTEM_PROMPT") or "").strip()
    model = (os.environ.get("AI_REPLY_MODEL") or "").strip() or "gpt-4o-mini"
    temp_raw = (os.environ.get("AI_REPLY_TEMPERATURE_RAW") or "").strip()
    draft = (os.environ.get("AI_REPLY_DRAFT_REPLY") or "").strip()
    followup = (os.environ.get("AI_REPLY_FOLLOWUP_PROMPT") or "").strip()
    auto_language = _truthy(os.environ.get("AI_REPLY_AUTO_LANGUAGE", "true"))
    reply_style = (os.environ.get("AI_REPLY_STYLE") or "professional").strip().lower()
    mail_thread_raw = (os.environ.get("AI_REPLY_MAIL_THREAD_JSON") or "").strip()

    if reply_style not in STYLE_INSTRUCTIONS:
        reply_style = "professional"

    try:
        temperature = float(temp_raw) if temp_raw else 0.4
    except ValueError:
        temperature = 0.4

    detected = detect(email)
    print("DETECTED_LANGUAGE=" + detected, file=sys.stderr)

    if not system_prompt:
        system_prompt = (
            "You are an email assistant. Write a ready-to-send reply based on the "
            "given email and user instructions. Be polite, accurate, and concise. "
            + STYLE_INSTRUCTIONS[reply_style]
            + " Output ONLY the reply body."
        )
        if auto_language:
            system_prompt += " Reply in the same language as the original email."

    parts = []

    # ── Mail thread context ────────────────────────────────────────────────
    # Prepend conversation history (oldest first) so the model sees the full
    # exchange before the current task. Silently ignore malformed JSON.
    if mail_thread_raw:
        try:
            thread_data = json.loads(mail_thread_raw)
            subject = thread_data.get("subject", "")
            thread = thread_data.get("thread", [])
            latest = thread_data.get("latest", {})

            # 'thread' from AppleScript is newest-first; reverse to oldest-first
            # and drop the latest message (it's already the main input_text).
            history_msgs = [m for m in reversed(thread)
                            if m.get("body", "").strip() != latest.get("body", "").strip()]

            if subject:
                parts.append(f"Email subject: {subject}")

            if history_msgs:
                history_lines = []
                for m in history_msgs:
                    history_lines.append(
                        f"[{m.get('date', '')}] {m.get('from', '')}:\n{m.get('body', '').strip()}"
                    )
                parts.append(
                    "--- Previous messages in this thread (oldest first) ---\n"
                    + "\n\n".join(history_lines)
                    + "\n--- End of thread history ---"
                )
        except (json.JSONDecodeError, KeyError):
            pass

    if user_prompt:
        parts.append("User instructions:\n" + user_prompt)
    if runtime_prompt:
        parts.append("Additional user requirements:\n" + runtime_prompt)
    parts.append("Email content:\n" + email)

    if draft and followup:
        parts.append("Current draft reply:\n" + draft)
        parts.append("Follow-up request:\n" + followup)
        parts.append("Rewrite the draft reply to satisfy the follow-up request. Output only the final reply body.")
    else:
        parts.append("Write the reply email body now. Output only the reply body.")

    payload = {
        "model": model,
        "temperature": temperature,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": "\n\n".join(parts)},
        ],
    }
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
