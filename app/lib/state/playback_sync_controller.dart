import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/base_audio_player.dart';
import 'lan_controller.dart';
import '../data/lan/lan_device.dart';
import '../data/lan/lan_service.dart';
import '../data/lan/playback_sync.dart';
import '../l10n/l10n.dart';
import 'album_controller.dart';
import 'player_controller.dart';

/// Whether this device is the one deciding what plays, the one following
/// another device, or neither.
enum SyncRole { off, host, follower }

class PlaybackSyncState {
  const PlaybackSyncState({
    this.hosting = false,
    this.following,
    this.delay = Duration.zero,
    this.drift = Duration.zero,
    this.aligned = false,
    this.followers = 0,
    this.status,
    this.error,
  });

  /// This device offers its playback for others to follow.
  final bool hosting;

  /// The device being followed, when this one is a follower.
  final LanDevice? following;

  /// This device's own delay: it runs this much *behind* the host, which is how
  /// a speaker in the next room is made to sound at the same time as the one
  /// next to you. Adjustable while following.
  final Duration delay;

  /// Last measured difference (local minus target). Shown to the user, and the
  /// reason the status line is trustworthy rather than decorative.
  final Duration drift;

  /// The clocks are in agreement, so the position above means something.
  final bool aligned;

  /// Host only: how many devices are following right now.
  final int followers;

  final String? status;
  final String? error;

  SyncRole get role => hosting
      ? SyncRole.host
      : (following != null ? SyncRole.follower : SyncRole.off);

  PlaybackSyncState copyWith({
    bool? hosting,
    Object? following = _unset,
    Duration? delay,
    Duration? drift,
    bool? aligned,
    int? followers,
    Object? status = _unset,
    Object? error = _unset,
  }) => PlaybackSyncState(
    hosting: hosting ?? this.hosting,
    following: identical(following, _unset)
        ? this.following
        : following as LanDevice?,
    delay: delay ?? this.delay,
    drift: drift ?? this.drift,
    aligned: aligned ?? this.aligned,
    followers: followers ?? this.followers,
    status: identical(status, _unset) ? this.status : status as String?,
    error: identical(error, _unset) ? this.error : error as String?,
  );

  static const _unset = Object();
}

/// Group playback: this device either hands its playback to the others, or
/// follows one of them.
///
/// The host owns "what plays". A follower never decides anything: its player is
/// driven from the host's snapshots, and its own transport buttons are
/// forwarded (see [PlayerController]) so that pressing pause on the phone
/// pauses the whole group instead of fighting it.
///
/// Staying in step is done two ways, deliberately. A large difference is
/// corrected with a seek, because it will not disappear on its own. A small one
/// is removed by leaning on the playback rate (a fraction of a percent), which
/// is inaudible — seeking every second would click, and that is exactly what
/// "unstable sync" sounds like.
class PlaybackSyncController extends Notifier<PlaybackSyncState> {
  WebSocket? _socket;
  Timer? _ticker;
  Timer? _pinger;
  ProviderSubscription<PlayerState>? _hostSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<AudioPlayerSnapshot>? _snapshotSub;

  final ClockSync _clock = ClockSync();
  PlaybackSnapshot? _remote;
  PlaybackSnapshot? _applied;
  int _lastPingSent = 0;
  Duration _localPosition = Duration.zero;
  bool _localPlaying = false;

  /// True while the follower is applying the host's state to its own player:
  /// those writes must go to the player, never back out as commands.
  bool applyingRemote = false;

  /// Wall clock before which a failed track load is not retried, so an album
  /// that cannot be opened does not turn into a request per position sample.
  int _nextLoadAttempt = 0;

  @override
  PlaybackSyncState build() {
    ref.onDispose(_teardown);
    // Installed up front, not when hosting starts: another device may ask this
    // one to follow at any time, and the service may come up later (the LAN
    // feature has its own switch), so both are covered.
    _installFollowHandler();
    ref.listen(lanControllerProvider, (_, _) => _installFollowHandler());
    return const PlaybackSyncState();
  }

  void _installFollowHandler() {
    _service?.onFollowRequest = _onFollowRequest;
  }

  void _onFollowRequest(LanDevice host) {
    // Being told to follow is the whole point of the request.
    unawaited(follow(host));
  }

