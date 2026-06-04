# Agent Guide

## Project Rules

- This is a native macOS SwiftUI/AppKit app for Roon desktop lyrics.
- Prefer small, focused changes that preserve the existing module boundaries: `App`, `Views`, `Models`, `Stores`, `Services`, and `Support`.
- Run builds and tests with the full Xcode toolchain when available:
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/swift build`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/swift test`
  - `./script/build_and_run.sh --verify`
- Do not log Roon auth tokens, raw lyrics, or private user data.

## Documentation Rule

Any code iteration that changes product behavior, setup flow, user-facing settings, module boundaries, protocol handling, persistence format, logging behavior, build/package flow, or acceptance criteria must update the docs in the same change:

- `docs/product-design.md`
- `docs/technical-architecture.md`

If a change only fixes an internal bug without changing product or technical design, no document update is required.

## Log Analysis

Runtime logs are written to both Apple unified logging and a local file. For Codex analysis, inspect:

`~/Library/Application Support/RoonLyric/Logs/roon-lyric.log`

The previous rotated file, when present, is:

`~/Library/Application Support/RoonLyric/Logs/roon-lyric.previous.log`
