import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../audio/audio_cache_manager.dart';
import '../audio/base_audio_player.dart';
import '../audio/just_audio_player_impl.dart';
import '../data/khinsider_client.dart';
import 'track_cache_controller.dart';

/// Preferred streaming format for the audio-quality switcher.
enum AudioFormat { mp3, flac }

/// One slot in the playback queue. Sources are resolved lazily (phase 2).
class QueueEntry {
  QueueEntry({required this.track, required this.album});

  final AlbumTrack track;
  final Album album;

  String? resolvedMp3Url;
  String? resolvedFlacUrl;

  /// URL for the currently preferred format, with fallback.
  String? urlFor(AudioFormat f) => f == AudioFormat.flac
      ? (resolvedFlacUrl ?? resolvedMp3Url)
      : (resolvedMp3Url ?? resolvedFlacUrl);

  /// URL for exactly [f], with **no** fallback to the other format.
  ///
  /// The fallback in [urlFor] is right for keeping audio flowing, but the
  /// quality switcher must not use it: it would advertise FLAC while really
  /// streaming MP3.
  String? urlForExact(AudioFormat f) =>
      f == AudioFormat.flac ? resolvedFlacUrl : resolvedMp3Url;
}

/// Everything the UI needs to render playback state.
class PlayerState {
  const PlayerState({
    this.entries = const [],
    this.currentIndex,
    this.playing = false,
    this.processing = false,
    this.resolvingAhead = false,
    this.position = Duration.zero,
    this.duration,
    this.error,
    this.preferredFormat = AudioFormat.mp3,
  });

  final List<QueueEntry> entries;
  final int? currentIndex;
  final bool playing;
  final bool processing;

  /// True while background prefetch (phase 2) is still filling the queue.
  final bool resolvingAhead;
  final Duration position;
  final Duration? duration;
  final String? error;

  /// User-selected audio quality (OSD menu switcher).
  final AudioFormat preferredFormat;

  QueueEntry? get current =>
      currentIndex != null && currentIndex! < entries.length
      ? entries[currentIndex!]
      : null;

  /// Sentinel used by [copyWith] so an explicitly passed `null` clears a
  /// nullable field instead of being indistinguishable from "leave as-is".
  static const _unset = Object();

  PlayerState copyWith({
    List<QueueEntry>? entries,
    Object? currentIndex = _unset,
    bool? playing,
    bool? processing,
    bool? resolvingAhead,
    Duration? position,
    Object? duration = _unset,
    Object? error = _unset,
    AudioFormat? preferredFormat,
  }) {
    return PlayerState(
      entries: entries ?? this.entries,
      currentIndex: identical(currentIndex, _unset)
          ? this.currentIndex
          : currentIndex as int?,
      playing: playing ?? this.playing,
      processing: processing ?? this.processing,
      resolvingAhead: resolvingAhead ?? this.resolvingAhead,
      position: position ?? this.position,
      duration: identical(duration, _unset)
          ? this.duration
          : duration as Duration?,
      error: identical(error, _unset) ? this.error : error as String?,
      preferredFormat: preferredFormat ?? this.preferredFormat,
    );
  }
}

