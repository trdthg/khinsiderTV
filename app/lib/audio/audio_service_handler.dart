import 'dart:async';
import 'package:audio_service/audio_service.dart';

import 'base_audio_player.dart';

/// The app's [MediaSession] (audio_service): publishes what the player is doing
/// to the system (macOS Now Playing & media keys, the Android notification and
/// lock-screen controls) and forwards system transport commands back into the
/// app.
///
/// **This is a bridge, not a player.** It reads the streams of the
/// [BaseAudioPlayer] it was built with and drives nothing itself: system
/// commands (`play` / `pause` / `skipToNext` / `skipToPrevious` / `stop`) go to
/// the [SystemMediaCommandHandler] installed by the state layer, so pressing
/// "next" on the lock screen behaves exactly like pressing it in the app —
/// including resolving the successor when it is not queued yet.
///
/// Keeping the two roles apart matters: if the state layer drove playback
/// through this object instead of through the player, `pause()` would land
/// here, forward to the controller, and the controller would call `pause()`
/// again — forever.
class KhinsiderAudioHandler extends BaseAudioHandler implements MediaSession {
  KhinsiderAudioHandler({required this.player}) {
    _subs
      ..add(
        player.snapshotStream.listen((snap) {
          _latestSnapshot = snap;
          _onSnapshot(snap);
        }),
      )
      ..add(
        // The media-session seek bar only appears once the current item
        // carries a duration, and the duration arrives after the item itself.
        player.durationStream.listen((d) {
          _lastDuration = d;
          _onSnapshot(_latestSnapshot);
        }),
      )
      ..add(
        player.positionStream.listen((p) {
          // A seek (the phone scrubber, the OSD bar, or the system's own) moves
          // the position in one jump. The throttle below exists to keep 60 Hz
          // ticks off the platform channel, but it would also leave the
          // system's progress bar a second behind the finger — so a jump
          // publishes immediately.
          final jumped = (p - _lastPosition).abs() > const Duration(seconds: 2);
          _lastPosition = p;
          _publishPlayback(force: jumped);
        }),
      );
  }

  /// The player this session mirrors and seeks. Owned by the app (the very
  /// same instance is what `audioPlayerProvider` serves) — never disposed here.
  final BaseAudioPlayer player;

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

  // ---------------------------------------------------------- media controls

  /// Notification action icons come from **this app's** resources, not from
  /// audio_service's bundled ones.
  ///
  /// Android resolves a control's `androidIcon` by *name* at runtime
  /// (`AudioService.getResourceId` -> `Resources.getIdentifier`), which no
  /// static analysis can see. The resource optimizer therefore treats
  /// audio_service's own drawables as unused and strips them from release APKs
  /// — verified on the shipped APK: `resources.arsc` contains the app's own
  /// resource names but none of the `audio_service_*` ones. `getResourceId`
  /// then returns 0, the notification action is built with a null icon, and
  /// SystemUI drops it (`MediaDataManager.createActionsFromNotification`:
  /// `if (action.getIcon() == null) ... continue`) — leaving a media card with
  /// album art, title and a progress bar but no transport buttons at all.
  ///
  /// Keeping the five icons in the app module (with an R-reference from
  /// MainActivity plus res/raw/keep.xml) makes them survive every build.
  static const String _iconPlay = 'drawable/khinsider_play';
  static const String _iconPause = 'drawable/khinsider_pause';
  static const String _iconSkipPrevious = 'drawable/khinsider_skip_previous';
  static const String _iconSkipNext = 'drawable/khinsider_skip_next';
  static const String _iconStop = 'drawable/khinsider_stop';

  static const MediaControl _controlPlay = MediaControl(
    androidIcon: _iconPlay,
    label: 'Play',
    action: MediaAction.play,
  );
  static const MediaControl _controlPause = MediaControl(
    androidIcon: _iconPause,
    label: 'Pause',
    action: MediaAction.pause,
  );
  static const MediaControl _controlSkipToPrevious = MediaControl(
    androidIcon: _iconSkipPrevious,
    label: 'Previous',
    action: MediaAction.skipToPrevious,
  );
  static const MediaControl _controlSkipToNext = MediaControl(
    androidIcon: _iconSkipNext,
    label: 'Next',
    action: MediaAction.skipToNext,
  );
  static const MediaControl _controlStop = MediaControl(
    androidIcon: _iconStop,
    label: 'Stop',
    action: MediaAction.stop,
  );

  @override
  void setSystemCommandHandler(SystemMediaCommandHandler? handler) {
    _commands = handler;
  }

  /// The handler system transport commands are currently routed to — the app's
  /// [PlayerController] — or null when none is installed.
  SystemMediaCommandHandler? get systemCommandHandler => _commands;

  /// Ends the session: no media item, no foreground service, no notification.
  @override
  Future<void> endSession() async {
    _lastDuration = null;
    mediaItem.add(null); // nothing is playing any more
    await super.stop();
  }

  /// Releases this bridge's subscriptions. The player it mirrors belongs to the
  /// app (the same instance is handed to `audioPlayerProvider`), so it is *not*
  /// disposed here.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }

  // -- audio_service interface: the *system's* entry points ------------------

  @override
  Future<void> play() => _commands?.play() ?? player.play();

  @override
  Future<void> pause() => _commands?.pause() ?? player.pause();

  @override
  Future<void> skipToNext() => _commands?.next() ?? player.next();

  @override
  Future<void> skipToPrevious() => _commands?.previous() ?? player.previous();

  @override
  Future<void> stop() async {
    final commands = _commands;
    if (commands != null) {
      // Routed through the controller so the app's own queue state is cleared
      // as well; that path ends the session itself (see [endSession]), which
      // is the affordance for `androidNotificationOngoing: true`'s missing
      // cancel button.
      await commands.stop();
      return;
    }
    await player.stop();
    await endSession();
  }

  @override
  Future<void> seek(Duration position) async {
    // Publish the target before the player reports back: `_lastPosition` is
    // what `updatePosition` carries, and the system's scrub bar must not snap
    // back to the old position while the player catches up with the request.
    _lastPosition = position;
    _publishPlayback(force: true);
    await player.seek(position);
  }

  // -- state sync ------------------------------------------------------------

  void _onSnapshot(AudioPlayerSnapshot? snap) {
    final i = snap?.currentIndex;
    final items = player.items;
    if (i != null && i >= 0 && i < items.length) {
      final item = items[i];
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
          _controlSkipToPrevious,
          playing ? _controlPause : _controlPlay,
          _controlSkipToNext,
          // Expanded-view only (compact view stays [0,1,2]); it is the way to
          // end the session, since the service stays in the foreground while
          // paused and the notification is therefore not swipe-dismissible on
          // older Android versions.
          _controlStop,
        ],
        // Compact-view order of [controls]; being explicit keeps play/pause in
        // the middle slot on every OEM.
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {MediaAction.seek},
        processingState: snap == null
            ? AudioProcessingState.idle
            : snap.completed
            ? AudioProcessingState.completed
            // Never report `buffering` while the track is playing. Android picks
            // the play/pause icon from `state == STATE_PLAYING` alone
            // (SystemUI's `MediaControlPanel.isPlaying`), so a buffering state
            // shows a *play* triangle even though the audio is running — i.e.
            // the notification has no pause button exactly when the user wants
            // one (a re-buffer mid-track, or the moment a track starts). The
            // wait is only worth reporting while nothing is playing.
            : snap.processing && !playing
            ? AudioProcessingState.buffering
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
