import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/audio/audio_cache_manager.dart';
import 'package:khinsider/audio/base_audio_player.dart';
import 'package:khinsider/core/keyboard/global_media_keys.dart';
import 'package:khinsider/data/khinsider_client.dart';
import 'package:khinsider/l10n/generated/app_localizations.dart';
import 'package:khinsider/state/album_controller.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider/state/track_cache_controller.dart';
import 'package:khinsider/ui/album/album_screen.dart';
import 'package:khinsider/ui/album/related_albums.dart';
import 'package:khinsider/ui/now_playing/now_playing_art.dart';
import 'package:khinsider/ui/search/search_screen.dart';
import 'package:khinsider_api/khinsider_api.dart';

import 'album_layout_test.dart' show FakeAudioPlayer, longTitleAlbum;

const String albumTitle =
    'A Very Long Original Soundtrack Album Title That '
    'Definitely Wraps Onto Multiple Lines When Rendered In The Side Panel';

/// Album page with 4 tracks + 4 related albums, small enough that the related
/// row is visible without scrolling.
Album uxAlbum() {
  final base = longTitleAlbum();
  return Album(
    summary: base.summary,
    tracks: List.generate(
      4,
      (i) => AlbumTrack(
        index: i + 1,
        name: 'Track ${i + 1}',
        trackPagePath: '/game-soundtracks/album/x/$i.mp3',
        duration: '1:0${i + 1}',
      ),
    ),
    relatedAlbums: const [
      AlbumSummary(
        id: 'related-a',
        title: 'Related A',
        urlPath: '/game-soundtracks/album/related-a',
        thumbUrl: 'https://img/a.jpg',
      ),
      AlbumSummary(
        id: 'related-b',
        title: 'Related B',
        urlPath: '/game-soundtracks/album/related-b',
        thumbUrl: 'https://img/b.jpg',
      ),
      AlbumSummary(
        id: 'related-c',
        title: 'Related C',
        urlPath: '/game-soundtracks/album/related-c',
        thumbUrl: 'https://img/c.jpg',
      ),
      AlbumSummary(
        id: 'related-d',
        title: 'Related D',
        urlPath: '/game-soundtracks/album/related-d',
        thumbUrl: 'https://img/d.jpg',
      ),
    ],
  );
}

/// Never touches the network: phase-2 URLs are handed out directly.
class FakeKhinsiderClient extends KhinsiderClient {
  @override
  Future<Album> getAlbum(
    String albumId, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async => uxAlbum();

  @override
  Future<TrackSource> getTrackSources(
    String trackPagePath, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    return TrackSource(
      trackPagePath: trackPagePath,
      mp3Url: 'https://cdn.example$trackPagePath.mp3',
      flacUrl: 'https://cdn.example$trackPagePath.flac',
    );
  }
}

/// Recording player so tests can assert that nothing started playing.
class RecordingFakePlayer extends FakeAudioPlayer {
  final List<String> queued = [];

  @override
  Future<void> loadQueue(List<PlayableItem> items, {int startIndex = 0}) async {
    queued.addAll(items.map((e) => e.id));
  }
}

Future<ProviderContainer> pumpAlbum(
  WidgetTester tester, {
  BaseAudioPlayer? player,
  required AudioCacheManager cacheManager,
  bool onTopOfHome = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      audioPlayerProvider.overrideWithValue(player ?? RecordingFakePlayer()),
      khinsiderClientProvider.overrideWithValue(FakeKhinsiderClient()),
      audioCacheManagerProvider.overrideWithValue(cacheManager),
      albumDetailProvider((
        'long-title-album',
        0,
      )).overrideWith((ref) async => uxAlbum()),
    ],
  );
  addTearDown(container.dispose);

