import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/core/platform/device.dart';
import 'package:khinsider/core/widgets/dpad_tile.dart';
import 'package:khinsider/state/search_controller.dart' as kh;
import 'package:khinsider/ui/search/search_screen.dart';
import 'package:khinsider/ui/search/tv_keyboard.dart';

/// Records what the screen asks for, so the keyboard's Search key can be
/// asserted without a network call.
class RecordingSearchController extends kh.SearchController {
  final List<String> queries = [];

  @override
  kh.SearchState build() => const kh.SearchState();

  @override
  Future<void> search(String query, {bool forceRefresh = false}) async =>
      queries.add(query);
}

void main() {
  Future<RecordingSearchController> pump(
    WidgetTester tester, {
    required bool tv,
    double devicePixelRatio = 1.0,
  }) async {
    // A TV window (Google TV is 1920x1080) and a phone one.
    tester.view.physicalSize = tv
        ? const Size(1920, 1080)
        : const Size(400, 900);
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = RecordingSearchController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWithValue(tv),
          kh.searchControllerProvider.overrideWith(() => controller),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pump();
    return controller;
  }

  Finder key(String character) =>
      find.widgetWithText(DpadTile, character).first;

  testWidgets('a TV opens with its own keyboard focused on the first key', (
    tester,
  ) async {
    await pump(tester, tv: true);

    expect(find.byType(TvKeyboard), findsOneWidget);
    // Nothing is left to the system IME, and the field cannot ask for it.
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);

    // The first key already has focus: pressing the remote's centre button
    // types it, without the user having to move focus anywhere first.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('1'), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1',
    );
  });

  testWidgets('TV keys append, delete and clear the query', (tester) async {
    await pump(tester, tv: true);

    await tester.tap(key('m'));
    await tester.pump();
    await tester.tap(key('a'));
    await tester.pump();
    await tester.tap(key('x'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'max',
    );

    await tester.tap(find.widgetWithText(DpadTile, 'Space'));
    await tester.pump();
    await tester.tap(key('p'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'max p',
    );

    await tester.tap(find.widgetWithText(DpadTile, 'Delete'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'max ',
    );

    await tester.tap(find.widgetWithText(DpadTile, 'Clear'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('the TV Search key submits the query and hides the keyboard', (
    tester,
  ) async {
    final controller = await pump(tester, tv: true);

    await tester.tap(key('z'));
    await tester.pump();
    await tester.tap(key('e'));
    await tester.pump();
    await tester.tap(find.widgetWithText(DpadTile, 'Search'));
    await tester.pump();
    await tester.pump();

    expect(controller.queries, ['ze']);
    expect(
      find.byType(TvKeyboard),
      findsNothing,
      reason: 'submitting hands the screen back to the results',
    );
  });

  testWidgets('Escape closes the keyboard and Enter brings it back', (
    tester,
  ) async {
    await pump(tester, tv: true);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(TvKeyboard), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byType(TvKeyboard), findsOneWidget);
  });

  testWidgets('the remote can reach every key, including the row right half', (
    tester,
  ) async {
    // Google TV reports 1920x1080 at density 2: 960x540 logical pixels, which is
    // much narrower than the default test window and is what the user is on.
    await pump(tester, tv: true, devicePixelRatio: 2.0);

    // Digits row: 1 -> 5, then down into the letter row under it (t).
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // ... and on to y, which the user cannot reach on a Chromecast.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'y',
      reason: 'right of t must be reachable with the remote',
    );
  });

  testWidgets('hiding the keyboard hands focus back to the search field', (
    tester,
  ) async {
    await pump(tester, tv: true);

    await tester.tap(find.widgetWithText(DpadTile, 'Hide'));
    await tester.pump();

    // No tap on the field first: Enter alone must bring the keyboard back.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byType(TvKeyboard), findsOneWidget);
    // The first key is focused again, so typing works right away.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1',
    );
  });

  testWidgets('a physical keyboard still types on a TV', (tester) async {
    await pump(tester, tv: true);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'a',
    );
  });

  testWidgets('phones and desktops keep the system keyboard and no TV panel', (
    tester,
  ) async {
    await pump(tester, tv: false);

    expect(find.byType(TvKeyboard), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).readOnly,
      isFalse,
      reason: 'non-TV layouts are unchanged',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the TV keyboard can type uppercase and symbols', (tester) async {
    await pump(tester, tv: true);

    // Uppercase: the shift key locks on (a remote user would otherwise need a
    // press per letter), and the letters turn into capitals.
    await tester.tap(key('⇧'));
    await tester.pump();
    expect(find.widgetWithText(DpadTile, 'A'), findsWidgets);
    await tester.tap(key('A'));
    await tester.pump();
    await tester.tap(key('B'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'AB',
      reason:
          'the shift key must stay on so a remote can type several capitals',
    );

    // Symbols: the layer key swaps the grid, and the same spot switches back.
    await tester.tap(key('#+='));
    await tester.pump();
    expect(find.widgetWithText(DpadTile, '@'), findsWidgets);
    await tester.tap(key('@'));
    await tester.pump();
    await tester.tap(key('é'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'AB@é',
      reason: 'punctuation and accented letters must be reachable',
    );

    await tester.tap(key('ABC'));
    await tester.pump();
    expect(find.widgetWithText(DpadTile, 'a'), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'AB@é',
      reason: 'switching back to letters must not type anything',
    );
  });
}
