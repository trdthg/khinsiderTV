import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/l10n/generated/app_localizations.dart';
import 'package:khinsider/state/album_controller.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider/ui/album/views/album_screen.dart';
import 'package:khinsider/ui/search/views/search_screen.dart';
import 'package:khinsider_api/khinsider_api.dart';

import 'album_layout_test.dart' show FakeAudioPlayer, longTitleAlbum;

Album albumWith(int trackCount) {
  final base = longTitleAlbum();
  return Album(
    summary: base.summary,
    tracks: List.generate(
      trackCount,
      (i) => AlbumTrack(
        index: i + 1,
        name: 'Track ${i + 1}',
        trackPagePath: '/game-soundtracks/album/x/$i.mp3',
      ),
    ),
  );
}

void main() {
  testWidgets('the header back button pops the route', (tester) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const albumRoute = '/album-under-test';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
          albumDetailProvider((
            'long-title-album',
            0,
          )).overrideWith((ref) async => longTitleAlbum()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          // The album screen is pushed ON TOP of the home screen, so there is
          // a route to pop (maybePop on the root route is a no-op).
          home: const SearchScreen(),
          routes: {
            albumRoute: (_) => const AlbumScreen(albumId: 'long-title-album'),
          },
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AlbumScreen), findsNothing);

    Navigator.of(
      tester.element(find.byType(SearchScreen)),
    ).pushNamed(albumRoute);
    // Fixed pumps: the album screen runs an endless vinyl animation, so
    // pumpAndSettle would never settle. Several frames are needed anyway for
    // the page route to finish its transition (it ignores pointers until
    // then, which would silently swallow the tap below).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AlbumScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byType(AlbumScreen),
      findsNothing,
      reason: 'the back button must actually leave the album screen',
    );
    expect(find.byType(SearchScreen), findsOneWidget);
  });

  testWidgets('a track-count change does not dispose a live FocusNode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const nonceKey = ('long-title-album', 0);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
          albumDetailProvider(
            nonceKey,
          ).overrideWith((ref) async => albumWith(12)),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: AlbumScreen(albumId: 'long-title-album'),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The first row is focused. Focus a row near the end so that shrinking
    // the list would retire a node that is currently in use.
    await tester.tap(find.text('Track 11'));
    await tester.pump();

    // Rebuild with a much shorter album: rows 6..11 must not be disposed
    // while still attached.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
          albumDetailProvider(
            nonceKey,
          ).overrideWith((ref) async => albumWith(3)),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: AlbumScreen(albumId: 'long-title-album'),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      tester.takeException(),
      isNull,
      reason:
          'shrinking the track list must not throw '
          '"A FocusNode was used after being disposed"',
    );
  });
}
