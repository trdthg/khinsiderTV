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
/// playing track streams **while** its bytes are written to the local cache
/// (Application Support/audio_cache, one stable file per URL). Queued /
/// prefetched tracks only mount their cache source — nothing is downloaded
/// until they are actually played (IMPORTANT: never call request() manually
/// here — concurrent request()+load() on the same source can deadlock the
/// UI). Replaying a cached track is instant and works offline; partial
/// downloads resume across restarts.
class JustAudioPlayerImpl implements BaseAudioPlayer {
  final AudioPlayer _player = AudioPlayer();
  final AudioCacheManager _cache = AudioCacheManager();

  /// Metadata of the items currently loaded in the queue, index-aligned with
  /// the player sequence. Used by [swapCurrentSource].
  final List<PlayableItem> _items = [];

  /// Creates a FRESH LockCachingAudioSource each time. The `cacheFile`
  /// param ensures the downloaded audio file is reused (partial downloads
  /// resume, fully cached tracks play instantly). We must NOT cache the
  /// source objects themselves: just_audio disposes old sources on
  /// setAudioSources, and reusing a disposed source causes a deadlock.

  Future<LockCachingAudioSource> _sourceFor(PlayableItem it) async {
    final file = await _cache.fileFor(it.url);
    return LockCachingAudioSource(Uri.parse(it.url), cacheFile: file);
  }

  final _snapshotCtrl = StreamController<AudioPlayerSnapshot>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration?>.broadcast();

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _currentIndexSub;

  void _init() {
    _playerStateSub = _player.playerStateStream.listen((s) {
      _snapshotCtrl.add(
        AudioPlayerSnapshot(
          playing: s.playing,
          currentIndex: _player.currentIndex,
          processing:
              s.processingState == ProcessingState.loading ||
              s.processingState == ProcessingState.buffering,
          completed: s.processingState == ProcessingState.completed,
        ),
      );
      // Auto-advance fallback: just_audio handles queue advancement itself;
      // completed means the *whole* queue ended.
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero, index: 0);
      }
    });
    _positionSub = _player.positionStream.listen(_positionCtrl.add);
    _durationSub = _player.durationStream.listen(_durationCtrl.add);
    _currentIndexSub = _player.currentIndexStream.listen((i) {
      _snapshotCtrl.add(
        AudioPlayerSnapshot(
          playing: _player.playing,
          currentIndex: i,
          processing:
              _player.playerState.processingState == ProcessingState.loading ||
              _player.playerState.processingState == ProcessingState.buffering,
        ),
      );
    });
  }

  @override
  Stream<AudioPlayerSnapshot> get snapshotStream => _snapshotCtrl.stream;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<Duration?> get durationStream => _durationCtrl.stream;

  @override
  Future<void> loadQueue(List<PlayableItem> items, {int startIndex = 0}) async {
    if (_positionSub == null) _init();
    _items
      ..clear()
      ..addAll(items);
    final sources = [for (final it in items) await _sourceFor(it)];
    await _player.setAudioSources(sources, initialIndex: startIndex);
    await _player.play();
  }

  @override
  Future<void> append(List<PlayableItem> items) async {
    if (_positionSub == null) _init();
    _items.addAll(items);
    final sources = [for (final it in items) await _sourceFor(it)];
    await _player.addAudioSources(sources);
  }

  @override
  Future<void> swapCurrentSource(String url) async {
    final index = _player.currentIndex;
    if (index == null || index < 0 || index >= _items.length) return;
    final old = _items[index];
    _items[index] = PlayableItem(
      id: old.id,
      title: old.title,
      url: url,
      artist: old.artist,
      albumTitle: old.albumTitle,
      artUri: old.artUri,
    );
    final position = _player.position;
    final wasPlaying = _player.playing;
    final sources = [for (final it in _items) await _sourceFor(it)];
    await _player.setAudioSources(
      sources,
      initialIndex: index,
      initialPosition: position,
    );
    if (wasPlaying) await _player.play();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _items.clear();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

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
    await _playerStateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _currentIndexSub?.cancel();
    await _snapshotCtrl.close();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _player.dispose();
  }
}
