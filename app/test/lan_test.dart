import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/data/lan/lan_device.dart';
import 'package:khinsider/data/lan/lan_service.dart';
import 'package:khinsider/data/preferences_store.dart';
import 'package:khinsider/data/storage/json_kv_store.dart';
import 'package:khinsider_api/khinsider_api.dart';

Map<String, Object?> albumJson(String id, String title) => {
  'id': id,
  'title': title,
  'urlPath': '/$id',
};

/// The LAN layer, end to end inside one process: two services, two HTTP
/// servers. Discovery relies on broadcast, which two processes on one host
/// cannot test honestly, so peers are handed over directly — exactly what
/// `addManual` does on a network that filters broadcasts.
void main() {
  test('a device pulls and pushes favorites over the LAN API', () async {
    final receivedByB = <Map<String, Object?>>[];
    final b = LanService(
      deviceId: 'bbbbbbbb',
      deviceName: 'Device B',
      appVersion: '0.2.0',
      discoveryPort: 41241,
      readFavorites: () async => [albumJson('t2', 'Two')],
      mergeFavorites: (incoming) async {
        receivedByB.addAll(incoming);
        return (added: incoming.length, total: incoming.length + 1);
      },
      replaceFavorites: (incoming) async {
        receivedByB.addAll(incoming);
        return (added: incoming.length, total: incoming.length + 1);
      },
    );
    final a = LanService(
      deviceId: 'aaaaaaaa',
      deviceName: 'Device A',
      appVersion: '0.2.0',
      discoveryPort: 41242,
      readFavorites: () async => [
        albumJson('t1', 'One'),
        albumJson('t2', 'Two'),
      ],
      mergeFavorites: (incoming) async => (added: 0, total: 0),
      replaceFavorites: (incoming) async => (added: 0, total: 0),
    );
    await a.start();
    await b.start();
    addTearDown(() async {
      await a.stop();
      await b.stop();
    });

    final push = await a.pushFavorites(
      LanDevice(
        id: 'b',
        name: 'Device B',
        host: '127.0.0.1',
        port: b.httpPort!,
      ),
    );
    expect(receivedByB.map((j) => j['id']), ['t1', 't2']);
    expect(push.added, 2, reason: "the peer's own count comes back");
    expect(push.total, 3);
    expect(push.incoming, isFalse);

    // ...and the same call the other way round, where the merge is local.
    final pull = await b.pullFavorites(
      LanDevice(
        id: 'a',
        name: 'Device A',
        host: '127.0.0.1',
        port: a.httpPort!,
      ),
    );
    expect(pull.added, 2, reason: "A's two favorites were merged into B");
    expect(pull.peer, 'Device A');
    expect(pull.incoming, isTrue);
  });

  test('a forced push overwrites the peer instead of merging', () async {
    var merged = 0;
    final replacedByB = <Object?>[];
    final b = LanService(
      deviceId: 'bbbbbbbb',
      deviceName: 'Device B',
      appVersion: '0.2.0',
      discoveryPort: 41247,
      readFavorites: () async => [albumJson('keep', 'Kept')],
      mergeFavorites: (incoming) async {
        merged++;
        return (added: incoming.length, total: incoming.length);
      },
      replaceFavorites: (incoming) async {
        replacedByB
          ..clear()
          ..addAll(incoming.map((j) => j['id']));
        return (added: incoming.length, total: incoming.length);
      },
    );
    final a = LanService(
      deviceId: 'aaaaaaaa',
      deviceName: 'Device A',
      appVersion: '0.2.0',
      discoveryPort: 41248,
      readFavorites: () async => [
        albumJson('t1', 'One'),
        albumJson('t2', 'Two'),
      ],
      mergeFavorites: (incoming) async => (added: 0, total: 0),
      replaceFavorites: (incoming) async => (added: 0, total: 0),
    );
    await a.start();
    await b.start();
    addTearDown(() async {
      await a.stop();
      await b.stop();
    });

    final result = await a.pushFavorites(
      LanDevice(
        id: 'b',
        name: 'Device B',
        host: '127.0.0.1',
        port: b.httpPort!,
      ),
      replace: true,
    );

    expect(result.replaced, isTrue);
    expect(replacedByB, ['t1', 't2'], reason: 'the peer was overwritten');
    expect(merged, 0, reason: 'a forced push must not quietly merge instead');
    expect(result.total, 2);
  });

  test('a forced pull overwrites the local list', () async {
    var merged = 0;
    List<Object?>? replaced;
    final b = LanService(
      deviceId: 'bbbbbbbb',
      deviceName: 'Device B',
      appVersion: '0.2.0',
      discoveryPort: 41249,
      readFavorites: () async => [albumJson('old', 'Old')],
      mergeFavorites: (incoming) async {
        merged++;
        return (added: incoming.length, total: incoming.length);
      },
      replaceFavorites: (incoming) async {
        replaced = incoming.map((j) => j['id']).toList();
        return (added: incoming.length, total: incoming.length);
      },
    );
    final a = LanService(
      deviceId: 'aaaaaaaa',
      deviceName: 'Device A',
      appVersion: '0.2.0',
      discoveryPort: 41250,
      readFavorites: () async => [albumJson('t1', 'One')],
      mergeFavorites: (incoming) async => (added: 0, total: 0),
      replaceFavorites: (incoming) async => (added: 0, total: 0),
    );
    await a.start();
    await b.start();
    addTearDown(() async {
      await a.stop();
      await b.stop();
    });

    final result = await b.pullFavorites(
      LanDevice(
        id: 'a',
        name: 'Device A',
        host: '127.0.0.1',
        port: a.httpPort!,
      ),
      replace: true,
    );

    expect(result.replaced, isTrue);
    expect(replaced, ['t1'], reason: "A's list replaced B's, old id is gone");
    expect(merged, 0);
    expect(result.total, 1);
  });

  test('the remote-sync callback fires when another device pushes', () async {
    LanSyncResult? seen;
    final b = LanService(
      deviceId: 'bbbbbbbb',
      deviceName: 'Device B',
      appVersion: '0.2.0',
      discoveryPort: 41243,
      readFavorites: () async => [],
      mergeFavorites: (incoming) async => (added: 1, total: 1),
      replaceFavorites: (incoming) async => (added: 1, total: 1),
      onRemoteSync: (result) => seen = result,
    );
    final a = LanService(
      deviceId: 'aaaaaaaa',
      deviceName: 'Device A',
      appVersion: '0.2.0',
      discoveryPort: 41244,
      readFavorites: () async => [albumJson('t1', 'One')],
      mergeFavorites: (incoming) async => (added: 0, total: 0),
      replaceFavorites: (incoming) async => (added: 0, total: 0),
    );
    await a.start();
    await b.start();
    addTearDown(() async {
      await a.stop();
      await b.stop();
    });

    await a.pushFavorites(
      LanDevice(
        id: 'b',
        name: 'Device B',
        host: '127.0.0.1',
        port: b.httpPort!,
      ),
    );

    expect(seen, isNotNull);
    expect(seen!.incoming, isTrue);
    expect(seen!.peer, 'Device A', reason: 'the pusher identifies itself');
  });

  test('a request without the app header is refused', () async {
    final service = LanService(
      deviceId: 'aaaaaaaa',
      deviceName: 'Device A',
      appVersion: '0.2.0',
      discoveryPort: 41245,
      readFavorites: () async => [albumJson('t1', 'One')],
      mergeFavorites: (incoming) async => (added: 0, total: 0),
      replaceFavorites: (incoming) async => (added: 0, total: 0),
    );
    await service.start();
    addTearDown(service.stop);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${service.httpPort}/kh/favorites'),
    );
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.forbidden);
    expect(service.isRunning, isTrue);
  });

  test('a sync against a device that is not there fails cleanly', () async {
    final service = LanService(
      deviceId: 'aaaaaaaa',
      deviceName: 'Device A',
      appVersion: '0.2.0',
      discoveryPort: 41246,
      readFavorites: () async => [],
      mergeFavorites: (incoming) async => (added: 0, total: 0),
      replaceFavorites: (incoming) async => (added: 0, total: 0),
    );
    await service.start();
    addTearDown(service.stop);

    await expectLater(
      service.pushFavorites(
        const LanDevice(id: 'x', name: 'Nowhere', host: '127.0.0.1', port: 1),
      ),
      throwsA(
        isA<LanException>().having(
          (e) => e.message,
          'message',
          // The address has to be in the message: "连不上 X" alone is what made
          // the first field report impossible to act on.
          allOf(contains('127.0.0.1:1'), contains('连不上')),
        ),
      ),
    );
  });

  test('discovery packets are parsed defensively', () {
    expect(LanDevice.tryFromJson(null), isNull);
    expect(LanDevice.tryFromJson('nope'), isNull);
    expect(LanDevice.tryFromJson({'id': 'a'}), isNull, reason: 'no port');
    expect(LanDevice.tryFromJson({'port': 1}), isNull, reason: 'no id');
    expect(
      LanDevice.tryFromJson({'id': 'a', 'port': 1}),
      isNull,
      reason: 'no address anywhere',
    );

    final device = LanDevice.tryFromJson({
      'id': 'a',
      'port': 4242,
      'name': 'TV',
      'v': '0.2.0',
      'fav': 7,
    }, host: '192.168.1.9');
    expect(device!.name, 'TV');
    expect(device.host, '192.168.1.9');
    expect(device.port, 4242);
    expect(device.favorites, 7);
  });

  test(
    'every beacon carries the favorites count, so peers see a real number',
    () async {
      // The first release sent probes and pongs with no count at all, and every
      // discovered device showed "0 个收藏" because 0 is also the default.
      final service = LanService(
        deviceId: 'aaaaaaaa',
        deviceName: 'Device A',
        appVersion: '0.2.0',
        discoveryPort: 41248,
        readFavorites: () async => [
          albumJson('a', 'A'),
          albumJson('b', 'B'),
          albumJson('c', 'C'),
        ],
        mergeFavorites: (incoming) async => (added: 0, total: 0),
        replaceFavorites: (incoming) async => (added: 0, total: 0),
      );

      expect(service.beaconPayload('probe')['fav'], 0, reason: 'not read yet');
      expect(await service.refreshFavoriteCount(), 3);
      for (final kind in ['probe', 'pong']) {
        final payload = service.beaconPayload(kind);
        expect(payload['fav'], 3, reason: '$kind must advertise the count');
        expect(payload['kh'], kind);
        expect(payload['id'], 'aaaaaaaa');
      }
      // ...and a peer that reads such a beacon learns the number.
      final peer = LanDevice.tryFromJson(
        service.beaconPayload('pong'),
        host: '192.168.1.5',
      );
      expect(peer!.favorites, 3);
    },
  );

  test('a device id is random and stable in format', () {
    final one = LanService.newDeviceId();
    final two = LanService.newDeviceId();
    expect(one, hasLength(32));
    expect(one, isNot(two));
    expect(one, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  group('favorites merge', () {
    late Directory dir;
    late JsonKvStore store;
    late ProviderContainer container;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('kh-lan-merge');
      store = await JsonKvStore.open(dir);
      container = ProviderContainer(
        overrides: [jsonKvStoreProvider.overrideWith((ref) async => store)],
      );
      addTearDown(() {
        container.dispose();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
    });

    AlbumSummary album(String id, String title) => AlbumSummary(
      id: id,
      title: title,
      urlPath: '/$id',
      platforms: const [],
    );

    test(
      'only ever adds, newest first, and reports how many were new',
      () async {
        final notifier = container.read(favoritesProvider.notifier);
        await container.read(favoritesProvider.future);

        expect(await notifier.mergeAll([album('a', 'A'), album('b', 'B')]), 2);
        expect(await notifier.mergeAll([album('b', 'B'), album('a', 'A')]), 0);
        expect(await notifier.mergeAll([album('c', 'C')]), 1);

        final ids = container
            .read(favoritesProvider)
            .value!
            .map((a) => a.id)
            .toList();
        expect(ids, ['c', 'a', 'b']);
      },
    );

    test('merges into a store that was never read this session', () async {
      // The other device can push before any screen watched favorites: the
      // merge must read what is on disk instead of writing over it.
      final notifier = container.read(favoritesProvider.notifier);
      await container.read(favoritesProvider.future);
      await notifier.toggle(album('kept', 'Kept'));
      // The store flushes lazily; the "second device" reads the file.
      await store.close();

      final fresh = ProviderContainer(
        overrides: [
          jsonKvStoreProvider.overrideWith(
            (ref) async => await JsonKvStore.open(dir),
          ),
        ],
      );
      addTearDown(fresh.dispose);

      final added = await fresh.read(favoritesProvider.notifier).mergeAll([
        album('new', 'New'),
      ]);

      expect(added, 1);
      final ids = fresh
          .read(favoritesProvider)
          .value!
          .map((a) => a.id)
          .toList();
      expect(ids, containsAll(<String>['kept', 'new']));
    });
  });

  test('a pong alone teaches the service about a peer', () async {
    // The answer to a unicast probe. It used to be parsed, answered and then
    // dropped: the manual address box, the saved addresses and the retry after
    // a failed connection all waited for a `probe` that never came.
    final service = LanService(
      deviceId: 'aaaaaaaa',
      deviceName: 'Device A',
      appVersion: '0.3.1',
      discoveryPort: 41259,
      readFavorites: () async => const [],
      mergeFavorites: (incoming) async => (added: 0, total: 0),
      replaceFavorites: (incoming) async => (added: 0, total: 0),
    );
    await service.start();
    final fake = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await service.stop();
      fake.close();
    });

    final appeared = service.deviceStream
        .firstWhere((devices) => devices.any((d) => d.id == 'peer-1'))
        .timeout(const Duration(seconds: 3));
    fake.send(
      utf8.encode(
        jsonEncode({
          'kh': 'pong',
          'id': 'peer-1',
          'name': 'Peer',
          'v': '0.3.1',
          'port': 45678,
          'fav': 3,
        }),
      ),
      InternetAddress.loopbackIPv4,
      service.discoveryPort,
    );

    await appeared;
    final peer = service.devices.singleWhere((d) => d.id == 'peer-1');
    expect(peer.host, '127.0.0.1');
    expect(peer.port, 45678);
    expect(peer.favorites, 3);
  });

  test('a failed test connection says which half failed', () {
    const silent = LanPeerDiagnosis(udp: false, tcp: false);
    expect(silent.ok, isFalse);
    expect(silent.describe('TV'), contains('地址探测没有回应'));

    const tcpBlocked = LanPeerDiagnosis(udp: true, tcp: false, port: 41234);
    expect(tcpBlocked.describe('TV'), contains('41234'));
    expect(tcpBlocked.describe('TV'), contains('客户端隔离'));

    const fine = LanPeerDiagnosis(
      udp: true,
      tcp: true,
      port: 4321,
      version: '0.3.3',
      favorites: 12,
    );
    expect(fine.ok, isTrue);
    expect(fine.describe('TV'), contains('一切正常'));
    expect(fine.describe('TV'), contains('12'));
  });

  test('diagnose reports UDP alive and TCP dead without a server', () async {
    // The peer is learned from a pong, then asked over HTTP - the split the
    // user needs, because the two failures have different fixes.
    final service = LanService(
      deviceId: 'aaaaaaaa',
      deviceName: 'Device A',
      appVersion: '0.3.3',
      discoveryPort: 41260,
      readFavorites: () async => const [],
      mergeFavorites: (incoming) async => (added: 0, total: 0),
      replaceFavorites: (incoming) async => (added: 0, total: 0),
    );
    await service.start();
    final fake = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    // A port nothing listens on, so the HTTP half must fail.
    final dead = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = dead.port;
    dead.close();
    addTearDown(() async {
      await service.stop();
      fake.close();
    });

    final appeared = service.deviceStream
        .firstWhere((devices) => devices.any((d) => d.id == 'peer-2'))
        .timeout(const Duration(seconds: 3));
    fake.send(
      utf8.encode(
        jsonEncode({
          'kh': 'pong',
          'id': 'peer-2',
          'name': 'Peer',
          'v': '0.3.3',
          'port': deadPort,
          'fav': 0,
        }),
      ),
      InternetAddress.loopbackIPv4,
      service.discoveryPort,
    );
    await appeared;

    final peer = service.devices.singleWhere((d) => d.id == 'peer-2');
    final result = await service.diagnose(peer);
    expect(result.udp, isTrue);
    expect(result.tcp, isFalse);
    expect(result.port, deadPort);
  });
}
