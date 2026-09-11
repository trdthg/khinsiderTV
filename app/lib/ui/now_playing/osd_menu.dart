import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/theme.dart';
import '../../core/widgets/dpad_tile.dart';
import '../../core/widgets/seek_bar.dart';
import '../../state/player_controller.dart';
import '../../state/theme_controller.dart';

/// Modal OSD menu overlay: seek, play/pause, skip, audio quality, theme.
/// Keyboard focus is trapped inside (the screen disables background focus).
class OsdMenu extends ConsumerWidget {
  const OsdMenu({
    super.key,
    required this.album,
    required this.onClose,
    required this.playFocusNode,
  });

  final Album album;
  final VoidCallback onClose;
  final FocusNode playFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final themeIndex = ref.watch(themeControllerProvider).value ?? 0;
    final notifier = ref.read(playerControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final entry = player.current;

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: FocusTraversalGroup(
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.escape ||
                        event.logicalKey == LogicalKeyboardKey.gameButtonB)) {
                  onClose();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Material(
                key: const ValueKey('osd-menu'),
                color: const Color(0xF314141B),
                borderRadius: BorderRadius.circular(20),
                elevation: 16,
                child: Container(
                  width: 620,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: current track.
                      Row(
                        children: [
                          Icon(Icons.graphic_eq, color: scheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry?.track.name ?? '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  album.summary.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Progress.
                      SeekBar(
                        position: player.position,
                        duration: player.duration ?? Duration.zero,
                        onSeek: (ms) =>
                            notifier.seek(Duration(milliseconds: ms.round())),
                      ),
                      const SizedBox(height: 8),
                      // Transport controls.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _MenuButton(
                            icon: Icons.skip_previous,
                            label: 'Previous',
                            onPressed: notifier.previous,
                          ),
                          const SizedBox(width: 12),
                          _MenuButton(
                            icon: player.playing
                                ? Icons.pause
                                : Icons.play_arrow,
                            label: player.playing ? 'Pause' : 'Play',
                            filled: true,
                            focusNode: playFocusNode,
                            onPressed: notifier.togglePlayPause,
                          ),
                          const SizedBox(width: 12),
                          _MenuButton(
                            icon: Icons.skip_next,
                            label: 'Next',
                            onPressed: notifier.next,
                          ),
                        ],
                      ),
                      const Divider(height: 32),
                      // Audio quality.
                      _MenuRow(
                        icon: Icons.high_quality,
                        label: 'Audio quality',
                        child: Row(
                          children: [
                            _QualityChip(
                              label: 'MP3',
                              selected:
                                  player.preferredFormat == AudioFormat.mp3,
                              enabled: true,
                              onTap: () =>
                                  notifier.setPreferredFormat(AudioFormat.mp3),
                            ),
                            const SizedBox(width: 8),
                            _QualityChip(
                              label: 'FLAC',
                              selected:
                                  player.preferredFormat == AudioFormat.flac,
                              enabled: notifier.flacAvailable,
                              onTap: notifier.flacAvailable
                                  ? () => notifier.setPreferredFormat(
                                      AudioFormat.flac,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Theme.
                      _MenuRow(
                        icon: Icons.palette_outlined,
                        label: 'Theme',
                        child: Row(
                          children: [
                            for (var i = 0; i < AppTheme.seeds.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _ThemeSwatch(
                                  color: AppTheme.seeds[i],
                                  tooltip: AppTheme.names[i],
                                  selected: i == themeIndex,
                                  onTap: () => ref
                                      .read(themeControllerProvider.notifier)
                                      .select(i),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: DpadIconButton(
        focusNode: focusNode,
        borderRadius: 24,
        icon: icon,
        iconSize: 28,
        filled: filled,
        tooltip: label,
        onPressed: onPressed,
      ),
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DpadTile(
      borderRadius: 18,
      onSelect: enabled ? () => onTap?.call() : () {},
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected
                ? scheme.primary.withValues(alpha: 0.35)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
            ),
          ),
          child: Text(
            selected ? '$label ✓' : label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.color,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DpadTile(
      borderRadius: 20,
      onSelect: onTap,
      child: Semantics(
        label: 'Theme $tooltip',
        button: true,
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
