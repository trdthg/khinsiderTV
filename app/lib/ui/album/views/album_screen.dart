import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../../core/platform/device.dart';
import '../../../core/widgets/dpad_nav.dart';
import '../../../core/widgets/dpad_tile.dart';
import '../../../data/preferences_store.dart';
import '../../../l10n/l10n.dart';
import '../../../state/track_cache_controller.dart';
import '../../../state/album_controller.dart';
import '../../../state/player_controller.dart';
import '../../now_playing/now_playing_art.dart';
import '../../shared/public_music.dart';
import '../../now_playing/osd_menu.dart';
import 'album_metadata.dart';
import 'album_track_list.dart';
import 'export_album_screen.dart';

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
  void _requestRowFocus(int index, {int attempts = 1, bool allowZen = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (!allowZen && _zen) || index >= _rowFocusNodes.length) {
        return;
      }
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
    // The zen layout replaces the whole page, so a single post-frame request
    // races the rebuild and used to leave the focus wherever it happened to be
    // (usually nowhere): retry, and keep the focused track = the one playing.
    _requestRowFocus(
      ref.read(playerControllerProvider).currentIndex ?? index,
      attempts: 12,
      allowZen: true,
    );
  }

  void _exitZen() {
    setState(() => _zen = false);
    _zenCtrl.reverse();
    // Back on the album page the remote lands on the track that was playing,
    // i.e. the one the user was looking at in zen mode.
    final i = ref.read(playerControllerProvider).currentIndex;
    if (i != null && i >= 0) _requestRowFocus(i, attempts: 12);
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
    final l = l10n(context);
    final detail = ref.watch(
      albumDetailProvider((widget.albumId, _refreshNonce)),
    );

    // The remote's back button (and the system back gesture) pops the route
    // directly instead of sending a key event, so zen mode has to intercept it
    // here: without this, back in zen mode left the album and landed on the
    // search screen. One back always means "one level out": menu -> zen ->
    // album -> search.
    return PopScope(
      canPop: !_zen && !_menuOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // Actually leaving the album: drop playback the same way the back
          // button does.
          _releaseAlbumPlayback(context, ref);
          return;
        }
        if (_menuOpen) {
          _toggleMenu();
        } else {
          _exitZen();
        }
      },
      child: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.albumLoadFailed('$e'), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => setState(() => _refreshNonce++),
                child: Text(l.actionRetry),
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
      ),
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
  /// The album's action buttons (favorite / download). Kept here because the
  /// cover and the track list both have to be able to point the D-pad at it:
  /// Flutter's default traversal picks by geometry and happily lands on a
  /// related album in the tail instead.
  final FocusNode _favoriteFocus = FocusNode(debugLabel: 'album-favorite');

  @override
  void dispose() {
    _favoriteFocus.dispose();
    super.dispose();
  }

  /// Leave the album: pop when there is a route to pop, otherwise fall back to
  /// the search screen.
  ///
  /// `maybePop` on the root route is a silent no-op, which used to make the
  /// back button (and Esc) look dead when the album screen happened to be the
  /// entry route.
  void _leave() {
    _releaseAlbumPlayback(context, ref);
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
                // The phone layout has no player UI of its own (the OSD menu is
                // zen-only), so the now-playing row doubles as a seek bar.
                enableScrub: true,
                // The album info lives ABOVE the track list, inside the same
                // scrollable — the phone layout must not lose the cover /
                // favorite button the way the bare title bar used to.
                header: _MobileAlbumHeader(album: album),
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
    final l = l10n(context);

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
      skipTraversal: true,
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
            skipTraversal: true,
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
                          child: ExcludeFocus(
                            excluding: widget.zen,
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
                                    tooltip: l.albumForceRefresh,
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
                      ),
                      // Morphing cover (D-Pad focusable; Enter toggles the
                      // menu in zen mode).
                      Positioned.fromRect(
                        rect: coverRect,
                        child: DpadNav(
                          right: widget.rowFocusNodes.isEmpty
                              ? null
                              : widget.rowFocusNodes.first,
                          // Down means "the album's own controls", which sit
                          // right below the cover. Without this the default
                          // traversal wanders into the track list and can land
                          // on a related album instead.
                          down: widget.zen ? null : _favoriteFocus,
                          child: DpadTile(
                            focusNode: widget.coverFocus,
                            autofocus: false,
                            onSelect: () {
                              if (widget.zen) {
                                widget.onToggleMenu();
                              }
                            },
                            child: NowPlayingArt(
                              coverUrl: album.imageUrl,
                              size: coverRect.width,
                              vinylOpacity: t,
                            ),
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
                            // In the normal layout the left neighbour the user
                            // wants is the album's controls (favorite,
                            // download), not the big picture: in normal mode
                            // Enter on the cover does nothing at all. Zen has
                            // no info panel, so there it stays the cover.
                            onLeftArrow: () =>
                                (widget.zen
                                        ? widget.coverFocus
                                        : _favoriteFocus)
                                    .requestFocus(),
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
                            child: ExcludeFocus(
                              excluding: widget.zen,
                              child: IgnorePointer(
                                ignoring: widget.zen,
                                child: _InfoPanel(
                                  album: album,
                                  favoriteFocus: _favoriteFocus,
                                  coverFocus: widget.coverFocus,
                                  firstRowFocus: widget.rowFocusNodes.isEmpty
                                      ? null
                                      : widget.rowFocusNodes.first,
                                ),
                              ),
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
  const _InfoPanel({
    required this.album,
    required this.favoriteFocus,
    required this.coverFocus,
    this.firstRowFocus,
  });

  final Album album;
  final FocusNode favoriteFocus;
  final FocusNode coverFocus;
  final FocusNode? firstRowFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = l10n(context);
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
          l.albumTrackCount(album.trackCount),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        // Up returns to the cover, Right jumps into the track list, so neither
        // column has to guess where the other one is.
        DpadNav(
          up: coverFocus,
          right: firstRowFocus,
          child: _FavoriteButton(
            album: album.summary,
            focusNode: favoriteFocus,
          ),
        ),
        // The download / export action. It used to be hidden on televisions,
        // which left the album page with a single button there.
        const SizedBox(height: 8),
        _ExportToMusicButton(album: album),
        if (album.metadata != null) ...[
          const SizedBox(height: 16),
          Text(
            l.albumDetailsTab,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          AlbumMetadataPanel(metadata: album.metadata!),
        ],
        const SizedBox(height: 16),
        _CacheFolderHint(album: album),
      ],
    );
  }
}

/// The album header used by the narrow (phone) layout: cover, title, track
/// count, favorite button and a collapsible details block, all rendered
/// ABOVE the track list.
///
/// It is a plain [Column] — the album screen drops it into
/// [AlbumTrackList.header], i.e. into the track list's own scroll view, so
/// the whole page scrolls as ONE list (no nested scrollables, and the info
/// scrolls away once the user starts reading the tracks).
class _MobileAlbumHeader extends ConsumerWidget {
  const _MobileAlbumHeader({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = l10n(context);
    final metadata = album.metadata;
    // One dim summary line, so the album is identifiable before the user
    // opens the details block.
    final summary = [
      if (album.summary.platforms.isNotEmpty)
        album.summary.platforms.join(', '),
      if (album.summary.year != null) album.summary.year!,
      if (metadata?.developedBy != null) metadata!.developedBy!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 104,
                  height: 104,
                  child: album.imageUrl == null
                      ? const _CoverPlaceholder()
                      : CachedNetworkImage(
                          imageUrl: album.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => const _CoverPlaceholder(),
                          errorWidget: (_, _, _) => const _CoverPlaceholder(),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.summary.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.albumTrackCount(album.trackCount),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (summary.isNotEmpty)
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Favorite and Export sit on ONE row under the cover, on the full
          // width of the screen. Inside the title column they only had the
          // leftover width (screen minus the 104 px cover), so the two buttons
          // wrapped onto two rows on every phone.
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _FavoriteButton(album: album.summary)),
              // The phone header is where this is discoverable: the
              // cache-folder row sits inside "Album details", which albums
              // without metadata do not even render.
              if (ref
                  .watch(audioCacheManagerProvider)
                  .supportsPublicMusicFolder) ...[
                const SizedBox(width: 8),
                Expanded(child: _ExportToMusicButton(album: album)),
              ],
            ],
          ),
          if (metadata != null) ...[
            const SizedBox(height: 6),
            Theme(
              // No dividers: the details block is part of the header, not a
              // separate card.
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 6),
                visualDensity: VisualDensity.compact,
                title: Text(
                  l.albumDetailsTitle,
                  style: theme.textTheme.titleSmall,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AlbumMetadataPanel(metadata: metadata),
                  ),
                  const SizedBox(height: 8),
                  // The cache-folder hint lives in here (collapsed by
                  // default) so the phone header stays short; the desktop
                  // side panel shows it inline as before. Only this (phone)
                  // layout offers the Android public-Music-folder switch, so
                  // the wide desktop/TV layout is untouched.
                  _CacheFolderHint(album: album, offerPublicMusic: true),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Placeholder shown while the cover loads / when the album has none.
class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
      child: const Center(child: Icon(Icons.music_note, size: 40)),
    );
  }
}

/// Favorite toggle that works for BOTH touch and D-Pad: the [DpadTile] owns
/// the gesture, the button underneath is inert (`IgnorePointer`) so a tap
/// cannot toggle twice.
class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.album, this.focusNode});

  final AlbumSummary album;

  /// Supplied by the wide layout, which points the cover and the track list at
  /// this node.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = l10n(context);
    final isFav =
        ref.watch(favoritesProvider).value?.any((a) => a.id == album.id) ??
        false;
    return DpadTile(
      focusNode: focusNode,
      borderRadius: 20,
      onSelect: () => ref.read(favoritesProvider.notifier).toggle(album),
      child: ExcludeFocus(
        child: IgnorePointer(
          child: FilledButton.tonalIcon(
            onPressed: () {},
            icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
            label: Text(isFav ? l.albumInFavorites : l.albumFavorite),
          ),
        ),
      ),
    );
  }
}

