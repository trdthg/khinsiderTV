import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import 'core/keyboard/global_media_keys.dart';
import 'core/theme.dart';
import 'ui/shared/update_banner.dart';
import 'state/theme_controller.dart';
import 'ui/album/album_screen.dart';
import 'ui/search/search_screen.dart';

/// Shared with [GlobalMediaKeys], which sits above the navigator and can
/// therefore not look it up with `Navigator.of`.
final GlobalKey<NavigatorState> khinsiderNavigatorKey =
    GlobalKey<NavigatorState>();

class KhinsiderApp extends ConsumerWidget {
  const KhinsiderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seedIndex = ref.watch(themeControllerProvider).value ?? 0;
    final seed = AppTheme.seeds[seedIndex.clamp(0, AppTheme.seeds.length - 1)];

    return MaterialApp(
      title: 'KHInsider',
      navigatorKey: khinsiderNavigatorKey,
      theme: AppTheme.dark(seed: seed),
      onGenerateRoute: (settings) {
        debugPrint('E2E: route ${settings.name} args ${settings.arguments}');
        if (settings.name == '/album') {
          final album = settings.arguments as AlbumSummary;
          return MaterialPageRoute<void>(
            builder: (_) => AlbumScreen(albumId: album.id),
          );
        }
        return MaterialPageRoute<void>(builder: (_) => const SearchScreen());
      },
      builder: (context, child) => GlobalMediaKeys(
        navigatorKey: khinsiderNavigatorKey,
        child: Column(
          children: [
            const UpdateBanner(),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}
