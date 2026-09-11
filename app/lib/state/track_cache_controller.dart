import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../audio/audio_cache_manager.dart';
import 'player_controller.dart';

/// Single [AudioCacheManager] for the whole app (the playback impl resolves
/// the very same root, so the UI and the player always agree on paths).
final audioCacheManagerProvider = Provider<AudioCacheManager>((ref) {
  return AudioCacheManager();
});

/// Per-track cache state, as shown on the right edge of each track row.
class TrackCacheEntry {
  const TrackCacheEntry({
    this.mp3Bytes,
    this.losslessBytes,
    this.downloading = false,
  });

  static const TrackCacheEntry empty = TrackCacheEntry();

  /// Completed MP3 file size in bytes (null when not cached).
  final int? mp3Bytes;

  /// Completed lossless file size in bytes (null when not cached).
  final int? losslessBytes;

  /// True while a partial download is on disk.
  final bool downloading;

  bool get cached => mp3Bytes != null || losslessBytes != null;

  /// True when the lossless copy is on disk as well.
  bool get hasLossless => losslessBytes != null;

  int get bytes => (mp3Bytes ?? 0) + (losslessBytes ?? 0);

  bool get isEmpty => !cached && !downloading;

  @override
  bool operator ==(Object other) =>
      other is TrackCacheEntry &&
      other.mp3Bytes == mp3Bytes &&
      other.losslessBytes == losslessBytes &&
      other.downloading == downloading;

  @override
  int get hashCode => Object.hash(mp3Bytes, losslessBytes, downloading);
}

/// Cache state of the album currently on screen.
class AlbumCacheState {
  const AlbumCacheState({
    this.albumId,
    this.folderPath,
    this.tracks = const {},
  });

  static const AlbumCacheState empty = AlbumCacheState();

  final String? albumId;

  /// `Music/KHInsider/<Album>` — surfaced in the UI so the user knows where
  /// to look for the files.
  final String? folderPath;

  /// Keyed by the 1-based track number shown on the site.
  final Map<int, TrackCacheEntry> tracks;

  bool get isEmpty => albumId == null && folderPath == null && tracks.isEmpty;

  AlbumCacheState copyWith({
    String? folderPath,
    Map<int, TrackCacheEntry>? tracks,
  }) => AlbumCacheState(
    albumId: albumId,
    folderPath: folderPath ?? this.folderPath,
    tracks: tracks ?? this.tracks,
  );

  @override
  bool operator ==(Object other) =>
      other is AlbumCacheState &&
      other.albumId == albumId &&
      other.folderPath == folderPath &&
      _mapEquals(other.tracks, tracks);

  @override
  int get hashCode =>
      Object.hash(albumId, folderPath, Object.hashAllUnordered(tracks.keys));
}

bool _mapEquals(Map<int, TrackCacheEntry> a, Map<int, TrackCacheEntry> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Watches the on-disk cache for the album the user is looking at.
///
/// File names are derived from the track number + title (never from the media
/// URL), so the state of every row can be resolved **before** the track's URL
/// is resolved — no extra network requests, just a couple of `stat` calls.
class AlbumCacheController extends Notifier<AlbumCacheState> {
  Album? _album;
  Timer? _timer;
  bool _scanning = false;

  /// Guards against a wedged scan (see [_scan]).
  final Stopwatch _watch = Stopwatch()..start();
  int _seq = 0;

  static const Duration _staleAfter = Duration(seconds: 3);

  /// Poll interval while a download is in flight (the file only appears on
  /// disk once `just_audio` renames the `.part` file).
  static const Duration pollInterval = Duration(milliseconds: 1200);

  @override
  AlbumCacheState build() {
    // Playback is what creates cache files: rescan whenever it moves.
    ref.listen(playerControllerProvider, (_, next) {
      if (next.processing || next.playing) _scan();
    });
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      _album = null;
    });
    return AlbumCacheState.empty;
  }

  /// Point the controller at the album being rendered by the screen.
  Future<void> sync(Album album) async {
    if (_album?.summary.id != album.summary.id) {
      _timer?.cancel();
      _timer = null;
      if (_album != null) state = AlbumCacheState.empty;
    }
    _album = album;
    await _scan();
  }

  /// Re-read the cache from disk (also used after a manual download).
  Future<void> refresh() => _scan();

  /// Reads the cache folder for [_album] and publishes the result.
  ///
  /// A scan that is still running coalesces further requests — EXCEPT when it
  /// looks stuck ([_staleAfter]), in which case a new scan supersedes it (via
  /// the sequence number) so a wedged scan can never block the UI for good.
  Future<void> _scan() async {
    final album = _album;
    if (album == null) return;
    if (_scanning && _watch.elapsed < _staleAfter) return;
    _scanning = true;
    _watch
      ..reset()
      ..start();
    final seq = ++_seq;
    try {
      final cache = ref.read(audioCacheManagerProvider);
      await cache.root();
      final dir = cache.locateAlbumDirSync(
        album.summary.id,
        album.summary.title,
      );
      final entries = <int, TrackCacheEntry>{};
      var downloading = false;
      for (final track in album.tracks) {
        final key = CacheLookupKey(
          albumId: album.summary.id,
          albumTitle: album.summary.title,
          trackIndex: track.index,
          trackTitle: track.name,
        );
        var entry = TrackCacheEntry.empty;
        for (final k in key.withLossless) {
          final status = cache.statusForSync(k);
          if (status.downloading) downloading = true;
          if (k.extension == '.flac') {
            entry = TrackCacheEntry(
              mp3Bytes: entry.mp3Bytes,
              losslessBytes: status.bytes,
              downloading: entry.downloading || status.downloading,
            );
          } else {
            entry = TrackCacheEntry(
              mp3Bytes: status.bytes,
              losslessBytes: entry.losslessBytes,
              downloading: entry.downloading || status.downloading,
            );
          }
        }
        if (!entry.isEmpty) entries[track.index] = entry;
      }
      if (!ref.mounted || seq != _seq) return;
      final next = AlbumCacheState(
        albumId: album.summary.id,
        folderPath: dir?.path,
        tracks: entries,
      );
      if (next != state) state = next;
      if (seq == _seq) _schedulePolling(downloading: downloading);
    } catch (_) {
      // Cache status is advisory: never let a disk hiccup break the screen.
    } finally {
      if (seq == _seq) _scanning = false;
    }
  }

  void _schedulePolling({required bool downloading}) {
    final playerBusy = ref.read(playerControllerProvider).processing;
    if (downloading || playerBusy) {
      _timer ??= Timer.periodic(pollInterval, (_) => _scan());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }
}

/// Auto-dispose: the polling timer (and the disk reads) only run while an
/// album screen is actually on screen.
final albumCacheProvider =
    NotifierProvider.autoDispose<AlbumCacheController, AlbumCacheState>(
      AlbumCacheController.new,
    );
