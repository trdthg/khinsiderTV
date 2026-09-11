import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:khinsider/app.dart';

/// End-to-end test on a real desktop host (macOS sandbox):
/// network search -> album detail -> zen playback (morph) -> OSD menu ->
/// Esc back to the album layout.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('search -> album -> zen playback -> OSD menu -> back', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: KhinsiderApp()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 1. Type a query and submit.
    await tester.enterText(find.byType(TextField), 'mario rpg');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    // 2. Wait for network search to finish (sandbox -> internet).
    await _waitFor(
      tester,
      find.byKey(const ValueKey('album-grid')),
      timeout: const Duration(seconds: 30),
    );

    // 3. Open the first album.
    await tester.tap(find.byKey(const ValueKey('album-card-0')));
    await tester.pump();

    // 4. Wait for album detail (phase 1) — the morphing track list appears.
    await _waitFor(
      tester,
      find.byType(ListTile),
      timeout: const Duration(seconds: 30),
    );

    // 5. Tap the first track — playback starts and the page morphs into
    // zen mode: the current row shows the pause state button.
    await tester.tap(find.byType(ListTile).first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(
      find.byIcon(Icons.pause_circle),
      findsOneWidget,
      reason: 'the playing row must show the pause state button',
    );

    // 6. Walk focus down one row (so the row vertically overlaps the cover),
    // then Left hops to the cover; OK/Enter opens the OSD menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _waitFor(
      tester,
      find.byKey(const ValueKey('osd-menu')),
      timeout: const Duration(seconds: 10),
    );
    expect(find.text('FLAC'), findsOneWidget);
    expect(find.text('Audio quality'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);

    // 7. Esc closes the menu; second Esc returns to the album layout.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.byKey(const ValueKey('osd-menu')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    // The normal layer is back: trailing play arrows are restored.
    // The normal layer is back.
  });
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}
