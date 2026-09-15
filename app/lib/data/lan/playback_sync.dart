/// The playback-sync protocol: one device plays, the others follow it in step.
///
/// Everything in this file is pure — no sockets, no player, no Flutter. The
/// transport (`lan_service.dart`) only carries these maps, and the state
/// machine that actually drives the local player lives in
/// `state/playback_sync_controller.dart`. Keeping the arithmetic here is what
/// makes "does it stay in sync" a unit test instead of an experiment on two
/// phones.
library;

/// What the host is playing, and what its clock said when it was taken.
///
/// The host sends this whenever anything changes (play/pause, seek, track) and
/// on every connect, several times a second while the position moves. Followers
/// extrapolate from it rather than waiting for the next message: that is the
/// whole trick, because a message is only ever a sample of a continuous
/// position.
///
/// It deliberately carries **no audio URLs**. The follower resolves the album
/// through its own API layer, exactly as if the user had tapped it: that keeps
/// its queue, its prefetching, its album page and its cache working, and it
/// means the two devices can even be on different formats.
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.atMillis,
    required this.playing,
    required this.position,
    required this.albumId,
    required this.index,
    this.albumTitle = '',
    this.trackTitle = '',
    this.artist,
  });

  /// The host's wall clock (ms since the epoch) when this was taken.
  final int atMillis;

  final bool playing;
  final Duration position;

  /// Which album, which track. Null-ish (empty album id) means "nothing is
  /// playing", which is a state a follower has to handle: it means stop.
  final String albumId;
  final int index;

  /// Carried for the follower's status line only ("following *album*").
  final String albumTitle;
  final String trackTitle;
  final String? artist;

  bool get isEmpty => albumId.isEmpty;

  /// Whether both snapshots point at the same track — the follower reloads its
  /// queue only when this changes, not on every position sample.
  bool sameTrack(PlaybackSnapshot? other) =>
      other != null &&
      !isEmpty &&
      other.albumId == albumId &&
      other.index == index;

  Map<String, Object?> toJson() => {
    'at': atMillis,
    'play': playing ? 1 : 0,
    'p': position.inMilliseconds,
    'album': albumId,
    'i': index,
    if (albumTitle.isNotEmpty) 'albumTitle': albumTitle,
    if (trackTitle.isNotEmpty) 'title': trackTitle,
    if (artist != null && artist!.isNotEmpty) 'artist': artist,
  };

  /// Null when the payload is not something this version understands — a peer
  /// running a different build must never crash the follower.
  static PlaybackSnapshot? tryFromJson(Map<String, Object?> json) {
    final at = json['at'];
    final position = json['p'];
    if (at is! int || position is! int) return null;
    return PlaybackSnapshot(
      atMillis: at,
      playing: json['play'] == 1,
      position: Duration(milliseconds: position),
      albumId: json['album'] is String ? json['album']! as String : '',
      index: json['i'] is int ? json['i']! as int : 0,
      albumTitle: json['albumTitle'] is String
          ? json['albumTitle']! as String
          : '',
      trackTitle: json['title'] is String ? json['title']! as String : '',
      artist: json['artist'] is String ? json['artist']! as String : null,
    );
  }
}

/// Estimates how far apart two clocks are, from ping/pong round trips.
///
/// The host answers with the time *it* saw, and the follower knows when it
/// asked and when the answer came back. Assuming the trip is symmetric — a
/// LAN makes that a good assumption, and the median below throws away the
/// samples where it was not — the difference between the two clocks is
/// `remote - (sent + received) / 2`.
class ClockSync {
  ClockSync({this.samples = 8});

  /// How many recent round trips to keep. Enough to survive a burst of jitter,
  /// few enough that a clock that legitimately drifts (or a device that went
  /// to sleep) is re-learned quickly.
  final int samples;

  final List<int> _offsets = [];
  final List<int> _trip = [];

