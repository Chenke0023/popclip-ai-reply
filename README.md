# AI Reply for PopClip

AI Reply is a macOS [PopClip](https://www.popclip.app/) extension that generates polished replies from selected text using OpenAI-compatible chat completion APIs.

It is designed for quick email and message replies: select text, click **AI Reply**, optionally add a short instruction, then copy or refine the generated draft with Follow Up.

## Highlights

- Generate replies directly from selected text in any app
- Default reply style in Settings: Professional, Friendly, or Concise
- Follow-up refinement dialog for iterative edits
- OpenAI-compatible endpoint and custom model support
- API key pool with retry, 429 cooldown, and key failover
- Optional Mail.app thread context for richer replies
- Local debug/history controls with privacy-first defaults
- Shell + Python + AppleScript implementation with CI tests

## Demo

Add release screenshots or GIFs here before announcing broadly:

- `assets/demo.gif` — select text → PopClip → generated reply
- `assets/settings.png` — extension Settings
- `assets/follow-up.png` — Follow Up refinement

## Installation

1. Download the latest `AIReply-vX.Y.Z.popclipextz` from [Releases](../../releases).
2. Double-click the file to install it in PopClip.
3. Open PopClip Settings and configure:
   - `API Key`, or `API Key File`
   - `Endpoint`
   - `Model`, or `Custom Model`
   - optional `API Key Pool File`

To build locally:

```bash
zsh package.sh 0.1.0
open dist/AIReply-v0.1.0.popclipextz
```

## Usage

1. Select an email or message body.
2. Click **AI Reply** in the PopClip toolbar.
3. Optionally enter extra instructions, or leave the prompt blank.
4. Review the generated reply:
   - **OK** closes the dialog.
   - **Copy** copies the editable reply text.
   - **Follow Up** asks AI to revise the current draft.

PopClip’s toolbar contains only the main **AI Reply** action. Model, style, and key pool behavior are configured in Settings to keep the toolbar uncluttered.

## Configuration

### API Key

Priority order:

1. PopClip Settings `API Key` field, stored as a secret option.
2. `AI_REPLY_API_KEY` environment variable, if PopClip inherits it.
3. First non-empty line of `API Key File`, defaulting to `~/.config/popclip-aireply/api_key`.

```bash
mkdir -p ~/.config/popclip-aireply
printf '%s\n' 'YOUR_KEY_HERE' > ~/.config/popclip-aireply/api_key
chmod 600 ~/.config/popclip-aireply/api_key
```

### Endpoint And Model

- `Endpoint` should be an OpenAI-compatible API base URL, for example `https://api.openai.com/v1`.
- `Model` is selected from Settings.
- Choose `Custom` and fill `Custom Model` to use any provider-specific model id.

Third-party OpenAI-compatible gateways may differ in available models, error formats, rate limits, and streaming behavior. This extension uses non-streaming `/chat/completions` requests.

### Reply Behavior

- `Default Style` controls both initial replies and Follow Up revisions.
- Default style is `Concise`.
- `Reply in Source Language` asks the model to reply in the same language as the selected text.
- `Show Language Badge` displays local language detection metadata in the result dialog.

### API Key Pool

For multiple keys, configure `API Key Pool File` in Settings. The file should contain:

```json
[
  { "api_key": "sk-aaa...", "endpoint": "https://api.openai.com/v1" },
  { "api_key": "sk-bbb...", "endpoint": "https://api.deepseek.com/v1" }
]
```

Recommended permissions:

```bash
chmod 600 ~/.config/popclip-aireply/pool.json
```

When a pool is configured, the extension retries retryable failures on another key. 429 responses honor `Retry-After` when provided and mark the key as cooling down.

### Mail.app Context

If `Mail.app Thread Context` is enabled and Mail.app is frontmost, AI Reply can fetch recent messages from the current thread. This requires macOS Automation/Accessibility permissions for the app running PopClip.

## Privacy & Security

AI Reply sends selected text, optional prompt instructions, and optional Mail.app thread context to your configured API endpoint. Do not use it with sensitive content unless you trust that endpoint and its data handling policy.

By default:

- Conversation history is disabled.
- API keys should be stored in PopClip’s secret option or a `600` key file.
- Runtime debug files are written under `~/Library/Logs/AIReplyPopClip/` and may contain request/response metadata.
- If `Save History` is enabled, `history.jsonl` may contain selected text and generated replies.

Security-related implementation details:

- Session handoff uses JSON instead of shell `source`.
- Key pool setup treats user input as data, not executable code.
- History, key health, and key pool files use restricted permissions where applicable.
- API keys are masked in debug request metadata.

## Troubleshooting

| Symptom | What To Check |
|---|---|
| Missing API key | Set `API Key`, `API Key File`, or `AI_REPLY_API_KEY`. |
| HTTP 401/403 | Key is invalid, expired, or lacks model access. |
| HTTP 404 | Endpoint or model name is wrong for the provider. |
| HTTP 429 | You are rate-limited; key cooldown/retry should engage. |
| Empty/disappearing dialog | Check `~/Library/Logs/AIReplyPopClip/last_dialog.log`. |
| Mail.app context missing | Grant Automation/Accessibility permissions and keep Mail.app frontmost. |

Debug files are in `~/Library/Logs/AIReplyPopClip/`. Remove private content and API keys before sharing logs.

## Development

Run validation locally:

```bash
zsh -n AIReply.popclipext/reply.zsh AIReply.popclipext/lib/dialog.zsh AIReply.popclipext/pool_setup.zsh AIReply.popclipext/models.zsh
python3 -m py_compile AIReply.popclipext/lib/*.py
PYTHONPATH=AIReply.popclipext python3 -m unittest discover -s AIReply.popclipext/tests -v
```

Package for release:

```bash
zsh package.sh 0.1.0
```

The release artifact is written to `dist/AIReply-v0.1.0.popclipextz`.

## Known Limitations

- macOS + PopClip only.
- Mail.app thread context depends on local AppleScript permissions and Mail.app UI state.
- OpenAI-compatible providers may return provider-specific model names and errors.
- Demo screenshots/GIFs are not included yet.

## License

MIT. See [LICENSE](LICENSE).
