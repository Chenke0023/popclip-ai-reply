#!/usr/bin/env python3
"""Detect dominant language of an email body for the UI badge only.

The actual language-matching for the reply is delegated to the model via
the system prompt; this script just produces a friendly label.
"""
import re
import sys

RANGES = {
    "Japanese": r"[぀-ゟ゠-ヿ]",
    "Korean": r"[가-힯]",
    "Chinese": r"[一-鿿]",
    "Russian": r"[Ѐ-ӿ]",
    "Arabic": r"[؀-ۿ]",
}


def detect(text: str) -> str:
    sample = (text or "")[:4000].strip()
    if not sample:
        return "English"
    total = len(sample)
    counts = {name: len(re.findall(pat, sample)) for name, pat in RANGES.items()}
    if counts["Japanese"] / total > 0.05:
        return "Japanese"
    if counts["Korean"] / total > 0.05:
        return "Korean"
    if counts["Chinese"] / total > 0.15:
        return "Chinese"
    if counts["Russian"] / total > 0.15:
        return "Russian"
    if counts["Arabic"] / total > 0.15:
        return "Arabic"
    return "English"


if __name__ == "__main__":
    print(detect(sys.stdin.read()))
