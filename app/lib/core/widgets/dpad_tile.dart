import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A focusable tile tuned for D-Pad / gamepad navigation (Android TV).
///
/// * Registers its own [FocusNode]; shows a scale + border highlight when
///   focused.
/// * `Select` (Enter / gamepad A) triggers [onSelect].
/// * Fully traversable with arrow keys via the default focus traversal.
/// * Mouse users get the same affordance as a D-Pad user: hovering a tile
///   highlights it AND moves keyboard focus onto it (see [hoverFocus]), so
///   "hover, then press Enter" always activates the tile under the cursor.
class DpadTile extends StatefulWidget {
  const DpadTile({
    super.key,
    required this.child,
    required this.onSelect,
    this.autofocus = false,
    this.borderRadius = 12,
    this.focusNode,
    this.hoverFocus = true,
  });

  final Widget child;
  final VoidCallback onSelect;
  final bool autofocus;
  final double borderRadius;
  final FocusNode? focusNode;

  /// Whether hovering moves keyboard focus to this tile. Keep it on unless a
  /// host screen manages focus itself.
  final bool hoverFocus;

  @override
  State<DpadTile> createState() => _DpadTileState();
}

class _DpadTileState extends State<DpadTile> {
  FocusNode? _ownedFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _onHoverHighlight(bool hovered) {
    if (!mounted || _hovered == hovered) return;
    setState(() => _hovered = hovered);
    if (hovered && widget.hoverFocus && !_focusNode.hasFocus) {
      // Same contract as the mouse click below: the keyboard focus follows the
      // pointer, otherwise Enter would still activate the previously focused
      // row.
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FocusableActionDetector(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: _onHoverHighlight,
      onFocusChange: (_) {},
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Mouse clicks must move keyboard focus too, otherwise Enter/Space
          // keep activating the autofocused row instead of the clicked one.
          _focusNode.requestFocus();
          widget.onSelect();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            // Hover feedback for mouse users (focus keeps its own, stronger
            // look): a faint fill, so a row is still recognisable while the
            // focus ring animates in.
            color: _hovered && !_focused
                ? scheme.onSurface.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          // Draw the ring on top of the child, otherwise an opaque
          // Card/IconButton child covers the inner part of the border and
          // the highlight looks chipped.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              width: _focused ? 2.5 : 0,
              color: _focused ? scheme.primary : Colors.transparent,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.35),
                      blurRadius: 16,
                    ),
                  ]
                : const [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Icon button that uses the same focus ring/traversal as [DpadTile],
/// instead of Material IconButton overlay.
class DpadIconButton extends StatelessWidget {
  const DpadIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.filled = false,
    this.iconSize = 24,
    this.focusNode,
    this.borderRadius = 24,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool filled;
  final double iconSize;
  final FocusNode? focusNode;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final handler = onPressed;
    final enabled = handler != null;
    final button = DpadTile(
      focusNode: focusNode,
      borderRadius: borderRadius,
      onSelect: () {
        if (handler != null) handler();
      },
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Container(
          width: iconSize + 20,
          height: iconSize + 20,
          alignment: Alignment.center,
          decoration: filled
              ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
              : null,
          child: Icon(
            icon,
            size: iconSize,
            color: filled ? scheme.onPrimary : null,
          ),
        ),
      ),
    );
    final message = tooltip;
    return message == null ? button : Tooltip(message: message, child: button);
  }
}
