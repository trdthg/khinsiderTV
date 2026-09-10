import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Rotating vinyl disc peeking out behind the cover, with a breathing glow.
/// Animations are driven by controllers owned by the screen.
class NowPlayingArt extends StatelessWidget {
  const NowPlayingArt({
    super.key,
    required this.coverUrl,
    required this.spin,
    required this.glow,
    this.size = 300.0,
  });

  final String? coverUrl;
  final AnimationController spin;
  final double glow;

  /// Side length of the square cover (vinyl scales relative to it).
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverSize = size;

    return SizedBox(
      width: coverSize * 1.55,
      height: coverSize + 24,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Vinyl disc sliding out to the right of the cover.
          Positioned(
            left: coverSize * 0.55,
            child: RotationTransition(
              turns: spin,
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
                      color: scheme.primary.withValues(alpha: 0.35),
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
          // Cover art.
          Container(
            width: coverSize,
            height: coverSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.30 + 0.25 * glow),
                  blurRadius: 42,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: coverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          const Center(child: Icon(Icons.music_note, size: 48)),
                      errorWidget: (_, _, _) =>
                          const Center(child: Icon(Icons.music_note, size: 80)),
                    )
                  : const Center(child: Icon(Icons.music_note, size: 80)),
            ),
          ),
        ],
      ),
    );
  }
}
