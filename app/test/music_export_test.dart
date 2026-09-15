import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/audio/android_storage.dart';
import 'package:khinsider/audio/audio_cache_manager.dart';
import 'package:khinsider/audio/music_export.dart';
import 'package:khinsider/core/platform/device.dart';
import 'package:khinsider/l10n/generated/app_localizations.dart';
import 'package:khinsider/state/album_controller.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider/state/track_cache_controller.dart';
import 'package:khinsider/ui/album/album_screen.dart';
import 'package:khinsider_api/khinsider_api.dart';

import 'album_layout_test.dart' show FakeAudioPlayer;
import 'audio_cache_manager_test.dart' show FakeAndroidStorage;

const String _albumId = 'export-album';
const String _albumTitle = 'Export Album';

Album albumFixture({int tracks = 3, String title = _albumTitle}) {
  return Album(
    summary: AlbumSummary(
      id: _albumId,
      title: title,
      urlPath: '/game-soundtracks/album/$_albumId',
    ),
    tracks: [
      for (var i = 1; i <= tracks; i++)
        AlbumTrack(
          index: i,
          name: 'Track $i',
          trackPagePath: '/game-soundtracks/album/$_albumId/0$i.mp3',
        ),
    ],
  );
}

/// The completed cache file the playback layer would have produced for [index]
/// (`<root>/<album>/<category>/<NN Track Name><ext>`).
File cachedFile(
  Directory root,
  int index,
  String title, {
  String ext = '.mp3',
  String albumTitle = _albumTitle,
}) {
  final name = AudioCacheManager.trackFileName(
    trackIndex: index,
    title: title,
    ext: ext,
  );
  return File(
    '${root.path}/$albumTitle/'
    '${AudioCacheManager.categoryForExtension(ext)}/$name',
  );
}

