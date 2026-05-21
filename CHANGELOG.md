# Changelog

## v0.1.0 - 2026-05-21

### Added
- PopClip action for generating replies from selected text.
- Configurable default styles: Professional, Friendly, and Concise.
- Follow Up dialog for iterative reply refinement.
- OpenAI-compatible endpoint and custom model configuration.
- API key pool support with failover, retry, and Retry-After cooldown handling.
- Optional Mail.app thread context.
- Local history option and debug logs.
- Unit tests for response parsing, pool loading, and pool writing.
- CI workflow for shell syntax checks, Python compilation, and unit tests.

### Changed
- PopClip toolbar is simplified to a single AI Reply action.
- Model, default style, and key pool behavior are configured in Settings.
- Default reply style is Concise.
- Release packaging writes `.popclipextz` artifacts to `dist/`.

### Security
- API key field uses PopClip's secret option.
- Session handoff uses JSON instead of shell source files.
- Key pool setup treats user input as data, not executable code.
- Local history/key health/pool files use restricted permissions where applicable.
- Debug request metadata masks API keys.

### Known Limitations
- macOS + PopClip only.
- Mail.app context requires local Automation/Accessibility permissions.
- Third-party OpenAI-compatible endpoints may vary in model names, limits, and error formats.
- Demo GIF/screenshots are still TODO before broad promotion.
