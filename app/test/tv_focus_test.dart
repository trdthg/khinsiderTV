import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/l10n/generated/app_localizations.dart';
import 'package:khinsider/state/album_controller.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider/ui/album/album_screen.dart';
import 'package:khinsider/ui/now_playing/now_playing_art.dart';
import 'package:khinsider/ui/search/search_screen.dart';
import 'package:khinsider_api/khinsider_api.dart';

import 'album_layout_test.dart'
    show FakeAudioPlayer, SeededPlayerController, longTitleAlbum;

/// An album with a related-albums tail, like the real page has.
Album albumWithRelated() {
  final base = longTitleAlbum();
  return Album(
    summary: base.summary,
    tracks: base.tracks,
    relatedAlbums: const [
      AlbumSummary(
        id: 'related-1',
        title: 'Related One',
        urlPath: '/game-soundtracks/album/related-1',
      ),
      AlbumSummary(
        id: 'related-2',
        title: 'Related Two',
        urlPath: '/game-soundtracks/album/related-2',
      ),
    ],
  );
}

String? focusedLabel() =>
    FocusManager.instance.primaryFocus?.debugLabel ??
    FocusManager.instance.primaryFocus?.context?.widget.runtimeType.toString();

/// Text inside the focused widget, for tiles that carry no debug label.
String? focusedText() {
  String? found;
  FocusManager.instance.primaryFocus?.context?.visitChildElements((e) {
    void walk(Element el) {
      final w = el.widget;
      if (w is Text) found ??= w.data;
      el.visitChildElements(walk);
    }

    walk(e);
  });
  return found;
}

Future<void> pumpWide(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final album = albumWithRelated();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
        playerControllerProvider.overrideWith(SeededPlayerController.new),
        albumDetailProvider((
          album.summary.id,
          0,
        )).overrideWith((ref) async => album),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: AlbumScreen(albumId: 'long-title-album'),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  testWidgets('right from the cover focuses the first track', (tester) async {
    await pumpWide(tester);

    await tester.tap(find.byType(NowPlayingArt).first);
    await tester.pump();
    expect(focusedLabel(), 'cover', reason: 'tapping the cover focuses it');

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(
      focusedLabel(),
      'row-0',
      reason: 'Right from the cover must land on the first track',
    );
  });

  testWidgets('down from the cover focuses the album actions', (tester) async {
    await pumpWide(tester);

    await tester.tap(find.byType(NowPlayingArt).first);
    await tester.pump();
    expect(focusedLabel(), 'cover');

    // The favorite / download buttons sit directly below the cover. The
    // default traversal used to skip past them and land on a related album.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(
      focusedText(),
      anyOf('Favorite', 'In favorites'),
      reason: 'Down from the cover must reach the album controls',
    );
  });

  testWidgets('left from a track reaches the album actions, not the art', (
    tester,
  ) async {
    await pumpWide(tester);

    await tester.tap(find.byType(NowPlayingArt).first);
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedLabel(), 'row-0');

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(
      focusedText(),
      anyOf('Favorite', 'In favorites'),
      reason:
          'Left in the normal layout is the way to the album controls; '
          'the cover stays reachable with Up',
    );

    // ...and Up from there really is the cover.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedLabel(), 'cover');
  });

  testWidgets('left on a zen row focuses the cover', (tester) async {
    await pumpWide(tester);

    // Play the first track: the wide layout morphs into zen mode.
    await tester.tap(find.text('Track 1 — Some Fairly Long Track Name Here'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(focusedLabel(), startsWith('row-'), reason: 'zen keeps row focus');

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(
      focusedLabel(),
      'cover',
      reason: 'Left from a row must reach the album art',
    );
  });

  testWidgets('zen: right and the last-row Down do not lose focus', (
    tester,
  ) async {
    await pumpWide(tester);

    await tester.tap(find.text('Track 1 — Some Fairly Long Track Name Here'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await press(tester, LogicalKeyboardKey.arrowRight);
    // Whatever it lands on, it has to be a track row: never one of the faded
    // header/info widgets that made the focus ring disappear.
    expect(
      focusedLabel(),
      startsWith('row-'),
      reason: 'Right in zen mode must stay on the track list',
    );

    for (var i = 0; i < 20; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(
      focusedLabel(),
      'row-11',
      reason: 'Down on the last row must keep the focus on it',
    );
  });

  testWidgets(
    'normal layout: Down from the last track reaches related albums',
    (tester) async {
      await pumpWide(tester);

      await tester.tap(find.byType(NowPlayingArt).first);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedLabel(), 'row-0');

      // Down from the first track: the tail is part of the same list, so the
      // related albums stay reachable with the remote (zen mode takes them out
      // of the focus tree instead, because there they are sliding away).
      var reached = false;
      for (var i = 0; i < 30 && !reached; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
        reached = focusedText() == 'Related One';
      }
      expect(
        reached,
        isTrue,
        reason: 'the related-album tail must stay part of the D-pad path',
      );
    },
  );

  testWidgets('the remote back in zen mode exits zen and keeps the album', (
    tester,
  ) async {
    await pumpWide(tester);

    await tester.tap(find.text('Track 1 — Some Fairly Long Track Name Here'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Android sends the remote's back press as a system pop, not as a key
    // event: it used to pop the album route and land on the search screen.
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.byType(SearchScreen),
      findsNothing,
      reason: 'back in zen mode must not leave the album',
    );
    // ...and the focus comes back onto the track that was playing.
    expect(focusedLabel(), 'row-0');
  });
}
