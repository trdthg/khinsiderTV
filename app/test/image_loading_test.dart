import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/audio/audio_cache_manager.dart';
import 'package:khinsider/audio/base_audio_player.dart';
import 'package:khinsider/data/khinsider_client.dart';
import 'package:khinsider/data/preferences_store.dart';
import 'package:khinsider/state/album_controller.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider/state/search_controller.dart' as kh;
import 'package:khinsider/state/track_cache_controller.dart';
import 'package:khinsider/ui/album/album_screen.dart';
import 'package:khinsider/ui/search/search_screen.dart';
import 'package:khinsider_api/khinsider_api.dart';

import 'album_layout_test.dart' show FakeAudioPlayer;

/// Everything the app draws must come from the 200×200 `thumbs_large` files.
/// The pages themselves only offer smaller ones (search: 60×60, album page:
/// 117×117), which is why the URL is rewritten — see `KhinsiderImage`.
const String _base = 'https://nu.vgmtreasurechest.com/soundtracks/demo-album';
const String _smallUrl = '$_base/thumbs_small/00%20Cover.jpg';
const String _mediumUrl = '$_base/thumbs/00%20Cover.jpg';
const String _largeUrl = '$_base/thumbs_large/00%20Cover.jpg';

/// Every URL a [CachedNetworkImage] is currently being asked to load.
List<String> _drawnImages(WidgetTester tester) => tester
    .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
    .map((w) => w.imageUrl)
    .toList();

void _expectAllLarge(WidgetTester tester, {required String where}) {
  final urls = _drawnImages(tester);
  expect(urls, isNotEmpty, reason: '$where: nothing rendered an image');
  expect(
    urls.where((u) => !u.contains('/thumbs_large/')),
    isEmpty,
    reason: '$where: a smaller variant is still being drawn',
  );
}

class _SeededSearch extends kh.SearchController {
  @override
  kh.SearchState build() => const kh.SearchState(
    query: 'zelda',
    results: [
      AlbumSummary(
        id: 'a',
        title: 'Album A',
        urlPath: '/game-soundtracks/album/a',
        thumbUrl: _smallUrl,
      ),
      AlbumSummary(
        id: 'b',
        title: 'Album B',
        urlPath: '/game-soundtracks/album/b',
        thumbUrl: _smallUrl,
      ),
    ],
  );
}

class _SeededFavorites extends FavoritesController {
  @override
  Future<List<AlbumSummary>> build() async => const [
    AlbumSummary(
      id: 'fav',
      title: 'Favorite',
      urlPath: '/game-soundtracks/album/fav',
      thumbUrl: _smallUrl,
    ),
  ];
}

/// Album whose `coverUrl` is the *medium* (117×117) file the album page
/// embeds — the app must still draw the large one.
Album _album() => const Album(
  summary: AlbumSummary(
    id: 'demo-album',
    title: 'Demo Album',
    urlPath: '/game-soundtracks/album/demo-album',
    thumbUrl: _mediumUrl,
  ),
  coverUrl: _mediumUrl,
  tracks: [
    AlbumTrack(
      index: 1,
      name: 'Track 1',
      trackPagePath: '/game-soundtracks/album/demo-album/01.mp3',
      duration: '1:00',
    ),
    AlbumTrack(
      index: 2,
      name: 'Track 2',
      trackPagePath: '/game-soundtracks/album/demo-album/02.mp3',
      duration: '1:00',
    ),
  ],
);

class _CapturingPlayer extends FakeAudioPlayer {
  final List<List<PlayableItem>> loaded = [];

  @override
  Future<void> loadQueue(List<PlayableItem> items, {int startIndex = 0}) async {
    loaded.add(items);
    await super.loadQueue(items, startIndex: startIndex);
  }
}

class _StubClient extends KhinsiderClient {
  _StubClient() : super(dio: Dio());

  @override
  Future<TrackSource> getTrackSources(
    String trackPagePath, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async => TrackSource(
    trackPagePath: trackPagePath,
    mp3Url: 'https://cdn.example.com/${trackPagePath.split('/').last}.mp3',
  );
}

void main() {
  late Directory tempRoot;
  late AudioCacheManager cache;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('khinsider-images');
    cache = AudioCacheManager(rootOverride: tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  test('the model upgrades the tier the pages hand out', () {
    expect(
      const AlbumSummary(
        id: 'a',
        title: 'A',
        urlPath: '/game-soundtracks/album/a',
        thumbUrl: _smallUrl,
      ).imageUrl,
      _largeUrl,
    );
    expect(_album().imageUrl, _largeUrl);
  });

  testWidgets('search result cards draw the 200×200 cover', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kh.searchControllerProvider.overrideWith(_SeededSearch.new),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pump();

    _expectAllLarge(tester, where: 'search result grid');
    expect(_drawnImages(tester), everyElement(isNot(_smallUrl)));
  });

  testWidgets('favorite / recent cards draw the 200×200 cover', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [favoritesProvider.overrideWith(_SeededFavorites.new)],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('Favorite'),
      findsOneWidget,
      reason: 'the idle home should show the seeded favorite card',
    );
    _expectAllLarge(tester, where: 'favorite cards');
  });

  testWidgets('album cover draws the 200×200 variant (phone and wide)', (
    tester,
  ) async {
    for (final size in const [Size(400, 860), Size(1280, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
            audioCacheManagerProvider.overrideWithValue(cache),
            albumDetailProvider((
              'demo-album',
              0,
            )).overrideWith((ref) async => _album()),
          ],
          child: const MaterialApp(home: AlbumScreen(albumId: 'demo-album')),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      _expectAllLarge(tester, where: 'album screen at $size');
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('system media artwork uses the 200×200 variant', (tester) async {
    final player = _CapturingPlayer();
    final container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWithValue(player),
        audioCacheManagerProvider.overrideWithValue(cache),
        khinsiderClientProvider.overrideWithValue(_StubClient()),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(playerControllerProvider.notifier)
        .playAlbum(_album(), startIndex: 0);

    expect(player.loaded, hasLength(1));
    final art = player.loaded.single.single.artUri;
    expect(art, isNotNull);
    expect(art!.path, contains('/thumbs_large/'));
  });

  test('already-cached playback advertises the 200×200 artwork too', () async {
    // Same expectation on the "play from disk" branch, which builds its
    // PlayableItem separately from the queue path.
    final album = _album();
    final track = album.tracks.first;
    final cached = cache.fileForSync(
      PlayableItem(
        id: '${album.summary.id}/${track.index}',
        title: track.name,
        url: 'https://example.com/audio.mp3',
        albumTitle: album.summary.title,
        albumId: album.summary.id,
        trackIndex: track.index,
      ),
    );
    await cached.create(recursive: true);
    await cached.writeAsBytes([1, 2, 3]);

    final player = _CapturingPlayer();
    final container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWithValue(player),
        audioCacheManagerProvider.overrideWithValue(cache),
        khinsiderClientProvider.overrideWithValue(_StubClient()),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(playerControllerProvider.notifier)
        .playAlbum(album, startIndex: 0);

    final item = player.loaded.single.single;
    expect(item.url, contains('file:'), reason: 'should play the cached file');
    expect(item.artUri, isNotNull);
    expect(item.artUri!.path, contains('/thumbs_large/'));
  });
}
