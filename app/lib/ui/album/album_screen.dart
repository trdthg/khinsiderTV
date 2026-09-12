import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../data/preferences_store.dart';
import '../../state/track_cache_controller.dart';
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
  bool _initialFocusDone = false;
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
  int _rowFocusCount = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final player = ref.read(playerControllerProvider);
      final current = player.current;
      if (current == null) return;
      if (current.album.summary.id == widget.albumId) return;
      unawaited(ref.read(playerControllerProvider.notifier).stop());
    });
  }

  /// Resizes the per-row focus nodes to [count].
  ///
  /// MUST NOT be called from `build()`: resizing disposes nodes that may
  /// still be attached to the previous frame (and possibly still focused),
  /// which throws "A FocusNode was used after being disposed". Surplus nodes
  /// are retired in a post-frame callback, once the tree has settled.
  List<FocusNode> _ensureRowFocusNodes(int count) {
    if (_rowFocusCount == count) return _rowFocusNodes;
    final retired = _rowFocusNodes.length > count
        ? _rowFocusNodes.sublist(count)
        : const <FocusNode>[];
    _rowFocusNodes = List<FocusNode>.generate(
      count,
      (i) => i < _rowFocusNodes.length
          ? _rowFocusNodes[i]
          : FocusNode(debugLabel: 'row-$i'),
    );
    _rowFocusCount = count;
    if (retired.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final n in retired) {
          n.dispose();
        }
      });
    }
    return _rowFocusNodes;
  }

  /// Puts the keyboard focus on the first track when the album opens.
  ///
  /// Nothing is played here — focus and playback are two different things.
  /// Without this the album page has NO focus at all, which means key events
  /// are delivered to the focus root and neither Esc nor the arrow keys do
  /// anything (see the page-level Focus below).
  void _focusFirstTrack() {
    if (_initialFocusDone || _zen) return;
    _initialFocusDone = true;
    _requestRowFocus(0, attempts: 12);
  }

  /// Focuses [index] after the current frame, retrying for a few frames.
  ///
  /// The retry matters because the page is usually pushed as a ROUTE: while
  /// the route transition runs, the navigator's own focus scope can grab the
  /// focus back, and a single post-frame request would be lost.
  void _requestRowFocus(int index, {int attempts = 1}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _zen || index >= _rowFocusNodes.length) return;
      final node = _rowFocusNodes[index];
      node.requestFocus();
      if (!node.hasFocus && attempts > 1) {
        _requestRowFocus(index, attempts: attempts - 1);
      }
    });
  }

  /// Points the cache-status controller at this album (post-frame: it is a
  /// side effect and must not run during build).
  void _syncCacheStatus(Album album) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(albumCacheProvider.notifier).sync(album));
    });
  }

  void _activateTrack(Album album, int index) {
    unawaited(
      ref
          .read(playerControllerProvider.notifier)
          .playAlbum(album, startIndex: index),
    );
    if (MediaQuery.sizeOf(context).width <= 700) {
      return;
    }

    setState(() {
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
      data: (album) {
        _focusFirstTrack();
        _syncCacheStatus(album);
        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: _AlbumPage(
            album: album,
            zen: _zen,
            zenT: _zenT,
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
      },
    );
  }
}

class _AlbumPage extends ConsumerStatefulWidget {
  const _AlbumPage({
    required this.album,
    required this.zen,
    required this.zenT,
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
  /// Leave the album: pop when there is a route to pop, otherwise fall back to
  /// the search screen.
  ///
  /// `maybePop` on the root route is a silent no-op, which used to make the
  /// back button (and Esc) look dead when the album screen happened to be the
  /// entry route.
  void _leave() {
    unawaited(ref.read(playerControllerProvider.notifier).pause());
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.maybePop();
    } else {
      navigator.pushReplacementNamed('/');
    }
  }

  /// Esc / gamepad B: menu open -> close it; otherwise exit zen mode.
  void _onBack() {
    if (widget.zen) {
      widget.menuOpen ? widget.onToggleMenu() : widget.onExitZen();
    } else {
      _leave();
    }
  }

  Widget _buildMobile(BuildContext context, Album album) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _leave();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  BackButton(onPressed: _leave),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      album.summary.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: AlbumTrackList(
                album: album,
                focusNodes: widget.rowFocusNodes,
                onTrackActivated: widget.onTrackActivated,
                showRelated: false,
                isZen: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final zenT = widget.zenT;

    if (MediaQuery.sizeOf(context).width <= 700) {
      return _buildMobile(context, album);
    }

    // This Focus is an ancestor of everything in _AlbumPage (including the
    // OSD menu), so Esc bubbled up from a focused row reaches it.
    //
    // It is also FOCUSABLE and autofocuses: with no focused widget at all
    // (right after entering the screen with a mouse, before the first row
    // took focus) key events are delivered to the focus root and this handler
    // would never see them. Being the fallback node is what makes Esc work
    // even when "there is no focus" on the page.
    return Focus(
      autofocus: true,
      debugLabel: 'album-page',
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.gameButtonB)) {
          _onBack();
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
            child: ListenableBuilder(
              listenable: widget.zenT,
              builder: (context, _) => LayoutBuilder(
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
                                BackButton(
                                  // Used to be `onPressed: widget.zen ? null
                                  // : ...`, which disabled the button in zen
                                  // mode; back always means "one level out".
                                  onPressed: _onBack,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    album.summary.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ),
                                DpadIconButton(
                                  tooltip: 'Force refresh (bypass cache)',
                                  icon: Icons.refresh,
                                  onPressed: widget.zen
                                      ? null
                                      : widget.onRefresh,
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
                      // Morphing track list. It moves to the right and is
                      // vertically centred by its own intrinsic height.
                      Positioned.fromRect(
                        rect: listRect,
                        child: Align(
                          alignment:
                              Alignment.lerp(
                                Alignment.topLeft,
                                Alignment.center,
                                Curves.easeInOut.transform(t),
                              ) ??
                              Alignment.topCenter,
                          child: AlbumTrackList(
                            album: album,
                            focusNodes: widget.rowFocusNodes,
                            onTrackActivated: widget.onTrackActivated,
                            // The tail must stay mounted while it flies away,
                            // otherwise it would pop out of the tree the moment
                            // zen starts (which is exactly what it used to do).
                            showRelated: !widget.zen || widget.zenT.value < 1.0,
                            zenT: widget.zenT,
                            isZen: widget.zen,
                          ),
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
        DpadTile(
          borderRadius: 20,
          onSelect: () =>
              ref.read(favoritesProvider.notifier).toggle(album.summary),
          child: ExcludeFocus(
            child: IgnorePointer(
              child: FilledButton.tonalIcon(
                onPressed: () {},
                icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
                label: Text(isFav ? 'In favorites' : 'Favorite'),
              ),
            ),
          ),
        ),
        if (album.metadata != null) ...[
          const SizedBox(height: 16),
          Text('Details', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          AlbumMetadataPanel(metadata: album.metadata!),
        ],
        const SizedBox(height: 16),
        _CacheFolderHint(albumId: album.summary.id),
      ],
    );
  }
}

/// Where the cached tracks of this album end up on disk
/// (`Music/KHInsider/<Album>/mp3|flac|image|other`), so the user can find,
/// export, delete or play them with another player.
class _CacheFolderHint extends ConsumerWidget {
  const _CacheFolderHint({required this.albumId});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(albumCacheProvider);
    if (cache.albumId != albumId) return const SizedBox.shrink();
    final path = cache.folderPath;
    final scheme = Theme.of(context).colorScheme;
    final text = path ?? 'Played tracks are saved to Music/KHInsider';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 6),
            child: Icon(Icons.folder_open, size: 16),
          ),
          Expanded(
            child: Tooltip(
              message:
                  'Cached files are kept here so you can find, export, '
                  'delete or play them with any other player.',
              waitDuration: const Duration(milliseconds: 350),
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          DpadIconButton(
            tooltip: 'Copy cache folder path',
            iconSize: 16,
            icon: Icons.copy,
            onPressed: path == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: path));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Copied: $path')));
                  },
          ),
        ],
      ),
    );
  }
}
