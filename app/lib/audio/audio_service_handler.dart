import 'package:audio_service/audio_service.dart';

import 'base_audio_player.dart';
import 'just_audio_player_impl.dart';

/// [BaseAudioHandler] (audio_service) that owns a [JustAudioPlayerImpl].
///
/// * Implements the app's [BaseAudioPlayer] interface by delegation.
/// * Publishes MediaItem / PlaybackState so macOS Now-Playing (media keys,
///   control center), Android notification & lock-screen controls work.
class KhinsiderAudioHandler extends BaseAudioHandler
    implements BaseAudioPlayer {
  final JustAudioPlayerImpl _inner = JustAudioPlayerImpl();

  Duration _lastPosition = Duration.zero;

  KhinsiderAudioHandler() {
    _inner.snapshotStream.listen((snap) {
      _latestSnapshot = snap;
      _onSnapshot(snap);
    });
    _inner.positionStream.listen((p) {
      _lastPosition = p;
      _publishPlayback();
    });
  }

  // -- BaseAudioPlayer -------------------------------------------------------

  @override
  Stream<AudioPlayerSnapshot> get snapshotStream => _inner.snapshotStream;

  @override
  Stream<Duration> get positionStream => _inner.positionStream;

  @override
  Stream<Duration?> get durationStream => _inner.durationStream;

  @override
  int get queueLength => _inner.queueLength;

  @override
  Future<void> loadQueue(List<PlayableItem> items, {int startIndex = 0}) async {
    _queueItems
      ..clear()
      ..addAll(items);
    await _inner.loadQueue(items, startIndex: startIndex);
  }

  @override
  Future<void> append(List<PlayableItem> items) async {
    _queueItems.addAll(items);
    await _inner.append(items);
  }

  @override
  Future<void> swapCurrentSource(String url) => _inner.swapCurrentSource(url);

  /// Caching: every source is a [LockCachingAudioSource], i.e. the currently
  /// playing track streams **while** its bytes are written to the local cache
  /// (Application Support/audio_cache, one stable file per URL). Queued /
  /// prefetched tracks only mount their cache source — nothing is downloaded
  /// until they are actually played (IMPORTANT: never call request() manually
  /// here — concurrent request()+load() on the same source can deadlock the
  /// UI). Replaying a cached track is instant and works offline; partial
  /// downloads resume across restarts.

  @override
  Future<void> seek(Duration position) => _inner.seek(position);

  @override
  Future<void> next() => _inner.next();

  @override
  Future<void> previous() => _inner.previous();

  @override
  Future<void> skipToIndex(int index) => _inner.skipToIndex(index);

  @override
  Future<void> dispose() => _inner.dispose();

  // -- audio_service interface (system media controls) -----------------------

  @override
  Future<void> play() async {
    await _inner.play();
  }

  @override
  Future<void> pause() async {
    await _inner.pause();
  }

  @override
  Future<void> skipToNext() async {
    await _inner.next();
  }

  @override
  Future<void> skipToPrevious() async {
    await _inner.previous();
  }

  @override
  Future<void> stop() async {
    _queueItems.clear();
    await _inner.stop();
    await super.stop(); // audio_service: end foreground/notification state
  }

  // -- state sync ------------------------------------------------------------

  final List<PlayableItem> _queueItems = [];

  void _onSnapshot(AudioPlayerSnapshot snap) {
    final i = snap.currentIndex;
    if (i != null && i >= 0 && i < _queueItems.length) {
      final item = _queueItems[i];
      final current = mediaItem.value;
      if (current == null ||
          current.id != item.id ||
          current.title != item.title) {
        mediaItem.add(
          MediaItem(
            id: item.id,
            title: item.title,
            artist: item.artist,
            album: item.albumTitle,
            artUri: item.artUri,
          ),
        );
      }
    }
    _publishPlayback();
  }

  void _publishPlayback() {
    final snap = _latestSnapshot;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (snap?.playing ?? false) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        processingState: snap == null
            ? AudioProcessingState.idle
            : snap.processing
            ? AudioProcessingState.buffering
            : snap.completed
            ? AudioProcessingState.completed
            : AudioProcessingState.ready,
        playing: snap?.playing ?? false,
        updatePosition: _lastPosition,
      ),
    );
  }

  AudioPlayerSnapshot? _latestSnapshot;
}
