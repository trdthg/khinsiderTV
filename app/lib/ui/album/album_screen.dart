import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../data/preferences_store.dart';
import '../../state/album_controller.dart';
import '../../state/player_controller.dart';
import '../now_playing/now_playing_art.dart';
import '../now_playing/osd_menu.dart';
import 'album_metadata.dart';
import 'album_track_list.dart';

/// Album detail screen with two modes on ONE page (no navigation):
///
///  * normal — header, info panel, related albums, track list;
///  * zen — immersive now-playing mode.
///
/// The cover and the track list are PERSISTENT elements: activating a track
/// starts playback and they MORPH (position + size animate) into their
/// now-playing positions while the info panel and related albums fly away.
/// Esc reverses the whole transition.
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key, required this.albumId});

  final String albumId;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen>
    with TickerProviderStateMixin {
  int _refreshNonce = 0;
  bool _zen = false;
  int _zenStartIndex = 0;
  bool _menuOpen = false;

  late final AnimationController _zenCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _zenT = CurvedAnimation(
    parent: _zenCtrl,
    curve: Curves.easeInOutCubic,
  );

  final _coverFocus = FocusNode(debugLabel: 'cover');
  final _menuPlayFocus = FocusNode(debugLabel: 'menu-play');
  List<FocusNode> _rowFocusNodes = const [];

  List<FocusNode> _ensureRowFocusNodes(int count) {
    if (_rowFocusNodes.length != count) {
      for (final n in _rowFocusNodes) {
        n.dispose();
      }
      _rowFocusNodes = List.generate(
        count,
        (i) => FocusNode(debugLabel: 'row-$i'),
      );
    }
    return _rowFocusNodes;
  }

  void _activateTrack(Album album, int index) {
    unawaited(
      ref
          .read(playerControllerProvider.notifier)
          .playAlbum(album, startIndex: index),
    );
    setState(() {
      _zenStartIndex = index;
      _zen = true;
    });
    _zenCtrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final i = ref.read(playerControllerProvider).currentIndex ?? index;
      if (i >= 0 && i < _rowFocusNodes.length) {
        _rowFocusNodes[i].requestFocus();
      }
    });
  }

  void _exitZen() {
    setState(() => _zen = false);
    _zenCtrl.reverse();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final i = ref.read(playerControllerProvider).currentIndex;
      if (i != null && i >= 0 && i < _rowFocusNodes.length) {
        _rowFocusNodes[i].requestFocus();
      }
    });
  }

  void _toggleMenu() {
    setState(() => _menuOpen = !_menuOpen);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_menuOpen) {
        _menuPlayFocus.requestFocus();
      } else {
        final i = ref.read(playerControllerProvider).currentIndex;
        if (i != null && i >= 0 && i < _rowFocusNodes.length) {
          _rowFocusNodes[i].requestFocus();
        }
      }
    });
  }

  @override
  void dispose() {
    _zenCtrl.dispose();
    _coverFocus.dispose();
    _menuPlayFocus.dispose();
    for (final n in _rowFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(
      albumDetailProvider((widget.albumId, _refreshNonce)),
    );

    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load album:\n$e', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => setState(() => _refreshNonce++),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (album) => _AlbumPage(
        album: album,
        zen: _zen,
        zenT: _zenT,
        zenStartIndex: _zenStartIndex,
        menuOpen: _menuOpen,
        rowFocusNodes: _ensureRowFocusNodes(album.tracks.length),
        coverFocus: _coverFocus,
        menuPlayFocus: _menuPlayFocus,
        onTrackActivated: (index) => _activateTrack(album, index),
        onExitZen: _exitZen,
        onToggleMenu: _toggleMenu,
        onRefresh: () => setState(() => _refreshNonce++),
      ),
    );
  }
}

class _AlbumPage extends ConsumerStatefulWidget {
  const _AlbumPage({
    required this.album,
    required this.zen,
    required this.zenT,
    required this.zenStartIndex,
    required this.menuOpen,
    required this.rowFocusNodes,
    required this.coverFocus,
    required this.menuPlayFocus,
    required this.onTrackActivated,
    required this.onExitZen,
    required this.onToggleMenu,
    required this.onRefresh,
  });

  final Album album;
  final bool zen;

