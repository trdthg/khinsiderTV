import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lightweight seek bar without Material Slider's Overlay dependency
/// (the player bar lives above the Navigator). TV-friendly: tap/click to
/// seek; when focused, arrow Left/Right seek ±10 s.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<double> onSeek; // milliseconds

  @override
  State<SeekBar> createState() => SeekBarState();
}

class SeekBarState extends State<SeekBar> {
  final _focusNode = FocusNode(debugLabel: 'seek-bar-focus');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(
      () => mounted ? setState(() => _focused = _focusNode.hasFocus) : null,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Milliseconds the bar spans, or null while the duration is unknown.
  /// Returning null (rather than clamping to 1ms) is what keeps the bar from
  /// rendering as completely full while a track is still buffering.
  double? get _maxMs {
    final ms = widget.duration.inMilliseconds;
    if (ms <= 0) return null;
    return ms.toDouble();
  }

  /// Seek relative to the current position, clamped to the loaded duration.
  void _seekBy(Duration delta) {
    final maxMs = _maxMs;
    if (maxMs == null) return;
    final target = (widget.position + delta).inMilliseconds.clamp(
      0,
      maxMs.toInt(),
    );
    widget.onSeek(target.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxMs = _maxMs;
    final progress = maxMs == null
        ? 0.0
        : (widget.position.inMilliseconds / maxMs).clamp(0.0, 1.0);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _seekBy(const Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _seekBy(const Duration(seconds: -10)),
      },
      child: Focus(
        focusNode: _focusNode,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final maxMs = _maxMs;
            if (maxMs == null) return; // nothing loaded to seek within
            final box = context.findRenderObject()! as RenderBox;
            final ratio = (d.localPosition.dx / box.size.width).clamp(0.0, 1.0);
            widget.onSeek(ratio * maxMs);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: _focused ? 8 : 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: scheme.surfaceContainerHighest,
                  border: _focused
                      ? Border.all(color: scheme.primary, width: 1.5)
                      : null,
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
