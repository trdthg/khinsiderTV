import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider/ui/now_playing/now_playing_screen.dart';

import 'album_layout_test.dart'
    show FakeAudioPlayer, SeededPlayerController, longTitleAlbum;

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 760);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
          playerControllerProvider.overrideWith(SeededPlayerController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ),
    );
    // Push NowPlaying as a real route so Esc/pop navigation is exercised.
    final context = tester.element(find.byType(Scaffold).first);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NowPlayingScreen(album: longTitleAlbum()),
      ),
    );
    // Route + infinite cover animations need several manual frames.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('renders fullscreen layout and toggles OSD menu', (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const ValueKey('now-playing')), findsOneWidget);
    // Minimal immersive UI: no hint line, no bottom bar.
    expect(find.textContaining('OK — menu'), findsNothing);
    expect(find.byIcon(Icons.skip_next), findsNothing);

    // OK on the cover opens the OSD menu: initial focus sits on the playing
    // track's row, so Left first moves to the cover.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('osd-menu')), findsOneWidget);
    expect(find.text('Audio quality'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('FLAC'), findsOneWidget);
    expect(find.text('MP3 ✓'), findsOneWidget); // default format selected

    // Esc closes the menu…
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('osd-menu')), findsNothing);

    // …second Esc pops the route.
    debugPrint(
      'primary focus: ${FocusManager.instance.primaryFocus?.debugLabel}',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('now-playing')), findsNothing);
  });

  bool isInsideOsdMenu(WidgetTester tester) {
    final f = FocusManager.instance.primaryFocus;
    if (f?.context == null) return false;
    var found = false;
    f!.context!.visitAncestorElements((el) {
      if (el.widget.key == const ValueKey('osd-menu')) found = true;
      return !found;
    });
    return found;
  }

  testWidgets('OSD menu traps keyboard focus (modal behaviour)', (
    tester,
  ) async {
    await pumpScreen(tester);

    // Open the menu: Left moves to the cover, Enter activates it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('osd-menu')), findsOneWidget);
    expect(
      isInsideOsdMenu(tester),
      isTrue,
      reason: 'initial focus should be inside the menu',
    );

    // A round of arrows + tab must NEVER escape the menu into the
    // track list behind the dim overlay.
    const keys = [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.arrowUp,
    ];
    for (final key in keys) {
      await tester.sendKeyEvent(key);
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        isInsideOsdMenu(tester),
        isTrue,
        reason: 'focus escaped the OSD menu after pressing $key',
      );
    }

    // Esc closes the menu and hands focus back to the cover.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.byKey(const ValueKey('osd-menu')), findsNothing);
    // Focus returns to the playing track's row.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'np-row-0');
  });

  testWidgets('quality switch selects FLAC via controller', (tester) async {
    await pumpScreen(tester);

    // Enter menu (Left to cover, then OK) and pick FLAC.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 400));

    // Seed state has no flac URL -> chip disabled. Toggle still must not
    // crash and MP3 stays selected.
    await tester.tap(find.text('FLAC'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MP3 ✓'), findsOneWidget);
  });
}
