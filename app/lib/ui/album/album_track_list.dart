import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';
import '../../core/widgets/dpad_tile.dart';
import '../../state/player_controller.dart';
import '../../state/track_cache_controller.dart';
import 'related_albums.dart';

/// The unified track list, shared by the normal album layout and the zen
/// now-playing layout. The current row always shows its live state
/// (spinner / pause / play) and a playback-progress background fill.
///
/// Every row also shows its **cache state** at the right edge, and the related
/// albums tail animates out (instead of popping away) while the screen morphs
/// into zen mode.
class AlbumTrackList extends ConsumerWidget {
  const AlbumTrackList({
    super.key,
    required this.album,
    required this.focusNodes,
    required this.onTrackActivated,
    this.showRelated = true,
    this.onLeftArrow,
    this.zenT,
    this.isZen = false,
  });

  final Album album;
  final List<FocusNode> focusNodes;
  final ValueChanged<int> onTrackActivated;

  /// Related albums tail is only shown in the normal layout.
  final bool showRelated;

  /// Invoked when Left is pressed while focus is inside the list (used to
  /// hop to the cover in the zen layout).
  final VoidCallback? onLeftArrow;

  /// 0 = album layout, 1 = zen layout. Drives the related-albums fly-out;
  /// null outside of the album screen.
  final Animation<double>? zenT;

  /// Whether the morph is currently in its zen/playback layout.
  final bool isZen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final cache = ref.watch(albumCacheProvider);
    final scheme = Theme.of(context).colorScheme;

    // The tail stays mounted while it flies away, and disappears for good
    // once the morph is over (zenT == 1).
    final exitT = zenT?.value ?? 0.0;
    final showRelatedRow =
        showRelated && album.relatedAlbums.isNotEmpty && exitT < 1.0;

    void cycleRow(int delta) {
      if (focusNodes.isEmpty) return;
      var current = focusNodes.indexWhere((node) => node.hasFocus);
      if (current < 0) current = delta > 0 ? -1 : 0;
      final next = (current + delta + focusNodes.length) % focusNodes.length;
      focusNodes[next].requestFocus();
    }

    return CallbackShortcuts(
      bindings: {
        // The cover sits left of the list but may not vertically overlap a
        // given row, so Left is bound explicitly as the menu entry point.
        const SingleActivator(LogicalKeyboardKey.arrowLeft): ?onLeftArrow,
        if (isZen)
          const SingleActivator(LogicalKeyboardKey.tab): () => cycleRow(1),
        if (isZen)
          const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
              cycleRow(-1),
      },
      child: Material(
        type: MaterialType.transparency,
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: album.tracks.length + (showRelatedRow ? 1 : 0),
          itemBuilder: (context, i) {
            if (showRelatedRow && i == album.tracks.length) {
              return RelatedAlbumsRow(
                albums: album.relatedAlbums,
                exitT: exitT,
              );
            }
            final track = album.tracks[i];
            final currentEntry = player.current;
            final isCurrent =
                player.currentIndex == i &&
                currentEntry != null &&
                currentEntry.album.summary.id == album.summary.id;
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
                  if (!isZen) {
                    onTrackActivated(i);
                    return;
                  }
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
                                ? const SizedBox(
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
                        // Right-aligned cache badge: is this track already on
                        // disk, still downloading, or network-only?
                        trailing: _CacheBadge(entry: cache.tracks[track.index]),
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

/// Right-aligned per-track cache indicator.
///
/// * `cloud` (dim)    — not cached, will stream from the network;
/// * spinner          — a download is in flight (partial file on disk);
/// * `download_done`  — cached, and `FLAC` is appended when the lossless copy
///   is on disk too.
class _CacheBadge extends StatelessWidget {
  const _CacheBadge({required this.entry});
  final TrackCacheEntry? entry;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = entry ?? TrackCacheEntry.empty;
    final text = state.isEmpty
        ? 'Not cached yet — plays from the network'
        : state.downloading
        ? 'Downloading to Music/KHInsider…'
        : 'Cached in Music/KHInsider${_sizeSuffix(state)}';
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 350),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: state.isEmpty
            ? Icon(
                Icons.cloud_outlined,
                size: 18,
                color: scheme.onSurface.withValues(alpha: 0.22),
              )
            : state.downloading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.hasLossless)
                    Text(
                      'FLAC',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Icon(Icons.download_done, size: 18, color: scheme.primary),
                ],
              ),
      ),
    );
  }

  String _sizeSuffix(TrackCacheEntry state) {
    if (state.bytes <= 0) return '';
    return ' · ${_formatBytes(state.bytes)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
