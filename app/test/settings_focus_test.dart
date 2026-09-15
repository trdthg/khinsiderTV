import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/core/platform/device.dart';
import 'package:khinsider/core/widgets/dpad_tile.dart';
import 'package:khinsider/data/update_service.dart';
import 'package:khinsider/l10n/generated/app_localizations.dart';
import 'package:khinsider/state/update_controller.dart';
import 'package:khinsider/ui/settings/settings_screen.dart';
import 'package:khinsider/ui/settings/settings_widgets.dart';

/// A controller whose state the test moves by hand, so a rebuild can be
/// triggered without a network, a timer or a new widget tree.
class _ScriptedUpdateController extends UpdateController {
  _ScriptedUpdateController(this._initial);

  final UpdateState _initial;

  @override
  UpdateState build() => _initial;

  void show(UpdateState next) => state = next;
}

/// The first line of text inside the focused widget.
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

const _release = UpdateInfo(
  version: '9.9.9',
  url: 'https://example.com/release',
  notes: '',
  assets: [
    UpdateAsset(name: 'khinsider-9.9.9-universal.apk', url: 'https://x/a.apk'),
  ],
);

Future<_ScriptedUpdateController> _pumpSettings(
  WidgetTester tester,
  UpdateState state,
) async {
  tester.view.physicalSize = const Size(460, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = _ScriptedUpdateController(state);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        updateControllerProvider.overrideWith(() => controller),
        appVersionProvider.overrideWith((ref) async => '0.3.5'),
        isTelevisionProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

/// Walks the focus down with the D-Pad, collecting the rows it lands on.
Future<List<String>> walkDown(WidgetTester tester, int steps) async {
  final seen = <String>[];
  for (var i = 0; i < steps; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final text = focusedText();
    if (text != null && !seen.contains(text)) seen.add(text);
  }
  return seen;
}

void main() {
  testWidgets('every settings row takes focus, in the order it is drawn', (
    tester,
  ) async {
    await _pumpSettings(tester, const UpdateState());

    final drawn = tester
        .widgetList<SettingsRow>(find.byType(SettingsRow))
        .map((row) => row.title)
        .toList();
    expect(drawn, isNotEmpty);

    // Three extra presses: one for whatever has focus before the list, one to
    // run past the end, one for safety. Anything skipped would be missing from
    // `seen`; anything out of order would be in a different position.
    final visited = await walkDown(tester, drawn.length + 3);
    expect(visited, drawn);
  });

  testWidgets('a row that only shows a value still takes focus', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SettingsSection(
            title: 'Storage',
            children: [
              const SettingsRow(icon: Icons.info_outline, title: 'Version v1'),
              SettingsRow(
                icon: Icons.delete_outline,
                title: 'Clear',
                onSelect: () => selected++,
              ),
            ],
          ),
        ),
      ),
    );

    // The value row is the first tile, so it is where traversal starts.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedText(), 'Version v1');
    expect(find.byType(DpadTile), findsNWidgets(2));

    // Selecting an inert row must not throw, and must not run anything else.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, 0);

    // ...and the tile below is still exactly one step away.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedText(), 'Clear');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, 1);
  });

  testWidgets('a check starting does not move the focus ring', (tester) async {
    final controller = await _pumpSettings(tester, const UpdateState());

    var guard = 0;
    while (focusedText() != 'Check for updates' && guard++ < 12) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(focusedText(), 'Check for updates');

    // This is the case that used to throw the focus away: the row stopped
    // being a tile (and became plain text) for as long as the check ran.
    controller.show(const UpdateState(checking: true));
    await tester.pump();

    expect(focusedText(), 'Check for updates');

    controller.show(const UpdateState());
    await tester.pump();
    expect(focusedText(), 'Check for updates');
  });

  testWidgets('rows appearing above do not move the focus ring', (
    tester,
  ) async {
    final controller = await _pumpSettings(tester, const UpdateState());

    var guard = 0;
    while (focusedText() != 'Cache' && guard++ < 12) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(focusedText(), 'Cache');

    // An update shows up: its rows are inserted between the focused row and
    // the top of the list, which must not hand the focus to a neighbour.
    controller.show(const UpdateState(available: _release));
    await tester.pump();

    expect(focusedText(), 'Cache');
  });
}
