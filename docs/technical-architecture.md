# Roon Lyric Technical Architecture

## Architecture Summary

Roon Lyric is a package-first native macOS app. SwiftUI owns regular app surfaces and settings, AppKit owns the floating desktop lyric panel, and service classes isolate Roon networking, lyric lookup, caching, and user preferences.

The MVP is intentionally modular so a later Windows build can reuse data models, lyric resolution, Roon protocol behavior, and synchronization policy while replacing the macOS windowing layer.

## Module Boundaries

- App: app entry point, app delegate, scene setup.
- Views: SwiftUI main window, settings, and reusable UI components.
- Models: Roon Core, Zone, Track, Lyrics, and display preference value types.
- Stores: persisted manual Cores, Roon tokens, lyric cache, and display preferences.
- Services: SOOD discovery, MOO WebSocket client, Roon connection, lyric providers, lyric resolver, sync engine, and desktop window controller.
- Support: logging, small formatters, and AppKit/SwiftUI glue.

## Roon Integration

### Discovery

Roon Core discovery uses SOOD:

- UDP port: `9003`
- Multicast group: `239.255.90.90`
- Query property: `query_service_id = 00720724-5143-4a9b-abac-0e50cba674bb`
- Relevant response properties: `unique_id`, `display_name`, `http_port`, and reply address.

The app also supports manual Core entries:

- `host` or IP address.
- `port`, usually the Roon Core WebSocket port returned by discovery.
- Optional friendly name.
- Last successful connection timestamp.

Automatic discovery and manual entries feed the same connection path.

The scanner sends SOOD queries to multicast, global broadcast, per-interface subnet broadcast addresses, and saved manual Core hosts. This is important for Docker or NAS deployments where multicast discovery may not cross container or network boundaries, but a directed UDP query to the known host can still return the real `http_port`.

### MOO WebSocket

The app connects to:

`ws://<host>:<port>/api`

Messages use the Roon MOO frame format:

- Request line: `MOO/1 REQUEST <service>/<method>`
- Response lines: `MOO/1 CONTINUE <name>` or `MOO/1 COMPLETE <name>`
- Headers include `Request-Id`, `Content-Length`, and `Content-Type`.
- JSON bodies are UTF-8 encoded.

Registration sequence:

1. Request `com.roonlabs.registry:1/info`.
2. Include any saved token for that Core.
3. Request `com.roonlabs.registry:1/register`.
4. Persist returned token on `Registered`.
5. Subscribe to `com.roonlabs.transport:2/subscribe_zones`.

The app provides minimal `com.roonlabs.ping:1` and `com.roonlabs.pairing:1` handlers so Roon can keep the extension alive and pair it normally.

## Lyrics Architecture

`LyricsProvider` defines a small provider interface. MVP ships:

- `LRCLIBLyricsProvider`
- `LyricsCache`
- `QQMusicOfficialLyricsProvider` for user-supplied official or partner endpoint integration
- `SpotifyMetadataLyricsProvider` for Spotify metadata matching configuration only

Lookup order:

1. Local cache by normalized title, artist, album, and duration.
2. LRCLIB exact lookup.
3. Optional QQ Music official/authorized endpoint when configured by the user.
4. Spotify metadata matching can be configured, but Spotify Web API does not expose a public lyrics endpoint, so it does not directly return lyrics.
5. Static lyrics fallback if synced lyrics are unavailable.
6. Not-found state.

The resolver stores successful synced and static lyrics. It does not cache transient network failures as permanent misses.

Provider settings are stored in `LyricsProviderSettingsStore`. QQ Music credentials and Spotify client credentials are persisted locally for MVP convenience; do not log these values.

## Synchronization

Roon Zone updates are the source of truth. `LyricsSyncEngine` uses:

- Roon `now_playing.seek_position` and `zones_seek_changed` when available.
- Local monotonic time between Roon updates while the Zone is playing.
- Frozen progress while paused, stopped, or loading.

Track identity changes clear the old lyric and trigger a new resolution. Seek changes reposition immediately.

## Persistence

Persistence uses JSON encoded values in `UserDefaults` for MVP:

- manual Core list
- Roon token map by Core ID
- selected Zone
- display preferences
- compact lyric cache
- lyric provider settings for LRCLIB, QQ Music, and Spotify

If the cache grows beyond MVP needs, move lyrics to Application Support as individual JSON files.

## Logging

`AppLogger` writes every important runtime milestone to two destinations:

