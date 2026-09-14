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
///
/// A `stopX` flag is the cheaper version of that for the *edge* of a row: the
/// key is swallowed, so the focus stays where it is. A horizontal row of album
/// cards needs it, because the default traversal happily answers "Right" at
/// the last card by jumping into the row below — a move that means nothing to
/// the user.
class DpadNav extends StatelessWidget {
  const DpadNav({
    super.key,
    this.up,
    this.down,
    this.left,
    this.right,
    this.stopUp = false,
    this.stopDown = false,
    this.stopLeft = false,
    this.stopRight = false,
    required this.child,
  });

  /// Focus targets for each direction; null means "nothing special".
  final FocusNode? up;
  final FocusNode? down;
  final FocusNode? left;
  final FocusNode? right;

  /// Swallow the key instead of moving the focus. Used on the first/last item
  /// of a row, so the row does not leak focus sideways into its neighbours.
  final bool stopUp;
  final bool stopDown;
  final bool stopLeft;
  final bool stopRight;

  final Widget child;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final FocusNode? target;
    final bool stop;
    if (key == LogicalKeyboardKey.arrowUp) {
      target = up;
      stop = stopUp;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      target = down;
      stop = stopDown;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      target = left;
      stop = stopLeft;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      target = right;
      stop = stopRight;
    } else {
      return KeyEventResult.ignored;
    }
    if (target != null) {
      target.requestFocus();
      return KeyEventResult.handled;
    }
    // No neighbour: either stay put (edge of a row) or let the default
    // traversal try.
    return stop ? KeyEventResult.handled : KeyEventResult.ignored;
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
