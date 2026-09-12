import 'dart:async';
import 'package:audio_service/audio_service.dart';

import 'base_audio_player.dart';
import 'just_audio_player_impl.dart';

/// [BaseAudioHandler] (audio_service) that owns a [BaseAudioPlayer] (by
/// default a [JustAudioPlayerImpl]).
///
/// * Implements the app's [BaseAudioPlayer] interface by delegation.
/// * Publishes MediaItem / PlaybackState so macOS Now-Playing (media keys,
///   control center), Android notification & lock-screen controls work.
///
/// System-originated commands (`play` / `pause` / `skipToNext` /
/// `skipToPrevious`) are forwarded to the app-level
/// [SystemMediaCommandHandler] installed by the state layer, so pressing
/// "next" on the lock screen behaves exactly like pressing it in the app —
/// including resolving the successor track when it is not queued yet.
class KhinsiderAudioHandler extends BaseAudioHandler
    implements BaseAudioPlayer {
  KhinsiderAudioHandler({BaseAudioPlayer? inner})
    : _inner = inner ?? JustAudioPlayerImpl() {
    _subs
      ..add(
        _inner.snapshotStream.listen((snap) {
          _latestSnapshot = snap;
          _onSnapshot(snap);
        }),
      )
      ..add(
        // The media-session seek bar only appears once the current item
        // carries a duration, and the duration arrives after the item itself.
        _inner.durationStream.listen((d) {
          _lastDuration = d;
          _onSnapshot(_latestSnapshot);
        }),
      )
      ..add(
        _inner.positionStream.listen((p) {
          _lastPosition = p;
          _publishPlayback();
        }),
      );
  }

  final BaseAudioPlayer _inner;

  SystemMediaCommandHandler? _commands;

  Duration _lastPosition = Duration.zero;
  Duration? _lastDuration;
  final List<StreamSubscription> _subs = [];
  bool _disposed = false;

  /// Throttles playback-state publication driven by position ticks: the
  /// system extrapolates the position from `updatePosition` + `updateTime`,
  /// so republishing on every ~200 ms tick only spams the platform channel.
  DateTime _lastPublishAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _positionPublishInterval = Duration(seconds: 1);

  @override
  void setSystemCommandHandler(SystemMediaCommandHandler? handler) {
    _commands = handler;
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
    // Publish the mirror only after the inner call succeeded, otherwise the
    // system media session could advertise a queue that is not playing.
    await _inner.loadQueue(items, startIndex: startIndex);
    _queueItems
      ..clear()
      ..addAll(items);
  }

  @override
  Future<void> append(List<PlayableItem> items) async {
    await _inner.append(items);
    _queueItems.addAll(items);
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
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _inner.dispose();
  }

  // -- audio_service interface (system media controls) -----------------------

  @override
  Future<void> play() => _commands?.play() ?? _inner.play();

  @override
  Future<void> pause() => _commands?.pause() ?? _inner.pause();

  @override
  Future<void> skipToNext() => _commands?.next() ?? _inner.next();

  @override
  Future<void> skipToPrevious() => _commands?.previous() ?? _inner.previous();

  @override
  Future<void> stop() async {
    // Route through the controller when there is one so the app's own queue
    // state is cleared as well (the notification has a dismiss/stop control
    // — the affordance that `androidNotificationOngoing: true` used to add
    // via its cancel button).
    final commands = _commands;
    if (commands != null) {
      await commands.stop();
    } else {
      await _inner.stop();
    }
    _queueItems.clear();
    _lastDuration = null;
    mediaItem.add(null); // nothing is playing any more
    await super.stop(); // audio_service: end foreground/notification state
  }

  // -- state sync ------------------------------------------------------------

  final List<PlayableItem> _queueItems = [];

  void _onSnapshot(AudioPlayerSnapshot? snap) {
    final i = snap?.currentIndex;
    if (i != null && i >= 0 && i < _queueItems.length) {
      final item = _queueItems[i];
      final current = mediaItem.value;
      if (current == null ||
          current.id != item.id ||
          current.title != item.title ||
          current.duration != _lastDuration) {
        mediaItem.add(
          MediaItem(
            id: item.id,
            title: item.title,
            artist: item.artist,
            album: item.albumTitle,
            artUri: item.artUri,
            // The media-session seek bar (and with it the lock-screen
            // progress) only appears once the item carries a duration.
            duration: _lastDuration,
          ),
        );
      }
    }
    _publishPlayback(force: true);
  }

  void _publishPlayback({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastPublishAt) < _positionPublishInterval) {
      return;
    }
    _lastPublishAt = now;

    final snap = _latestSnapshot;
    final playing = snap?.playing ?? false;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          // Expanded-view only (compact view stays [0,1,2]); it is the way to
          // end the session, since the service stays in the foreground while
          // paused and the notification is therefore not swipe-dismissible on
          // older Android versions.
          MediaControl.stop,
        ],
        // Compact-view order of [controls]; being explicit keeps play/pause in
        // the middle slot on every OEM.
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {MediaAction.seek},
        processingState: snap == null
            ? AudioProcessingState.idle
            : snap.processing
            ? AudioProcessingState.buffering
            : snap.completed
            ? AudioProcessingState.completed
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: _lastPosition,
        bufferedPosition: _lastPosition,
        queueIndex: snap?.currentIndex,
      ),
    );
  }

  AudioPlayerSnapshot? _latestSnapshot;
}
