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
    this.albumId = '',
    this.trackIndex,
  });

  /// Stable identity, e.g. `<albumId>/<trackIndex>`.
  final String id;

  final String title;

  /// Direct media URL (resolved via phase 2 of the API layer).
  final String url;

  final String? artist;
  final String? albumTitle;

  /// Album id and 1-based track number. Together with [albumTitle] they
  /// decide **where** the track is cached on disk, and let the UI report the
  /// cache state of a track before its media URL has even been resolved.
  final String albumId;
  final int? trackIndex;

  final Uri? artUri;
}

/// Handles the commands that arrive from the *system* media controls
/// (Android notification / lock screen, macOS Now Playing, headset buttons)
/// at the app level.
///
/// The state layer installs one via [MediaSession.setSystemCommandHandler].
/// Without it, system "next" can only advance within the already-loaded queue
/// — and this app deliberately queues just the current track plus one
/// prefetched successor, so a system "next" that arrives before the prefetch
/// finished used to be a silent no-op. Routing the command through the
/// controller runs exactly the same logic as an in-app press, including
/// resolving the successor on demand.
abstract class SystemMediaCommandHandler {
  Future<void> play();
  Future<void> pause();
  Future<void> next();
  Future<void> previous();

  /// End the session (notification "stop"/dismiss). Must clear the app's own
  /// queue state too, not just the player's.
  Future<void> stop();
}

/// The system media session: the Android notification / lock screen, macOS Now
/// Playing, headset and media keys.
///
/// Deliberately **not** a [BaseAudioPlayer]. Its `play`/`pause`/`stop` are the
/// *system's* entry points and forward into the installed
/// [SystemMediaCommandHandler], which is the app's own [PlayerController]. If
/// the controller drove playback through this same object, then
/// `controller.pause()` → `session.pause()` → `controller.pause()` → … would
/// recurse until the app hung — which is exactly what the production wiring
/// used to do. Playback is therefore driven through [BaseAudioPlayer]; the
/// session is only there to publish state and to receive system commands.
abstract class MediaSession {
  /// Installs the app-level handler for system transport commands.
  ///
  /// Call with `null` on teardown.
  void setSystemCommandHandler(SystemMediaCommandHandler? handler);

  /// Drops the media item and ends the foreground service, so the notification
  /// / lock-screen controls disappear with the playback they belong to.
  Future<void> endSession();
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

  /// Items currently loaded in the queue, index-aligned with the player's own
  /// sequence. The media session mirrors these as its `MediaItem`s.
  List<PlayableItem> get items;

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

  /// Nudge the playback rate, used to stay in step with a host device (see
  /// `data/lan/playback_sync.dart`). Defaulted to a no-op so a test double that
  /// only cares about the transport does not have to implement it; the real
  /// implementation does.
  Future<void> setSpeed(double speed) async {}
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
