import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/core/platform/device.dart';
import 'package:khinsider/l10n/generated/app_localizations.dart';
import 'package:khinsider/state/locale_controller.dart';
import 'package:khinsider/state/update_controller.dart';
import 'package:khinsider/ui/settings/settings_screen.dart';

/// The update section must not reach for the network in a language test.
class _IdleUpdateController extends UpdateController {
  @override
  UpdateState build() => const UpdateState();
}

Future<void> _pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(460, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        updateControllerProvider.overrideWith(_IdleUpdateController.new),
        appVersionProvider.overrideWith((ref) async => '0.3.4'),
        isTelevisionProvider.overrideWithValue(false),
      ],
      child: Consumer(
        // Exactly what KhinsiderApp does with the value: `null` (nothing read
        // yet) has to mean English, never the system locale.
        builder: (context, ref, _) => MaterialApp(
          locale: ref.watch(localeControllerProvider) ?? defaultLanguage,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('only English and Simplified Chinese are recognised', () {
    expect(defaultLanguage.languageCode, 'en');
    expect(supportedLanguages.length, 2);
    expect(languageFromCode('en'), const Locale('en'));
    expect(languageFromCode('zh'), const Locale('zh'));
    // Anything else must fall back to the default instead of being accepted.
    expect(languageFromCode('fr'), isNull);
    expect(languageFromCode(7), isNull);
    expect(languageFromCode(null), isNull);
  });

  testWidgets('opens in English and switches to Chinese in Settings', (
    tester,
  ) async {
    await _pumpSettings(tester);

    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);

    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();

    // The whole screen follows, not just the row that was tapped.
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('Check for updates'), findsNothing);
    // The language names themselves are never translated.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
  });

  testWidgets('switches back to English', (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('检查更新'), findsNothing);
  });
}
