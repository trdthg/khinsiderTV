import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/audio/audio_cache_manager.dart';

/// The parts of the cache the Settings screen drives, against a real temp
/// folder. (The Settings screen itself is tested with a fake manager: real
/// async IO cannot make progress inside a widget test.)
void main() {
  late Directory root;
  late AudioCacheManager cache;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kh-cache-api');
    cache = AudioCacheManager(rootOverride: root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  final sep = Platform.pathSeparator;

  /// One album folder, exactly as the player writes it.
  void seed(
    String title, {
    required int bytes,
    int tracks = 1,
    String id = '',
    bool cover = false,
    bool part = false,
  }) {
    final album = Directory('${root.path}$sep$title');
    for (final folder in ['mp3', 'image', 'other']) {
      Directory('${album.path}$sep$folder').createSync(recursive: true);
    }
    if (part) {
      File(
        '${album.path}${sep}mp3${sep}02 Part.mp3.part',
      ).writeAsBytesSync(List<int>.filled(bytes, 1));
    } else {
      for (var i = 1; i <= tracks; i++) {
        File(
          '${album.path}${sep}mp3${sep}0$i Track.mp3',
        ).writeAsBytesSync(List<int>.filled(bytes ~/ tracks, 1));
        // just_audio leaves this beside every finished track.
        File(
          '${album.path}${sep}mp3${sep}0$i Track.mp3.mime',
        ).writeAsStringSync('audio/mpeg');
      }
    }
    if (cover) {
      File(
        '${album.path}${sep}image${sep}cover.jpg',
      ).writeAsBytesSync(List<int>.filled(16, 2));
    }
    File(
      '${album.path}${sep}other${sep}album.json',
    ).writeAsStringSync('{"id":"$id","title":"$title"}');
  }

  test('lists every album folder, biggest first', () async {
    seed('Album One', bytes: 2048, tracks: 2, id: 'a1');
    seed('Album Two', bytes: 4096, tracks: 1, id: 'a2', cover: true);

    final albums = await cache.listCachedAlbums();

    expect(albums.map((a) => a.title), ['Album Two', 'Album One']);
    expect(albums.first.id, 'a2');
    expect(albums.first.tracks, 1);
    expect(albums.first.hasCover, isTrue);
    expect(albums.last.id, 'a1');
    expect(albums.last.tracks, 2);
    expect(albums.last.hasCover, isFalse);
  });

  test('counts bytes but not sidecars as tracks', () async {
    seed('Album One', bytes: 1000, tracks: 1, id: 'a1');

    final album = (await cache.listCachedAlbums()).single;

    // The .mime sidecar is part of the size, the manifest is not a track.
    expect(album.bytes, greaterThan(1000));
    expect(album.tracks, 1);
    expect(album.downloading, isFalse);
  });

  test('flags an in-flight download', () async {
    seed('Album One', bytes: 1000, part: true, id: 'a1');

    final album = (await cache.listCachedAlbums()).single;

    expect(album.downloading, isTrue);
    expect(
      album.tracks,
      1,
      reason: 'the .part file is the track being written',
    );
  });

  test('falls back to the folder name when there is no manifest', () async {
    Directory('${root.path}${sep}No Manifest').createSync(recursive: true);

    final album = (await cache.listCachedAlbums()).single;

    expect(album.title, 'No Manifest');
    expect(album.id, '');
    expect(album.bytes, 0);
  });

  test('deletes one album and leaves the others alone', () async {
    seed('Album One', bytes: 1024, id: 'a1');
    seed('Album Two', bytes: 1024, id: 'a2');
    final target = (await cache.listCachedAlbums()).firstWhere(
      (a) => a.title == 'Album One',
    );

    await cache.deleteCachedAlbum(target.path);

    final left = await cache.listCachedAlbums();
    expect(left.map((a) => a.title), ['Album Two']);
  });

  test('refuses to delete anything outside the cache root', () async {
    final outside = Directory.systemTemp.createTempSync('kh-cache-outside');
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync(recursive: true);
    });
    seed('Album One', bytes: 1024, id: 'a1');

    await cache.deleteCachedAlbum(outside.path);

    expect(outside.existsSync(), isTrue);
    expect((await cache.listCachedAlbums()).length, 1);
  });

  test('clear empties the root but keeps it usable', () async {
    seed('Album One', bytes: 1024, id: 'a1');
    seed('Album Two', bytes: 1024, id: 'a2');

    await cache.clear();

    expect((await cache.listCachedAlbums()), isEmpty);
    expect(root.existsSync(), isTrue);
    expect(await cache.totalSize(), 0);
  });
}
