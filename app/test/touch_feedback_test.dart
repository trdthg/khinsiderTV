import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/core/theme.dart';
import 'package:khinsider/core/widgets/dpad_tile.dart';
import 'package:khinsider/l10n/generated/app_localizations.dart';

/// Touch screens and D-Pads want different feedback from a tile.
///
/// A remote or a keyboard needs a focus ring ("where am I?"), a mouse needs a
/// hover fill. A finger needs neither: it never hovers, and a ring left behind
/// on whatever was tapped last reads as a selection that cannot be cleared.
/// So in touch mode the highlight is suppressed and a tap ripple is painted
/// instead — the same rule Flutter applies to its own Material widgets.
void main() {
  /// Pins the input mode the test is about instead of relying on the platform
  /// the widget tests happen to run as.
  void useHighlightStrategy(FocusHighlightStrategy strategy) {
    FocusManager.instance.highlightStrategy = strategy;
    addTearDown(() {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    });
  }

  double ringWidth(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(DpadTile),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = container.foregroundDecoration! as BoxDecoration;
    return (decoration.border! as Border).top.width;
  }

  Future<void> pumpTile(
    WidgetTester tester, {
    bool autofocus = false,
    Widget? child,
    ThemeData? theme,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        theme: theme ?? AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: DpadTile(
                autofocus: autofocus,
                onSelect: () {},
                child: child ?? const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a touch tap leaves no highlight behind on the tile', (
    tester,
  ) async {
    useHighlightStrategy(FocusHighlightStrategy.alwaysTouch);
    await pumpTile(tester);
    await tester.pump();

    // Tapping plays the tile, and (like a mouse click) moves the keyboard
    // focus there, so a keyboard plugged in later carries on from it.
    await tester.tap(find.byType(DpadTile));
    await tester.pumpAndSettle();

    expect(
      ringWidth(tester),
      0,
      reason: 'a finger must not paint a focus ring',
    );
    expect(
      FocusManager.instance.primaryFocus?.hasFocus,
      isTrue,
      reason: 'the focus still follows the tap, it is only invisible',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard and D-Pad focus still paints the ring', (tester) async {
    useHighlightStrategy(FocusHighlightStrategy.alwaysTraditional);
    await pumpTile(tester, autofocus: true);
    await tester.pump();

    expect(
      ringWidth(tester),
      greaterThan(0),
      reason: 'a remote or keyboard user needs to see where the focus is',
    );
  });

  testWidgets('the ring follows the input mode that was used last', (
    tester,
  ) async {
    useHighlightStrategy(FocusHighlightStrategy.alwaysTouch);
    await pumpTile(tester, autofocus: true);
    await tester.pump();
    expect(ringWidth(tester), 0);

    // Picking up a keyboard (or a mouse, on a desktop) brings the ring back
    // without the tile being rebuilt by its owner.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pump();
    expect(ringWidth(tester), greaterThan(0));

    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await tester.pump();
    expect(ringWidth(tester), 0);
  });

  testWidgets('a tap paints a ripple on top of the tile content', (
    tester,
  ) async {
    // InkSparkle (the M3 default) only paints once its fragment shader has
    // compiled, which never happens in a widget test, so the ripple factory is
    // pinned to keep the captured frame deterministic.
    final theme = AppTheme.dark().copyWith(
      splashFactory: InkRipple.splashFactory,
    );
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        theme: theme,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: const SizedBox(
                width: 200,
                height: 100,
                child: DpadTile(
                  autofocus: true,
                  onSelect: _noop,
                  // Opaque content: Material paints ink *below* the widget it
                  // wraps, so an InkWell around this child would be hidden.
                  child: ColoredBox(color: Color(0xFF101010)),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final flat = await _snapshot(tester, boundaryKey);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DpadTile)),
    );
    // First pump seeds the ripple's ticker, the second one animates it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final pressed = await _snapshot(tester, boundaryKey);

    expect(
      _changedPixels(flat, pressed),
      greaterThan(200),
      reason: 'the ripple must be visible over the tile content',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ripple layer does not steal hits from widgets inside', (
    tester,
  ) async {
    var inner = 0;
    var tile = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: DpadTile(
                onSelect: () => tile++,
                child: GestureDetector(
                  onTap: () => inner++,
                  child: const SizedBox.expand(child: Text('inner')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('inner'));
    await tester.pumpAndSettle();

    expect(inner, 1, reason: 'the innermost gesture wins, as it did before');
    expect(tile, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tile removed mid-ripple leaves no ticker behind', (
    tester,
  ) async {
    await pumpTile(tester);
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DpadTile)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Navigating away while the ripple is still running must not leave the
    // ripple's tickers running on the disposed Material.
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: Scaffold(body: SizedBox()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<Uint8List> _snapshot(WidgetTester tester, GlobalKey boundaryKey) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

int _changedPixels(Uint8List a, Uint8List b) {
  var changed = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
      changed++;
    }
  }
  return changed;
}

void _noop() {}
