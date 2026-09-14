import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/dpad_tile.dart';

/// The on-screen keyboard the TV layouts type with.
///
/// Android TV shows a system IME for a focused text field, but **a remote can
/// never reach it from a Flutter app**: the D-pad down that should hand focus to
/// the IME window is consumed by the framework first (`WidgetsApp`'s default
/// shortcuts traverse focus, `DefaultTextEditingShortcuts` move the caret), so
/// the key never reaches Android's window manager. The keyboard stayed on
/// screen, unnavigable, and whether it appeared at all depended on the system's
/// own IME timing (it does not come back for a field that never lost focus).
///
/// So TVs do not open the system IME at all (the field is read-only there) and
/// type with this instead: a D-pad navigable grid of keys that writes into the
/// field's controller. Nothing here is phone/desktop code — those layouts keep
/// the ordinary editable field.
///
/// The arrows are handled here rather than left to Flutter's directional focus
/// traversal: that walks the widget tree by geometry, and on a real TV window
/// (1920x1080 at density 2, i.e. 960x540 logical pixels) it refused to move
/// right inside the letter row, so the keys after `t` could not be reached at
/// all. Moving an index in a grid is exact, cheap, and cannot depend on the
/// screen size. Rows keep their own length, and moving vertically keeps the
/// column (clamped), which is what every TV keyboard does.
///
/// Two layers, because a remote cannot do what a shift key does on a phone:
/// * letters — digits, the `qwerty` rows, and a `⇧` key that locks uppercase on
///   (a remote user would otherwise need three presses for "ABBA");
/// * symbols — `!@#$%&*()?`, brackets and punctuation, plus the accented
///   letters album titles actually use (`é è ü ö ä ñ ç`). The last key of the
///   bottom row switches layers in the same spot, so switching back and forth
///   never moves the target out from under the thumb.
class TvKeyboard extends StatefulWidget {
  const TvKeyboard({
    super.key,
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
    required this.onClose,
  });

  /// A single character to append.
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  /// Dismiss the keyboard (Escape / the "Hide" key); the search field keeps its
  /// text and can be re-opened with Enter.
  final VoidCallback onClose;

  @override
  State<TvKeyboard> createState() => _TvKeyboardState();
}

/// Which set of keys the grid is showing.
enum _Layer { letters, symbols }

class _TvKeyboardState extends State<TvKeyboard> {
  static const String _shiftKey = 'SHIFT';
  static const String _layerKey = 'LAYER';

