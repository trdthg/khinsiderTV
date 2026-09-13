import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Moves the D-Pad focus to explicit neighbours instead of letting Flutter
/// guess.
///
/// Flutter answers an arrow key with `DirectionalFocusIntent`, whose traversal
/// walks the widget tree **by geometry**. On a TV window that is not good
/// enough: it happily lands on widgets that are faded out or positioned
/// off-screen (the zen layout keeps both mounted), and it can land on the
/// page's own container node, which paints nothing at all — so the focus ring
/// vanishes and the remote looks dead. Layouts that know their regions should
/// say where the arrows go; this says it.
///
/// Directions without a target are left to the default traversal, so a region
/// keeps its normal up/down behaviour inside itself. Give a direction `null`
/// on purpose *and* wrap the region's siblings as unfocusable
/// (`ExcludeFocus`) to make the focus stay put instead.
class DpadNav extends StatelessWidget {
  const DpadNav({
    super.key,
    this.up,
    this.down,
    this.left,
    this.right,
    required this.child,
  });

  /// Focus targets for each direction; null means "nothing special".
  final FocusNode? up;
  final FocusNode? down;
  final FocusNode? left;
  final FocusNode? right;

  final Widget child;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final FocusNode? target;
    if (key == LogicalKeyboardKey.arrowUp) {
      target = up;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      target = down;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      target = left;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      target = right;
    } else {
      return KeyEventResult.ignored;
    }
    if (target == null) return KeyEventResult.ignored;
    target.requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Never a focus target itself: this node only listens to the keys that
      // bubble up from whatever is focused inside [child].
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: child,
    );
  }
}