/// Bridges the UI to [BaseAudioPlayer] and performs lazy phase-2 URL
/// resolution: the clicked track is resolved immediately, remaining tracks
/// are resolved one-by-one in the background and appended to the queue.
///
/// It also acts as the app's [SystemMediaCommandHandler], so a play / pause /
/// next press on the Android notification or the lock screen runs the exact
/// same code path as a press inside the app.
class PlayerController extends Notifier<PlayerState>
    implements SystemMediaCommandHandler {
  BaseAudioPlayer get _player => ref.read(audioPlayerProvider);

  /// The system media session, when the platform has one (Android / iOS /
  /// macOS); null on desktop.
  ///
  /// Playback is never driven through it: the session's own `play` / `pause` /
  /// `stop` are the *system's* entry points and forward straight back into this
  /// controller (see [MediaSession]), so using it as the player would recurse
  /// until the app hung. It is only here to receive system commands and to end
  /// the session.
  MediaSession? get _session => ref.read(mediaSessionProvider);

  /// Cancellation for the in-flight phase-2 resolution of the current
  /// playAlbum call (the track-list spinner cancel button).
  CancelToken? _loadCancelToken;

  /// One-ahead prefetch. KHInsider is not a CDN we can hammer, so we
  /// resolve and append at most the next track, never the whole album.
  CancelToken? _prefetchToken;
  bool _prefetchInFlight = false;

  /// The in-flight [_prefetchNext] run, so a system "next" that arrives while
  /// the successor is still being resolved can wait for it instead of
  /// silently doing nothing.
  Future<void>? _prefetchFuture;
  Album? _playingAlbum;

  /// Maps impl-queue position -> album track index. The audio queue only
  /// contains tracks resolved so far, starting at the clicked track, so the
  /// impl's currentIndex must be translated before UI code uses it.
  final List<int> _albumIndexOfQueue = [];

  int? _implIndexToAlbumIndex(int? implIndex) {
    if (implIndex == null ||
        implIndex < 0 ||
        implIndex >= _albumIndexOfQueue.length) {
      return null;
    }
    return _albumIndexOfQueue[implIndex];
  }

  /// Subscriptions opened in [build]; cancelled on dispose so a rebuilt
  /// controller never keeps listening to (and writing to) a dead provider.
  final List<StreamSubscription> _subs = [];

  @override
  PlayerState build() {
    // Wire impl streams to UI state (kept for the lifetime of the app).
    final p = _player;
    // System media controls (notification / lock screen / media keys) must
    // run through this controller, not straight into the player: only the
    // controller knows the album queue and can resolve a missing successor.
    // Registered on the *session* — never on the player, which is what this
    // controller drives.
    final session = _session;
    session?.setSystemCommandHandler(this);
    _subs
      ..add(
        p.snapshotStream.listen((snap) {
          if (!ref.mounted) return;
          state = state.copyWith(
            playing: snap.playing,
            processing: snap.processing,
            // null (nothing loaded) clears the index instead of keeping the
            // previous track highlighted.
            currentIndex: _implIndexToAlbumIndex(snap.currentIndex),
          );
          unawaited(_prefetchNext());
        }),
      )
      ..add(
        // Throttled: positionStream can tick at up to 60 Hz, which would
        // otherwise rebuild every listening widget at 60 Hz and freeze the UI.
        p.positionStream.listen((pos) {
          if (!ref.mounted) return;
          final current = state.position;
          final wentBackwards = pos < current;
          final movedEnough =
              (pos - current).abs() >= const Duration(milliseconds: 250);
          final jumped = current == Duration.zero && pos > Duration.zero;
          if (movedEnough || wentBackwards || jumped) {
            state = state.copyWith(position: pos);
          }
        }),
      )
      ..add(
        p.durationStream.listen((d) {
          if (!ref.mounted) return;
          state = state.copyWith(duration: d);
        }),
      );
    // NOTE: the player is owned by whoever provided it (see
    // [audioPlayerProvider] / main.dart's override). Disposing it here would
    // tear down an object the app still needs, so only our subscriptions are
    // released.
    ref.onDispose(() {
      for (final sub in _subs) {
        unawaited(sub.cancel());
      }
      _prefetchToken?.cancel();
      _subs.clear();
      session?.setSystemCommandHandler(null);
    });
    return const PlayerState();
  }

  /// Start playback of [album] at [startIndex]. Resolves the clicked track
  /// now and at most one following track in the background.
  Future<void> playAlbum(Album album, {int startIndex = 0}) async {
    final tracks = album.tracks;
    if (tracks.isEmpty) return;

    // If this track is already in the live queue (e.g. the one-ahead
    // prefetch), reuse that source instead of creating a second
    // LockCachingAudioSource for the same .part file. Two sources writing
    // the same cache file can make just_audio fail with PathNotFoundException
    // when one of them tries to rename the .part file.
    final existingPos = _albumIndexOfQueue.indexOf(startIndex);
    final sameAlbum = _playingAlbum?.summary.id == album.summary.id;
    if (existingPos >= 0 && sameAlbum) {
      await _player.skipToIndex(existingPos);
      await _player.play();
      return;
    }

    final cachedUri = _cachedUriFor(album, startIndex);
    if (cachedUri != null) {
      _loadCancelToken?.cancel();
      _prefetchToken?.cancel();
      _prefetchToken = null;
      _prefetchInFlight = false;
      _playingAlbum = album;
      final entries = tracks
          .map((t) => QueueEntry(track: t, album: album))
          .toList();
      _albumIndexOfQueue
        ..clear()
        ..add(startIndex);
      state = PlayerState(
        entries: entries,
        currentIndex: startIndex,
        processing: false,
        resolvingAhead: false,
        preferredFormat: state.preferredFormat,
      );
      unawaited(_cacheAlbumSidecar(album));
      await _player.loadQueue([_playableFromUri(album, startIndex, cachedUri)]);
      if (!ref.mounted) return;
      unawaited(_prefetchNext(fromIndex: startIndex));
      return;
    }

    // A new play request always invalidates the previous load/prefetch.
    _loadCancelToken?.cancel();
    _prefetchToken?.cancel();
    _prefetchToken = null;
    _prefetchInFlight = false;
    _playingAlbum = album;
    final token = CancelToken();
    _loadCancelToken = token;

    // Preserve the quality the user picked in the OSD menu; only playback
    // progress/queue state is reset here.
    state = PlayerState(
      processing: true,
      resolvingAhead: false,
      preferredFormat: state.preferredFormat,
    );
    final entries = tracks
        .map((t) => QueueEntry(track: t, album: album))
        .toList();

    try {
      // Phase 2 — just the clicked track (both formats come in one request).
      final src = await ref
          .read(khinsiderClientProvider)
          .getTrackSources(
            tracks[startIndex].trackPagePath,
            cancelToken: token,
          );
      if (!ref.mounted || token.isCancelled) return;
      if (src.isEmpty) {
        state = state.copyWith(
          processing: false,
          resolvingAhead: false,
          error: 'No audio stream found for "${tracks[startIndex].name}"',
        );
        return;
      }
      entries[startIndex]
        ..resolvedMp3Url = src.mp3Url
        ..resolvedFlacUrl = src.flacUrl;
      state = state.copyWith(entries: entries);

      // Cache sidecar: describe the album + grab the cover into the
      // user-visible cache folder. Fire-and-forget: it must never delay or
      // break playback.
      unawaited(_cacheAlbumSidecar(album));

      _albumIndexOfQueue.clear();
      final first = _toPlayable(entries[startIndex]);
      if (first != null) {
        _albumIndexOfQueue.add(startIndex);
        await _player.loadQueue([first], startIndex: 0);
      }
      if (!ref.mounted) return;

      // Background prefetch: resolve and append exactly one track ahead.
      unawaited(_prefetchNext(fromIndex: startIndex));
    } catch (e) {
      state = state.copyWith(processing: false, error: 'Playback failed: $e');
    }
  }

  /// Writes `album.json` + the cover into `Music/KHInsider/<Album>/`, so the
  /// folder is self-describing (and the cover lands in `image/`).
  Future<void> _cacheAlbumSidecar(Album album) async {
    final cache = ref.read(audioCacheManagerProvider);
    try {
      await cache.saveAlbumManifest(album);
      await cache.cacheAlbumCover(
        album.summary.id,
        album.summary.title,
        // `imageUrl` (200×200 `thumbs_large`), not the raw album-page URL:
        // this is the same file the UI draws.
        album.imageUrl,
      );
    } catch (_) {
      // Sidecar files are a nice-to-have; never break playback over them.
    }
  }

  /// Called from the track-row spinner button: abort the pending load and
  /// drop whatever was already queued, returning the row to its idle state.
  Future<void> cancelLoading() => stop();

  /// Resolves and appends at most ONE following track (see
  /// [_prefetchNextImpl]).
  ///
  /// Returns the run that is already in flight, so a caller that needs the
  /// successor to be in the queue *now* (the system "next" button) can await
  /// it instead of racing it.
  ///
  /// Resolution failures are swallowed here: prefetching is a background
  /// optimisation and `next()` re-checks the queue instead of relying on an
  /// exception. Without this, the `unawaited` call sites in [playAlbum] would
  /// turn a flaky track page into an unhandled async error.
  Future<void> _prefetchNext({int? fromIndex}) {
    final pending = _prefetchFuture;
    if (pending != null) return pending;
    final run = _prefetchNextImpl(
      fromIndex: fromIndex,
    ).catchError((Object _) {});
    _prefetchFuture = run;
    return run.whenComplete(() {
      if (identical(_prefetchFuture, run)) _prefetchFuture = null;
    });
  }

  /// Resolves and appends at most ONE following track.
  ///
  /// KHInsider is not a CDN we can hammer, so we deliberately never resolve
  /// or queue the rest of the album. Each new current track asks for its own
  /// single successor.
  Future<void> _prefetchNextImpl({int? fromIndex}) async {
    final album = _playingAlbum;
    if (album == null || _prefetchInFlight) return;

    final current = fromIndex ?? state.currentIndex;
    if (current == null) return;

    final nextIndex = current + 1;
    if (nextIndex >= album.tracks.length) {
      if (state.resolvingAhead) {
        state = state.copyWith(resolvingAhead: false);
      }
      return;
    }
    if (_albumIndexOfQueue.contains(nextIndex)) return;

    _prefetchInFlight = true;
    _prefetchToken?.cancel();
    final token = CancelToken();
    _prefetchToken = token;
    if (ref.mounted) {
      state = state.copyWith(resolvingAhead: true);
    }

    final cachedUri = _cachedUriFor(album, nextIndex);
    if (cachedUri != null) {
      try {
        final item = _playableFromUri(album, nextIndex, cachedUri);
        await _player.append([item]);
        if (ref.mounted == false) return;
        if (token.isCancelled) return;
        _albumIndexOfQueue.add(nextIndex);
        state = state.copyWith(resolvingAhead: false);
      } finally {
        // Must run even if `append` throws, otherwise `_prefetchInFlight`
        // stays true forever and no track is ever prefetched again.
        if (identical(_prefetchToken, token)) {
          _prefetchToken = null;
          _prefetchInFlight = false;
        }
      }
      return;
    }

    try {
      final src = await ref
          .read(khinsiderClientProvider)
          .getTrackSources(
            album.tracks[nextIndex].trackPagePath,
            cancelToken: token,
          );
      if (ref.mounted == false) return;
      if (token.isCancelled) return;

      final entries = List<QueueEntry>.of(state.entries);
      if (nextIndex >= entries.length) return;
      entries[nextIndex]
        ..resolvedMp3Url = src.mp3Url
        ..resolvedFlacUrl = src.flacUrl;

      final item = _toPlayable(entries[nextIndex]);
      if (item == null) {
        if (ref.mounted) {
          state = state.copyWith(entries: entries, resolvingAhead: false);
        }
        return;
      }

      await _player.append([item]);
      if (ref.mounted == false) return;
      if (token.isCancelled) return;

      _albumIndexOfQueue.add(nextIndex);
      state = state.copyWith(entries: entries, resolvingAhead: false);
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(resolvingAhead: false);
      }
    } finally {
      if (identical(_prefetchToken, token)) {
        _prefetchToken = null;
        _prefetchInFlight = false;
      }
    }
  }

  Uri? _cachedUriFor(Album album, int index) {
    final track = album.tracks[index];
    final cache = ref.read(audioCacheManagerProvider);
    final mp3Key = CacheLookupKey(
      albumId: album.summary.id,
      albumTitle: album.summary.title,
      trackIndex: track.index,
      trackTitle: track.name,
      extension: '.mp3',
    );
    final flacKey = CacheLookupKey(
      albumId: album.summary.id,
      albumTitle: album.summary.title,
      trackIndex: track.index,
      trackTitle: track.name,
      extension: '.flac',
    );
    if (state.preferredFormat == AudioFormat.flac) {
      return cache.cachedFileUri(flacKey) ?? cache.cachedFileUri(mp3Key);
    }
    return cache.cachedFileUri(mp3Key) ?? cache.cachedFileUri(flacKey);
  }

  PlayableItem _playableFromUri(Album album, int index, Uri uri) {
    final track = album.tracks[index];
    final coverUrl = album.imageUrl;
    return PlayableItem(
      id: '${album.summary.id}/${track.index}',
      title: track.name,
      url: uri.toString(),
      artist: album.summary.title,
      albumTitle: album.summary.title,
      albumId: album.summary.id,
      trackIndex: track.index,
      artUri: coverUrl == null ? null : Uri.tryParse(coverUrl),
    );
  }

  PlayableItem? _toPlayable(QueueEntry e) {
    final url = e.urlFor(state.preferredFormat);
    if (url == null) return null;
    return PlayableItem(
      id: '${e.album.summary.id}/${e.track.index}',
      title: e.track.name,
      url: url,
      artist: e.album.summary.title,
      albumTitle: e.album.summary.title,
      albumId: e.album.summary.id,
      trackIndex: e.track.index,
      artUri: e.album.imageUrl != null ? Uri.tryParse(e.album.imageUrl!) : null,
    );
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() => _player.play();

  Future<void> togglePlayPause() async {
    if (state.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  /// Advance one track.
  ///
  /// The successor is resolved on demand when it is not in the queue yet:
  /// the queue deliberately holds only the current track plus one prefetched
  /// successor, so a system "next" that arrives while that prefetch is still
  /// running used to be a silent no-op — the notification button looked dead.
  @override
  Future<void> next() async {
    final album = _playingAlbum;
    final current = state.currentIndex;
    if (album != null && current != null) {
      final nextIndex = current + 1;
      if (nextIndex >= album.tracks.length) return; // end of the album
      if (!_albumIndexOfQueue.contains(nextIndex)) {
        await _prefetchNext(fromIndex: current);
        // Resolution failed or was cancelled: stay where we are rather than
        // jumping to a track we cannot play.
        if (!_albumIndexOfQueue.contains(nextIndex)) return;
      }
    }
    await _player.next();
  }

  @override
  Future<void> previous() => _player.previous();

  /// Halt playback and drop the queue (media Stop key).
  @override
  Future<void> stop() async {
    final session = _session;
    _loadCancelToken?.cancel();
    _prefetchToken?.cancel();
    _prefetchToken = null;
    _prefetchInFlight = false;
    _playingAlbum = null;
    _loadCancelToken = null;
    _albumIndexOfQueue.clear();
    await _player.stop();
    // The system controls belong to the playback that was just dropped: end
    // the session as well, otherwise the notification would linger on a
    // stopped player.
    await session?.endSession();
    if (!ref.mounted) return;
    state = PlayerState(preferredFormat: state.preferredFormat);
  }

  Future<void> seek(Duration pos) => _player.seek(pos);

  /// Switch streaming quality; the current track re-loads at its position.
  Future<void> setPreferredFormat(AudioFormat format) async {
    final entry = state.current;
    if (entry == null) return;
    // No fallback here: switching to a format that this track does not
    // actually offer must be a no-op, otherwise the menu would show FLAC
    // selected while MP3 keeps playing.
    final url = entry.urlForExact(format);
    if (url == null) return; // format unavailable for this track
    // Commit only once the source really switched, otherwise the UI would
    // advertise a quality that is not actually playing.
    try {
      await _player.swapCurrentSource(url);
    } catch (_) {
      return;
    }
    if (!ref.mounted) return;
    state = state.copyWith(preferredFormat: format);
  }

  /// Whether the quality switcher can offer FLAC right now.
  bool get flacAvailable {
    final entry = state.current;
    return entry?.resolvedFlacUrl != null;
  }

  void clearError() => state = state.copyWith(error: null);
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);

/// The single [BaseAudioPlayer] instance for the whole app, i.e. the object
/// every `play` / `pause` / queue mutation goes to.
/// (Switch port: replace this provider's implementation only.)
final audioPlayerProvider = Provider<BaseAudioPlayer>((ref) {
  return JustAudioPlayerImpl();
});

/// The system media session of the current platform, or null when there is
/// none (Windows/Linux, where audio_service has no platform channels, and
/// tests).
///
/// Overridden in `main.dart` with the `audio_service` bridge, which publishes
/// the media item / playback state and receives the notification, lock-screen
/// and headset commands.
final mediaSessionProvider = Provider<MediaSession?>((ref) => null);
