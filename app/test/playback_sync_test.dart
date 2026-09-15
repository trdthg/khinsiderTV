import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/data/lan/lan_device.dart';
import 'package:khinsider/data/lan/lan_service.dart';
import 'package:khinsider/data/lan/playback_sync.dart';

/// A host that always reports the same thing, for the transport tests below.
class _FakeHost {
  PlaybackSnapshot snapshot = PlaybackSnapshot(
    atMillis: 1000,
    playing: true,
    position: const Duration(seconds: 30),
    albumId: 'some-album',
    index: 2,
    albumTitle: 'Some Album',
    trackTitle: 'Track Three',
  );
  final List<String> commands = [];
  int? lastSeek;

  void install(LanService service) {
    service.hostingPlayback = true;
    service.playbackSnapshot = () => snapshot;
    service.onPlaybackCommand = (action, position) {
      commands.add(action);
      if (position != null) lastSeek = position;
    };
  }
}

LanService _service({
  required String id,
  required String name,
  int discoveryPort = 41270,
}) => LanService(
  deviceId: id,
  deviceName: name,
  appVersion: '0.3.6',
  discoveryPort: discoveryPort,
  readFavorites: () async => const [],
  mergeFavorites: (incoming) async => (added: 0, total: 0),
  replaceFavorites: (incoming) async => (added: 0, total: 0),
);

