import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:khinsider/app.dart';

/// End-to-end test on a real desktop host (macOS sandbox):
/// network request -> search -> album detail -> playback starts.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('search -> album -> play', (tester) async {
    IntegrationTestWidgetsFlutterBinding
        .instance
        .defaultBinaryMessenger; // ensure binding ready
    await tester.pumpWidget(const ProviderScope(child: KhinsiderApp()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

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

    // 4. Wait for album detail (phase 1) — track rows appear.
    await _waitFor(
      tester,
      find.byIcon(Icons.play_arrow),
      timeout: const Duration(seconds: 30),
    );

    // 5. Tap first track (phase 2 lazy resolution + playback).
    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await tester.pump();

    // 6. Immersive fullscreen Now Playing takes over.
    await _waitFor(
      tester,
      find.byKey(const ValueKey('zen-now-playing')),
      timeout: const Duration(seconds: 30),
    );
    // Minimal immersive UI: no transport icons outside the OSD menu.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byIcon(Icons.skip_next), findsNothing);

    // 7. Left moves to the cover; OK/Enter opens the OSD menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _waitFor(
      tester,
      find.byKey(const ValueKey('osd-menu')),
      timeout: const Duration(seconds: 10),
    );
    expect(find.text('FLAC'), findsOneWidget);
    expect(find.text('Audio quality'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);

    // 8. Esc closes the menu; second Esc exits to the album page.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.byKey(const ValueKey('osd-menu')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _waitFor(
      tester,
      find.byIcon(Icons.play_arrow),
      timeout: const Duration(seconds: 10),
    );
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
