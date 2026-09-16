import 'dart:async';

// LockCachingAudioSource is experimental upstream but is the only built-in
// play-while-caching primitive; intentionally adopted here.
// ignore_for_file: experimental_member_use
import 'package:just_audio/just_audio.dart';

import 'audio_cache_manager.dart';
import 'base_audio_player.dart';

/// [BaseAudioPlayer] backed by `just_audio`.
///
/// On Android this runs on ExoPlayer (low CPU, background-friendly); on
/// desktop it uses the platform bindings of just_audio. The rest of the app
/// never sees this class — only [BaseAudioPlayer].
///
/// Caching: every source is a [LockCachingAudioSource], i.e. the currently
/// playing track streams **while** its bytes are written to the user-visible
/// cache (`Music/KHInsider/<Album>/mp3|flac|image|other`, one readable file
/// name per track, see [AudioCacheManager]). Queued /
/// prefetched tracks only mount their cache source — nothing is downloaded
/// until they are actually played (IMPORTANT: never call request() manually
/// here — concurrent request()+load() on the same source can deadlock the
/// UI). Replaying a cached track is instant and works offline; partial
/// downloads resume across restarts.
class JustAudioPlayerImpl implements BaseAudioPlayer {
  JustAudioPlayerImpl({AudioCacheManager? cacheManager})
    : _cache = cacheManager ?? AudioCacheManager();

  final AudioPlayer _player = AudioPlayer();
  final AudioCacheManager _cache;

  /// Metadata of the items currently loaded in the queue, index-aligned with
  /// the player sequence. Used by [swapCurrentSource] and mirrored by the
  /// media session ([KhinsiderAudioHandler]).
  final List<PlayableItem> _items = [];

  @override
  List<PlayableItem> get items => List<PlayableItem>.unmodifiable(_items);

  /// Serialises queue mutations so a loadQueue/append/stop burst cannot
  /// interleave and leave [_items] out of step with the player's sequence.
  Future<void> _queueOp = Future<void>.value();

  bool _disposed = false;

  /// Creates a FRESH LockCachingAudioSource each time. The `cacheFile`
  /// param ensures the downloaded audio file is reused (partial downloads
  /// resume, fully cached tracks play instantly). We must NOT cache the
  /// source objects themselves: just_audio disposes old sources on
  /// setAudioSources, and reusing a disposed source causes a deadlock.

  Future<LockCachingAudioSource> _sourceFor(PlayableItem it) async {
    final file = await _cache.fileFor(it);
    // Fetch it ourselves too, in the background. just_audio's caching source
    // never renames its `.part` file into place on Windows — not even for a
    // track played end to end — so relying on it alone leaves a cache folder
    // that never holds one single finished track.
    unawaited(_cache.downloadTrackSource(it.url, file));
    return LockCachingAudioSource(Uri.parse(it.url), cacheFile: file);
  }

  final _snapshotCtrl = StreamController<AudioPlayerSnapshot>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration?>.broadcast();

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _currentIndexSub;
  bool _initialized = false;

  /// One source of truth for the snapshot: a single listener that reads the
  /// player's current state, instead of two overlapping listeners that both
  /// pushed a (differently populated) snapshot.
  bool get _processing =>
      _player.playerState.processingState == ProcessingState.loading ||
      _player.playerState.processingState == ProcessingState.buffering;

