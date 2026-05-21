# Contributing

Thanks for considering a contribution to AI Reply for PopClip.

## Development Setup

Requirements:

- macOS
- PopClip for manual extension testing
- `/bin/zsh`
- Python 3

Run checks before opening a pull request:

```bash
zsh -n AIReply.popclipext/reply.zsh AIReply.popclipext/lib/dialog.zsh AIReply.popclipext/pool_setup.zsh AIReply.popclipext/models.zsh
python3 -m py_compile AIReply.popclipext/lib/*.py
PYTHONPATH=AIReply.popclipext python3 -m unittest discover -s AIReply.popclipext/tests -v
```

Package locally:

```bash
zsh package.sh 0.1.0
```

## Pull Requests

Please keep changes focused and include tests for Python helpers when practical. Avoid committing local API keys, debug logs, history files, or packaged `.popclipextz` artifacts.

## Bug Reports

When reporting bugs, include:

- macOS version
- PopClip version
- Extension version or commit
- Endpoint provider
- Model name
- Error message
- Sanitized debug logs from `~/Library/Logs/AIReplyPopClip/`

Remove private email content and API keys before sharing logs.