/// Where the cached tracks of this album end up on disk
/// (`Music/KHInsider/<Album>/mp3|flac|image|other`), so the user can find,
/// export, delete or play them with another player.
class _CacheFolderHint extends ConsumerWidget {
  const _CacheFolderHint({required this.album, this.offerPublicMusic = false});

  final Album album;

  /// Whether this layout may offer to store the cache in the system `Music/`
  /// folder. Only the phone layout sets it: the wide desktop/TV layout keeps
  /// its current look (there the one-off [PublicMusicPrompt] is the way in).
  final bool offerPublicMusic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = l10n(context);
    final albumId = album.summary.id;
    final cache = ref.watch(albumCacheProvider);
    if (cache.albumId != albumId) return const SizedBox.shrink();
    final path = cache.folderPath;
    final scheme = Theme.of(context).colorScheme;
    final text = path ?? l.albumPlayedSavedTo;
    final canRelocate =
        offerPublicMusic &&
        ref.watch(audioCacheManagerProvider).supportsPublicMusicFolder;
    // Exporting goes through MediaStore, so it needs no all-files-access
    // toggle — but only Android has that route, and a TV has no Music folder
    // to show it in. Phone layouts get their own button in the album header
    // instead (see _ExportToMusicButton), so this row does not repeat it.
    final canExport =
        ref.watch(audioCacheManagerProvider).supportsPublicMusicFolder &&
        !ref.watch(isTelevisionProvider) &&
        !offerPublicMusic;

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
              message: l.albumCacheKeptHere,
              waitDuration: const Duration(milliseconds: 350),
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (canExport)
            DpadIconButton(
              tooltip: l.albumExportHint,
              iconSize: 16,
              icon: Icons.library_music_outlined,
              onPressed: () => exportAlbumToMusic(context, ref, album),
            ),
          if (canRelocate)
            DpadIconButton(
              tooltip: l.albumSaveHint,
              iconSize: 16,
              icon: Icons.drive_file_move_outlined,
              onPressed: () => offerPublicMusicFolder(context, ref),
            ),
          DpadIconButton(
            tooltip: l.albumCopyPath,
            iconSize: 16,
            icon: Icons.copy,
            onPressed: path == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: path));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.albumCopied(path))),
                    );
                  },
          ),
        ],
      ),
    );
  }
}

