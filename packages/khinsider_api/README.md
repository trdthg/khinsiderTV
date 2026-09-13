# khinsider_api

Pure-Dart client for [khinsider](https://downloads.khinsider.com): an HTML parser plus a small
typed data API. `dio` + `html` only — no Flutter, no native dependencies — so it can be reused
from a CLI, a test, or an embedded port (the app keeps its player behind
`app/lib/audio/base_audio_player.dart` for exactly that reason).

## Usage

```dart
import 'package:khinsider_api/khinsider_api.dart';

final client = KhinsiderClient();

// Phase 1 — search: one HTML request, typed results.
final results = await client.searchAlbums('chrono trigger');

// Phase 1 — album page: one HTML request, cover + ordered track list.
final album = await client.getAlbum(results.first.id);

// Phase 2 — direct media URLs, only when a track is actually played/downloaded.
final source = await client.getTrackSources(album.tracks.first.trackPagePath);
print(source.bestUrl);

client.close();
```

### Two-phase loading

* **Phase 1** — `searchAlbums` / `getAlbum` cost exactly one HTML request and return parsed
  models. Everything the UI needs to draw a list or an album page comes from here.
* **Phase 2** — `getTrackSources(trackPagePath)` fetches one track page and extracts the direct
  CDN URL from `<audio id="audio" src="…">` plus the FLAC `<a>` links. Called only when a track
  enters the queue. `getAlbumTrackSources(album)` is a convenience loop that stays
  **sequential on purpose**: parallel bursts look bot-like to the site.

### Disk cache

```dart
final cache = HttpCache(() async => Directory('${appSupport.path}/khinsider'));
final client = KhinsiderClient(cache: cache);
```

`HttpCache` stores bodies under a SHA-1 of the URL and exposes `get(url, ttl:)`, `put`,
`remove` and `clear`. Passing one to the client makes search/album pages **cache-first**
(`forceRefresh: true` bypasses and overwrites); track pages are cached for
`KhinsiderClient.trackPageTtl` (30 minutes) because the CDN tokens eventually rotate.

### Models

| Type | Fields |
| --- | --- |
| `AlbumSummary` | `id`, `title`, `urlPath`, `thumbUrl`, `platforms`, `type`, `year` |
| `AlbumTrack` | `index`, `name`, `trackPagePath`, `songId`, `duration`, `mp3SizeMb`, `flacSizeMb` |
| `AlbumMetadata` | `alternativeTitles`, `platforms`, `year`, `developedBy`, `publishedBy`, `fileCount`, `totalFilesize`, `dateAdded`, `albumType`, `uploadedBy` |
| `Album` | `summary`, `coverUrl`, `tracks`, `metadata`, `relatedAlbums` |
| `TrackSource` | `trackPagePath`, `mp3Url`, `flacUrl`, `bestUrl`, `isEmpty` |

### Cover images

The site serves every cover pre-rendered at the same path with only the folder segment changed
(`<file>` original / `thumbs_large/` 200×200 / `thumbs/` 117×117 / `thumbs_small/` 60×60), but
the pages only hand out the two smallest ones. `KhinsiderImage.large(url)` rewrites the folder
segment back to `thumbs_large`, so every cover the app draws is the 200×200 file (~15–80 KB)
instead of the 60×60 the search results embed. Originals (up to ~10 MB) are never loaded.
The helper is idempotent and returns non-album URLs untouched.

## Site notes (reverse-engineered)

* Album paths are **plural**: `/game-soundtracks/album/<id>`. The singular variant
  (`/game-soundtrack/album/…`) is blocked by the Cloudflare WAF with a 403.
* Requests must send a browser-like `User-Agent` and `Accept` header — that is what
  `KhinsiderClient.defaultUserAgent` is for.
* Track pages hold rotating CDN URLs, so they are resolved as late as possible and only cached
  briefly.

## Tests

```sh
dart test        # offline, driven by real page fixtures in test/fixtures/
```

Fixtures are checked-in pages, so the parser tests never touch the network. To re-parse a fresh
page after a site change: drop the HTML into `test/fixtures/` and extend `parsers_test.dart`.

## Layout

```
lib/khinsider_api.dart         # public exports
lib/src/khinsider_client.dart  # Dio setup, phase 1/phase 2 requests, cache wiring
lib/src/parsers.dart           # HTML -> models (search, album, track page)
lib/src/models.dart            # AlbumSummary, AlbumTrack, AlbumMetadata, Album, TrackSource
lib/src/image_urls.dart        # KhinsiderImage.large
lib/src/http_cache.dart        # dependency-free disk cache
```
