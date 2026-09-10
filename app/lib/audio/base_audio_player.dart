import 'dart:async';

/// A single playable queue entry handed to a [BaseAudioPlayer] impl.
///
/// Kept UI-agnostic: no Flutter types here, so the whole audio layer can be
/// re-targeted (e.g. a future Nintendo Switch embedded build).
class PlayableItem {
  const PlayableItem({
    required this.id,
    required this.title,
    required this.url,
    this.artist,
    this.albumTitle,
    this.artUri,
  });

  /// Stable identity, e.g. `<albumId>/<trackIndex>`.
  final String id;

  final String title;

  /// Direct media URL (resolved via phase 2 of the API layer).
  final String url;

  final String? artist;
  final String? albumTitle;
  final Uri? artUri;
}

/// Abstract audio playback interface.
///
/// **Switch-port reserved channel**: the Flutter app only ever talks to this
/// interface. Today it is implemented by [JustAudioPlayerImpl] (ExoPlayer on
/// Android). If the app is later ported to an embedded Flutter engine, only
/// this implementation needs to be swapped — UI, state and data layers stay
/// untouched.
abstract class BaseAudioPlayer {
  /// Full player state (processing/ready, playing flag, current index).
  Stream<AudioPlayerSnapshot> get snapshotStream;

  /// Current item playback position (throttled by the impl).
  Stream<Duration> get positionStream;

  /// Duration of the currently loaded item (null while unknown/buffering).
  Stream<Duration?> get durationStream;

  /// Replace the whole queue and start playing at [startIndex].
  Future<void> loadQueue(List<PlayableItem> items, {int startIndex});

  /// Append one item to the end of the queue (lazy phase-2 resolution flow).
  Future<void> append(List<PlayableItem> items);

  /// Swap the media URL of the currently playing item without losing queue
  /// position or playback position (used by the audio-quality switcher).
  Future<void> swapCurrentSource(String url);

  /// Stop playback and drop the whole queue (used by cancel-loading).
  Future<void> stop();

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> skipToIndex(int index);
  Future<void> next();
  Future<void> previous();

  /// Queue length currently known to the player.
  int get queueLength;

  Future<void> dispose();
}

/// Immutable snapshot of player state, broadcast to the UI.
class AudioPlayerSnapshot {
  const AudioPlayerSnapshot({
    required this.playing,
    required this.currentIndex,
    this.processing = false,
    this.completed = false,
    this.error,
  });

  final bool playing;

  /// Index into the loaded queue, or null when nothing is loaded.
  final int? currentIndex;

  /// True while buffering / loading a source.
  final bool processing;
  final bool completed;
  final String? error;
}
