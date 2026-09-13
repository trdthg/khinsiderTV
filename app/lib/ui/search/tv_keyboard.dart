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

class _TvKeyboardState extends State<TvKeyboard> {
  /// Letter rows, Leanback style: digits on top, then the alphabet.
  static const List<List<String>> _letterRows = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  /// Names for the last row, which holds the action keys.
  static const List<String> _actionLabels = [
    'space',
    'delete',
    'clear',
    'search',
    'hide',
  ];

  /// One focus node per key, row by row, actions last. Holding them here is what
  /// makes arrow navigation exact.
  late final List<List<FocusNode>> _nodes = [
    for (final row in [..._letterRows, _actionLabels])
      [
        for (final label in row)
          FocusNode(debugLabel: 'tv-key-$label', skipTraversal: true),
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
    final rows = _nodes.length;
    final nextRow = row.clamp(0, rows - 1);
    final nextCol = col.clamp(0, _nodes[nextRow].length - 1);
    _row = nextRow;
    _col = nextCol;
    _nodes[nextRow][nextCol].requestFocus();
  }

  /// Moves one step in the grid, clamped to the row/column that exists there.
  void _move({int row = 0, int col = 0}) => _focus(_row + row, _col + col);

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

    Widget tile(
      int row,
      int index,
      VoidCallback onSelect, {
      Widget? child,
      String? label,
    }) {
      return Padding(
        padding: const EdgeInsets.all(2),
        child: DpadTile(
          focusNode: _nodes[row][index],
          borderRadius: 8,
          onSelect: onSelect,
          child: Container(
            width: label == null ? null : 46,
            height: 44,
            alignment: Alignment.center,
            padding: label == null
                ? const EdgeInsets.symmetric(horizontal: 14)
                : null,
            child: child ?? Text(label!, style: const TextStyle(fontSize: 16)),
          ),
        ),
      );
    }

    Widget action(
      int index,
      String name,
      IconData icon,
      VoidCallback onSelect, {
      Color? foreground,
    }) => tile(
      4,
      index,
      onSelect,
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
              for (var row = 0; row < _letterRows.length; row++)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _letterRows[row].length; i++)
                      tile(
                        row,
                        i,
                        () => widget.onKey(_letterRows[row][i]),
                        label: _letterRows[row][i],
                      ),
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
                  tile(
                    4,
                    3,
                    widget.onSubmit,
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
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
