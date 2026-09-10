import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import 'core/keyboard/global_media_keys.dart';
import 'core/theme.dart';
import 'ui/shared/update_banner.dart';
import 'state/theme_controller.dart';
import 'ui/album/album_screen.dart';
import 'ui/now_playing/now_playing_screen.dart';
import 'ui/search/search_screen.dart';

class KhinsiderApp extends ConsumerWidget {
  const KhinsiderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seedIndex = ref.watch(themeControllerProvider).value ?? 0;
    final seed = AppTheme.seeds[seedIndex.clamp(0, AppTheme.seeds.length - 1)];

    return MaterialApp(
      title: 'KHInsider',
      theme: AppTheme.dark(seed: seed),
      onGenerateRoute: (settings) {
        if (settings.name == '/album') {
          final album = settings.arguments as AlbumSummary;
          return MaterialPageRoute<void>(
            builder: (_) => AlbumScreen(albumId: album.id),
          );
        }
        if (settings.name == '/now-playing') {
          final (album, trackIndex) = settings.arguments as (Album, int);
          return PageRouteBuilder<void>(
            settings: settings,
            opaque: true,
            transitionDuration: const Duration(milliseconds: 280),
            pageBuilder: (_, _, _) =>
                NowPlayingScreen(album: album, initialTrackIndex: trackIndex),
            transitionsBuilder: (_, animation, _, child) => FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
              child: ScaleTransition(
                scale: Tween(begin: 0.96, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              ),
            ),
          );
        }
        return MaterialPageRoute<void>(builder: (_) => const SearchScreen());
      },
      builder: (context, child) => GlobalMediaKeys(
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