  /// Digits on top, then the alphabet — Leanback style.
  static const List<List<String>> _letterRows = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', _shiftKey, _layerKey],
  ];

  /// Punctuation, brackets and the accented letters the site's titles use.
  static const List<List<String>> _symbolRows = [
    ['!', '@', '#', '\$', '%', '&', '*', '(', ')', '?'],
    ['-', '_', '=', '+', '[', ']', '{', '}', '/', '\\'],
    ['.', ',', ':', ';', '\'', '"', '~', '`', '<'],
    ['>', 'é', 'è', 'ü', 'ö', 'ä', 'ñ', 'ç', _layerKey],
  ];

  /// Action keys on their own row: Space / Delete / Clear / Search / Hide.
  static const List<String> _actionLabels = [
    'space',
    'delete',
    'clear',
    'search',
    'hide',
  ];

  static const int _maxKeysPerRow = 10;

  _Layer _layer = _Layer.letters;
  bool _shift = false;

  /// The keys of the layer currently shown.
  List<List<String>> get _rows =>
      _layer == _Layer.letters ? _letterRows : _symbolRows;

  /// Keys per row, action row last: what navigation clamps against.
  List<int> get _sizes => [
    for (final row in _rows) row.length,
    _actionLabels.length,
  ];

  /// One focus node per grid cell, held for the lifetime of the keyboard so the
  /// key a node belongs to survives a layer switch. Holding them here is what
  /// makes arrow navigation exact.
  late final List<List<FocusNode>> _nodes = [
    for (var row = 0; row < _letterRows.length + 1; row++)
      [
        for (var col = 0; col < _maxKeysPerRow; col++)
          FocusNode(debugLabel: 'tv-key-$row-$col', skipTraversal: true),
      ],
  ];

  /// Where the remote is in the grid. Only used to compute the next key; the
  /// focus nodes themselves are the source of truth for the highlight.
  int _row = 0;
  int _col = 0;

  @override
  void initState() {
    super.initState();
    // The remote has to land somewhere useful the moment the keyboard appears,
    // including when it is re-opened after "Hide" — `autofocus` only ever fires
    // for a node that is created, and focus has to be taken back from whatever
    // held it (the field, or the screen's idle node).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus(0, 0);
    });
  }

  @override
  void dispose() {
    for (final row in _nodes) {
      for (final node in row) {
        node.dispose();
      }
    }
    super.dispose();
  }

  void _focus(int row, int col) {
    final sizes = _sizes;
    final nextRow = row.clamp(0, sizes.length - 1);
    final nextCol = col.clamp(0, sizes[nextRow] - 1);
    _row = nextRow;
    _col = nextCol;
    _nodes[nextRow][nextCol].requestFocus();
  }

  /// Moves one step in the grid, clamped to the row/column that exists there.
  void _move({int row = 0, int col = 0}) => _focus(_row + row, _col + col);

  void _setLayer(_Layer layer) {
    setState(() {
      _layer = layer;
      _shift = false;
    });
    // The grid changed shape around the current column: re-clamp and put the
    // focus back onto a key that exists.
    _focus(_row, _col);
  }

  void _toggleShift() {
    setState(() => _shift = !_shift);
    _nodes[_row][_col].requestFocus();
  }

  /// Presses the grid key at [row]/[col]: types it, or toggles a mode key.
  void _activateKey(int row, int col) {
    final character = _characterAt(row, col);
    if (character != null) {
      widget.onKey(character);
      return;
    }
    if (row >= _rows.length) return;
    final label = _rows[row][col];
    if (label == _shiftKey) {
      _toggleShift();
    } else if (label == _layerKey) {
      _setLayer(_layer == _Layer.letters ? _Layer.symbols : _Layer.letters);
    }
  }

  /// What the key at [row]/[col] types, or null for the keys that act instead
  /// (shift, layer switch).
  String? _characterAt(int row, int col) {
    if (row >= _rows.length) return null;
    final label = _rows[row][col];
    if (label == _shiftKey || label == _layerKey) return null;
    if (_layer == _Layer.letters && _shift) return label.toUpperCase();
    return label;
  }

  /// Physical keyboards keep working: the panel sits above the key tiles in the
  /// focus tree, so printable keys arrive here after the tiles decline them.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      widget.onBackspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _move(col: -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _move(col: 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(row: -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(row: 1);
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null &&
        character.length == 1 &&
        character.codeUnitAt(0) >= 0x20) {
      widget.onKey(character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget cell(
      int row,
      int col, {
      required Widget child,
      // Fixed key width for the grid; null lets the action keys take the width
      // their icon + label need.
      double? width = 46,
      Color? background,
      Color? foreground,
      VoidCallback? onSelect,
    }) {
      return Padding(
        padding: const EdgeInsets.all(2),
        child: DpadTile(
          focusNode: _nodes[row][col],
          borderRadius: 8,
          onSelect: onSelect ?? () => _activateKey(row, col),
          child: Container(
            width: width,
            height: 44,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: width == null ? 14 : 4),
            decoration: background == null
                ? null
                : BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(8),
                  ),
            child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: 16, color: foreground),
              child: child,
            ),
          ),
        ),
      );
    }

    /// A typing key, or one of the two keys that switch modes.
    Widget key(int row, int col) {
      final label = _rows[row][col];
      if (label == _shiftKey) {
        return cell(
          row,
          col,
          background: _shift ? scheme.primary : null,
          foreground: _shift ? scheme.onPrimary : null,
          child: const Text('⇧'),
        );
      }
      if (label == _layerKey) {
        return cell(
          row,
          col,
          child: Text(
            _layer == _Layer.letters ? '#+=' : 'ABC',
            style: const TextStyle(fontSize: 14),
          ),
        );
      }
      return cell(
        row,
        col,
        child: Text(
          _layer == _Layer.letters && _shift ? label.toUpperCase() : label,
        ),
      );
    }

    Widget action(
      int col,
      String name,
      IconData icon,
      VoidCallback onSelect, {
      Color? foreground,
    }) => cell(
      4,
      col,
      width: null,
      onSelect: onSelect,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 6),
          Text(name, style: TextStyle(color: foreground)),
        ],
      ),
    );

    return Focus(
      onKeyEvent: _onKeyEvent,
      child: Material(
        color: scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var row = 0; row < _rows.length; row++)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var col = 0; col < _rows[row].length; col++)
                      key(row, col),
                  ],
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  action(0, 'Space', Icons.space_bar, () => widget.onKey(' ')),
                  const SizedBox(width: 4),
                  action(
                    1,
                    'Delete',
                    Icons.backspace_outlined,
                    widget.onBackspace,
                  ),
                  const SizedBox(width: 4),
                  action(2, 'Clear', Icons.clear, widget.onClear),
                  const SizedBox(width: 4),
                  cell(
                    4,
                    3,
                    width: null,
                    onSelect: widget.onSubmit,
                    background: scheme.primary,
                    foreground: scheme.onPrimary,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search, size: 18, color: scheme.onPrimary),
                        const SizedBox(width: 6),
                        Text(
                          'Search',
                          style: TextStyle(color: scheme.onPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  action(
                    4,
                    'Hide',
                    Icons.keyboard_hide_outlined,
                    widget.onClose,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
