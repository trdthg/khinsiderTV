import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/core/widgets/seek_bar.dart';
import 'package:khinsider/l10n/generated/app_localizations.dart';

void main() {
  /// A 100-second track sitting at 30 seconds.
  Future<List<double>> pumpBar(
    WidgetTester tester, {
    required bool relativeDrag,
  }) async {
    final seeks = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: SeekBar(
                position: const Duration(seconds: 30),
                duration: const Duration(seconds: 100),
                onSeek: seeks.add,
                relativeDrag: relativeDrag,
              ),
            ),
          ),
        ),
      ),
    );
    return seeks;
  }

  testWidgets('a touch drag adjusts relative to where the finger landed', (
    tester,
  ) async {
    final short = await pumpBar(tester, relativeDrag: true);
    await tester.drag(find.byType(SeekBar), const Offset(60, 0));
    await tester.pumpAndSettle();

    final long = await pumpBar(tester, relativeDrag: true);
    await tester.drag(find.byType(SeekBar), const Offset(160, 0));
    await tester.pumpAndSettle();

    expect(short, hasLength(1), reason: 'one seek per drag, not one per frame');
    // 100px more finger travel is a quarter of the 400px bar, so a quarter of
    // the 100s track. (Comparing two drags rather than predicting one, because
    // the gesture recognizer swallows the first ~18px as touch slop.)
    expect(long.single - short.single, closeTo(25000, 1500));
    // Relative means the position grew from 30s; absolute would have put the
    // thumb under the finger at 65s+.
    expect(short.single, lessThan(60000));
    expect(short.single, greaterThan(30000));
  });

  testWidgets('a mouse drag jumps to the pointer instead', (tester) async {
    final seeks = await pumpBar(tester, relativeDrag: false);

    await tester.drag(find.byType(SeekBar), const Offset(60, 0));
    await tester.pumpAndSettle();

    // The drag starts at the bar's centre (200px) and ends 60px right of it.
    expect(seeks.single, closeTo(65000, 2000));
    expect(seeks.single, greaterThan(60000));
  });

  testWidgets('a tap still jumps to the tapped spot', (tester) async {
    final seeks = await pumpBar(tester, relativeDrag: true);

    final bar = tester.getRect(find.byType(SeekBar));
    await tester.tapAt(Offset(bar.left + bar.width * 0.25, bar.center.dy));
    await tester.pumpAndSettle();

    expect(seeks.single, closeTo(25000, 1000));
  });

  testWidgets('a drag does nothing while the duration is unknown', (
    tester,
  ) async {
    final seeks = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(
          body: SeekBar(
            position: Duration.zero,
            duration: Duration.zero,
            onSeek: seeks.add,
          ),
        ),
      ),
    );

    await tester.drag(find.byType(SeekBar), const Offset(40, 0));
    await tester.pumpAndSettle();

    expect(seeks, isEmpty);
  });
}
