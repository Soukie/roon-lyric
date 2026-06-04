# Roon Lyric Product Design

## Product Goal

Roon Lyric is a macOS desktop lyric companion for Roon users. It discovers the current Roon Core on the local network, reads the active playback metadata, resolves synced lyrics from public sources, and displays the current lyric line in a floating desktop window.

The first release focuses on stable local playback awareness and readable desktop lyrics. It does not inspect audio streams, alter Roon playback, or ship unofficial QQ Music / NetEase Cloud Music scrapers.

## Target Users

- Roon users who play music through local network endpoints and want lyrics visible outside the Roon app.
- Desktop listeners who prefer a QQ Music-style floating lyric line while working.
- Power users who may need to enter a Roon Core host manually when multicast discovery is blocked.

## MVP Scope

- Native macOS `.app` built from SwiftUI and AppKit.
- Automatic Roon Core discovery through Roon SOOD.
- Manual Roon Core configuration when automatic discovery fails.
- Roon extension registration and token persistence.
- Zone subscription for current playback metadata and seek position.
- LRCLIB lyric lookup with local caching.
- Configurable official or authorized lyric/metadata channels for QQ Music and Spotify.
- Floating desktop lyric window with adjustable font size, opacity, and color.
- App icon with a music-note, lyric-line, and network-orbit motif.
- Runtime logging to support post-failure analysis by Codex.
- Open-source repository readiness with bilingual README, ignore rules for local configuration, and release DMG workflow.
- Product and technical documents updated alongside behavior changes.

Out of scope for MVP:

- Windows app packaging.
- Audio fingerprinting or audio stream inspection.
- Playback controls beyond passive display.
- Built-in QQ Music or NetEase Cloud Music scraping.
- Advanced skin marketplace or karaoke effects.
- Automatic certificate provisioning. Release signing requires a user-owned Apple Developer ID certificate.

## User Flows

### First Launch With Automatic Discovery

1. User launches Roon Lyric.
2. The app scans the local network for Roon Core.
3. Discovered Cores appear in the main window.
4. User connects to a Core.
5. Roon shows the extension in Settings > Setup > Extensions.
6. User authorizes the extension in Roon.
7. Roon Lyric subscribes to Zones and starts showing playback state.

### First Launch Without Automatic Discovery

1. User launches Roon Lyric.
2. No Core is found within the scan window.
3. The app keeps scanning and shows a manual Core form.
4. User enters host/IP, port, and optional display name.
5. The app sends a directed SOOD probe to the host so it can discover the real Roon API port when multicast or broadcast discovery is blocked.
6. User tests or connects to the manual Core.
7. If connection succeeds, the manual Core is saved and reused.
8. If connection fails, the app shows a recoverable error and keeps the form editable.

### Lyrics Display

1. Roon reports a playing Zone with track title, artist, album, duration, and seek position.
2. Roon Lyric resolves synced lyrics from cache or LRCLIB.
3. The floating window displays the current line and advances according to Roon seek updates.
4. Pause freezes the lyric. Seek and track changes reposition or reload the lyric.
5. If synced lyrics are unavailable, the app shows static lyrics when available.
6. If no lyric source finds a match, both the main lyric preview and desktop lyric window show a clear "未找到歌词" state.

## Interface Design

### Main Window

- Connection status and current Core.
- Discovered Core list.
- Manual Core form and saved manual Core list.
- Active Zone and current track.
- Current lyric preview.
- Quick actions: scan, connect, show/hide desktop lyrics, open settings.

### Settings Window

- Roon Core management.
- Preferred Zone selection.
- Lyric source status.
- Lyric provider configuration for LRCLIB, QQ Music official/authorized API access, and Spotify metadata matching.
- Desktop lyric style: font size, opacity, text color, and shadow.

### Desktop Lyrics Window

- Always-on-top borderless panel.
- Transparent background.
- One current line and optional next-line preview.
- Drag to reposition.
- QQ Music-inspired high-contrast text with glow/shadow.
- Adjustable display style persisted between launches.

### Open Source Distribution

- The GitHub repository should include a bilingual README for users and contributors.
- The repository uses the MIT License for public open-source distribution.
- Local credentials, signing certificates, and runtime configuration files must be ignored by git.
- Release artifacts are produced as macOS `.dmg` files under `assets/releases/` locally and uploaded to GitHub Release assets when publishing a tag.
- Signed public releases require a Developer ID Application certificate. Unsigned DMGs are acceptable only for local smoke testing.

## Acceptance Criteria

- The app builds into a double-clickable `.app`.
- Automatic discovery finds a reachable Roon Core on a normal LAN.
- Manual host/IP and port connection works when multicast is unavailable.
- Roon extension token survives app relaunch.
- Current track, artist, album, duration, seek position, and Zone state are visible.
- Synced lyrics advance in time with play, pause, seek, and track changes.
- Missing lyrics and connection failures are understandable and recoverable.
- Missing lyrics are visible in both the in-app lyric preview and the desktop lyric window.
- Startup, Roon discovery, connection, lyrics resolution, and window actions are recorded in local logs for troubleshooting.
- The repository includes a Chinese/English README aligned with product and technical design.
- Local configuration, credentials, certificates, build products, and release binaries are excluded by `.gitignore`.
- A release command can generate a macOS `.dmg` in `assets/releases/`; signed public releases require a configured Developer ID Application identity.
- GitHub Release automation can upload the generated `.dmg` as a downloadable release asset.
- This product document and `docs/technical-architecture.md` are kept current with behavior changes.
