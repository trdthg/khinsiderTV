import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/state/search_controller.dart' as kh;
import 'package:khinsider/ui/search/search_screen.dart';
import 'package:khinsider_api/khinsider_api.dart';

class SeededSearchController extends kh.SearchController {
  @override
  kh.SearchState build() => const kh.SearchState(
    query: 'q',
    results: [
      AlbumSummary(id: 'a', title: 'A', urlPath: '/a'),
      AlbumSummary(id: 'b', title: 'B', urlPath: '/b'),
    ],
  );
}

void main() {
  testWidgets('down from the search field enters the results', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kh.searchControllerProvider.overrideWith(SeededSearchController.new),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final field = tester.widget<TextField>(find.byType(TextField));
    field.focusNode?.requestFocus();
    await tester.pump();
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(field.focusNode?.hasFocus, isFalse);
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('the field does not take focus, so no keyboard, on open', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kh.searchControllerProvider.overrideWith(SeededSearchController.new),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofocus, isFalse);
    expect(
      field.focusNode?.hasFocus,
      isFalse,
      reason: 'a focused field raises the on-screen keyboard on launch',
    );
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
    );
  });
}