- Apple unified logging with subsystem `com.soukie.RoonLyric`.
- Local file: `~/Library/Application Support/RoonLyric/Logs/roon-lyric.log`.

The file log rotates to `roon-lyric.previous.log` at 5 MB. Logging covers app startup and termination, menu commands, Roon discovery, Core connection, MOO request/response milestones, Zone subscription updates, lyric lookup outcomes, lyric sync track changes, and desktop lyric panel visibility.

Logs must not include Roon auth tokens, raw lyric contents, or unnecessary personal data. Track title and artist may be logged as debugging context because they are required to diagnose lyric matching failures.

## Packaging

The project uses SwiftPM plus shell scripts. The scripts default `DEVELOPER_DIR` to `/Applications/Xcode.app/Contents/Developer` when that full Xcode installation exists, because Command Line Tools alone may not provide a Swift/SDK pair that can compile SwiftUI apps.

The local scripts pass `--disable-sandbox` to SwiftPM because Codex and some CI shells may already run inside an outer sandbox. The package has no SwiftPM plugins or build-time network dependencies, so this only avoids nested sandbox failures and does not change app behavior.

`script/build_and_run.sh` is for debug packaging and launch verification.

The script:

1. Builds the executable with `swift build`.
2. Stages `dist/RoonLyric.app`.
3. Writes a minimal `Info.plist`.
4. Copies the executable into `Contents/MacOS`.
5. Copies `Resources/RoonLyric.icns` into `Contents/Resources`.
6. Writes `CFBundleIconFile=RoonLyric.icns`, `CFBundleShortVersionString`, and `CFBundleVersion`.
7. Touches the staged bundle and registers it with LaunchServices so Finder and Dock refresh the icon metadata.
8. Launches or verifies the app.

`script/package_release.sh` is for release packaging:

1. Builds with `swift build -c release`.
2. Stages `dist/release/RoonLyric.app`.
3. Writes production bundle metadata and copies `Resources/RoonLyric.icns`.
4. Signs the app with `DEVELOPER_ID_APPLICATION` when provided.
5. Creates `assets/releases/RoonLyric-<version>-macOS.dmg` with `hdiutil create`; if the current environment cannot create UDZO images, it falls back to `hdiutil makehybrid`.
6. Signs the DMG when a signing identity is provided.
7. Optionally notarizes and staples the DMG when `--notarize` and `NOTARY_PROFILE` are configured.

Unsigned release DMGs can be built only with `--allow-unsigned` and are intended for local smoke testing, not public distribution.

The `.app` does not require a Node runtime or sidecar service.

## GitHub Distribution

Repository bootstrap has two paths:

- `script/github_bootstrap.sh` expects GitHub CLI (`gh`) to be installed and authenticated. It can create or reuse a GitHub repository, attach it as `origin`, and push `main`.
- `script/github_api_bootstrap.sh` is a fallback for machines without `gh`. It uses `GITHUB_TOKEN` and the GitHub REST API to create or reuse a repository, attach `origin`, and push `main`.

`.github/workflows/release.yml` builds a macOS DMG on tag pushes matching `v*`, uploads the DMG as a workflow artifact, and publishes it to GitHub Release assets. Signed CI releases require these repository secrets:

- `DEVELOPER_ID_APPLICATION`
- `MACOS_CERTIFICATE_P12`
- `MACOS_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`

Local and CI signing credentials must never be committed. `.gitignore` excludes `.env`, local release configs, certificates, keychains, provision profiles, build output, and generated release binaries.

For direct local asset upload without GitHub CLI, `script/github_release_upload.sh` uses `GITHUB_TOKEN` and the GitHub releases REST API to create or reuse a tag release and upload `assets/releases/RoonLyric-<version>-macOS.dmg`. The token must have repository contents write permission and must be exported in the shell, not committed.

## Visual Assets

The app icon source is stored at `Resources/Images/roon-lyric-icon-source.png`, with a normalized 1024 px source at `Resources/Images/roon-lyric-icon-1024.png`. The packaged macOS icon is `Resources/RoonLyric.icns`.

The icon was generated with GPT-Image using this design direction: a luminous music note, lyric lines, and subtle circular audio-orbit motif on a dark graphite background with cyan and warm amber highlights. It intentionally avoids text and third-party logos.

## Documentation Rule

Any change to product behavior, setup flow, architecture, public data shape, persistence format, logging behavior, build process, or acceptance criteria must update `docs/product-design.md` or this document in the same change. Agents should also follow the repository guide in `agent.md`.