  /// 0 = album layout, 1 = zen layout.
  final Animation<double> zenT;
  final int zenStartIndex;
  final bool menuOpen;
  final List<FocusNode> rowFocusNodes;
  final FocusNode coverFocus;
  final FocusNode menuPlayFocus;
  final ValueChanged<int> onTrackActivated;
  final VoidCallback onExitZen;
  final VoidCallback onToggleMenu;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends ConsumerState<_AlbumPage> {
  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final zenT = widget.zenT;

    // Esc: menu open -> close it; otherwise exit zen mode. This Focus is an
    // ancestor of everything in _AlbumPage (including the OSD menu), so
    // bubbled Esc events reach it.
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (widget.zen &&
            event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.gameButtonB)) {
          widget.menuOpen ? widget.onToggleMenu() : widget.onExitZen();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // Background content (unfocusable while the OSD menu is open).
          Focus(
            canRequestFocus: false,
            descendantsAreFocusable: !widget.menuOpen,
            child: LayoutBuilder(
              builder: (context, c) {
                final h = c.maxHeight;
                final w = c.maxWidth;
                final wide = w > 700;
                final headerH = 56.0;
                final t = zenT.value;
                final coverSize = math.min(252.0, h * 0.35);

                final coverNormal = Rect.fromLTWH(
                  24,
                  headerH + 8,
                  coverSize,
                  coverSize,
                );
                final coverZenSize = (w * 0.24).clamp(200.0, 320.0);
                final coverZen = Rect.fromCenter(
                  center: Offset(w * 0.25, h / 2),
                  width: coverZenSize,
                  height: coverZenSize,
                );
                final listNormal = Rect.fromLTWH(
                  292,
                  headerH + 8,
                  w - 292 - 12,
                  h - headerH - 8,
                );
                final listZen = Rect.fromLTWH(
                  w / 2 + 16,
                  (h - h * 0.8) / 2,
                  w / 2 - 16 - 32,
                  h * 0.8,
                );
                final coverRect = Rect.lerp(
                  coverNormal,
                  coverZen,
                  Curves.easeInOut.transform(t),
                )!;
                final listRect = Rect.lerp(
                  listNormal,
                  listZen,
                  Curves.easeInOut.transform(t),
                )!;

                final infoOpacity = (1 - t).clamp(0.0, 1.0);

                return Stack(
                  children: [
                    // Header (fades out in zen mode).
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: headerH,
                      child: Opacity(
                        opacity: (1 - t).clamp(0.0, 1.0),
                        child: IgnorePointer(
                          ignoring: widget.zen,
                          child: Row(
                            children: [
                              BackButton(onPressed: widget.zen ? null : () {}),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  album.summary.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Force refresh (bypass cache)',
                                onPressed: widget.zen ? null : widget.onRefresh,
                                icon: const Icon(Icons.refresh),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Morphing cover (D-Pad focusable; Enter toggles the
                    // menu in zen mode).
                    Positioned.fromRect(
                      rect: coverRect,
                      child: DpadTile(
                        focusNode: widget.coverFocus,
                        autofocus: false,
                        onSelect: () {
                          if (widget.zen) {
                            widget.onToggleMenu();
                          }
                        },
                        child: NowPlayingArt(
                          coverUrl: album.coverUrl,
                          size: coverRect.width,
                          vinylOpacity: t,
                        ),
                      ),
                    ),
                    // Morphing track list.
                    Positioned.fromRect(
                      rect: listRect,
                      child: AlbumTrackList(
                        album: album,
                        focusNodes: widget.rowFocusNodes,
                        onTrackActivated: widget.onTrackActivated,
                        showRelated: !widget.zen,
                      ),
                    ),
                    // Info panel (wide, normal mode only; flies away).
                    if (wide)
                      Positioned(
                        left: 24 - 360 * t,
                        top: headerH + 8 + coverSize + 12 + 200 * t,
                        width: 252,
                        child: Opacity(
                          opacity: infoOpacity,
                          child: IgnorePointer(
                            ignoring: widget.zen,
                            child: _InfoPanel(album: album),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          // OSD menu overlay (zen mode only) — OUTSIDE the background Focus
          // so its widgets stay focusable while the background is trapped.
          if (widget.zen && widget.menuOpen)
            OsdMenu(
              album: album,
              onClose: widget.onToggleMenu,
              playFocusNode: widget.menuPlayFocus,
            ),
        ],
      ),
    );
  }
}

class _InfoPanel extends ConsumerWidget {
  const _InfoPanel({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav =
        ref
            .watch(favoritesProvider)
            .value
            ?.any((a) => a.id == album.summary.id) ??
        false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          album.summary.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          '${album.trackCount} tracks',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () =>
              ref.read(favoritesProvider.notifier).toggle(album.summary),
          icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
          label: Text(isFav ? 'In favorites' : 'Favorite'),
        ),
        if (album.metadata != null) ...[
          const SizedBox(height: 16),
          Text('Details', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          AlbumMetadataPanel(metadata: album.metadata!),
        ],
      ],
    );
  }
}