/// Creates that file, i.e. marks the track as fully cached. Goes through the
/// manager so a disambiguated album folder is honoured.
File seedCached(
  Directory root,
  int index,
  String title, {
  String ext = '.mp3',
  String albumTitle = _albumTitle,
  String albumId = _albumId,
  AudioCacheManager? cache,
}) {
  var file = cachedFile(root, index, title, ext: ext, albumTitle: albumTitle);
  final dir = cache?.locateAlbumDirSync(albumId, albumTitle, create: true);
  if (dir != null) {
    file = File(
      '${dir.path}/${AudioCacheManager.categoryForExtension(ext)}'
      '/${file.uri.pathSegments.last}',
    );
  }
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(List<int>.filled(1024, 0));
  return file;
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('khinsider-export');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  ({AudioCacheManager cache, FakeAndroidStorage storage}) build() {
    final storage = FakeAndroidStorage('/storage/emulated/0/Music');
    final cache = AudioCacheManager(
      rootOverride: root,
      androidStorage: storage,
      isAndroid: true,
    );
    return (cache: cache, storage: storage);
  }

  test('exports the best cached copy of every cached track', () async {
    final (:cache, :storage) = build();
    seedCached(root, 1, 'Track 1');
    seedCached(root, 3, 'Track 3');
    final album = albumFixture();

    final report = await MusicExporter(
      cache,
      storage: storage,
    ).exportAlbum(album);

    expect(report.folder, 'Music/KHInsider/$_albumTitle');
    expect(report.exported, 2);
    expect(report.considered, 2, reason: 'the uncached track 2 is not counted');
    expect(report.summary, 'Exported 2 tracks to Music/KHInsider/$_albumTitle');
    expect(storage.exports.map((e) => e.displayName), [
      '01 Track 1.mp3',
      '03 Track 3.mp3',
    ]);
    expect(
      storage.exports.every((e) => e.relativePath == report.folder),
      isTrue,
    );
    expect(storage.exports.first.mimeType, 'audio/mpeg');
    expect(storage.exports.first.title, 'Track 1');
    expect(storage.exports.first.album, _albumTitle);
    expect(
      storage.exports.first.sourcePath,
      cachedFile(root, 1, 'Track 1').path,
    );
  });

  test('prefers the lossless copy when both are cached', () async {
    final (:cache, :storage) = build();
    seedCached(root, 1, 'Track 1');
    final flac = seedCached(root, 1, 'Track 1', ext: '.flac');
    final album = albumFixture(tracks: 1);

    final report = await MusicExporter(
      cache,
      storage: storage,
    ).exportAlbum(album);

    expect(report.exported, 1);
    expect(storage.exports.single.displayName, '01 Track 1.flac');
    expect(storage.exports.single.mimeType, 'audio/flac');
    expect(storage.exports.single.sourcePath, flac.path);
  });

  test('ignores tracks that are still downloading', () async {
    final (:cache, :storage) = build();
    // Only the `.part` file exists: just_audio is mid-download.
    File('${cachedFile(root, 1, 'Track 1').path}.part')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(16, 0));
    final album = albumFixture(tracks: 1);

    final report = await MusicExporter(
      cache,
      storage: storage,
    ).exportAlbum(album);

    expect(report.isEmpty, isTrue);
    expect(report.summary, 'Nothing cached yet.');
    expect(storage.exports, isEmpty);
  });

  test('counts what the platform reports back', () async {
    final (:cache, :storage) = build();
    for (var i = 1; i <= 3; i++) {
      seedCached(root, i, 'Track $i');
    }
    final album = albumFixture();

    storage.exportStatus = MusicExportStatus.failed;
    expect(
      (await MusicExporter(cache, storage: storage).exportAlbum(album)).summary,
      '3 failed',
    );

    storage.exportStatus = MusicExportStatus.unsupported;
    expect(
      (await MusicExporter(cache, storage: storage).exportAlbum(album)).summary,
      '3 need Android 10+',
    );

    storage.exportStatus = MusicExportStatus.alreadyThere;
    expect(
      (await MusicExporter(cache, storage: storage).exportAlbum(album)).summary,
      '3 already there',
    );
  });

  test('reports progress once per file', () async {
    final (:cache, :storage) = build();
    seedCached(root, 1, 'Track 1');
    seedCached(root, 2, 'Track 2');
    final seen = <(int, int)>[];

    await MusicExporter(cache, storage: storage).exportAlbum(
      albumFixture(tracks: 2),
      onProgress: (done, total) => seen.add((done, total)),
    );

    expect(seen, [(1, 2), (2, 2)]);
  });

  test('keeps the cache folder name when two albums share a title', () async {
    final (:cache, :storage) = build();
    // Album "a" owns the plain folder; album "export-album" then has to use a
    // disambiguated one (see AudioCacheManager.locateAlbumDirSync).
    await cache.albumDir('other-album', _albumTitle);
    seedCached(root, 1, 'Track 1', cache: cache);

    final report = await MusicExporter(
      cache,
      storage: storage,
    ).exportAlbum(albumFixture(tracks: 1));

    expect(report.folder, startsWith('Music/KHInsider/$_albumTitle ('));
  });

  group('export button', () {
    Future<FakeAndroidStorage> pumpAlbum(
      WidgetTester tester, {
      bool isTelevision = false,
      bool isAndroid = true,
      Album? album,
      Size size = const Size(1024, 800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final target = album ?? albumFixture(tracks: 1);
      final storage = FakeAndroidStorage('/storage/emulated/0/Music');
      final cache = AudioCacheManager(
        rootOverride: root,
        androidStorage: storage,
        isAndroid: isAndroid,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
            audioCacheManagerProvider.overrideWithValue(cache),
            androidStorageProvider.overrideWithValue(storage),
            isTelevisionProvider.overrideWithValue(isTelevision),
            albumDetailProvider((
              target.summary.id,
              0,
            )).overrideWith((ref) async => target),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('en'),
            home: AlbumScreen(albumId: target.summary.id),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return storage;
    }

    Finder exportButton() =>
        find.byTooltip('Export cached tracks to the system Music folder');

    testWidgets('copies the cached tracks and reports the result', (
      tester,
    ) async {
      seedCached(root, 1, 'Track 1', cache: build().cache);
      final storage = await pumpAlbum(tester);

      expect(exportButton(), findsOneWidget);
      await tester.ensureVisible(exportButton());
      await tester.pump();
      await tester.tap(exportButton());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(storage.exports.single.displayName, '01 Track 1.mp3');
      expect(find.text('Export to Music'), findsOneWidget);
      expect(
        find.text('Exported 1 track to Music/KHInsider/$_albumTitle'),
        findsOneWidget,
      );

      // The Done button leaves the export screen.
      await tester.tap(find.text('Done'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Done'), findsNothing);
    });

    testWidgets('says so when nothing is cached yet', (tester) async {
      final storage = await pumpAlbum(tester);

      await tester.ensureVisible(exportButton());
      await tester.pump();
      await tester.tap(exportButton());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(storage.exports, isEmpty);
      expect(find.text('Export to Music'), findsOneWidget);
      expect(find.text('Nothing cached yet.'), findsOneWidget);
    });

    testWidgets('the wide (TV) layout offers the download button too', (
      tester,
    ) async {
      final storage = await pumpAlbum(
        tester,
        isTelevision: true,
        size: const Size(1280, 800),
      );

      expect(
        find.widgetWithText(FilledButton, 'Export to Music'),
        findsOneWidget,
        reason:
            'televisions used to get only the Favorite button, because the '
            'export was hidden from them',
      );
      expect(storage.exports, isEmpty, reason: 'nothing was tapped yet');
    });

    testWidgets('phone layouts export from the album header', (tester) async {
      seedCached(root, 1, 'Track 1', cache: build().cache);
      final storage = await pumpAlbum(tester, size: const Size(400, 900));

      final button = find.widgetWithText(FilledButton, 'Export to Music');
      expect(
        button,
        findsOneWidget,
        reason: 'the phone header is where the export is discoverable',
      );
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(storage.exports.single.displayName, '01 Track 1.mp3');
      expect(
        find.text('Exported 1 track to Music/KHInsider/$_albumTitle'),
        findsOneWidget,
      );
    });

    testWidgets('is not offered on a TV or off Android', (tester) async {
      await pumpAlbum(tester, isTelevision: true);
      expect(exportButton(), findsNothing);

      await pumpAlbum(tester, isAndroid: false);
      expect(exportButton(), findsNothing);
    });
  });
}