  void _init() {
    if (_initialized) return;
    _initialized = true;

    _playerStateSub = _player.playerStateStream.listen((s) {
      _pushSnapshot(currentIndex: _player.currentIndex);
      // Auto-advance fallback: just_audio handles queue advancement itself;
      // completed means the *whole* queue ended.
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero, index: 0);
      }
    });
    _positionSub = _player.positionStream.listen(
      _positionCtrl.add,
      onError: _positionCtrl.addError,
    );
    _durationSub = _player.durationStream.listen(
      _durationCtrl.add,
      onError: _durationCtrl.addError,
    );
    _currentIndexSub = _player.currentIndexStream.listen((_) {
      _pushSnapshot(currentIndex: _player.currentIndex);
    });
  }

  void _pushSnapshot({int? currentIndex}) {
    if (_disposed) return;
    _snapshotCtrl.add(
      AudioPlayerSnapshot(
        playing: _player.playing,
        currentIndex: currentIndex,
        processing: _processing,
        completed:
            _player.playerState.processingState == ProcessingState.completed,
      ),
    );
  }

  @override
  Stream<AudioPlayerSnapshot> get snapshotStream => _snapshotCtrl.stream;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<Duration?> get durationStream => _durationCtrl.stream;

  /// Runs [op] after every previously queued mutation has settled, so the
  /// `_items` mirror can never be updated by two operations at once.
  Future<void> _serialize(Future<void> Function() op) {
    final run = _queueOp.then((_) => op());
    _queueOp = run.catchError((Object _) {});
    return run;
  }

  @override
  Future<void> loadQueue(List<PlayableItem> items, {int startIndex = 0}) {
    return _serialize(() async {
      _init();
      // Build the sources BEFORE publishing the new metadata: if source
      // creation throws, `_items` must stay consistent with what the player
      // is actually holding.
      final sources = [for (final it in items) await _sourceFor(it)];
      _items
        ..clear()
        ..addAll(items);
      await _player.setAudioSources(sources, initialIndex: startIndex);
      // `play()` completes only when playback pauses/stops. Awaiting it
      // here would block the queue serialization and prefetch forever.
      unawaited(_player.play());
    });
  }

  @override
  Future<void> append(List<PlayableItem> items) {
    return _serialize(() async {
      _init();
      final sources = [for (final it in items) await _sourceFor(it)];
      _items.addAll(items);
      try {
        await _player.addAudioSources(sources);
      } catch (_) {
        // Roll the mirror back so it still matches the player's sequence.
        _items.removeRange(_items.length - items.length, _items.length);
        rethrow;
      }
    });
  }

  @override
  Future<void> swapCurrentSource(String url) {
    return _serialize(() async {
      final index = _player.currentIndex;
      if (index == null || index < 0 || index >= _items.length) return;
      final old = _items[index];
      if (old.url == url) return; // nothing to do
      final replacement = PlayableItem(
        id: old.id,
        title: old.title,
        url: url,
        artist: old.artist,
        albumTitle: old.albumTitle,
        albumId: old.albumId,
        trackIndex: old.trackIndex,
        artUri: old.artUri,
      );
      final position = _player.position;
      final wasPlaying = _player.playing;
      final sources = [
        for (final it in _items)
          it == old ? await _sourceFor(replacement) : await _sourceFor(it),
      ];
      _items[index] = replacement;
      await _player.setAudioSources(
        sources,
        initialIndex: index,
        initialPosition: position,
      );
      if (wasPlaying) unawaited(_player.play());
    });
  }

  @override
  Future<void> stop() {
    return _serialize(() async {
      // AudioPlayer.stop() halts playback but KEEPS the playlist, so the
      // queue must be cleared explicitly or queueLength and `_items` drift
      // apart and every later append lands at the wrong index.
      await _player.stop();
      await _player.clearAudioSources();
      _items.clear();
      if (!_disposed) {
        _snapshotCtrl.add(
          const AudioPlayerSnapshot(
            playing: false,
            currentIndex: null,
            processing: false,
            completed: false,
          ),
        );
      }
    });
  }

  @override
  Future<void> play() async {
    // A play command should return once playback has been requested, not
    // when the track eventually ends.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToIndex(int index) =>
      _player.seek(Duration.zero, index: index);

  @override
  Future<void> next() async {
    final hasNext = (_player.currentIndex ?? -1) < queueLength - 1;
    if (hasNext) {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> previous() async {
    // TV-style behaviour: restart current track first, then jump back.
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  @override
  int get queueLength => _player.sequence.length;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _playerStateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _currentIndexSub?.cancel();
    _playerStateSub = null;
    _positionSub = null;
    _durationSub = null;
    _currentIndexSub = null;
    await _queueOp;
    await _snapshotCtrl.close();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _player.dispose();
  }
}
