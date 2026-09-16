import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/audio/audio_cache_manager.dart';

void main() {
  late Directory root;
  late HttpServer server;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kh-cache-test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void respond(List<int> body, {int status = 200}) {
    server.listen((request) async {
      request.response.statusCode = status;
      if (status == 200) request.response.add(body);
      await request.response.close();
    });
  }

  AudioCacheManager manager() => AudioCacheManager(rootOverride: root);

  test('a download we run ourselves ends as a real file', () async {
    // The step that never happened on Windows: temp file, handle closed,
    // renamed into place. Without this a cache folder held only `.part` files.
    respond(List<int>.filled(4096, 7));
    final target = File('${root.path}${Platform.pathSeparator}Track 1.mp3');
    final url = 'http://127.0.0.1:${server.port}/t.mp3';

    expect(await manager().downloadTrackSource(url, target), isTrue);
    expect(target.existsSync(), isTrue);
    expect(target.lengthSync(), 4096);
    expect(
      File('${target.path}${AudioCacheManager.tempSuffix}').existsSync(),
      isFalse,
      reason: 'the temporary file must not survive a successful download',
    );
  });

  test('a failed download leaves nothing behind', () async {
    respond(const [], status: 404);
    final target = File('${root.path}${Platform.pathSeparator}Track 2.mp3');
    final url = 'http://127.0.0.1:${server.port}/missing.mp3';

    expect(await manager().downloadTrackSource(url, target), isFalse);
    expect(target.existsSync(), isFalse);
    expect(
      File('${target.path}${AudioCacheManager.tempSuffix}').existsSync(),
      isFalse,
      reason: 'a half file left behind reads as an interrupted download',
    );
  });

  test('an already downloaded track is not fetched again', () async {
    var hits = 0;
    server.listen((request) async {
      hits++;
      request.response.add(List<int>.filled(16, 1));
      await request.response.close();
    });
    final target = File('${root.path}${Platform.pathSeparator}Track 3.mp3');
    target.writeAsBytesSync(List<int>.filled(16, 1));

    expect(
      await manager().downloadTrackSource('http://127.0.0.1:1/x', target),
      isTrue,
    );
    expect(hits, 0);
  });

  test('cleaning removes stale leftovers and keeps a running download', () async {
    final stale = File('${root.path}${Platform.pathSeparator}A.mp3.part')
      ..writeAsBytesSync(List<int>.filled(10, 1));
    stale.setLastModifiedSync(
      DateTime.now().subtract(const Duration(minutes: 30)),
    );
    final oursStale = File(
      '${root.path}${Platform.pathSeparator}B.mp3${AudioCacheManager.tempSuffix}',
    )..writeAsBytesSync(List<int>.filled(10, 1));
    oursStale.setLastModifiedSync(
      DateTime.now().subtract(const Duration(minutes: 30)),
    );
    // Fresh: a download that is actually running right now.
    final fresh = File('${root.path}${Platform.pathSeparator}C.mp3.part')
      ..writeAsBytesSync(List<int>.filled(10, 1));
    final complete = File('${root.path}${Platform.pathSeparator}D.mp3')
      ..writeAsBytesSync(List<int>.filled(10, 1));

    expect(await manager().cleanIncomplete(), 2);
    expect(stale.existsSync(), isFalse);
    expect(oursStale.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue, reason: 'a live download must survive');
    expect(complete.existsSync(), isTrue, reason: 'finished files stay');
  });
}
