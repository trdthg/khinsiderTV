import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A focusable tile tuned for D-Pad / gamepad navigation (Android TV) and for
/// touch screens.
///
/// * Registers its own [FocusNode]; shows a border highlight when focused.
/// * `Select` (Enter / gamepad A) triggers [onSelect].
/// * Fully traversable with arrow keys via the default focus traversal.
/// * Mouse users get the same affordance as a D-Pad user: hovering a tile
///   highlights it AND moves keyboard focus onto it (see [hoverFocus]), so
///   "hover, then press Enter" always activates the tile under the cursor.
/// * Touch users get a tap ripple instead of the highlight: a finger never
///   hovers, and the ring a tap would leave behind on the last tile touched
///   reads as a selection that cannot be cleared. See [_showHighlight].
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

  /// The layer the tap ripple is painted in, and the box its coordinates are
  /// measured against. Both are needed because the ripple is driven by hand
  /// (see [_handleTapDown]).
  final GlobalKey _inkKey = GlobalKey();

  /// The ripple under the finger, and every ripple that is still fading.
  /// A confirmed or cancelled ripple keeps animating after the finger is gone,
  /// so all of them have to be remembered until they remove themselves —
  /// otherwise a tile that leaves the screen mid-tap leaves its tickers
  /// running on the [Material] that owned them.
  final Set<InteractiveInkFeature> _splashes = <InteractiveInkFeature>{};
  InteractiveInkFeature? _currentSplash;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _focused = _focusNode.hasFocus);
    });
    // Fingers and D-Pads want different feedback, and Flutter tracks which one
    // was used last: `highlightMode` is `touch` until a key is pressed (or on a
    // desktop with a mouse attached). Material's own widgets hide their focus
    // highlight in that mode, so the same rule is applied here.
    FocusManager.instance.addHighlightModeListener(_handleHighlightModeChange);
  }

  @override
  void deactivate() {
    // A ripple owns tickers of the [Material] that paints it, so it has to be
    // disposed while that Material is still alive — that is here, not in
    // [dispose]: the tile is an ancestor of the ink layer, and descendants are
    // unmounted before it. Same reasoning as InkResponse.
    for (final splash in _splashes.toList()) {
      splash.dispose();
    }
    _splashes.clear();
    _currentSplash = null;
    super.deactivate();
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(
      _handleHighlightModeChange,
    );
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _handleHighlightModeChange(FocusHighlightMode mode) {
    if (mounted) setState(() {});
  }

  /// Whether the focus ring should be painted.
  ///
  /// The ring and the hover fill answer "where am I?" for a keyboard, a remote
  /// or a mouse. A finger needs no such answer, and painting the ring there
  /// leaves it stuck on whatever was tapped last with no way to clear it — so
  /// in touch mode the tile stays flat and the tap ripple carries the feedback.
  bool get _showHighlight =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

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

  /// Starts a Material ripple in [_inkKey]'s layer, which sits *above*
  /// [DpadTile.child].
  ///
  /// A plain [InkWell] cannot be used here: Material paints ink below the
  /// widget it wraps, so a well around the child would stay invisible under an
  /// opaque Card or album cover. Driving the feature by hand keeps hit testing
  /// exactly as it was as well — the layer ignores pointers, so widgets inside
  /// the tile (cache badges, tooltips) keep their own gestures.
  void _handleTapDown(TapDownDetails details) {
    final inkContext = _inkKey.currentContext;
    if (inkContext == null) return;
    final referenceBox = inkContext.findRenderObject();
    if (referenceBox is! RenderBox || !referenceBox.hasSize) return;
    final factory = Theme.of(context).splashFactory;

    final previous = _currentSplash;
    if (previous != null) {
      _currentSplash = null;
      previous.cancel();
    }

    late final InteractiveInkFeature splash;
    splash = factory.create(
      controller: Material.of(inkContext),
      referenceBox: referenceBox,
      position: referenceBox.globalToLocal(details.globalPosition),
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
      textDirection: Directionality.of(context),
      containedInkWell: true,
      borderRadius: BorderRadius.circular(widget.borderRadius),
      onRemoved: () {
        _splashes.remove(splash);
        if (identical(_currentSplash, splash)) _currentSplash = null;
      },
    );
    _splashes.add(splash);
    _currentSplash = splash;
  }

  void _handleTapUp(TapUpDetails details) {
    final splash = _currentSplash;
    _currentSplash = null;
    splash?.confirm();
  }

  void _handleTapCancel() {
    final splash = _currentSplash;
    _currentSplash = null;
    splash?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final focused = _focused && _showHighlight;

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
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: () {
          // Mouse clicks must move keyboard focus too, otherwise Enter/Space
          // keep activating the autofocused row instead of the clicked one.
          // Touch taps do the same: the focus is invisible there, but a
          // keyboard attached later carries on from the tile last touched.
          _focusNode.requestFocus();
          widget.onSelect();
        },
        child: Stack(
          // `passthrough` hands the tile's child the very constraints it used
          // to get before the ripple layer existed.
          fit: StackFit.passthrough,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                // Hover feedback for mouse users (focus keeps its own, stronger
                // look): a faint fill, so a row is still recognisable while the
                // focus ring animates in. Only a real pointer ever hovers, and
                // only while highlights are shown at all.
                color: _hovered && !focused
                    ? scheme.onSurface.withValues(alpha: 0.06)
                    : Colors.transparent,
              ),
              // Draw the ring on top of the child, otherwise an opaque
              // Card/IconButton child covers the inner part of the border and
              // the highlight looks chipped.
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: Border.all(
                  width: focused ? 2.5 : 0,
                  color: focused ? scheme.primary : Colors.transparent,
                ),
                boxShadow: focused
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
            // The ink layer for the tap ripple: on top of the content, and
            // transparent to pointers so nothing inside the tile loses its
            // gestures.
            Positioned.fill(
              child: IgnorePointer(
                child: Material(
                  type: MaterialType.transparency,
                  child: SizedBox.expand(key: _inkKey),
                ),
              ),
            ),
          ],
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
