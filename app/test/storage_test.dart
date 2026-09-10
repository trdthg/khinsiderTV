import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/data/storage/json_kv_store.dart';
import 'package:khinsider/data/preferences_store.dart';
import 'package:khinsider_api/khinsider_api.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('khinsider_store_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('JsonKvStore persists across reopen', () async {
    final store = await JsonKvStore.open(tmp);
    store.write('s', 'hello');
    store.writeList('list', [1, 2, 3]);
    store.remove('s');
    await store.close();

    final reopened = await JsonKvStore.open(tmp);
    expect(reopened.read<String>('s'), isNull);
    expect(reopened.readList<int>('list'), [1, 2, 3]);
    await reopened.close();
  });

  test('corrupt store file is ignored, not fatal', () async {
    File('${tmp.path}/khinsider_store.json').writeAsStringSync('{broken');
    final store = await JsonKvStore.open(tmp);
    expect(store.read<String>('anything'), isNull);
    await store.close();
  });

  test('AlbumSummary JSON round-trip', () async {
    const album = AlbumSummary(
      id: 'mario-luigi-rpg-sound-selection',
      title: 'Mario & Luigi RPG Sound Selection',
      urlPath: '/game-soundtracks/album/mario-luigi-rpg-sound-selection',
      thumbUrl: 'https://example.com/thumb.jpg',
      platforms: ['DS', 'GBA'],
      type: 'Soundtrack',
      year: '2009',
    );
    final json = albumSummaryToJson(album);
    final restored = albumSummaryFromJson(json);

    expect(restored.id, album.id);
    expect(restored.title, album.title);
    expect(restored.platforms, album.platforms);
    expect(restored.year, album.year);
    expect(restored.pageUrl, album.pageUrl);
  });
}