  /// Feed one round trip. [sent] and [received] are this device's clock,
  /// [remote] is the host's clock at the moment it answered (all in ms).
  void addSample({
    required int sent,
    required int received,
    required int remote,
  }) {
    if (received < sent) return; // nonsense sample (clock went backwards)
    _offsets.add(remote - (sent + received) ~/ 2);
    _trip.add(received - sent);
    _lastSampleAt = received;
    if (_offsets.length > samples) {
      _offsets.removeAt(0);
      _trip.removeAt(0);
    }
  }

  /// Enough samples to trust: one round trip can be delayed by anything.
  bool get ready => _offsets.length >= 3;

  /// Median rather than mean: one sample caught behind a GC pause or a busy
  /// WiFi retry must not tilt the whole estimate.
  int get _medianOffset {
    final sorted = [..._offsets]..sort();
    return sorted[sorted.length ~/ 2];
  }

  int get _medianTrip {
    final sorted = [..._trip]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Local time the newest sample came back, used by [isFresh].
  int _lastSampleAt = 0;

  /// How long an estimate stays usable. Beyond this the follower goes back to
  /// "not yet aligned" rather than extrapolating from a clock that may have
  /// been suspended meanwhile (a phone that went to sleep still answers, but
  /// its clock and its audio have both drifted apart from the host's).
  static const Duration maxAge = Duration(seconds: 20);

  bool isFresh(int nowMillis) =>
      _offsets.isNotEmpty && nowMillis - _lastSampleAt <= maxAge.inMilliseconds;

  /// Host clock minus local clock, in milliseconds. Null until [ready].
  int? get offsetMillis => _offsets.length >= 3 ? _medianOffset : null;

  /// Half the median round trip — what a message takes one way, which is the
  /// part of the offset estimate that cannot be removed.
  Duration get oneWay => Duration(milliseconds: _medianTrip ~/ 2);

  /// Start over: used when the peer reconnects or the app resumes.
  void reset() {
    _offsets.clear();
    _trip.clear();
    _lastSampleAt = 0;
  }
}

/// What the follower should do right now to stay in step.
class SyncAdvice {
  const SyncAdvice({
    required this.target,
    required this.drift,
    this.seekTo,
    this.speed = 1.0,
    this.play,
  });

  /// Where this device should be, host's position minus this device's own
  /// delay (a speaker in the next room is told to run slightly late so the
  /// sound arrives together).
  final Duration target;

  /// Local position minus [target]: positive means this device is ahead.
  final Duration drift;

  /// Set when the drift is too big to remove by nudging the speed: the caller
  /// must seek. Null when a speed nudge (or nothing) is enough.
  final Duration? seekTo;

  /// Playback rate to apply. 1.0 in the common case.
  final double speed;

  /// Null when the local player already agrees with the host.
  final bool? play;

