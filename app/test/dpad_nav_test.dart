import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/core/widgets/dpad_nav.dart';
import 'package:khinsider/core/widgets/dpad_tile.dart';
import 'package:khinsider/l10n/generated/app_localizations.dart';

/// The `stopX` flags: a horizontal row of cards must swallow Left/Right at its
/// own ends instead of handing the focus to whatever the default traversal
/// finds — which on the search screen was the row underneath.
void main() {
  /// Two cards in a row, and a third one further right on the next line, so
  /// there is always something for a leaked Right to land on.
  Future<void> pump(WidgetTester tester, {required bool stopEdges}) async {
    tester.view.physicalSize = const Size(900, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < 2; i++)
                    DpadNav(
                      stopLeft: stopEdges && i == 0,
                      stopRight: stopEdges && i == 1,
                      child: DpadTile(
                        key: ValueKey('card-$i'),
                        autofocus: i == 0,
                        onSelect: () {},
                        child: SizedBox(
                          width: 120,
                          height: 80,
                          child: Text('card $i'),
                        ),
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 300),
                  DpadTile(
                    key: const ValueKey('below'),
                    onSelect: () {},
                    child: const SizedBox(
                      width: 120,
                      height: 80,
                      child: Text('below'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  FocusNode? focused() => FocusManager.instance.primaryFocus;

  testWidgets('Right at the last card stays on the last card', (tester) async {
    await pump(tester, stopEdges: true);

    await press(tester, LogicalKeyboardKey.arrowRight);
    final second = focused();
    expect(second, isNotNull);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(
      focused(),
      same(second),
      reason:
          'the end of the row must swallow Right, not jump to the row below',
    );

    // Left is the same story at the other end.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    final first = focused();
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focused(), same(first));
  });

  testWidgets('without the flags the row does leak sideways', (tester) async {
    await pump(tester, stopEdges: false);

    await press(tester, LogicalKeyboardKey.arrowRight);
    final second = focused();
    await press(tester, LogicalKeyboardKey.arrowRight);

    expect(
      focused(),
      isNot(same(second)),
      reason:
          'this is the behaviour the flags exist to prevent: focus leaving '
          'the row through its right edge',
    );
  });
}
