import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../state/player_controller.dart';

/// Right pane of the now-playing screen: navigable track list where the
/// leading element is a state button (number -> spinner -> play/pause) and
/// the row background fills with the playback progress of the current track.
class NowPlayingTrackList extends ConsumerWidget {
  const NowPlayingTrackList({
    super.key,
    required this.album,
    required this.focusNodes,
    required this.coverFocusNode,
  });

  final Album album;

  /// Focus nodes owned by the screen, index-aligned with [album.tracks].
  final List<FocusNode> focusNodes;

  /// Cover tile node: Left from any row moves there (menu entry point).
  final FocusNode coverFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
        // The cover sits left of the list but may not vertically overlap a
        // given row, so Left is bound explicitly as the menu entry point.
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            coverFocusNode.requestFocus,
      },
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        itemCount: album.tracks.length,
        itemBuilder: (context, i) {
          final track = album.tracks[i];
          final isCurrent = player.currentIndex == i;
          final isLoading = isCurrent && player.processing;
          final isPlaying = isCurrent && player.playing && !player.processing;
          final isPaused = isCurrent && !player.playing && !player.processing;

          var progress = 0.0;
          if (isCurrent &&
              player.duration != null &&
              player.duration!.inMilliseconds > 0) {
            progress =
                (player.position.inMilliseconds /
                        player.duration!.inMilliseconds)
                    .clamp(0.0, 1.0);
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: DpadTile(
              focusNode: focusNodes[i],
              autofocus: false,
              borderRadius: 10,
              onSelect: () async {
                final notifier = ref.read(playerControllerProvider.notifier);
                if (isLoading) {
                  await notifier.cancelLoading();
                } else if (isPlaying) {
                  await notifier.pause();
                } else if (isPaused) {
                  await notifier.play();
                } else {
                  await notifier.playAlbum(album, startIndex: i);
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    if (isCurrent)
                      Positioned.fill(
                        child: ColoredBox(
                          color: scheme.primary.withValues(alpha: 0.10),
                        ),
                      ),
                    if (isCurrent && progress > 0)
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: ColoredBox(
                            color: scheme.primary.withValues(alpha: 0.22),
                          ),
                        ),
                      ),
                    ListTile(
                      leading: _LeadingState(
                        isLoading: isLoading,
                        isPlaying: isPlaying,
                        isPaused: isPaused,
                        index: track.index,
                      ),
                      title: Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: isCurrent
                            ? TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              )
                            : null,
                      ),
                      subtitle: track.duration != null
                          ? Text(
                              track.duration!,
                              style: const TextStyle(fontSize: 12),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Leading state button: number (idle), spinner (loading), pause/play.
class _LeadingState extends StatelessWidget {
  const _LeadingState({
    required this.isLoading,
    required this.isPlaying,
    required this.isPaused,
    required this.index,
  });

  final bool isLoading;
  final bool isPlaying;
  final bool isPaused;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 36,
      height: 36,
      child: Center(
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: scheme.primary,
                ),
              )
            : isPlaying || isPaused
            ? Icon(
                isPlaying ? Icons.pause_circle : Icons.play_circle,
                size: 30,
                color: scheme.primary,
              )
            : Text(
                '$index.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
      ),
    );
  }
}
