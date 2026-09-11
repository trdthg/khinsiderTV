import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/player_controller.dart';

/// Self-contained animated album art: floating cover with a breathing glow
/// and a vinyl disc that slides out behind it while playing.
///
/// [vinylOpacity] fades the vinyl/glow in (0 = plain cover, e.g. normal
/// album layout; 1 = full zen presentation).
class NowPlayingArt extends ConsumerStatefulWidget {
  const NowPlayingArt({
    super.key,
    required this.coverUrl,
    required this.size,
    this.vinylOpacity = 1,
  });

  final String? coverUrl;
  final double size;
  final double vinylOpacity;

  @override
  ConsumerState<NowPlayingArt> createState() => _NowPlayingArtState();
}

class _NowPlayingArtState extends ConsumerState<NowPlayingArt>
    with TickerProviderStateMixin {
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

  bool _playing = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(playerControllerProvider, (_, next) {
      _playing = next.playing;
      _syncAnimations();
    }, fireImmediately: true);
  }

  @override
  void didUpdateWidget(NowPlayingArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimations();
  }

  void _ensureFloatRunning() {
    if (_floatCtrl.isAnimating) return;
    _floatCtrl.repeat();
  }

  void _ensureGlowRunning() {
    if (_glowCtrl.isAnimating) return;
    _glowCtrl.repeat(reverse: true);
  }

  void _ensureSpinRunning() {
    if (_spinCtrl.isAnimating) return;
    _spinCtrl.repeat();
  }

  void _syncAnimations() {
    final zen = widget.vinylOpacity > 0;
    if (zen) {
      _ensureFloatRunning();
      _ensureGlowRunning();
      if (_playing) {
        _ensureSpinRunning();
      } else {
        _spinCtrl.stop();
      }
    } else {
      _floatCtrl.stop();
      _glowCtrl.stop();
      _spinCtrl.stop();
    }
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _spinCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverSize = widget.size;
    final v = widget.vinylOpacity;

    return AnimatedBuilder(
      animation: Listenable.merge([_floatCtrl, _glowCtrl, _spinCtrl]),
      builder: (context, _) {
        final t = _floatCtrl.value * 2 * math.pi;
        return Transform.translate(
          offset: Offset(0, math.sin(t) * 7 * v),
          child: Transform.scale(
            scale: 1.0 + 0.015 * math.sin(t + math.pi / 3) * v,
            child: SizedBox(
              width: coverSize * (1 + 0.55 * v),
              height: coverSize + 24 * v,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  if (v > 0)
                    Positioned(
                      left: coverSize * 0.55,
                      child: RotationTransition(
                        turns: _spinCtrl,
                        child: Opacity(
                          opacity: v,
                          child: Container(
                            width: coverSize * 0.95,
                            height: coverSize * 0.95,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  scheme.primary.withValues(alpha: 0.9),
                                  const Color(0xFF15151C),
                                  const Color(0xFF0B0B10),
                                ],
                                stops: const [0, 0.12, 1],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.primary.withValues(
                                    alpha: 0.35 * v,
                                  ),
                                  blurRadius: 30,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF0A0A0F),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    width: coverSize,
                    height: coverSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(
                            alpha: 0.18 + 0.22 * v * _glowCtrl.value,
                          ),
                          blurRadius: 42,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: widget.coverUrl != null
                          ? CachedNetworkImage(
                              imageUrl: widget.coverUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => const Center(
                                child: Icon(Icons.music_note, size: 48),
                              ),
                              errorWidget: (_, _, _) => const Center(
                                child: Icon(Icons.music_note, size: 80),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.music_note, size: 80),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
