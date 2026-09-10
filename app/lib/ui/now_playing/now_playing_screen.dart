import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../state/player_controller.dart';
import '../../state/ui_state.dart';
import 'now_playing_art.dart';
import 'osd_menu.dart';
import 'track_list_pane.dart';

/// Immersive fullscreen playback: album art (animated) on the left, track
/// list on the right. The bottom PlayerBar is hidden while this screen is
/// open (immersion). Controls:
///   * OK/Enter on the cover (or tap) -> OSD menu (seek / pause / quality /
///     theme). Esc closes the menu, second Esc exits back to the album page.
///   * Enter on a track row plays that track.
///   * Esc with the menu closed exits fullscreen.
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({
    super.key,
    required this.album,
    this.initialTrackIndex = 0,
  });

  final Album album;

  /// Album index of the track the user just activated, so keyboard focus
  /// lands on the PLAYING row (Down then walks to the next track).
  final int initialTrackIndex;

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen>
    with TickerProviderStateMixin {
  bool _menuOpen = false;

  final _coverFocus = FocusNode(debugLabel: 'np-cover');
  final _menuPlayFocus = FocusNode(debugLabel: 'np-menu-play');

  /// One focus node per track row, owned by the screen so it can steer
  /// focus (initial focus = playing row; Down on cover jumps here too).
  late final List<FocusNode> _rowFocusNodes = List.generate(
    widget.album.tracks.length,
    (i) => FocusNode(debugLabel: 'np-row-$i'),
  );

  FocusNode get _currentRowNode {
    final i =
        ref.read(playerControllerProvider).currentIndex ??
        widget.initialTrackIndex;
    if (i >= 0 && i < _rowFocusNodes.length) return _rowFocusNodes[i];
    return _rowFocusNodes.first;
  }

  /// Cached in initState: [ref] must not be used from dispose().
  FullscreenController? _fullscreenController;

  late final AnimationController _floatCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();
  late final AnimationController _spinCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );
  late final AnimationController _glowCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _fullscreenController = ref.read(fullscreenProvider.notifier);
    // Spin the vinyl only while audio is playing.
    ref.listenManual(playerControllerProvider, (_, next) {
      if (next.playing) {
        if (!_spinCtrl.isAnimating) _spinCtrl.repeat();
      } else {
        _spinCtrl.stop();
      }
    }, fireImmediately: true);

    // autofocus is not enough: the previous screen may already hold focus.
    // Initial focus goes to the PLAYING track's row so Down walks to the
    // next track immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _currentRowNode.requestFocus();
    });
  }

  @override
  void dispose() {
    // Deferred: Riverpod forbids provider mutation inside dispose.
    Future.microtask(() => _fullscreenController?.hide());
    _coverFocus.dispose();
    _menuPlayFocus.dispose();
    for (final n in _rowFocusNodes) {
      n.dispose();
    }
    _floatCtrl.dispose();
    _spinCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() => _menuOpen = !_menuOpen);
    // Both branches must wait for the post-frame state: opening mounts the
    // menu (its nodes don't exist yet), closing re-enables background focus
    //ability (the request would be swallowed before the rebuild).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_menuOpen ? _menuPlayFocus : _currentRowNode).requestFocus();
    });
  }

  Future<void> _exitFullscreen() async => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final scheme = Theme.of(context).colorScheme;

    return Focus(
      // Not focusable itself: it only listens for Esc bubbling up from
      // descendants. Initial focus goes to the cover tile.
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.gameButtonB)) {
          if (_menuOpen) {
            _toggleMenu();
          } else {
            _exitFullscreen();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        key: const ValueKey('now-playing'),
        backgroundColor: const Color(0xFF0A0A0F),
        body: Stack(
          children: [
            // Ambient background glow, pulsing with the beat.
            AnimatedBuilder(
              animation: _glowCtrl,
              builder: (context, _) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.55, -0.2),
                    radius: 1.3,
                    colors: [
                      scheme.primary.withValues(
                        alpha: 0.22 + 0.12 * _glowCtrl.value,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            // Modal focus isolation: while the OSD menu is open, the
            // background (cover + track list) cannot take focus at all, so
            // arrow keys / Tab / Enter can never reach items under the dim.
            Focus(
              canRequestFocus: false,
              descendantsAreFocusable: !_menuOpen,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, c) {
                    // Wide: art left / list right, each ~half the width.
                    // Narrow (phone portrait): art on top, list below.
                    final narrow = c.maxWidth < 720;
                    final artPane = SizedBox(
                      width: narrow ? double.infinity : c.maxWidth * 0.5,
                      height: narrow ? c.maxHeight * 0.42 : double.infinity,
                      child: Center(
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(
                              LogicalKeyboardKey.arrowDown,
                            ): () =>
                                _currentRowNode.requestFocus(),
                          },
                          child: DpadTile(
                            focusNode: _coverFocus,
                            autofocus: false,
                            onSelect: _toggleMenu,
                            child: AnimatedBuilder(
                              animation: Listenable.merge([
                                _floatCtrl,
                                _glowCtrl,
                              ]),
                              builder: (context, _) {
                                final t = _floatCtrl.value * 2 * math.pi;
                                final artSize = narrow
                                    ? (c.maxWidth * 0.6).clamp(140.0, 260.0)
                                    : (c.maxWidth * 0.5 * 0.62).clamp(
                                        160.0,
                                        300.0,
                                      );
                                return Transform.translate(
                                  offset: Offset(0, math.sin(t) * 7),
                                  child: Transform.scale(
                                    scale:
                                        1.0 + 0.015 * math.sin(t + math.pi / 3),
                                    child: Hero(
                                      tag: 'cover-${album.summary.id}',
                                      child: NowPlayingArt(
                                        coverUrl: album.coverUrl,
                                        spin: _spinCtrl,
                                        glow: _glowCtrl.value,
                                        size: artSize,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                    final listPane = Padding(
                      padding: EdgeInsets.only(right: narrow ? 16 : 32),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: c.maxHeight * 0.8,
                          ),
                          child: NowPlayingTrackList(
                            album: album,
                            focusNodes: _rowFocusNodes,
                            coverFocusNode: _coverFocus,
                          ),
                        ),
                      ),
                    );
                    return narrow
                        ? Column(
                            children: [
                              artPane,
                              Expanded(child: listPane),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: artPane),
                              Expanded(child: listPane),
                            ],
                          );
                  },
                ),
              ),
            ),
            // ------- OSD menu -------
            if (_menuOpen)
              OsdMenu(
                album: album,
                onClose: _toggleMenu,
                playFocusNode: _menuPlayFocus,
              ),
          ],
        ),
      ),
    );
  }
}
