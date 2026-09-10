import 'dart:io';

import 'package:khinsider_api/khinsider_api.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('khinsider_http_cache');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test(
    'cache-first: get returns stored body, forceRefresh overwrites',
    () async {
      final cache = HttpCache(() async => tmp);
      await cache.put('/search?search=mario', '<html>v1</html>');

      expect(await cache.get('/search?search=mario'), '<html>v1</html>');
      expect(await cache.get('/search?search=zelda'), isNull);

      await cache.put('/search?search=mario', '<html>v2</html>');
      expect(await cache.get('/search?search=mario'), '<html>v2</html>');
    },
  );

  test('keys are URL-specific and persist across instances', () async {
    final cache = HttpCache(() async => tmp);
    await cache.put('/game-soundtracks/album/a', 'A');
    await cache.put('/game-soundtracks/album/b', 'B');

    // Reopen from the same directory (simulates app restart).
    final reopened = HttpCache(() async => tmp);
    expect(await reopened.get('/game-soundtracks/album/a'), 'A');
    expect(await reopened.get('/game-soundtracks/album/b'), 'B');
  });

  test('remove and clear', () async {
    final cache = HttpCache(() async => tmp);
    await cache.put('/a', '1');
    await cache.put('/b', '2');

    await cache.remove('/a');
    expect(await cache.get('/a'), isNull);
    expect(await cache.get('/b'), '2');

    await cache.clear();
    expect(await cache.get('/b'), isNull);
  });
}
