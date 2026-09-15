import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/core/platform/device.dart';
import 'package:khinsider/l10n/generated/app_localizations.dart';
import 'package:khinsider/state/search_controller.dart' as kh;
import 'package:khinsider/state/update_controller.dart';
import 'package:khinsider/ui/search/search_screen.dart';
import 'package:khinsider/ui/search/tv_system_text_field.dart';

/// Records what the screen asks for, so a search can be asserted without a
/// network call.
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
          // The settings gear watches this; keep the check out of the test.
          updateControllerProvider.overrideWith(QuietUpdateController.new),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: SearchScreen(),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  String? focusedDebugLabel() => FocusManager.instance.primaryFocus?.debugLabel;

  testWidgets('a TV types with the platform keyboard', (tester) async {
    await pump(tester, tv: true);

    // A native EditText in a platform view: with a Flutter TextField the
    // platform keyboard never gets the remote's D-pad, and the field cannot be
    // typed into at all (flutter/flutter#177360).
    expect(find.byType(TvSystemTextField), findsOneWidget);
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'the TV field is the platform one, not a Flutter TextField',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('phones and desktops keep the ordinary field', (tester) async {
    await pump(tester, tv: false);

    expect(find.byType(TvSystemTextField), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).readOnly,
      isFalse,
      reason: 'non-TV layouts are unchanged',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the platform field is anchored in the focus tree', (
    tester,
  ) async {
    await pump(tester, tv: true);

    // The native view owns the Android focus, so this Flutter node is how the
    // remote gets back to the field (up from the results, or when the update
    // banner hands the focus back).
    expect(focusedDebugLabel(), 'search-field-native');
  });

  testWidgets('the platform field is created with the app hint', (
    tester,
  ) async {
    await pump(tester, tv: true);

    final view = tester.widget<AndroidView>(find.byType(AndroidView));
    expect(view.viewType, 'dev.khinsider/tvtextfield');
    expect(
      view.creationParams,
      containsPair('hint', 'Search game soundtracks…'),
    );
  });

  testWidgets('the search bar carries the settings entry point', (
    tester,
  ) async {
    await pump(tester, tv: true);

    // The bar is the app's only permanent chrome, so this is where Settings
    // lives (the album page is a full-screen detail view).
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('the Search button submits what was typed', (tester) async {
    // Phones keep a real Flutter field, so this is also the only place a test
    // can actually type: the TV field lives on the platform side.
    final controller = await pump(tester, tv: false);

    await tester.enterText(find.byType(TextField), 'ze');
    await tester.pump();
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.pump();

    expect(controller.queries, ['ze']);
  });
}

/// The settings gear reads the update state; this keeps the launch check out of
/// the widget tests.
class QuietUpdateController extends UpdateController {
  @override
  UpdateState build() => const UpdateState();
}
