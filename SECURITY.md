# Security Policy

AI Reply handles selected text, optional email thread context, and API credentials. Please report security issues responsibly.

## Reporting A Vulnerability

Please do not open a public issue for vulnerabilities that expose secrets, private email content, or code execution paths.

Preferred options:

- Open a private GitHub security advisory if available.
- If private advisory is unavailable, open a minimal public issue that says you have a security report, without posting API keys, private content, or exploit details.

Please include:

- Affected version or commit.
- macOS and PopClip versions.
- Steps to reproduce.
- Potential impact.
- Sanitized logs with API keys and private text removed.

## Scope

Security-sensitive areas include:

- API key handling and masking.
- Local history/debug files that may contain private content.
- Shell, Python, or AppleScript injection paths.
- Mail.app thread context collection.
- File permissions for local secrets and runtime state.