  // Same shell as the real app: no `home`, everything goes through
  // onGenerateRoute, the navigator key + GlobalMediaKeys live ABOVE the
  // navigator, and the album screen is pushed on top of the search screen.
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        navigatorKey: navigatorKey,
        builder: (context, child) => GlobalMediaKeys(
          navigatorKey: navigatorKey,
          child: child ?? const SizedBox.shrink(),
        ),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (_) => settings.name == '/album'
              ? const AlbumScreen(albumId: 'long-title-album')
              : const SearchScreen(),
        ),
        // `onTopOfHome == false` makes the album screen the ENTRY route:
        // there is nothing to pop underneath it, which is the case where
        // back/Esc used to be a silent no-op.
        initialRoute: onTopOfHome ? '/' : '/album',
        onGenerateInitialRoutes: (initialRoute) => onTopOfHome
            ? [
                MaterialPageRoute<void>(
                  builder: (_) => const SearchScreen(),
                  settings: const RouteSettings(name: '/'),
                ),
              ]
            : [
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const AlbumScreen(albumId: 'long-title-album'),
                  settings: const RouteSettings(name: '/album'),
                ),
              ],
      ),
    ),
  );
  if (onTopOfHome) {
    navigatorKey.currentState!.pushNamed('/album');
  }
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The cache-status scan does real disk I/O, which must happen OUTSIDE the
  // fake-async zone of `testWidgets` (a real I/O future never completes inside
  // it). The temp root is therefore created in setUp and handed to every test.
  late Directory tempRoot;
  late AudioCacheManager testCache;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('khinsider-ux-test');
    testCache = AudioCacheManager(rootOverride: tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  testWidgets('the first track row gets the focus, nothing auto-plays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player = RecordingFakePlayer();
    await pumpAlbum(
      tester,
      player: player,
      cacheManager: testCache,
      onTopOfHome: false,
    );

    final primary = FocusManager.instance.primaryFocus;
    expect(
      primary?.debugLabel,
      'row-0',
      reason: 'entering an album must land the focus on the first track',
    );

    final container = tester.element(find.byType(AlbumScreen));
    final state = ProviderScope.containerOf(
      container,
    ).read(playerControllerProvider);
    expect(state.entries, isEmpty, reason: 'no track may start playing');
    expect(state.currentIndex, isNull);
    expect(player.queued, isEmpty, reason: 'focus alone must not play');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Esc pops the album even when the focus fell back to the route '
      'scope', (tester) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAlbum(tester, cacheManager: testCache);
    expect(find.byType(AlbumScreen), findsOneWidget);

    // The user clicked somewhere non-focusable: the focus falls back to the
    // ROUTE's focus scope, which is an ANCESTOR of any handler inside the
    // page. This is exactly the state in which Esc used to be a no-op.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus,
      isA<FocusScopeNode>(),
      reason: 'precondition: no widget on the page holds the focus',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(
      find.byType(AlbumScreen),
      findsNothing,
      reason: 'Esc must leave the album page even without any focused row',
    );
  });

  testWidgets('Esc leaves the album when it is the entry route (nothing to '
      'pop)', (tester) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAlbum(tester, cacheManager: testCache, onTopOfHome: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    // Root route: nothing to pop -> fall back to the search screen instead of
    // silently doing nothing.
    expect(
      find.byType(SearchScreen),
      findsOneWidget,
      reason: 'the album page must hand over to the search screen',
    );
    expect(
      find.byType(AlbumScreen),
      findsNothing,
      reason: 'and the album page must be gone once the transition ends',
    );
  });

  testWidgets('hovering a track row highlights it and moves the focus there', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAlbum(tester, cacheManager: testCache, onTopOfHome: false);

    // Without this the framework is in "touch" highlight mode inside widget
    // tests (no connected mouse is assumed) and hover callbacks never fire.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.text('Track 3')));
    // Fixed pumps: the album page runs an endless vinyl animation, so
    // pumpAndSettle would never settle.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'row-2',
      reason: 'hover must move the keyboard focus to the hovered row',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('each row shows its cache state at the right edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    PlayableItem playable(String url, int index, String title) => PlayableItem(
      id: 'long-title-album/$index',
      title: title,
      url: url,
      albumTitle: albumTitle,
      albumId: 'long-title-album',
      trackIndex: index,
    );

    // Track 1 fully cached, track 2 downloading (lossless), 3 & 4 nothing.
    // Real I/O has to leave the fake-async zone via runAsync.
    await tester.runAsync(() async {
      final mp3 = await testCache.fileFor(
        playable('https://cdn/1.mp3', 1, 'Track 1'),
      );
      await mp3.create(recursive: true);
      await mp3.writeAsBytes(List.filled(2048, 1));
      final flac = await testCache.fileFor(
        playable('https://cdn/2.flac', 2, 'Track 2'),
      );
      await flac.parent.create(recursive: true);
      await File('${flac.path}.part').writeAsBytes([1, 2]);
    });

    await pumpAlbum(tester, cacheManager: testCache, onTopOfHome: false);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(
      find.byIcon(Icons.download_done),
      findsOneWidget,
      reason: 'the cached track is marked as on disk',
    );
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
      reason: 'a partial download shows a progress spinner',
    );
    expect(
      find.byIcon(Icons.cloud_outlined),
      findsNWidgets(2),
      reason: 'tracks that are not cached show a network-only marker',
    );
    expect(
      find.text('FLAC'),
      findsNothing,
      reason: 'the lossless copy is still downloading',
    );

    // ... and once it lands, the row advertises the lossless copy.
    await tester.runAsync(() async {
      final flac = await testCache.fileFor(
        playable('https://cdn/2.flac', 2, 'Track 2'),
      );
      if (await File('${flac.path}.part').exists()) {
        await File('${flac.path}.part').rename(flac.path);
      }
    });
    // The status scan is synchronous, so the next frame already knows.
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('FLAC'), findsOneWidget);
  });

  testWidgets('related albums fly away (not pop) while entering zen', (
    tester,
  ) async {
    // Tall enough that the related row is visible without scrolling.
    tester.view.physicalSize = const Size(1024, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await pumpAlbum(
      tester,
      cacheManager: testCache,
      onTopOfHome: false,
    );

    double opacityOfCard() => tester
        .renderObject<RenderOpacity>(
          find
              .ancestor(
                of: find.text('Related A'),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    // The window is tall enough that the related row is already on screen,
    // so the first track stays tappable too.
    expect(find.text('Related A'), findsOneWidget);
    expect(opacityOfCard(), 1.0, reason: 'fully visible before the morph');

    // Activate the first track -> zen morph starts.
    await tester.tap(find.text('Track 1'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      debugPrint(
        'zen probe $i: opacity=${opacityOfCard()} screens=${find.byType(AlbumScreen).evaluate().length}',
      );
    }
    expect(
      opacityOfCard(),
      lessThan(1.0),
      reason: 'the related row must FADE out during the morph',
    );
    // Mid-morph the cards must still be moving (no hard cut).
    await tester.pump(const Duration(milliseconds: 120));
    expect(opacityOfCard(), greaterThan(0.0));

    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(
      find.text('People who viewed this also viewed'),
      findsNothing,
      reason: 'once the morph is over the row is gone for good',
    );

    // Esc leaves zen -> the related row comes back.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('People who viewed this also viewed'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Tear the app-level container down INSIDE the fake-async zone: the cache
    // controller owns a polling timer, and every timer must be gone by the
    // time the test framework checks its invariants.
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('RelatedAlbumsRow slides as one group', (tester) async {
    const albums = [
      AlbumSummary(id: 'a', title: 'A', urlPath: '/game-soundtracks/album/a'),
      AlbumSummary(id: 'b', title: 'B', urlPath: '/game-soundtracks/album/b'),
      AlbumSummary(id: 'c', title: 'C', urlPath: '/game-soundtracks/album/c'),
      AlbumSummary(id: 'd', title: 'D', urlPath: '/game-soundtracks/album/d'),
    ];

    Future<Offset> cardPosition(double exitT) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 460,
              child: RelatedAlbumsRow(albums: albums, exitT: exitT),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getTopLeft(find.text('A'));
    }

    final atRest = await cardPosition(0.0);
    final flying = await cardPosition(0.5);

    expect(
      flying,
      isNot(atRest),
      reason: 'cards must MOVE away, not fade in place',
    );
    expect(
      flying.dy,
      isNot(atRest.dy),
      reason: 'the row moves as a group, not just fading in place',
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 460,
            child: RelatedAlbumsRow(albums: albums, exitT: 1.0),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('A'), findsNothing, reason: 'fully gone at exitT == 1');
  });

  testWidgets('zen track list animates to the vertical centre', (tester) async {
    tester.view.physicalSize = const Size(1024, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await pumpAlbum(
      tester,
      cacheManager: testCache,
      onTopOfHome: false,
    );

    double listCentre() {
      final first = tester.getCenter(find.text('Track 1')).dy;
      final last = tester.getCenter(find.text('Track 4')).dy;
      return (first + last) / 2;
    }

    final before = listCentre();
    await tester.tap(find.text('Track 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final middle = listCentre();
    expect(middle, greaterThan(before + 20));
    expect(middle, lessThan(500 - 20));

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(listCentre(), closeTo(500, 35));

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('album art stops breathing after leaving zen', (tester) async {
    tester.view.physicalSize = const Size(1024, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await pumpAlbum(
      tester,
      cacheManager: testCache,
      onTopOfHome: false,
    );

    await tester.tap(find.text('Track 1'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    double artScale() {
      final transforms = tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(NowPlayingArt),
              matching: find.byType(Transform),
            ),
          )
          .toList();
      return transforms[1].transform.getMaxScaleOnAxis();
    }

    final s1 = artScale();
    await tester.pump(const Duration(milliseconds: 400));
    final s2 = artScale();
    expect((s2 - s1).abs(), greaterThan(0.0005));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    final settled = artScale();
    await tester.pump(const Duration(milliseconds: 600));
    final still = artScale();
    expect(still, closeTo(settled, 0.000001));
    expect(still, closeTo(1.0, 0.000001));

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('related albums leave together as one group', (tester) async {
    const albums = [
      AlbumSummary(id: 'a', title: 'A', urlPath: '/game-soundtracks/album/a'),
      AlbumSummary(id: 'b', title: 'B', urlPath: '/game-soundtracks/album/b'),
      AlbumSummary(id: 'c', title: 'C', urlPath: '/game-soundtracks/album/c'),
      AlbumSummary(id: 'd', title: 'D', urlPath: '/game-soundtracks/album/d'),
      AlbumSummary(id: 'e', title: 'E', urlPath: '/game-soundtracks/album/e'),
    ];

    Future<Offset> position(String title, double exitT) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 520,
              child: RelatedAlbumsRow(albums: albums, exitT: exitT),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getCenter(find.text(title));
    }

    final aRest = await position('A', 0.0);
    final bRest = await position('B', 0.0);
    final eRest = await position('E', 0.0);

    final aEarly = await position('A', 0.05);
    final bEarly = await position('B', 0.05);
    expect((aEarly - aRest).distance, greaterThan(0.2));
    expect((bEarly - bRest).distance, greaterThan(0.2));

    final aMid = await position('A', 0.5);
    final bMid = await position('B', 0.5);
    final eMid = await position('E', 0.5);
    final deltaA = aMid - aRest;
    final deltaB = bMid - bRest;
    final deltaE = eMid - eRest;
    expect((deltaB - deltaA).distance, lessThan(0.5));
    expect((deltaE - deltaA).distance, lessThan(0.5));
  });

  testWidgets('enter after esc reopens the zen playback page', (tester) async {
    tester.view.physicalSize = const Size(1024, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await pumpAlbum(
      tester,
      cacheManager: testCache,
      onTopOfHome: false,
    );

    await tester.tap(find.text('Track 1'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(
      tester.widget<NowPlayingArt>(find.byType(NowPlayingArt)).vinylOpacity,
      greaterThan(0.9),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(
      tester.widget<NowPlayingArt>(find.byType(NowPlayingArt)).vinylOpacity,
      lessThan(0.1),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(
      tester.widget<NowPlayingArt>(find.byType(NowPlayingArt)).vinylOpacity,
      greaterThan(0.9),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('tab wraps through zen track rows', (tester) async {
    tester.view.physicalSize = const Size(1024, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await pumpAlbum(
      tester,
      cacheManager: testCache,
      onTopOfHome: false,
    );

    await tester.tap(find.text('Track 1'));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'row-0');
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'row-0');

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('mobile layout keeps a plain list and never enters zen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await pumpAlbum(
      tester,
      cacheManager: testCache,
      onTopOfHome: false,
    );

    expect(find.text('Track 1'), findsOneWidget);
    expect(find.byType(NowPlayingArt), findsNothing);
    expect(find.text('People who viewed this also viewed'), findsNothing);

    await tester.tap(find.text('Track 1'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.byType(NowPlayingArt), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