void main() {
  group('sync arithmetic', () {
    const offset = 5000; // the host's clock is 5s ahead
    final snapshot = PlaybackSnapshot(
      atMillis: 100000,
      playing: true,
      position: const Duration(seconds: 10),
      albumId: 'a',
      index: 0,
    );

    test('the target follows the host clock, not the local one', () {
      // Snapshot taken at host 100000 with position 10s; it is now local
      // 97000, i.e. host 102000: two seconds later.
      final target = syncTarget(
        snapshot: snapshot,
        nowMillis: 97000,
        offsetMillis: offset,
      );
      expect(target, const Duration(seconds: 12));

      // The same moment, 20ms further on.
      final later = syncTarget(
        snapshot: snapshot,
        nowMillis: 97020,
        offsetMillis: offset,
      );
      expect(later - target, const Duration(milliseconds: 20));
    });

    test('a delayed device aims that much earlier', () {
      final target = syncTarget(
        snapshot: snapshot,
        nowMillis: 97000,
        offsetMillis: offset,
        delay: const Duration(milliseconds: 80),
      );
      expect(target, const Duration(milliseconds: 11920));
    });

    test('a paused host has a fixed target', () {
      final paused = PlaybackSnapshot(
        atMillis: 100000,
        playing: false,
        position: const Duration(seconds: 42),
        albumId: 'a',
        index: 0,
      );
      expect(
        syncTarget(snapshot: paused, nowMillis: 999999, offsetMillis: offset),
        const Duration(seconds: 42),
      );
    });

    test('in step: no seek, no speed change', () {
      final advice = adviseSync(
        snapshot: snapshot,
        nowMillis: 97000,
        offsetMillis: offset,
        localPosition: const Duration(seconds: 12),
        localPlaying: true,
      );
      expect(advice.needsSeek, isFalse);
      expect(advice.speed, 1.0);
      expect(advice.play, isNull);
      expect(advice.drift.abs() < syncDeadZone, isTrue);
    });

    test('slightly ahead slows down, slightly behind speeds up', () {
      final ahead = adviseSync(
        snapshot: snapshot,
        nowMillis: 97000,
        offsetMillis: offset,
        localPosition: const Duration(milliseconds: 12050),
        localPlaying: true,
      );
      expect(ahead.needsSeek, isFalse);
      expect(ahead.speed, lessThan(1.0));
      expect(ahead.speed, greaterThan(1.0 - syncMaxRateDelta));

      final behind = adviseSync(
        snapshot: snapshot,
        nowMillis: 97000,
        offsetMillis: offset,
        localPosition: const Duration(milliseconds: 11950),
        localPlaying: true,
      );
      expect(behind.needsSeek, isFalse);
      expect(behind.speed, greaterThan(1.0));
      expect(behind.speed, lessThan(1.0 + syncMaxRateDelta));
    });

    test('a position sample that is a little old is not read as drift', () {
      // just_audio reports the position about five times a second, so a sample
      // read as "now" invents up to 200ms of drift. The correction then chases
      // a difference that does not exist — with a seek, every half second,
      // which is heard as stuttering.
      final extrapolated = adviseSync(
        snapshot: snapshot,
        nowMillis: 97000,
        offsetMillis: offset,
        localPosition: const Duration(milliseconds: 11800),
        localSampledAtMillis: 96800,
        localPlaying: true,
      );
      expect(extrapolated.drift.inMilliseconds, closeTo(0, 5));
      expect(extrapolated.needsSeek, isFalse);

      // The same sample taken at face value — what the follower used to do.
      final naive = adviseSync(
        snapshot: snapshot,
        nowMillis: 97000,
        offsetMillis: offset,
        localPosition: const Duration(milliseconds: 11800),
        localPlaying: true,
      );
      expect(naive.drift.inMilliseconds, lessThan(-100));
    });

    test('a paused player is not extrapolated forwards', () {
      expect(
        livePosition(
          sampled: const Duration(seconds: 5),
          sampledAtMillis: 1000,
          nowMillis: 9000,
          playing: false,
        ),
        const Duration(seconds: 5),
      );
      // And a sample from the future is not extrapolated backwards either.
      expect(
        livePosition(
          sampled: const Duration(seconds: 5),
          sampledAtMillis: 9000,
          nowMillis: 1000,
          playing: true,
        ),
        const Duration(seconds: 5),
      );
    });

    test('far out of step seeks instead of crawling back', () {
      final advice = adviseSync(
        snapshot: snapshot,
        nowMillis: 97000,
        offsetMillis: offset,
        localPosition: const Duration(seconds: 15),
        localPlaying: true,
      );
      expect(advice.needsSeek, isTrue);
      expect(advice.seekTo, const Duration(seconds: 12));
      // A seek fixes the position, so the rate goes back to normal.
      expect(advice.speed, 1.0);
    });

    test('paused because the host paused', () {
      final paused = PlaybackSnapshot(
        atMillis: 100000,
        playing: false,
        position: const Duration(seconds: 12),
        albumId: 'a',
        index: 0,
      );
      final advice = adviseSync(
        snapshot: paused,
        nowMillis: 97000,
        offsetMillis: offset,
        localPosition: const Duration(seconds: 12),
        localPlaying: true,
      );
      expect(advice.play, isFalse);
      expect(advice.needsSeek, isFalse);
    });

    test('starts playing when the host is playing and we are not', () {
      final advice = adviseSync(
        snapshot: snapshot,
        nowMillis: 97000,
        offsetMillis: offset,
        localPosition: const Duration(seconds: 12),
        localPlaying: false,
      );
      expect(advice.play, isTrue);
    });

    test('a paused follower that drifted seeks rather than starting wrong', () {
      final paused = PlaybackSnapshot(
        atMillis: 100000,
        playing: false,
        position: const Duration(seconds: 12),
        albumId: 'a',
        index: 0,
      );
      final advice = adviseSync(
        snapshot: paused,
        nowMillis: 97000,
        offsetMillis: offset,
        localPosition: const Duration(seconds: 30),
        localPlaying: false,
      );
      expect(advice.seekTo, const Duration(seconds: 12));
      expect(advice.play, isNull, reason: 'nothing to change: both paused');
    });
  });

  group('clock sync', () {
    test('is not trusted until there are a few samples', () {
      final clock = ClockSync();
      clock.addSample(sent: 1000, received: 1010, remote: 5010);
      clock.addSample(sent: 1020, received: 1030, remote: 5030);
      expect(clock.ready, isFalse);
      expect(clock.offsetMillis, isNull);
      clock.addSample(sent: 1040, received: 1050, remote: 5050);
      expect(clock.ready, isTrue);
    });

    test('recovers a symmetric offset exactly', () {
      final clock = ClockSync();
      // Host 5000ms ahead, 10ms each way.
      for (var i = 0; i < 4; i++) {
        final sent = 2000 + i * 100;
        clock.addSample(
          sent: sent,
          received: sent + 20,
          remote: sent + 10 + 5000,
        );
      }
      expect(clock.offsetMillis, 5000);
      expect(clock.oneWay, const Duration(milliseconds: 10));
    });

    test('one slow round trip does not move the estimate', () {
      final clock = ClockSync();
      for (var i = 0; i < 4; i++) {
        final sent = 2000 + i * 100;
        clock.addSample(
          sent: sent,
          received: sent + 20,
          remote: sent + 10 + 5000,
        );
      }
      // A sample caught behind a WiFi retry: 400ms round trip, so the naive
      // midpoint is off by 200ms. The median must ignore it.
      final sent = 3000;
      clock.addSample(
        sent: sent,
        received: sent + 400,
        remote: sent + 200 + 5000,
      );
      expect(clock.offsetMillis, 5000);
    });

    test('an estimate goes stale', () {
      final clock = ClockSync();
      for (var i = 0; i < 3; i++) {
        clock.addSample(sent: 1000, received: 1010, remote: 6010);
      }
      expect(clock.isFresh(1050), isTrue);
      expect(
        clock.isFresh(1010 + ClockSync.maxAge.inMilliseconds + 1),
        isFalse,
      );
      clock.reset();
      expect(clock.ready, isFalse);
    });

    test('a sample that went backwards is dropped', () {
      final clock = ClockSync();
      clock.addSample(sent: 2000, received: 1000, remote: 7000);
      expect(clock.ready, isFalse);
    });
  });

  group('snapshot payload', () {
    test('round trips', () {
      final snapshot = PlaybackSnapshot(
        atMillis: 123456,
        playing: true,
        position: const Duration(milliseconds: 4321),
        albumId: 'mario',
        index: 7,
        albumTitle: 'Mario',
        trackTitle: 'Theme',
      );
      final decoded = PlaybackSnapshot.tryFromJson(snapshot.toJson());
      expect(decoded, isNotNull);
      expect(decoded!.albumId, 'mario');
      expect(decoded.index, 7);
      expect(decoded.position, const Duration(milliseconds: 4321));
      expect(decoded.playing, isTrue);
      expect(decoded.sameTrack(snapshot), isTrue);
    });

    test('a track change is not the same track', () {
      PlaybackSnapshot make(int index) => PlaybackSnapshot(
        atMillis: 1,
        playing: true,
        position: Duration.zero,
        albumId: 'a',
        index: index,
      );
      expect(make(1).sameTrack(make(2)), isFalse);
      expect(make(1).sameTrack(make(1)), isTrue);
      // Nothing playing is never "the same track".
      const empty = PlaybackSnapshot(
        atMillis: 1,
        playing: false,
        position: Duration.zero,
        albumId: '',
        index: 0,
      );
      expect(empty.sameTrack(make(1)), isFalse);
      expect(empty.sameTrack(empty), isFalse);
    });

    test('junk is refused rather than guessed at', () {
      expect(PlaybackSnapshot.tryFromJson(const <String, Object?>{}), isNull);
      expect(PlaybackSnapshot.tryFromJson(const {'at': 'x', 'p': 1}), isNull);
      expect(PlaybackSnapshot.tryFromJson(const {'at': 1}), isNull);
      // Missing optional fields are fine.
      final partial = PlaybackSnapshot.tryFromJson(const {'at': 1, 'p': 2});
      expect(partial, isNotNull);
      expect(partial!.isEmpty, isTrue, reason: 'no album means nothing plays');
    });
  });

  group('over the wire', () {
    late LanService host;
    late LanService follower;
    late _FakeHost fake;

    setUp(() async {
      fake = _FakeHost();
      host = _service(id: 'host', name: 'Host');
      fake.install(host);
      // A different discovery port: the two services share one process, and
      // only the transport is under test here.
      follower = _service(id: 'fol', name: 'Follower', discoveryPort: 41271);
      await host.start();
      await follower.start();
    });

    tearDown(() async {
      await follower.stop();
      await host.stop();
    });

    LanDevice hostAsPeer() => LanDevice(
      id: 'host',
      name: 'Host',
      host: '127.0.0.1',
      port: host.httpPort!,
    );

    test('the beacon says when there is playback to follow', () {
      expect(host.beaconPayload('probe')['pb'], 1);
      expect(follower.beaconPayload('probe')['pb'], isNull);
      host.hostingPlayback = false;
      expect(host.beaconPayload('probe')['pb'], isNull);
    });

    test('a follower is sent the state as soon as it connects', () async {
      final socket = await follower.connectPlayback(hostAsPeer());
      addTearDown(socket.close);
      final first = await socket.first.timeout(const Duration(seconds: 5));
      final decoded = jsonDecode(first as String) as Map<String, dynamic>;
      expect(decoded['t'], SyncMessage.state);
      final snapshot = PlaybackSnapshot.tryFromJson(
        Map<String, Object?>.from(decoded),
      );
      expect(snapshot?.albumId, 'some-album');
      expect(snapshot?.index, 2);
      expect(snapshot?.playing, isTrue);
    });

    test('pings are answered with the host clock', () async {
      final socket = await follower.connectPlayback(hostAsPeer());
      addTearDown(socket.close);
      final pongs = StreamController<Map<String, Object?>>();
      socket.listen((data) {
        final decoded = jsonDecode(data as String);
        if (decoded is Map && decoded['t'] == SyncMessage.pong) {
          pongs.add(Map<String, Object?>.from(decoded));
        }
      });
      final sent = DateTime.now().millisecondsSinceEpoch;
      socket.add(jsonEncode({'t': SyncMessage.ping, 'c': sent}));
      final pong = await pongs.stream.first.timeout(const Duration(seconds: 5));
      expect(pong['c'], sent);
      expect(pong['s'], isA<int>());
      expect((pong['s']! as int) - sent, greaterThan(0));
    });

    test('a command reaches the host, and is the host that runs it', () async {
      final socket = await follower.connectPlayback(hostAsPeer());
      addTearDown(socket.close);
      socket.add(
        jsonEncode({'t': SyncMessage.command, 'a': SyncMessage.pause}),
      );
      socket.add(
        jsonEncode({
          't': SyncMessage.command,
          'a': SyncMessage.seek,
          'p': 42000,
        }),
      );
      // Wait for both to land rather than sleeping a fixed time.
      await _until(() => fake.commands.length >= 2);
      expect(
        fake.commands,
        containsAllInOrder([SyncMessage.pause, SyncMessage.seek]),
      );
      expect(fake.lastSeek, 42000);
    });

    test('the host pushes every change to its follower', () async {
      final socket = await follower.connectPlayback(hostAsPeer());
      addTearDown(socket.close);
      final states = <PlaybackSnapshot>[];
      socket.listen((data) {
        final decoded = jsonDecode(data as String);
        if (decoded is Map && decoded['t'] == SyncMessage.state) {
          final snapshot = PlaybackSnapshot.tryFromJson(
            Map<String, Object?>.from(decoded),
          );
          if (snapshot != null) states.add(snapshot);
        }
      });
      await _until(() => states.isNotEmpty);

      fake.snapshot = PlaybackSnapshot(
        atMillis: DateTime.now().millisecondsSinceEpoch,
        playing: true,
        position: const Duration(seconds: 5),
        albumId: 'some-album',
        index: 3,
      );
      host.broadcastPlayback();
      await _until(() => states.length >= 2);
      expect(states.last.index, 3);
      expect(host.followerCount, 1);
    });

    test('a hostile payload is dropped, not thrown', () async {
      final socket = await follower.connectPlayback(hostAsPeer());
      addTearDown(socket.close);
      socket.add('not json at all');
      socket.add(jsonEncode({'t': SyncMessage.command})); // no action
      socket.add(jsonEncode({'t': 'something-else'}));
      // The connection must still work afterwards.
      socket.add(jsonEncode({'t': SyncMessage.command, 'a': SyncMessage.play}));
      await _until(() => fake.commands.contains(SyncMessage.play));
      expect(host.followerCount, 1);
    });

    test(
      'a device can be asked to follow, and is told where to connect',
      () async {
        final asked = <LanDevice>[];
        host.onFollowRequest = asked.add;
        await follower.requestFollow(hostAsPeer(), port: 45678);
        expect(asked, hasLength(1));
        // The id and the port come from the payload...
        expect(asked.single.id, 'fol');
        expect(asked.single.port, 45678);
        // ...but the address comes from the connection, so a peer cannot point
        // this device at somebody else on the LAN.
        expect(asked.single.host, '127.0.0.1');
      },
    );

    test('a device with no sync controller refuses to be followed', () async {
      // onFollowRequest is only installed once the sync controller exists: a
      // request to a plain file-sharing device is a bad request, not a crash.
      await expectLater(
        follower.requestFollow(hostAsPeer(), port: 1),
        throwsA(isA<LanException>()),
      );
    });

    test('a follow request that names no port is refused', () async {
      var called = false;
      host.onFollowRequest = (_) => called = true;
      await expectLater(
        follower.requestFollow(hostAsPeer(), port: 0),
        throwsA(isA<LanException>()),
      );
      expect(called, isFalse);
    });

    test('a follower that goes away is forgotten', () async {
      final socket = await follower.connectPlayback(hostAsPeer());
      await _until(() => host.followerCount == 1);
      await socket.close();
      await _until(() => host.followerCount == 0);
    });

    test('the host is told when the number of followers changes', () async {
      // The screen showing "0 following" while a device is following was
      // exactly this: the count was read once, before anyone had connected.
      var notifications = 0;
      host.onFollowerCountChanged = () => notifications++;
      final socket = await follower.connectPlayback(hostAsPeer());
      await _until(() => host.followerCount == 1);
      expect(notifications, greaterThan(0));
      final seen = notifications;
      await socket.close();
      await _until(() => host.followerCount == 0);
      expect(notifications, greaterThan(seen));
    });

    test(
      'reaching a device that is not there fails with a real reason',
      () async {
        final nowhere = LanDevice(
          id: 'gone',
          name: 'Gone',
          host: '127.0.0.1',
          port: 9,
        );
        await expectLater(
          follower.connectPlayback(nowhere),
          throwsA(isA<LanException>()),
        );
      },
    );
  });
}

/// Waits for a condition instead of sleeping a fixed amount: the sockets are
/// real, so the timing is real too.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition never became true');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
