import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/audio/android_storage.dart';
import 'package:khinsider/audio/audio_cache_manager.dart';
import 'package:khinsider/audio/base_audio_player.dart';
import 'package:khinsider_api/khinsider_api.dart';

Future<Directory> tempRoot() async {
  final dir = await Directory.systemTemp.createTemp('khinsider-cache-test');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

PlayableItem item(
  String url, {
  String album = 'Test Album',
  String albumId = 'test-album',
  int index = 1,
  String title = 'Track 1',
}) {
  return PlayableItem(
    id: '$albumId/$index',
    title: title,
    url: url,
    albumTitle: album,
    albumId: albumId,
    trackIndex: index,
  );
}

void main() {
  test(
    'media is cached under Music/KHInsider/<Album>/mp3 with a readable name',
    () async {
      final root = await tempRoot();
      final cache = AudioCacheManager(rootOverride: root);

      final file = await cache.fileFor(item('https://cdn/x/a.mp3?token=1'));
      expect(
        file.path,
        endsWith(
          'Test Album${Platform.pathSeparator}mp3${Platform.pathSeparator}01 Track 1.mp3',
        ),
      );
      expect(
        await file.exists(),
        isFalse,
        reason: 'fileFor must not create the file',
      );
      expect(
        await file.parent.exists(),
        isTrue,
        reason: 'but it does prepare the folder so the download can be written',
      );

      final albumDir = cache.locateAlbumDirSync('test-album', 'Test Album');
      expect(albumDir, isNotNull);
      final found = albumDir!;
      for (final name in AudioCacheManager.categoryFolders) {
        expect(
          Directory('${found.path}${Platform.pathSeparator}$name').existsSync(),
          isTrue,
          reason: '$name/ must exist so the user sees the expected structure',
        );
      }
    },
  );

  test('lossless goes to flac/, anything else to other/', () async {
    final root = await tempRoot();
    final cache = AudioCacheManager(rootOverride: root);

    final flac = await cache.fileFor(item('https://cdn/x/a.flac'));
    expect(flac.path, contains('flac'));
    final m4a = await cache.fileFor(item('https://cdn/x/a.m4a'));
    expect(m4a.path, contains('other'));
    expect(AudioCacheManager.categoryForExtension('.flac'), 'flac');
    expect(AudioCacheManager.categoryForExtension('.mp3'), 'mp3');
    expect(AudioCacheManager.categoryForExtension('.ogg'), 'other');
  });

  test('illegal characters in album / track names are sanitized', () async {
    final root = await tempRoot();
    final cache = AudioCacheManager(rootOverride: root);

    final file = await cache.fileFor(
      item('https://cdn/x/a.mp3', album: 'AC/DC: "Back" <in> Black?'),
    );
    final albumFolder = file.parent.parent;
    expect(
      albumFolder.path.split(Platform.pathSeparator).last,
      'AC DC Back in Black',
      reason: r'\\ / : * ? " < > | are all replaced by spaces',
    );
    expect(file.uri.pathSegments.last, '01 Track 1.mp3');
  });

  test(
    'two different albums with the same title do not overwrite each other',
    () async {
      final root = await tempRoot();
      final cache = AudioCacheManager(rootOverride: root);

      final a = await cache.fileFor(item('https://cdn/x/a.mp3'));
      final b = await cache.fileFor(
        item(
          'https://cdn/x/b.mp3',
          album: 'Test Album',
          albumId: 'other-album',
        ),
      );
      expect(
        a.parent.parent.path,
        isNot(b.parent.parent.path),
        reason: 'same title, different album id -> separate folders',
      );

      final resolved = cache.locateAlbumDirSync('other-album', 'Test Album');
      expect(resolved!.path, b.parent.parent.path);
      // ... and the same album always resolves to the same folder.
      final resolvedA = cache.locateAlbumDirSync('test-album', 'Test Album');
      expect(resolvedA, isNotNull);
      expect(resolvedA!.path, a.parent.parent.path);
    },
  );

  test('statusFor reports absent -> downloading -> cached', () async {
    final root = await tempRoot();
    final cache = AudioCacheManager(rootOverride: root);
    const key = CacheLookupKey(
      albumId: 'test-album',
      albumTitle: 'Test Album',
      trackIndex: 3,
      trackTitle: 'Track 3',
    );

    expect((cache.statusForSync(key)).isEmpty, isTrue);

    final file = await cache.fileFor(
      item('https://cdn/x/c.mp3', index: 3, title: 'Track 3'),
    );
    await file.parent.create(recursive: true);
    await File('${file.path}.part').writeAsBytes([1, 2, 3]);
    final partial = cache.statusForSync(key);
    expect(partial.downloading, isTrue);
    expect(partial.cached, isFalse);

    await File('${file.path}.part').rename(file.path);
    final done = cache.statusForSync(key);
    expect(done.cached, isTrue);
    expect(done.downloading, isFalse);
    expect(done.bytes, 3);
  });

  test(
    'album.json describes the album so the folder can be used standalone',
    () async {
      final root = await tempRoot();
      final cache = AudioCacheManager(rootOverride: root);
      const summary = AlbumSummary(
        id: 'nice-album',
        title: 'Nice Album',
        urlPath: '/game-soundtracks/album/nice-album',
      );
      final album = Album(
        summary: summary,
        coverUrl: 'https://img/cover.jpg',
        tracks: [
          const AlbumTrack(
            index: 1,
            name: 'First',
            trackPagePath: '/p/1',
            duration: '1:02',
          ),
          const AlbumTrack(index: 2, name: 'Second', trackPagePath: '/p/2'),
        ],
      );
      await cache.saveAlbumManifest(album);

      final dir = (cache.locateAlbumDirSync('nice-album', 'Nice Album'))!;
      final manifest = File(
        '${dir.path}${Platform.pathSeparator}other${Platform.pathSeparator}album.json',
      );
      expect(await manifest.exists(), isTrue);
      final decoded =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      expect(decoded['id'], 'nice-album');
      expect(decoded['coverUrl'], 'https://img/cover.jpg');
      expect((decoded['tracks'] as List).length, 2);
      expect((decoded['tracks'] as List).first['duration'], '1:02');
    },
  );

  test('covers are stored in image/', () async {
    final root = await tempRoot();
    final cache = AudioCacheManager(rootOverride: root);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((req) async {
      req.response.add(utf8.encode('fake-jpeg-bytes'));
      await req.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/cover.jpg';

    final cover = await cache.cacheAlbumCover(
      'cover-album',
      'Cover Album',
      url,
    );
    expect(cover, isNotNull);
    expect(cover!.path, contains('image'));
    expect(cover.path, endsWith('cover.jpg'));

    // A second call must not re-download.
    final again = await cache.cacheAlbumCover(
      'cover-album',
      'Cover Album',
      url,
    );
    expect(again!.path, cover.path);
  });

  test('totalSize / deleteAlbum / clear', () async {
    final root = await tempRoot();
    final cache = AudioCacheManager(rootOverride: root);
    final file = await cache.fileFor(item('https://cdn/x/a.mp3'));
    await file.writeAsBytes(List.filled(10, 1));
    expect(
      await cache.totalSize(),
      greaterThanOrEqualTo(10),
      reason: 'totalSize walks the album folders recursively',
    );

    await cache.deleteAlbum('test-album', 'Test Album');
    expect(await file.exists(), isFalse);
    expect(await cache.totalSize(), 0);

    await cache.fileFor(item('https://cdn/x/a.mp3'));
    await cache.clear();
    expect(await cache.totalSize(), 0);
  });

  group('Android public Music folder', () {
    late Directory docs;
    late Directory music;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      docs = await tempRoot();
      music = await tempRoot();
      // The Android branch falls back to the app documents folder while
      // all-files access is missing; that goes through path_provider.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => switch (call.method) {
              'getApplicationDocumentsDirectory' => docs.path,
              'getApplicationSupportDirectory' => docs.path,
              _ => null,
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
    });

    test('is used once all-files access is granted', () async {
      final storage = FakeAndroidStorage(music.path);
      final cache = AudioCacheManager(androidStorage: storage, isAndroid: true);

      expect(cache.supportsPublicMusicFolder, isTrue);
      expect(await cache.isUsingPublicMusicFolder, isFalse);

      storage.granted = true;
      final root = await cache.root();
      expect(root.path, '${music.path}${Platform.pathSeparator}KHInsider');
      expect(await cache.isUsingPublicMusicFolder, isTrue);
      // The Music folder itself is created on demand.
      expect(await root.exists(), isTrue);
      expect(storage.requests, 0);
    });

    test('needs no permission and stays private elsewhere', () async {
      final storage = FakeAndroidStorage(music.path)..granted = true;
      final desktop = AudioCacheManager(
        rootOverride: docs,
        androidStorage: storage,
        isAndroid: false,
      );
      // A non-Android build has no public music folder to switch to.
      expect(desktop.supportsPublicMusicFolder, isFalse);
      expect(await desktop.isUsingPublicMusicFolder, isFalse);
    });

    test('forgetRoot re-resolves after the grant, without a restart', () async {
      final storage = FakeAndroidStorage(music.path);
      final cache = AudioCacheManager(androidStorage: storage, isAndroid: true);

      // Resolved before the user granted anything: still the private folder.
      final first = await cache.root();
      expect(first.path, isNot(startsWith(music.path)));

      storage.granted = true;
      expect(
        await cache.root().then((d) => d.path),
        first.path,
        reason: 'the resolved root is memoized until it is forgotten',
      );

      cache.forgetRoot();
      expect(
        await cache.root().then((d) => d.path),
        '${music.path}${Platform.pathSeparator}KHInsider',
      );
    });

    test('requestPublicMusicAccess asks the platform', () async {
      final storage = FakeAndroidStorage(music.path);
      final cache = AudioCacheManager(androidStorage: storage, isAndroid: true);

      await cache.requestPublicMusicAccess();
      expect(storage.requests, 1);

      // A pinned root (tests) must never be forgotten.
      final pinned = AudioCacheManager(
        rootOverride: music,
        androidStorage: storage,
        isAndroid: true,
      );
      await pinned.requestPublicMusicAccess();
      pinned.forgetRoot();
      expect(await pinned.root().then((d) => d.path), music.path);
    });
  });
}

/// Drives [AudioCacheManager]'s Android branch off-device.
class FakeAndroidStorage implements AndroidStorage {
  FakeAndroidStorage(this.musicPath);

  final String musicPath;

  /// Whether the user has granted "all files access".
  bool granted = false;

  /// How often the settings screen was requested.
  int requests = 0;

  @override
  Future<bool> canWritePublicMusic() async => granted;

  @override
  Future<String?> publicMusicPath() async => musicPath;

  @override
  Future<void> requestAllFilesAccess() async => requests++;
}
