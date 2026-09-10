import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A focusable tile tuned for D-Pad / gamepad navigation (Android TV).
///
/// * Registers its own [FocusNode]; shows a scale + border highlight when
///   focused.
/// * `Select` (Enter / gamepad A) triggers [onSelect].
/// * Fully traversable with arrow keys via the default focus traversal.
class DpadTile extends StatefulWidget {
  const DpadTile({
    super.key,
    required this.child,
    required this.onSelect,
    this.autofocus = false,
    this.borderRadius = 12,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback onSelect;
  final bool autofocus;
  final double borderRadius;
  final FocusNode? focusNode;

  @override
  State<DpadTile> createState() => _DpadTileState();
}

class _DpadTileState extends State<DpadTile> {
  FocusNode? _ownedFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());
  bool _focused = false;

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FocusableActionDetector(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
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
