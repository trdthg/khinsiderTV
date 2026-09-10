import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../state/player_controller.dart';
import '../../state/ui_state.dart';
import '../../core/widgets/seek_bar.dart';

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

    final duration = player.duration ?? Duration.zero;
    final position = player.position;

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
                          ? Image.network(
                              entry.album.coverUrl!,
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
                        Row(
                          children: [
                            Text(
                              _fmt(position),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Expanded(
                              child: SeekBar(
                                position: position,
                                duration: duration,
                                onSeek: (v) => ref
                                    .read(playerControllerProvider.notifier)
                                    .seek(Duration(milliseconds: v.round())),
                              ),
                            ),
                            Text(
                              _fmt(duration),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
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

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
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
