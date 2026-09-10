import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../state/player_controller.dart';
import 'now_playing_art.dart';
import 'osd_menu.dart';
import 'track_list_pane.dart';

/// Immersive "zen" now-playing layout embedded INSIDE the album page.
///
/// The album page cross-fades into this view when playback starts (see
/// AlbumScreen's zen transition); Esc pops back to the normal album layout.
/// Owns the OSD menu, the modal focus trap and all playback-row focus nodes.
class ZenNowPlaying extends ConsumerStatefulWidget {
  const ZenNowPlaying({
    super.key,
    required this.album,
    required this.active,
    required this.initialTrackIndex,
    required this.onExitZen,
  });

  final Album album;

  /// True while the parent shows this view fullscreen-ish. Used to grab
  /// focus when activated.
  final bool active;

  final int initialTrackIndex;
  final VoidCallback onExitZen;

  @override
  ConsumerState<ZenNowPlaying> createState() => _ZenNowPlayingState();
}

class _ZenNowPlayingState extends ConsumerState<ZenNowPlaying>
    with TickerProviderStateMixin {
  bool _menuOpen = false;

  final _coverFocus = FocusNode(debugLabel: 'np-cover');
  final _menuPlayFocus = FocusNode(debugLabel: 'np-menu-play');

  /// One focus node per track row, owned here so focus can be steered
  /// (initial focus = playing row; Down on cover jumps here too).
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

  late final AnimationController _floatCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  late final AnimationController _spinCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );
  late final AnimationController _glowCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    ref.listenManual(playerControllerProvider, (_, next) {
      if (next.playing) {
        if (!_spinCtrl.isAnimating) _spinCtrl.repeat();
      } else {
        _spinCtrl.stop();
      }
    }, fireImmediately: true);
    _applyActivity();
    // When activated, grab focus onto the playing row.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _currentRowNode.requestFocus();
    });
  }

  /// Infinite animations only run while this view is the active mode —
  /// otherwise pumpAndSettle never settles (tests) and the GPU burns cycles
  /// for an invisible layer.
  void _applyActivity() {
    if (widget.active) {
      if (!_floatCtrl.isAnimating) _floatCtrl.repeat();
      if (!_glowCtrl.isAnimating) _glowCtrl.repeat(reverse: true);
    } else {
      _floatCtrl.stop();
      _glowCtrl.stop();
      _spinCtrl.stop();
    }
  }

  @override
  void didUpdateWidget(ZenNowPlaying old) {
    super.didUpdateWidget(old);
    _applyActivity();
    if (!old.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _currentRowNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_menuOpen ? _menuPlayFocus : _currentRowNode).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final scheme = Theme.of(context).colorScheme;

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.gameButtonB)) {
          if (_menuOpen) {
            _toggleMenu();
          } else {
            widget.onExitZen();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        key: const ValueKey('zen-now-playing'),
        backgroundColor: Colors.transparent,
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
            // Modal focus isolation: while the OSD menu is open, the cover and
            // track list cannot take focus at all.
            Focus(
              canRequestFocus: false,
              descendantsAreFocusable: !_menuOpen,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, c) {
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
                                    child: NowPlayingArt(
                                      coverUrl: album.coverUrl,
                                      spin: _spinCtrl,
                                      glow: _glowCtrl.value,
                                      size: artSize,
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
            if (_menuOpen)
              OsdMenu(
                album: album,
                onClose: _toggleMenu,
                playFocusNode: _menuPlayFocus,
              ),
          ],
        ),
      ), // Scaffold body
    );
  }
}
