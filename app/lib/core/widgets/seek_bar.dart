import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lightweight seek bar without Material Slider's Overlay dependency
/// (the player bar lives above the Navigator). TV-friendly: tap/click to
/// seek; when focused, arrow Left/Right seek ±10 s.
///
/// On a touch screen dragging adjusts **relative** to where the finger went
/// down instead of snapping the thumb under it: a fingertip covers 40-odd
/// pixels of a bar that may only be 300 wide, so absolute positioning makes a
/// short track impossible to fine-tune. A tap still jumps to the tapped spot.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.relativeDrag,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<double> onSeek; // milliseconds

  /// Whether a drag adjusts relative to the touch-down point. Defaults to the
  /// platform answer ([_relativeDrag]); overridable so the behaviour can be
  /// tested on a desktop host.
  final bool? relativeDrag;

  @override
  State<SeekBar> createState() => SeekBarState();
}

class SeekBarState extends State<SeekBar> {
  final _focusNode = FocusNode(debugLabel: 'seek-bar-focus');
  bool _focused = false;

  /// Where a drag is heading, in milliseconds. The bar renders this instead of
  /// the player's position while dragging and only seeks once on release, so a
  /// long scrub is one seek instead of dozens.
  double? _dragMs;

  /// Touch devices scrub relative to the touch-down point; a mouse or remote
  /// drags the thumb to the pointer, which is what those users expect.
  bool get _relativeDrag =>
      widget.relativeDrag ?? (Platform.isAndroid || Platform.isIOS);

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

  double? get _width {
    final box = context.findRenderObject();
    if (box is! RenderBox) return null;
    final width = box.size.width;
    return width <= 0 ? null : width;
  }

  void _onDragStart(DragStartDetails details) {
    if (_maxMs == null) return;
    setState(() => _dragMs = widget.position.inMilliseconds.toDouble());
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final maxMs = _maxMs;
    final width = _width;
    final current = _dragMs;
    if (maxMs == null || width == null || current == null) return;
    final perPixel = maxMs / width;
    final next = _relativeDrag
        ? current + details.delta.dx * perPixel
        : details.localPosition.dx * perPixel;
    setState(() => _dragMs = next.clamp(0.0, maxMs));
  }

  void _onDragEnd(DragEndDetails details) {
    final target = _dragMs;
    setState(() => _dragMs = null);
    if (target != null) widget.onSeek(target);
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
    final shownMs = _dragMs ?? widget.position.inMilliseconds.toDouble();
    final progress = maxMs == null ? 0.0 : (shownMs / maxMs).clamp(0.0, 1.0);

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
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: () => setState(() => _dragMs = null),
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
                height: _focused || _dragMs != null ? 8 : 5,
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
