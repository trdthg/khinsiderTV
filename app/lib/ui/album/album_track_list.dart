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
    this.enableScrub = false,
    this.header,
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

  /// Turns the now-playing row into a seek bar (drag left/right, release to
  /// jump). Only the narrow phone layout asks for it: the phone has no player
  /// UI of its own (the OSD menu below is zen-only), so its progress fill is
  /// the only progress readout there is. Wide TV/desktop layouts keep the OSD
  /// menu's seek control and are deliberately left alone.
  final bool enableScrub;

  /// Optional content rendered as the FIRST child of the same scrollable —
  /// used by the narrow (phone) album layout to keep the album info above the
  /// tracks without nesting a second scroll view inside this one.
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final cache = ref.watch(albumCacheProvider);

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
          itemCount:
              (header == null ? 0 : 1) +
              album.tracks.length +
              (showRelatedRow ? 1 : 0),
          itemBuilder: (context, i) {
            if (header != null) {
              if (i == 0) return header!;
              i -= 1;
            }
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
                  child: _ScrubLayer(
                    // Only the now-playing row of the phone layout is a seek
                    // bar; every other row (and both wide layouts) is exactly
                    // what it was before.
                    enabled: enableScrub && isCurrent,
                    highlight: isCurrent,
                    progress: progress,
                    position: player.position,
                    duration: player.duration,
                    onSeek: (target) => ref
                        .read(playerControllerProvider.notifier)
                        .seek(target),
                    child: ListTile(
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

/// The playback-progress background of a row — and, on the phone layout, the
/// seek bar the now-playing row doubles as.
///
/// Dragging horizontally moves the fill under the finger and shows a readout
/// pill with where the jump would land; the seek itself is committed **once**,
/// on release. That split is not just about feel: seeking here is not free.
/// The audio is played through `LockCachingAudioSource`, whose local proxy
/// answers a range request from the downloaded prefix instantly but has to
/// wait for the sequential download to reach a position that is not on disk
/// yet — so seeking on every drag update would stall the player behind the
/// finger instead of following it.
///
/// A touch that never moves is not a drag: the gesture arena gives it to
/// [DpadTile]'s tap recognizer, so tapping the now-playing row still means
/// play/pause. Nothing is attached at all when [enabled] is false, which is
/// every row but the current one and every layout but the phone's.
class _ScrubLayer extends StatefulWidget {
  const _ScrubLayer({
    required this.enabled,
    required this.highlight,
    required this.progress,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.child,
  });

  /// Whether this row accepts the scrub gesture (phone layout + current row).
  final bool enabled;

  /// Whether the row is the now-playing one (it keeps its tint either way).
  final bool highlight;

  /// Playback progress, 0..1, from the player.
  final double progress;

  /// Playback position, shown in the readout before the first drag update.
  final Duration position;

  /// Total length; without it there is nothing to seek within.
  final Duration? duration;

  final ValueChanged<Duration> onSeek;
  final Widget child;

  @override
  State<_ScrubLayer> createState() => _ScrubLayerState();
}

class _ScrubLayerState extends State<_ScrubLayer> {
  /// Where the finger is, as a 0..1 fraction; null when not scrubbing.
  double? _scrub;

  /// Milliseconds the row spans, or null while the duration is unknown.
  double? get _maxMs {
    final ms = widget.duration?.inMilliseconds ?? 0;
    return ms > 0 ? ms.toDouble() : null;
  }

  bool get _canScrub => widget.enabled && _maxMs != null;

  /// Maps a pointer position inside the row to a 0..1 fraction of its width.
  double? _fractionAt(Offset local) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.width <= 0) return null;
    return (local.dx / box.size.width).clamp(0.0, 1.0);
  }

  void _onDragStart(DragStartDetails details) {
    final fraction = _fractionAt(details.localPosition);
    if (fraction == null) return;
    HapticFeedback.selectionClick();
    setState(() => _scrub = fraction);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_scrub == null) return; // started outside the row: ignore the drag
    final fraction = _fractionAt(details.localPosition);
    if (fraction == null) return;
    setState(() => _scrub = fraction);
  }

  void _onDragEnd(DragEndDetails details) {
    final fraction = _scrub;
    final maxMs = _maxMs;
    if (_scrub != null) setState(() => _scrub = null);
    if (fraction == null || maxMs == null) return;
    widget.onSeek(Duration(milliseconds: (maxMs * fraction).round()));
  }

  void _onDragCancel() {
    if (_scrub != null) setState(() => _scrub = null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scrub = _scrub;
    final maxMs = _maxMs;
    // While dragging, the fill follows the finger instead of the player.
    final fill = (scrub ?? widget.progress).clamp(0.0, 1.0);
    final target = scrub == null || maxMs == null
        ? null
        : Duration(milliseconds: (maxMs * scrub).round());

    final content = Stack(
      children: [
        if (widget.highlight)
          Positioned.fill(
            child: ColoredBox(color: scheme.primary.withValues(alpha: 0.10)),
          ),
        if (fill > 0)
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fill,
              child: ColoredBox(
                color: scheme.primary.withValues(
                  alpha: scrub == null ? 0.22 : 0.30,
                ),
              ),
            ),
          ),
        widget.child,
        if (target != null)
          Positioned(
            top: 0,
            bottom: 0,
            right: 8,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.6),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    '${_formatTime(target)} / ${_formatTime(widget.duration!)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (!_canScrub) return content;
    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      child: content,
    );
  }
}

/// `m:ss`, or `h:mm:ss` past the hour (game OSTs have long tracks).
String _formatTime(Duration d) {
  final seconds = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h == 0) return '$m:$ss';
  return '$h:${m.toString().padLeft(2, '0')}:$ss';
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
