import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/audio/audio_cache_manager.dart';
import 'package:khinsider/data/preferences_store.dart';
import 'package:khinsider/core/widgets/dpad_tile.dart';
import 'package:khinsider/l10n/generated/app_localizations.dart';
import 'package:khinsider/state/album_controller.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider/state/search_controller.dart' as kh;
import 'package:khinsider/state/track_cache_controller.dart';
import 'package:khinsider/ui/album/views/album_screen.dart';
import 'package:khinsider/ui/search/search_screen.dart';
import 'package:khinsider_api/khinsider_api.dart';

import 'album_layout_test.dart' show FakeAudioPlayer;

/// In-memory favorites so the "like" button can be exercised without a real
/// store (the app's own store is a JSON file; a widget test would have to do
/// real disk I/O inside the fake-async zone).
class FakeFavorites extends FavoritesController {
  @override
  Future<List<AlbumSummary>> build() async => const [];

  @override
  Future<void> toggle(AlbumSummary album) async {
    final current = [...?state.value];
    final existing = current.indexWhere((a) => a.id == album.id);
    if (existing >= 0) {
      current.removeAt(existing);
    } else {
      current.insert(0, album);
    }
    state = AsyncData(current);
  }
}

class SeededSearchController extends kh.SearchController {
  @override
  kh.SearchState build() => const kh.SearchState(
    query: 'zelda',
    results: [
      AlbumSummary(id: 'a', title: 'Album A', urlPath: '/a'),
      AlbumSummary(id: 'b', title: 'Album B', urlPath: '/b'),
    ],
  );
}

const _summary = AlbumSummary(
  id: 'mobile-album',
  title: 'Mobile Album',
  urlPath: '/game-soundtracks/album/mobile-album',
  platforms: ['SNES'],
  year: '1994',
);

Album mobileAlbum() => Album(
  summary: _summary,
  tracks: List.generate(
    5,
    (i) => AlbumTrack(
      index: i + 1,
      name: 'Track ${i + 1}',
      trackPagePath: '/game-soundtracks/album/mobile-album/0$i.mp3',
      duration: '1:0$i',
    ),
  ),
  metadata: const AlbumMetadata(
    platforms: ['SNES'],
    year: '1994',
    developedBy: 'Square',
    publishedBy: 'Square',
    fileCount: 5,
    totalFilesize: '12 MB',
  ),
);

void main() {
  late Directory tempRoot;
  late AudioCacheManager testCache;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('khinsider-mobile-test');
    testCache = AudioCacheManager(rootOverride: tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  Future<void> pumpMobileAlbum(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
          audioCacheManagerProvider.overrideWithValue(testCache),
          favoritesProvider.overrideWith(FakeFavorites.new),
          albumDetailProvider((
            'mobile-album',
            0,
          )).overrideWith((ref) async => mobileAlbum()),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: AlbumScreen(albumId: 'mobile-album'),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('mobile album screen shows the album info above the track list', (
    tester,
  ) async {
    await pumpMobileAlbum(tester);

    expect(find.text('Track 1'), findsOneWidget);
    expect(find.text('5 tracks'), findsOneWidget);
    expect(find.text('SNES · 1994 · Square'), findsOneWidget);
    expect(
      find.byType(FilledButton),
      findsOneWidget,
      reason: 'the favorite button must exist on a phone',
    );
    expect(find.text('Album details'), findsOneWidget);

    // The info is ABOVE the first track row, not below it.
    final infoY = tester.getBottomLeft(find.byType(FilledButton)).dy;
    final firstTrackY = tester.getTopLeft(find.text('Track 1')).dy;
    expect(
      infoY,
      lessThanOrEqualTo(firstTrackY),
      reason: 'album info belongs above the list',
    );

    // …and nothing overflows on a 400x900 phone.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the mobile favorite button actually toggles', (tester) async {
    await pumpMobileAlbum(tester);

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.text('Favorite'), findsOneWidget);

    // A real tap lands on the DpadTile that wraps the (inert) button.
    await tester.tap(
      find.ancestor(
        of: find.byType(FilledButton),
        matching: find.byType(DpadTile),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byIcon(Icons.favorite),
      findsOneWidget,
      reason: 'tapping the like button must favorite the album',
    );
    expect(find.text('In favorites'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow search keeps the field at the bottom and results above', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kh.searchControllerProvider.overrideWith(SeededSearchController.new),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: SearchScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final grid = find.byType(GridView);
    final field = find.byType(TextField);
    expect(grid, findsOneWidget);

    // Results stack from the bottom up…
    expect(tester.widget<GridView>(grid).reverse, isTrue);
    // …and the field sits BELOW them.
    expect(
      tester.getCenter(field).dy,
      greaterThan(tester.getCenter(grid).dy),
      reason: 'the phone layout moves the search field to the bottom',
    );

    // Wide (TV / desktop) layout is unchanged.
    tester.view.physicalSize = const Size(1024, 800);
    await tester.pump();
    expect(
      tester.widget<GridView>(find.byType(GridView)).reverse,
      isFalse,
      reason: 'the reversed layout is a narrow-screen affordance only',
    );
    expect(
      tester.getCenter(find.byType(TextField)).dy,
      lessThan(tester.getCenter(find.byType(GridView)).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
