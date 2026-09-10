import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:khinsider/app.dart';
import 'package:khinsider/data/storage/json_kv_store.dart';
import 'package:khinsider/data/preferences_store.dart';
import 'package:khinsider/data/khinsider_client.dart';
import 'package:khinsider/state/search_controller.dart'
    show SearchState, searchControllerProvider;
import 'package:khinsider/state/search_controller.dart' as app_state;
import 'package:khinsider_api/khinsider_api.dart';

/// A tiny local HTTP server serving one second of silent WAV, so playback
/// flows work fully offline in integration tests.
class FakeAudioServer {
  HttpServer? _server;

  Future<Uri> start() async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    _server = server;
    server.listen((request) async {
      request.response.add(_silentWav());
      await request.response.close();
    });
    return Uri.parse('http://127.0.0.1:${server.port}/audio.mp3');
  }

  Future<void> stop() => _server?.close(force: true) ?? Future.value();

  static Uint8List _silentWav() {
    const sampleRate = 8000;
    const seconds = 1;
    const channels = 1;
    const bitsPerSample = 16;
    final dataLen = sampleRate * seconds * channels * (bitsPerSample ~/ 8);
    final b = BytesBuilder();
    final header = ByteData(44);
    void str(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    header.setUint32(4, 36 + dataLen, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * 2, Endian.little);
    header.setUint16(32, channels * 2, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    str(36, 'data');
    header.setUint32(40, dataLen, Endian.little);
    b.add(header.buffer.asUint8List());
    b.add(Uint8List(dataLen)); // silence
    return b.toBytes();
  }
}

/// Offline API client: deterministic data, zero network.
class FakeKhinsiderClient extends KhinsiderClient {
  FakeKhinsiderClient(this.audioUrl) : super(dio: Dio());

  final Uri audioUrl;

  AlbumSummary _seed(int i) => AlbumSummary(
    id: 'seed-album-$i',
    title: 'Seeded Album $i — A Long Title For Text Layout Stress',
    urlPath: '/game-soundtracks/album/seed-album-$i',
    platforms: const ['PC-98', 'DS'],
    type: 'Soundtrack',
    year: '198${8 + i % 10}',
  );

  Album _album(String id) {
    final i = int.tryParse(id.split('-').last) ?? 0;
    return Album(
      summary: _seed(i),
      tracks: List.generate(
        12,
        (t) => AlbumTrack(
          index: t + 1,
          name: 'Track ${t + 1} — Some Long Track Name For The List',
          trackPagePath: '/game-soundtracks/album/$id/0$t.mp3',
          duration: '2:0$t',
        ),
      ),
      metadata: const AlbumMetadata(
        alternativeTitles: ['きまぐれオレンジ☆ロード'],
        platforms: ['PC-98'],
        year: '1988',
        developedBy: 'Microcabin',
        publishedBy: 'Microcabin',
        fileCount: 6,
        totalFilesize: '27 MB',
        dateAdded: 'Sep 16th, 2025',
        albumType: 'Gamerip',
        uploadedBy: 'eet4649',
      ),
      relatedAlbums: [_seed(1), _seed(2), _seed(3)],
    );
  }

  @override
  Future<List<AlbumSummary>> searchAlbums(
    String query, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return List.generate(12, _seed);
  }

  @override
  Future<Album> getAlbum(
    String albumId, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return _album(albumId);
  }

  @override
  Future<TrackSource> getTrackSources(
    String trackPagePath, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    return TrackSource(
      trackPagePath: trackPagePath,
      mp3Url: audioUrl.toString(),
      flacUrl: audioUrl.toString(),
    );
  }
}

/// Instant, offline search results (no network at all).
class SeededSearchController extends app_state.SearchController {
  @override
  Future<void> search(String query, {bool forceRefresh = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    state = SearchState(
      query: query,
      results: List.generate(
        12,
        (i) => AlbumSummary(
          id: 'seed-album-$i',
          title: 'Seeded Album $i — A Long Title For Text Layout Stress',
          urlPath: '/game-soundtracks/album/seed-album-$i',
          platforms: const ['PC-98', 'DS'],
          type: 'Soundtrack',
          year: '198${8 + i % 10}',
        ),
      ),
    );
  }
}

/// Hunts RenderFlex overflow (yellow-black stripe) warnings across
/// representative window sizes, text scales, and all main UI states
/// (idle home with seeded history/favorites, results, album, now playing).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final sizes = <String, Size>{
    'desktop-wide': const Size(1920, 1080),
    'laptop': const Size(1280, 800),
    'small-window': const Size(820, 600),
    'narrow-landscape': const Size(560, 480),
    'very-short': const Size(640, 360),
    'phone-portrait': const Size(390, 720),
  };

  final overflowErrors = <String>[];

  setUpAll(() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('overflowed') || msg.contains('RenderFlex')) {
        overflowErrors.add(msg);
      }
      original?.call(details);
    };
  });

  Future<void> pumpSteady(
    WidgetTester tester, [
    Duration duration = const Duration(milliseconds: 250),
  ]) async {
    await tester.pump(duration);
    try {
      await tester.pumpAndSettle(
        duration,
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );
    } on FlutterError {
      // pumpAndSettle can bail on infinite animations (cursor blink, now
      // playing art); harmless for layout inspection.
    }
  }

  testWidgets('no overflow at any size / scale / state', (tester) async {
    final audio = FakeAudioServer();
    final audioUrl = await audio.start();

    // Seed the KV store so the home screen renders favorites, recents and
    // history chips — layouts that stay invisible with an empty store.
    final dir = await Directory.systemTemp.createTemp('khinsider_seed');
    final store = await JsonKvStore.open(dir);
    const seeded = AlbumSummary(
      id: 'seed-album-0',
      title:
          'Seeded Album 0 — A Deliberately Long Album Title That Wraps Onto '
          'Several Lines To Stress Text Layout',
      urlPath: '/game-soundtracks/album/seed-album-0',
      platforms: ['DS', 'GBA'],
      type: 'Soundtrack',
      year: '2009',
    );
    store.write('favorites', [
      {
        'id': seeded.id,
        'title': seeded.title,
        'urlPath': seeded.urlPath,
        'thumbUrl': null,
        'platforms': seeded.platforms,
        'type': seeded.type,
        'year': seeded.year,
      },
    ]);
    store.write('recent_albums', [
      {
        'id': seeded.id,
        'title': seeded.title,
        'urlPath': seeded.urlPath,
        'thumbUrl': null,
        'platforms': seeded.platforms,
        'type': seeded.type,
        'year': seeded.year,
      },
    ]);
    store.write('search_history', <String>[
      'mario rpg',
      'zelda ocarina of time original soundtrack complete edition',
    ]);

    debugPrint('OVF: pumping app');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jsonKvStoreProvider.overrideWith((ref) async {
            ref.onDispose(store.close);
            return store;
          }),
          khinsiderClientProvider.overrideWith(
            (ref) => FakeKhinsiderClient(audioUrl),
          ),
          searchControllerProvider.overrideWith(SeededSearchController.new),
        ],
        child: const KhinsiderApp(),
      ),
    );
    debugPrint('OVF: app pumped, settling');
    await pumpSteady(tester);
    debugPrint('OVF: settled');

    Future<void> sweep() async {
      for (final entry in sizes.entries) {
        debugPrint('OVF: sweep size ${entry.key}');
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        await pumpSteady(tester, const Duration(seconds: 1));

        // One extra pass at large text scale for the tightest sizes.
        if (entry.key == 'narrow-landscape' || entry.key == 'phone-portrait') {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          await pumpSteady(tester, const Duration(seconds: 1));
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        }
      }
    }

    // 1. Idle home (history chips + favorites + recents rows).
    debugPrint('OVF: idle sweep');
    await sweep();

    // 2. Search results grid (offline, instant).
    debugPrint('OVF: searching');
    await tester.enterText(find.byType(TextField), 'mario rpg');
    debugPrint('OVF: text entered');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    debugPrint('OVF: submitted');
    await _waitFor(tester, find.byKey(const ValueKey('album-grid')));
    debugPrint('OVF: grid visible');
    await sweep();

    // 3. Album detail (cover panel + details + track list + related row).
    debugPrint('OVF: opening album');
    await tester.tap(find.byKey(const ValueKey('album-card-0')));
    await _waitFor(tester, find.byIcon(Icons.play_arrow));
    debugPrint('OVF: album visible');
    await sweep();

    // 4. Immersive Now Playing screen.
    debugPrint('OVF: starting playback');
    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await _waitFor(tester, find.byKey(const ValueKey('now-playing')));
    debugPrint('OVF: now playing visible');
    await sweep();

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await audio.stop();

    expect(
      overflowErrors,
      isEmpty,
      reason:
          'RenderFlex overflows detected:\n${overflowErrors.join('\n---\n')}',
    );
  });
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, [
  Duration timeout = const Duration(seconds: 30),
]) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}
