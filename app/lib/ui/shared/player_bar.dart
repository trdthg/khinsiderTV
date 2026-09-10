import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../state/player_controller.dart';
import '../../state/ui_state.dart';

/// Persistent bottom player bar. Visible on every screen; all controls are
/// D-Pad focusable.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Immersive fullscreen playback: hide the persistent bar entirely.
    if (ref.watch(fullscreenProvider)) return const SizedBox.shrink();

    final player = ref.watch(playerControllerProvider);
    final entry = player.current;

    if (entry == null) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (player.resolvingAhead)
              const LinearProgressIndicator(minHeight: 2),
            if (player.processing) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // Cover
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: entry.album.coverUrl != null
                          ? CachedNetworkImage(
                              imageUrl: entry.album.coverUrl!,
                              fit: BoxFit.cover,
                            )
                          : const Icon(Icons.album),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title + progress
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          entry.album.summary.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Transport controls (D-Pad focusable)
                  _PlayerIconButton(
                    icon: Icons.skip_previous,
                    semanticLabel: 'Previous track',
                    onPressed: () =>
                        ref.read(playerControllerProvider.notifier).previous(),
                  ),
                  _PlayerIconButton(
                    icon: player.playing ? Icons.pause : Icons.play_arrow,
                    semanticLabel: 'Play / Pause',
                    onPressed: () => ref
                        .read(playerControllerProvider.notifier)
                        .togglePlayPause(),
                  ),
                  _PlayerIconButton(
                    icon: Icons.skip_next,
                    semanticLabel: 'Next track',
                    onPressed: () =>
                        ref.read(playerControllerProvider.notifier).next(),
                  ),
                ],
              ),
            ),
            if (player.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  player.error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerIconButton extends StatelessWidget {
  const _PlayerIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DpadTile(
      borderRadius: 24,
      onSelect: onPressed,
      child: Semantics(
        label: semanticLabel,
        button: true,
        child: IconButton(icon: Icon(icon), onPressed: onPressed),
      ),
    );
  }
}