  /// One tap on the host: ask every device in the list to follow this one. This
  /// is the remote-control path — the other devices do not have to be touched,
  /// which is the difference between "walk to the TV" and "use the phone".
  Future<void> inviteAll() async {
    final service = _service;
    final port = service?.httpPort;
    final devices = ref.read(lanControllerProvider).value?.devices ?? const [];
    final l = stringsFor(currentUiLocale);
    if (service == null || port == null || devices.isEmpty) {
      state = state.copyWith(status: l.syncInvitedNone);
      return;
    }
    var asked = 0;
    for (final device in devices) {
      try {
        await service.requestFollow(device, port: port);
        asked++;
      } catch (_) {
        // A device that does not answer is simply not invited; the rest still
        // are, and the count says how many took it.
      }
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      status: asked == 0 ? l.syncInvitedNone : l.syncInvited(asked),
    );
  }

  LanService? get _service => ref.read(lanControllerProvider.notifier).service;

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  bool get isFollowing => state.following != null;

  // ---------------------------------------------------------------- hosting

  /// Offers this device's playback to the network. Whoever turns it on first is
  /// the host; there is no pairing step.
  void startHosting() {
    final service = _service;
    if (service == null) {
      state = state.copyWith(
        error: stringsFor(currentUiLocale).lanServiceNotRunning,
      );
      return;
    }
    service
      ..hostingPlayback = true
      ..playbackSnapshot = _snapshot
      ..onPlaybackCommand = _runCommand;
    _hostSub?.close();
    // Every change of what is playing (including the position ticking) goes out
    // at once, so a play or a pause lands in milliseconds rather than at the
    // next poll. The payload is a few hundred bytes.
    _hostSub = ref.listen<PlayerState>(playerControllerProvider, (_, _) {
      ref.read(lanControllerProvider.notifier).service?.broadcastPlayback();
    });
    // Re-announce, so devices already in the list learn there is something to
    // follow without waiting for their next probe.
    unawaited(service.refresh());
    service.broadcastPlayback();
    state = state.copyWith(
      hosting: true,
      following: null,
      error: null,
      status: null,
      followers: service.followerCount,
    );
  }

  void stopHosting() {
    _hostSub?.close();
    _hostSub = null;
    final service = _service;
    if (service != null) {
      service
        ..hostingPlayback = false
        ..playbackSnapshot = null
        ..onPlaybackCommand = null;
      // The followers' sockets are closed by the service: a follower that loses
      // the host stops following rather than freezing on a stale position.
      unawaited(service.refresh());
    }
    state = const PlaybackSyncState();
  }

  /// Host side: what a follower should be doing right now.
  PlaybackSnapshot _snapshot() {
    final player = ref.read(playerControllerProvider);
    final current = player.current;
    if (current == null) {
      // Nothing loaded: followers are told to stop rather than being left on
      // the last thing they heard.
      return PlaybackSnapshot(
        atMillis: _now,
        playing: false,
        position: Duration.zero,
        albumId: '',
        index: 0,
      );
    }
    return PlaybackSnapshot(
      atMillis: _now,
      playing: player.playing,
      position: player.position,
      albumId: current.album.summary.id,
      index: player.currentIndex ?? 0,
      albumTitle: current.album.summary.title,
      trackTitle: current.track.name,
    );
  }

  /// Host side: a follower pressed something. Running it here (rather than
  /// applying it locally on the follower) is what keeps every device on the
  /// same track: the host's own state change is what everyone then receives.
  void _runCommand(String action, int? positionMillis) {
    final player = ref.read(playerControllerProvider.notifier);
    switch (action) {
      case SyncMessage.play:
        unawaited(player.play());
      case SyncMessage.pause:
        unawaited(player.pause());
      case SyncMessage.toggle:
        unawaited(player.togglePlayPause());
      case SyncMessage.next:
        unawaited(player.next());
      case SyncMessage.previous:
        unawaited(player.previous());
      case SyncMessage.seek:
        if (positionMillis != null) {
          unawaited(player.seek(Duration(milliseconds: positionMillis)));
        }
      case SyncMessage.stop:
        unawaited(player.stop());
    }
  }

  // --------------------------------------------------------------- following

