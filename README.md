# Khinsider

KHInsider game-soundtrack client — Flutter + pure-Dart data package,
designed around a strict three-layer Clean Architecture.

详细分层、数据流、焦点系统与状态一览见 [ARCHITECTURE.md](ARCHITECTURE.md)。

```
khinsider/
├── app/                        # Flutter client
│   └── lib/
│       ├── core/               # theme · dpad/seek widgets · global media keys
│       ├── data/               # client provider · json KV store · preferences
│       ├── audio/              # BaseAudioPlayer · just_audio · media session · cache
│       ├── state/              # Riverpod controllers (search/album/player/theme)
│       └── ui/                 # search/ · album/ · now_playing/ · shared/
└── packages/khinsider_api/     # Pure Dart: dio + html parser & data API
```

## Architecture

**UI layer** — Flutter. Responsive grid/list layouts; D-Pad & gamepad focus
system (`DpadTile`, `FocusTraversalGroup`); app-wide media-key shortcuts
(`MediaPlayPause`, `MediaTrackNext`, …) via `CallbackShortcuts`.

**State layer** — `flutter_riverpod`. `PlayerController` bridges the UI to the
abstract `BaseAudioPlayer` and implements **two-phase lazy loading**:
only the clicked track is resolved immediately (1 request), remaining tracks
are resolved sequentially in the background and appended to the queue.

**Playback backend** — `JustAudioPlayerImpl` wrapped by a `KhinsiderAudioHandler`
(`audio_service`): macOS Now-Playing / media keys, Android notification &
lock-screen controls. The app never depends on audio_service directly — only
`main()` wires the handler in via a provider override.

**Local storage** — `storage/json_kv_store.dart`, a dependency-free JSON-file
KV store (Application Support dir, atomic writes, debounced flush). Powers:
persistent favorites, search history (chips on the home screen) and recently
viewed albums. Swappable for Isar/Hive later without touching providers.

**Data layer** — `packages/khinsider_api`, pure Dart (`dio` + `html`), zero
Flutter/native dependencies:

* Phase 1: search / album page — **one** HTML request, parsed into typed models.
* Phase 2: track page — resolved only on demand, extracts the direct CDN URL
  from `<audio id="audio" src="…">` and FLAC `<a>` links.

## Site notes (reverse-engineered)

* Album paths are **plural**: `/game-soundtracks/album/<id>`. The singular
  variant (`/game-soundtrack/album/…`) is blocked by Cloudflare WAF (403).
* Requests must send a browser-like `User-Agent` and `Accept` headers.

## CI / Build matrix

`.github/workflows/ci.yml` builds and releases on every `v*` tag
(analyze + unit tests gate everything):

| Target | Artifact | Runner |
|---|---|---|
| Android (TV / Google TV) | `khinsider-*-universal.apk` + `armv7` / `arm64` splits | ubuntu |
| macOS | ad-hoc signed `.app` zip (`xattr -cr` on first launch) | macos-14 |
| Windows | zip of `Release/` (playback via just_audio_media_kit) | windows-latest |
| Steam Deck / Linux | single-file `.flatpak` (freedesktop 23.08 runtime) | ubuntu + flathub container |

Flatpak manifest & desktop/metainfo live in `packaging/flatpak/`.
Release job publishes all artifacts to GitHub Releases with install notes.

## Commands

```sh
# API package tests (offline, uses real page fixtures)
cd packages/khinsider_api && dart test

# Flutter app unit tests
cd app && flutter pub get && flutter analyze && flutter test

# End-to-end on macOS (sandbox network -> search -> album -> playback)
flutter test integration_test/app_e2e_test.dart -d macos

# Run on macOS
flutter run -d macos

# Android build (ARMv7a/ARM64, works on old TV boxes)
flutter build apk --release --target-platform android-arm,android-arm64
```

## Switch-port reserved channel

`app/lib/audio/base_audio_player.dart` defines the playback interface used
exclusively by the UI/state layers. Replacing `JustAudioPlayerImpl` with an
embedded-engine implementation is the only change needed to port the audio
backend; the `khinsider_api` package is already Flutter-free.
