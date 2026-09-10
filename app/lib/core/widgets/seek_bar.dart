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

  double get _maxMs => widget.duration.inMilliseconds
      .clamp(1, double.maxFinite.toInt())
      .toDouble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = (widget.position.inMilliseconds / _maxMs).clamp(0.0, 1.0);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            widget.onSeek(
              (widget.position + const Duration(seconds: 10)).inMilliseconds
                  .clamp(0, _maxMs)
                  .toDouble(),
            ),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            widget.onSeek(
              (widget.position - const Duration(seconds: 10)).inMilliseconds
                  .clamp(0, _maxMs)
                  .toDouble(),
            ),
      },
      child: Focus(
        focusNode: _focusNode,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final box = context.findRenderObject()! as RenderBox;
            final ratio = (d.localPosition.dx / box.size.width).clamp(0.0, 1.0);
            widget.onSeek(ratio * _maxMs);
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