  Future<void> follow(LanDevice peer) async {
    // A device cannot both lead and follow in this version, so following
    // cleanly ends any sharing of our own — including the endpoints on the
    // service, which a state reset alone would leave running.
    stopHosting();
    await stopFollowing(keepStatus: true);
    final service = _service;
    if (service == null) {
      state = state.copyWith(
        error: stringsFor(currentUiLocale).lanServiceNotRunning,
      );
      return;
    }
    final l = stringsFor(currentUiLocale);
    state = state.copyWith(
      hosting: false,
      following: peer,
      aligned: false,
      drift: Duration.zero,
      status: l.syncConnecting(peer.name),
      error: null,
    );
    try {
      final socket = await service.connectPlayback(peer);
      if (state.following?.id != peer.id) {
        // The user moved on while we were connecting.
        await socket.close();
        return;
      }
      _socket = socket;
      _clock.reset();
      _applied = null;
      _remote = null;
      // The follower's own transport is not its own any more: park whatever it
      // was playing until the host says what to do.
      final local = ref.read(audioPlayerProvider);
      await local.pause();
      _listenToLocalPlayer();
      socket.listen(
        _onMessage,
        onDone: () => _hostGone(),
        onError: (Object _) => _hostGone(),
        cancelOnError: true,
      );
      _pinger = Timer.periodic(const Duration(seconds: 2), (_) => _ping());
      _ping();
      _ticker = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => unawaited(_tick()),
      );
    } catch (e) {
      state = state.copyWith(
        following: null,
        status: null,
        error: e is LanException ? e.message : '$e',
      );
    }
  }

  Future<void> stopFollowing({bool keepStatus = false}) async {
    _ticker?.cancel();
    _ticker = null;
    _pinger?.cancel();
    _pinger = null;
    _positionSub?.cancel();
    _positionSub = null;
    _snapshotSub?.cancel();
    _snapshotSub = null;
    final socket = _socket;
    _socket = null;
    _clock.reset();
    _remote = null;
    _applied = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
    }
    state = PlaybackSyncState(delay: state.delay);
    if (keepStatus) return;
  }

  /// This device's own audio is what the sync is measured against, so it is
  /// read from the player's streams rather than from the throttled UI state:
  /// a quarter-second-old position would swamp the correction.
  void _listenToLocalPlayer() {
    final player = ref.read(audioPlayerProvider);
    _localPosition = ref.read(playerControllerProvider).position;
    _localPlaying = ref.read(playerControllerProvider).playing;
    _positionSub = player.positionStream.listen((pos) => _localPosition = pos);
    _snapshotSub = player.snapshotStream.listen((s) {
      _localPlaying = s.playing;
    });
  }

  void _ping() {
    final socket = _socket;
    if (socket == null) return;
    _lastPingSent = _now;
    try {
      socket.add(jsonEncode({'t': SyncMessage.ping, 'c': _lastPingSent}));
    } catch (_) {
      _hostGone();
    }
  }

  void _onMessage(Object? data) {
    if (data is! String) return;
    Map<String, Object?>? message;
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) message = JsonMap.from(decoded);
    } catch (_) {
      return;
    }
    if (message == null) return;
    switch (message['t']) {
      case SyncMessage.pong:
        final remote = message['s'];
        if (remote is! int) return;
        _clock.addSample(
          sent: message['c'] is int ? message['c']! as int : _lastPingSent,
          received: _now,
          remote: remote,
        );
        final offset = _clock.offsetMillis;
        state = state.copyWith(
          aligned: offset != null,
          status: offset == null ? null : _statusLine(),
        );
      case SyncMessage.state:
        final snapshot = PlaybackSnapshot.tryFromJson(message);
        if (snapshot == null) return;
        _remote = snapshot;
        unawaited(_applyTrack());
        unawaited(_tick());
    }
  }

  String _statusLine() {
    final name = state.following?.name ?? '';
    final l = stringsFor(currentUiLocale);
    final drift = state.drift.inMilliseconds;
    final tuned = state.delay == Duration.zero
        ? ''
        : l.syncDelaySuffix(_signed(state.delay.inMilliseconds));
    return l.syncFollowing(name, _signed(drift), tuned);
  }

  /// `+20` / `-8` / `0`: the sign is the whole point of the number, so it is
  /// never left to the reader to guess.
  static String _signed(int ms) => ms > 0 ? '+$ms' : '$ms';

  /// The host changed track (or album): load it here the ordinary way, through
  /// this device's own API layer, so the queue, the album page, the prefetching
  /// and the cache all behave as if the user had tapped it.
  Future<void> _applyTrack() async {
    final remote = _remote;
    if (remote == null || remote.sameTrack(_applied)) return;
    if (_now < _nextLoadAttempt) return;
    applyingRemote = true;
    try {
      final local = ref.read(audioPlayerProvider);
      if (remote.isEmpty) {
        _applied = remote;
        await local.pause();
        return;
      }
      final album = await ref.read(
        albumDetailProvider((remote.albumId, 0)).future,
      );
      if (!ref.mounted) return;
      await ref
          .read(playerControllerProvider.notifier)
          .playAlbum(album, startIndex: remote.index);
      if (!ref.mounted) return;
      final failure = ref.read(playerControllerProvider).error;
      if (failure != null) {
        // The album was found but nothing could be played from it. Say so: a
        // follower that sits in silence with no explanation is the worst
        // possible outcome.
        _applied = null;
        _nextLoadAttempt = _now + 3000;
        state = state.copyWith(
          error: stringsFor(currentUiLocale).syncFailed(failure),
        );
        return;
      }
      // Straight to where the host is, instead of starting at zero and drifting
      // in over the next few seconds.
      final target = _target();
      if (target != null) await local.seek(target);
      // Marked as loaded only now: setting this first (as it did before) meant a
      // failed load was never retried for that track, so the follower stayed
      // silent for the whole song it could not open.
      _applied = remote;
      state = state.copyWith(error: null);
    } catch (e) {
      _applied = null;
      _nextLoadAttempt = _now + 3000;
      if (ref.mounted) {
        state = state.copyWith(
          error: stringsFor(currentUiLocale).syncFailed('$e'),
        );
      }
    } finally {
      applyingRemote = false;
    }
  }

  Duration? _target() {
    final remote = _remote;
    final offset = _clock.offsetMillis;
    if (remote == null || offset == null) return null;
    return syncTarget(
      snapshot: remote,
      nowMillis: _now,
      offsetMillis: offset,
      delay: state.delay,
    );
  }

  /// The correction loop: measured, small, and mostly silent.
  Future<void> _tick() async {
    final remote = _remote;
    final offset = _clock.offsetMillis;
    if (remote == null || offset == null) return;
    try {
      await _apply(remote, offset);
    } catch (e) {
      // A correction that throws (no source loaded, player in a bad state) must
      // not disappear into an unawaited future: it is exactly the kind of
      // failure the user needs to see rather than a silent follower.
      if (ref.mounted) {
        state = state.copyWith(
          error: stringsFor(currentUiLocale).syncFailed('$e'),
        );
      }
    }
  }

  Future<void> _apply(PlaybackSnapshot remote, int offset) async {
    final local = ref.read(audioPlayerProvider);
    final advice = adviseSync(
      snapshot: remote,
      nowMillis: _now,
      offsetMillis: offset,
      localPosition: _localPosition,
      localPlaying: _localPlaying,
      delay: state.delay,
    );
    // Order matters: land in the right place, then agree on whether it plays.
    if (advice.needsSeek) await local.seek(advice.seekTo!);
    await local.setSpeed(advice.speed);
    if (advice.play == true) {
      await local.play();
    } else if (advice.play == false) {
      await local.pause();
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      drift: advice.drift,
      aligned: true,
      status: _statusLine(),
    );
  }

  /// The host stopped (sync turned off, app closed, network gone). A follower
  /// must not keep playing a stale position as if nothing happened.
  void _hostGone() {
    if (!isFollowing) return;
    unawaited(stopFollowing());
    state = state.copyWith(status: stringsFor(currentUiLocale).syncHostStopped);
  }

  // ------------------------------------------------------------------ knobs

  /// Nudge this device's delay. Positive means "play this much later", which is
  /// what a room further away needs.
  void nudgeDelay(Duration by) {
    final next = state.delay + by;
    final clamped = Duration(
      milliseconds: next.inMilliseconds.clamp(-500, 500),
    );
    state = state.copyWith(delay: clamped, status: _statusLine());
  }

  /// A follower's transport press is the group's press. The host performs it
  /// and its new state comes back to everyone, so nothing is applied locally.
  Future<void> forwardCommand(String action, {Duration? position}) async {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.add(
        jsonEncode({
          't': SyncMessage.command,
          'a': action,
          if (position != null) 'p': position.inMilliseconds,
        }),
      );
    } catch (_) {
      _hostGone();
    }
  }

  /// Dismisses the error line once the user has read it.
  void clearError() => state = state.copyWith(error: null);

  void _teardown() {
    _hostSub?.close();
    _hostSub = null;
    _ticker?.cancel();
    _pinger?.cancel();
    _positionSub?.cancel();
    _snapshotSub?.cancel();
    _socket?.close();
    _socket = null;
  }
}

final playbackSyncControllerProvider =
    NotifierProvider<PlaybackSyncController, PlaybackSyncState>(
      PlaybackSyncController.new,
    );
