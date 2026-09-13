# Khinsider

English · [中文](README.zh-CN.md)

A simple client for the [khinsider](https://downloads.khinsider.com) website.

Download: see [Releases](https://github.com/trdthg/khinsiderTV/releases) (Android armv7 / arm64 / universal APK, macOS, Windows, Linux / Steam Deck flatpak)

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

## Building & releasing

```sh
# API package tests (offline, uses real page fixtures)
cd packages/khinsider_api && dart test

# App unit tests
cd app && flutter pub get && flutter analyze && flutter test

# Run on macOS locally
flutter run -d macos

# Android (armv7a/arm64, works on old TV boxes)
flutter build apk --release --target-platform android-arm,android-arm64

# Release: bump pubspec, commit, tag, push (CI builds and publishes the artifacts)
./scripts/release.sh patch          # 0.1.3 -> 0.1.4
./scripts/release.sh minor          # 0.1.3 -> 0.2.0
./scripts/release.sh major          # 0.1.3 -> 1.0.0
./scripts/release.sh repin          # re-point the newest tag at the current commit and rebuild the GitHub Release (after fixing a CI failure)
./scripts/release.sh repin v0.1.3   # re-point a specific tag
./scripts/release.sh patch --dry-run
```
