import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../state/player_controller.dart';
import 'related_albums.dart';

/// The unified track list, shared by the normal album layout and the zen
/// now-playing layout. The current row always shows its live state
/// (spinner / pause / play) and a playback-progress background fill.
class AlbumTrackList extends ConsumerWidget {
  const AlbumTrackList({
    super.key,
    required this.album,
    required this.focusNodes,
    required this.onTrackActivated,
    this.showRelated = true,
    this.onLeftArrow,
  });

  final Album album;
  final List<FocusNode> focusNodes;
  final ValueChanged<int> onTrackActivated;

  /// Related albums tail is only shown in the normal layout.
  final bool showRelated;

  /// Invoked when Left is pressed while focus is inside the list (used to
  /// hop to the cover in the zen layout).
  final VoidCallback? onLeftArrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
        // The cover sits left of the list but may not vertically overlap a
        // given row, so Left is bound explicitly as the menu entry point.
        if (onLeftArrow != null)
          const SingleActivator(LogicalKeyboardKey.arrowLeft): onLeftArrow!,
      },
      child: Material(
        type: MaterialType.transparency,
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: album.tracks.length + (showRelated ? 1 : 0),
          itemBuilder: (context, i) {
            if (showRelated && i == album.tracks.length) {
              return RelatedAlbumsRow(albums: album.relatedAlbums);
            }
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
                autofocus: i == 0 && !showRelated,
                borderRadius: 10,
                onSelect: () {
                  final notifier = ref.read(playerControllerProvider.notifier);
                  if (isLoading) {
                    notifier.cancelLoading();
                  } else if (isPlaying) {
                    notifier.pause();
                  } else if (isPaused) {
                    notifier.play();
                  } else {
                    onTrackActivated(i);
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
                        leading: SizedBox(
                          width: 36,
                          height: 36,
                          child: Center(
                            child: isLoading
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : isPlaying || isPaused
                                ? Icon(
                                    isPlaying
                                        ? Icons.pause_circle
                                        : Icons.play_circle,
                                    size: 30,
                                  )
                                : Text(
                                    '${track.index}.',
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                        ),
                        title: Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: track.duration != null
                            ? Text(track.duration!)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
