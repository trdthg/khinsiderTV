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
class TvKeyboard extends StatelessWidget {
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

  /// Letter rows, Leanback style: digits on top, then the alphabet.
  static const List<List<String>> _rows = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  /// Physical keyboards keep working: the panel sits above the key tiles in the
  /// focus tree, so printable keys arrive here after the tiles decline them.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      onBackspace();
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null &&
        character.length == 1 &&
        character.codeUnitAt(0) >= 0x20) {
      onKey(character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var first = true;

    Widget keyTile(String label, VoidCallback onSelect, {Widget? child}) {
      final tile = DpadTile(
        // The remote has to land somewhere useful the moment the keyboard
        // appears, so the first key takes the initial focus.
        autofocus: first,
        borderRadius: 8,
        onSelect: onSelect,
        child: Container(
          width: 46,
          height: 44,
          alignment: Alignment.center,
          child: child ?? Text(label, style: const TextStyle(fontSize: 16)),
        ),
      );
      first = false;
      return Padding(padding: const EdgeInsets.all(2), child: tile);
    }

    Widget action(String label, IconData icon, VoidCallback onSelect) =>
        DpadTile(
          borderRadius: 8,
          onSelect: onSelect,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Text(label),
              ],
            ),
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
              for (final row in _rows)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final character in row)
                      keyTile(character, () => onKey(character)),
                  ],
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  action('Space', Icons.space_bar, () => onKey(' ')),
                  const SizedBox(width: 4),
                  action('Delete', Icons.backspace_outlined, onBackspace),
                  const SizedBox(width: 4),
                  action('Clear', Icons.clear, onClear),
                  const SizedBox(width: 4),
                  DpadTile(
                    borderRadius: 8,
                    onSelect: onSubmit,
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
                  action('Hide', Icons.keyboard_hide_outlined, onClose),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