  bool get needsSeek => seekTo != null;
}

/// Drift small enough to ignore: below this the correction is more likely to
/// be the measurement's own noise than a real offset.
const Duration syncDeadZone = Duration(milliseconds: 30);

/// Drift beyond which leaning on the playback rate would take too long, so a
/// single seek is the lesser evil.
///
/// Deliberately generous. Seeking a track that is still being cached costs a
/// re-open and a fresh buffer — that is heard as a gap — so the rate correction
/// is given a wide band to work in (5% removes 250ms in five seconds).
const Duration syncSeekThreshold = Duration(milliseconds: 250);

/// A seek needs a moment before the position it reports means anything. Acting
/// on the in-flight value turns one correction into a burst of them.
const Duration syncSettleAfterSeek = Duration(milliseconds: 800);

/// The least time between two seeks. Even a real drift is not worth a gap every
/// half second, and the rate correction keeps working meanwhile.
const Duration syncSeekCooldown = Duration(milliseconds: 5000);

/// How much of the drift to remove per second while nudging. 1/s means the
/// whole difference is gone in a second; the cap below keeps the rate change
/// inaudible.
const double syncNudgePerSecond = 0.5;

/// The most the playback rate is ever moved by. 5% is at the edge of what a
/// listener notices on a sustained note, and the nudge only lasts until the
/// drift is gone.
const double syncMaxRateDelta = 0.05;

/// Where the local player actually is, given a sample that was taken
/// [sampledAtMillis] and only arrives every so often (just_audio ticks about
/// five times a second).
///
/// This matters more than it looks. Comparing a sample that is up to 200ms old
/// against a target that is extrapolated to *now* invents a drift of exactly
/// that much, so the correction chases a difference that does not exist — with
/// a seek, every half second, which is heard as stuttering.
Duration livePosition({
  required Duration sampled,
  required int sampledAtMillis,
  required int nowMillis,
  required bool playing,
}) {
  if (!playing) return sampled;
  final elapsed = nowMillis - sampledAtMillis;
  // A sample from the future, or a clock that went backwards, is not something
  // to extrapolate from.
  if (elapsed <= 0) return sampled;
  return sampled + Duration(milliseconds: elapsed);
}

/// Where this device should be at local time [nowMillis].
Duration syncTarget({
  required PlaybackSnapshot snapshot,
  required int nowMillis,
  required int offsetMillis,
  Duration delay = Duration.zero,
}) {
  if (!snapshot.playing) return snapshot.position - delay;
  // The host's clock now, and how long ago the snapshot was taken.
  final hostNow = nowMillis + offsetMillis;
  final elapsed = hostNow - snapshot.atMillis;
  return snapshot.position + Duration(milliseconds: elapsed) - delay;
}

/// Turns a measurement into an action.
SyncAdvice adviseSync({
  required PlaybackSnapshot snapshot,
  required int nowMillis,
  required int offsetMillis,
  required Duration localPosition,
  int? localSampledAtMillis,
  required bool localPlaying,
  Duration delay = Duration.zero,
}) {
  // Extrapolated to now, not read as-is: see [livePosition].
  final local = livePosition(
    sampled: localPosition,
    sampledAtMillis: localSampledAtMillis ?? nowMillis,
    nowMillis: nowMillis,
    playing: localPlaying,
  );
  final target = syncTarget(
    snapshot: snapshot,
    nowMillis: nowMillis,
    offsetMillis: offsetMillis,
    delay: delay,
  );

  // Paused (or never started): the only thing that matters is agreeing on the
  // position, so the next play starts together.
  if (!snapshot.playing) {
    final behind = target - local;
    return SyncAdvice(
      target: target,
      drift: local - target,
      seekTo: behind.abs() > syncSeekThreshold ? target : null,
      play: localPlaying ? false : null,
    );
  }

  final drift = local - target;
  final magnitude = drift.abs();

  // Big drift: one seek. Small drift: lean on the playback rate, which is
  // continuous and therefore silent, instead of seeking, which clicks.
  if (magnitude > syncSeekThreshold) {
    return SyncAdvice(
      target: target,
      drift: drift,
      seekTo: target,
      play: localPlaying ? null : true,
    );
  }
  if (magnitude > syncDeadZone) {
    // Ahead (positive drift) must slow down: 1 - drift/second.
    final seconds = drift.inMicroseconds / 1e6;
    final delta = (-seconds * syncNudgePerSecond).clamp(
      -syncMaxRateDelta,
      syncMaxRateDelta,
    );
    return SyncAdvice(
      target: target,
      drift: drift,
      speed: 1.0 + delta,
      play: localPlaying ? null : true,
    );
  }
  return SyncAdvice(
    target: target,
    drift: drift,
    play: localPlaying ? null : true,
  );
}

/// The message kinds on the wire. Kept as constants so both ends and the
/// tests agree on the spelling.
abstract final class SyncMessage {
  static const state = 'state';
  static const ping = 'ping';
  static const pong = 'pong';
  static const command = 'cmd';

  /// Commands a follower may ask the host to run. "What plays" belongs to the
  /// host, so a follower never acts on these itself while it follows.
  static const play = 'play';
  static const pause = 'pause';
  static const toggle = 'toggle';
  static const next = 'next';
  static const previous = 'previous';
  static const seek = 'seek';
  static const stop = 'stop';
}
