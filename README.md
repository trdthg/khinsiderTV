# Khinsider

A simple client for the [khinsider](https://downloads.khinsider.com) website.

English · [中文](README.zh-CN.md)

Download the latest `v*` release from [Releases](https://github.com/trdthg/khinsiderTV/releases):
Android (armv7 / arm64 / universal APK), iOS, macOS, Windows, Linux / Steam Deck (flatpak).

## Status

I have tested it on Android / iOS / macOS / Windows / Chromecast and it runs on all of them.

## Architecture / Design

The software contains two parts: a GUI, and the khinsider API, which fetches its data by parsing HTML. There are basically just two things in it — search, and fetching album information — so I think it could even support several data sources, other sites included.

* As far as possible I want all of it — the downloaded audio and the cached search results and images — to live directly in the `Music` folder, so the user can copy it, wipe it or do anything else with it.
* Playback streams while a track is downloading, and the next track is prefetched once one starts playing, so it stays smooth.
* There is no "download this album" button on purpose: khinsider is effectively a public-service site, and I do not want to hammer its servers (especially if you would not even treat everything you downloaded with care). Please respect the site itself too.

## Why Flutter

My original goal was to write it for my Chromecast and my Steam Deck. The Steam Deck would have been fine either way, but the Chromecast is the awkward one: it uses the armv7a architecture, i.e. it is a 32-bit device.
Then I also wanted to provide clients for my Android / macOS / Windows / iOS devices, so in the end I went with a cross-platform approach.

I considered wiliwili's approach. Its Steam Deck experience is excellent, but after looking into the framework it uses, supporting Android devices with it looked rather painful, and I am not particularly keen on supporting the Switch either, since I don't own one yet.

I also considered VacuumTube's approach: wrapping the original web page in Electron. But a few days ago I heard that the latest Electron has dropped the armv7a architecture, and Electron is far too heavyweight anyway — for the Chromecast experience it is better not to use it for now. That said, wrapping a web page is genuinely one of my favourite approaches:
the original experience, plus a bit of JavaScript to provide controller support — excellent. I originally wanted my AI to do it that way, but it didn't seem to grasp what I meant. That's fine though: this is only a small piece of software. But if I have the time, or if there is a need — logging in, for example — I will reconsider that approach.

React Native? I don't know. I used to be a devoted React user, especially of the JSX/TSX syntax, but I'm tired of `useEffect`. The Hermes engine performs well and would give me hot updates, but I don't think it's necessary — this is only a small piece of software, after all.

Kotlin/Swift? I have tried both, and the code is genuinely fun, but I am not very familiar with their cross-platform situation, so I didn't consider them for now. Also, I don't really like the heavy nesting in Dart... but never mind, let's leave it at that. This software is written by AI and I don't read much of the code either, though I will try to keep it simple and maintainable.

SDL? Not for now...

Anyway, my role model is LocalSend: it is very simple and beautiful, and I hope this software can be like that too.

## Implementation

The client is a Flutter app plus a pure-Dart data package, designed around a strict three-layer Clean Architecture.
The full layer, data-flow, focus-system and state overview is in [ARCHITECTURE.md](ARCHITECTURE.md).
Focus is laid out explicitly rather than left to Flutter's geometry-based arrow traversal, which on a TV lands on faded or off-screen containers and makes the remote look dead.

```
khinsider/
├── app/                        # Flutter client
│   └── lib/
│       ├── core/               # theme · dpad/seek widgets · global media keys
│       ├── data/               # client provider · json KV store · preferences
│       ├── audio/              # BaseAudioPlayer · just_audio · media session · cache
│       ├── state/              # Riverpod controllers (search/album/player/theme)
│       └── ui/                 # search/ · album/ · now_playing/ · shared/
├── packages/khinsider_api/     # Pure Dart: dio + html parser & data API
└── packages/audio_service/     # Vendored audio_service 0.18.19 + one Android patch
                                #   (compact notification actions, see ARCHITECTURE.md)
```

**UI layer** — Flutter. Responsive grid/list layouts; D-Pad & gamepad focus
system (`DpadTile`, `FocusTraversalGroup`); app-wide media-key shortcuts
(`MediaPlayPause`, `MediaTrackNext`, …) via `CallbackShortcuts`. Narrow
(phone) layouts put the search bar at the **bottom** with the results stacked
bottom-up, and show the album header (cover · title · favorite · details)
above the track list. On Android TV the search field never opens the system
IME: the app draws its own D-Pad keyboard instead
(`ui/search/tv_keyboard.dart`), because Flutter consumes the arrow keys that
would otherwise move focus into the system keyboard window.

**State layer** — `flutter_riverpod`. `PlayerController` bridges the UI to the
abstract `BaseAudioPlayer` and implements **two-phase lazy loading**:
only the clicked track is resolved immediately (1 request), remaining tracks
are resolved sequentially in the background and appended to the queue. It also
implements `SystemMediaCommandHandler`, so notification/lock-screen/headset
commands run the same code path as in-app presses — including resolving the
successor track when the notification's "next" arrives before the prefetch
finished.

**Playback backend** — `JustAudioPlayerImpl` wrapped by a `KhinsiderAudioHandler`
(`audio_service`): macOS Now-Playing / media keys, Android notification &
lock-screen controls. The app never depends on audio_service directly — only
`main()` wires the handler in via a provider override. On Android the service
deliberately stays in the foreground while paused
(`androidStopForegroundOnPause: false`), because Android 12+ refuses to restart
a foreground service from the background — which is what used to make the
notification's play/pause/next buttons unresponsive. The notification icons are
declared by name inside the app module (`android/app/src/main/res/drawable`),
because R8/resource shrinking otherwise strips drawables that are only
referenced by name at runtime.

**Local storage** — `storage/json_kv_store.dart`, a dependency-free JSON-file
KV store (Application Support dir, atomic writes, debounced flush). Powers:
persistent favorites, search history (chips on the home screen) and recently
viewed albums. Swappable for Isar/Hive later without touching providers.

**Downloads & the system music library** — every downloaded track goes through
`LockCachingAudioSource`, so playback streams while the file is written and
later plays from disk. On Android the cache lives in the app's private
directory by default; the user can move it into `Music/KHInsider/<Album>`
(needs "all files access" on Android 11+), and phone layouts additionally
offer **Export to Music**, which contributes the cached files to `MediaStore`
with `RELATIVE_PATH` + `IS_PENDING` — that route needs no permission at all on
Android 10+. Export copies, never moves, and skips tracks that are already
in the Music folder.

**Data layer** — `packages/khinsider_api`, pure Dart (`dio` + `html`), zero
Flutter/native dependencies:

* Phase 1: search / album page — **one** HTML request, parsed into typed models.
* Phase 2: track page — resolved only on demand, extracts the direct CDN URL
  from `<audio id="audio" src="…">` and FLAC `<a>` links.

**Images** — covers come in pre-rendered sizes at the same path
(`<file>` original / `thumbs_large/` 200×200 / `thumbs/` 117×117 /
`thumbs_small/` 60×60). The pages only hand out the smallest two, so
`KhinsiderImage.large` rewrites the folder segment and every cover the app
draws is the 200×200 file (~15–80 KB) — see `AlbumSummary.imageUrl` /
`Album.imageUrl`. Originals (up to ~10 MB) are deliberately never loaded.

## Site notes (reverse-engineered)

* Album paths are **plural**: `/game-soundtracks/album/<id>`. The singular
  variant (`/game-soundtrack/album/…`) is blocked by Cloudflare WAF (403).
* Requests must send a browser-like `User-Agent` and `Accept` headers.

## Releasing

```bash
./scripts/release.sh patch          # 0.1.3 -> 0.1.4: bump pubspec, commit, tag, push (CI publishes)
./scripts/release.sh minor          # 0.1.3 -> 0.2.0
./scripts/release.sh major          # 0.1.3 -> 1.0.0
./scripts/release.sh repin          # move the newest tag onto the current commit and rebuild the GitHub Release (after fixing a CI failure)
./scripts/release.sh repin v0.1.3   # re-pin a specific tag
./scripts/release.sh patch --dry-run
```

`repin` deletes the GitHub Release for that tag first (removing the old
artifacts); the CI re-run recreates it.

### Android release signing

Android refuses to update an installed app if the new APK is signed with a
different key. The CI workflow therefore reads a **stable release keystore**
from GitHub repository secrets.

Add these secrets in **GitHub repo Settings > Secrets and variables > Actions**:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_TYPE` (`JKS` or `PKCS12`)
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Generate the keystore once and keep it backed up:

```bash
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload

# Linux:
base64 -w0 upload-keystore.jks
# macOS:
base64 -i upload-keystore.jks
```

Paste the base64 output into `ANDROID_KEYSTORE_BASE64`. The workflow decodes it
into `app/android/app/upload-keystore.<type>` and writes
`app/android/key.properties` before building. If the secrets are absent, the
build falls back to the debug key (local development only).

If your JDK `keytool` crashes with a `CodeHeap::allocate` SIGBUS (some macOS
JDK builds), generate a PKCS12 keystore with OpenSSL instead:

```bash
openssl req -newkey rsa:2048 -nodes -keyout key.pem -x509 -days 10000 \
  -out cert.pem -subj "/CN=KHInsider/OU=Mobile/O=trdthg/C=CN"
openssl pkcs12 -export -out upload-keystore.p12 \
  -inkey key.pem -in cert.pem -name upload -passout pass:YOUR_PASSWORD
base64 -i upload-keystore.p12 | tr -d '\n' > keystore.b64
```
Then set `ANDROID_KEYSTORE_TYPE=PKCS12`.

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
