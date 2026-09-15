import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import 'core/keyboard/global_media_keys.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/l10n.dart';
import 'core/widgets/keep_screen_awake.dart';
import 'core/theme.dart';
import 'ui/shared/public_music.dart';
import 'state/locale_controller.dart';
import 'state/theme_controller.dart';
import 'state/lan_controller.dart';
import 'ui/album/album_screen.dart';
import 'ui/search/search_screen.dart';
import 'ui/settings/settings_screen.dart';

/// Shared with [GlobalMediaKeys], which sits above the navigator and can
/// therefore not look it up with `Navigator.of`.
final GlobalKey<NavigatorState> khinsiderNavigatorKey =
    GlobalKey<NavigatorState>();

/// Brings the LAN service up for the whole session: devices must be able to
/// find this one without the user first opening Settings. Reading `.notifier`
/// in [initState] (rather than watching the value in `build`) means discovery
/// updates never rebuild the app shell.
class _LanBootstrap extends ConsumerStatefulWidget {
  const _LanBootstrap({required this.child});

  final Widget child;

  @override
  ConsumerState<_LanBootstrap> createState() => _LanBootstrapState();
}

class _LanBootstrapState extends ConsumerState<_LanBootstrap> {
  @override
  void initState() {
    super.initState();
    ref.read(lanControllerProvider.notifier);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class KhinsiderApp extends ConsumerWidget {
  const KhinsiderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seedIndex = ref.watch(themeControllerProvider).value ?? 0;
    final seed = AppTheme.seeds[seedIndex.clamp(0, AppTheme.seeds.length - 1)];
    // English unless the user picked otherwise: `null` (still loading, or the
    // store could not be read) must not fall back to the system locale, which
    // on a Chinese phone would show Chinese before the real choice arrives.
    final locale = ref.watch(localeControllerProvider) ?? defaultLanguage;
    currentUiLocale = locale;

    return MaterialApp(
      title: 'KHInsider',
      navigatorKey: khinsiderNavigatorKey,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark(seed: seed),
      onGenerateRoute: (settings) {
        debugPrint('E2E: route ${settings.name} args ${settings.arguments}');
        if (settings.name == '/settings') {
          return MaterialPageRoute<void>(
            builder: (_) => const SettingsScreen(),
          );
        }
        if (settings.name == '/album') {
          final album = settings.arguments as AlbumSummary;
          return MaterialPageRoute<void>(
            builder: (_) => AlbumScreen(albumId: album.id),
          );
        }
        return MaterialPageRoute<void>(builder: (_) => const SearchScreen());
      },
      builder: (context, child) => KeepScreenAwake(
        child: GlobalMediaKeys(
          navigatorKey: khinsiderNavigatorKey,
          // Updates used to be a banner pinned here, across every screen; the
          // Settings screen owns them now and nothing pops up at launch.
          child: _LanBootstrap(
            child: Column(
              children: [
                // Android only, asked once: offer the public Music folder.
                PublicMusicPrompt(navigatorKey: khinsiderNavigatorKey),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
