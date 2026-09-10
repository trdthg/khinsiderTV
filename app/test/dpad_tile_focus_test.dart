import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/core/widgets/dpad_tile.dart';

/// Regression: mouse clicks must move keyboard focus. Previously, clicking a
/// row left focus on the autofocused first row, so Enter/Space always
/// re-activated the FIRST item instead of the clicked one.
void main() {
  testWidgets('clicking a tile moves focus; Enter activates the clicked tile',
      (tester) async {
    final activated = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DpadTile(
                autofocus: true,
                onSelect: () => activated.add(0),
                child: const ListTile(title: Text('Track 1')),
              ),
              DpadTile(
                onSelect: () => activated.add(1),
                child: const ListTile(title: Text('Track 2')),
              ),
              DpadTile(
                onSelect: () => activated.add(2),
                child: const ListTile(title: Text('Track 3')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Click the third tile (mouse), then press Enter (keyboard).
    await tester.tap(find.text('Track 3'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    // Tap activates tile 2 (plays it); focus moved there, so Enter
    // re-activates tile 2 — NOT the autofocused tile 0.
    expect(activated, [2, 2],
        reason: 'Enter must activate the clicked tile, not the autofocused '
            'first one');
  });
}