/// Android only: copy this album's cached tracks into the system `Music/`
/// folder. The album header shows it on phone layouts, the cache row shows it
/// as an icon on wide ones, and a TV shows neither.
class _ExportToMusicButton extends ConsumerWidget {
  const _ExportToMusicButton({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Used to return nothing on televisions, which is where a user noticed the
    // album page offering only "Favorite".
    if (!ref.watch(audioCacheManagerProvider).supportsPublicMusicFolder) {
      return const SizedBox.shrink();
    }
    final l = l10n(context);
    return Tooltip(
      message: l.albumCopyExplain,
      child: FilledButton.tonalIcon(
        onPressed: () => exportAlbumToMusic(context, ref, album),
        icon: const Icon(Icons.library_music_outlined, size: 18),
        label: Text(l.albumExport),
      ),
    );
  }
}

/// Copies [album]'s cached tracks into `Music/KHInsider/<Album>`.
///
/// The files are contributed through MediaStore, which on Android 10+ needs no
/// permission at all — that is the whole point: the user does not have to flip
/// the "all files access" switch for their music to show up in the system music
/// library.
///
/// The copy runs on its own screen ([ExportAlbumScreen]) so the album page can
/// show progress and the result without a `Scaffold` of its own; see that file
/// and TODO.md I3 for why the flow does not live in a dialog here.
Future<void> exportAlbumToMusic(
  BuildContext context,
  WidgetRef ref,
  Album album,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ExportAlbumScreen(album: album)),
  );
}

/// Drops playback when the album screen is left on a TV.
///
/// Wide layouts have no mini player: the album page IS the player UI, so
/// popping back to the search screen with audio still running would leave
/// nothing on screen to control it. A phone keeps its mini player and only
/// pauses, exactly as before.
void _releaseAlbumPlayback(BuildContext context, WidgetRef ref) {
  final controller = ref.read(playerControllerProvider.notifier);
  if (MediaQuery.sizeOf(context).width > 700) {
    unawaited(controller.stop());
  } else {
    unawaited(controller.pause());
  }
}
