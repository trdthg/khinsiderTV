import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/platform/device.dart';
import '../../core/widgets/dpad_tile.dart';
import '../../data/preferences_store.dart';
import '../../state/search_controller.dart';
import 'tv_keyboard.dart';

/// Search screen: text field + responsive album grid (list on narrow /
/// portrait layouts, grid on TV / landscape).
///
/// TVs type with the system IME by default, exactly like every other platform:
/// the field is a normal editable field, focused on entry so Android TV's own
/// (D-pad navigable) keyboard comes up. The app's own D-pad keyboard
/// ([TvKeyboard]) is kept as a fallback and is one button press away — the
/// keyboard button in the search bar — for boxes whose IME cannot be driven
/// from a Flutter text field. The choice is persisted (`TvKeyboardMode`).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  late final FocusNode _searchFocus = FocusNode(
    debugLabel: 'search-field',
    onKeyEvent: _onSearchKey,
  );

  /// Whether the TV's *built-in* keyboard is up. Always false off TV, and
  /// unused in system-IME mode.
  late bool _keyboardOpen;

  /// Whether this is a TV: the layout whose input method can be switched.
  late final bool _tv;

  /// The keyboard-mode button (TV only), so "left" from the field can reach it.
  late final FocusNode _keyboardModeFocus = FocusNode(
    debugLabel: 'tv-keyboard-mode',
    onKeyEvent: _onKeyboardModeKey,
  );

  /// True when this TV types with the app's own keyboard, i.e. the field is
  /// read-only and [TvKeyboard] is up. Everything else (phones, desktops, and a
  /// TV on the system IME) behaves like a normal editable field.
  bool get _builtinKeyboard {
    if (!_tv) return false;
    final mode =
        ref.read(tvKeyboardModeProvider).value ?? TvKeyboardMode.system;
    return mode == TvKeyboardMode.builtin;
  }

  @override
  void initState() {
    super.initState();
    _tv = ref.read(isTelevisionProvider);
    // A remote cannot type into a field, so the keyboard is already up when the
    // screen opens; Enter on the field brings it back after "Hide".
    _keyboardOpen = _tv;
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchFocus.dispose();
    _keyboardModeFocus.dispose();
    super.dispose();
  }

  void _setKeyboardOpen(bool open, {bool focusField = false}) {
    if (_keyboardOpen == open) return;
    setState(() => _keyboardOpen = open);
    // Closing the built-in keyboard disposes the focused key, so focus has to
    // be put somewhere deliberate — otherwise the remote is dead until the user
    // finds the field again by hand. In this mode the field is read-only, and
    // Flutter only creates an input connection for an editable one
    // (`EditableText._shouldCreateInputConnection`), so focusing it here cannot
    // summon the system IME behind the panel.
    if (!open && focusField && _tv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  /// Asks the platform to show the IME for the focused field.
  ///
  /// `TextField` only asks when the field *gains* focus, so after the user
  /// dismisses the IME with Back there is no way back: the field never lost
  /// focus, so nothing re-requests it. There is no public API for this on
  /// `EditableText`, so this sends the same message the framework sends when it
  /// opens a connection.
  void _showSystemKeyboard() {
    if (!_tv || _builtinKeyboard) return;
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  /// Left from the field reaches the keyboard-mode button, so the fallback
  /// keyboard stays one press away on a remote.
  KeyEventResult _onKeyboardModeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// True when the caret sits at the very start (or the field was never
  /// touched), i.e. when "left" has nothing to move inside the text.
  bool get _caretAtStart {
    final selection = _controller.selection;
    return selection.isCollapsed && selection.baseOffset <= 0;
  }

  /// Switches between the system IME and the built-in keyboard, and moves the
  /// focus (and the IME) to wherever the new mode types.
  Future<void> _toggleKeyboardMode() async {
    await ref.read(tvKeyboardModeProvider.notifier).toggle();
    if (!mounted) return;
    if (_builtinKeyboard) {
      _setKeyboardOpen(true);
    } else {
      _searchFocus.requestFocus();
      _showSystemKeyboard();
    }
  }

  void _append(String character) {
    _controller.value = TextEditingValue(
      text: _controller.text + character,
      selection: TextSelection.collapsed(
        offset: _controller.text.length + character.length,
      ),
    );
  }

  void _backspace() {
    final text = _controller.text;
    if (text.isEmpty) return;
    _controller.value = TextEditingValue(
      text: text.substring(0, text.length - 1),
      selection: TextSelection.collapsed(offset: text.length - 1),
    );
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (_tv) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.gameButtonA) {
        if (_builtinKeyboard) {
          // The built-in keyboard was hidden: this is the way back to it.
          _setKeyboardOpen(true);
        } else {
          _showSystemKeyboard();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft && _caretAtStart) {
        _keyboardModeFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (_builtinKeyboard) {
        // In this mode the field is read-only, so it is the place that has to
        // accept a physical keyboard's characters itself.
        final character = event.character;
        if (character != null &&
            character.length == 1 &&
            character.codeUnitAt(0) >= 0x20) {
          _append(character);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.backspace) {
          _backspace();
          return KeyEventResult.handled;
        }
      }
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      // On the narrow layout the field sits BELOW the results, so "into the
      // results" is the upward direction there.
      final moved = FocusScope.of(context).focusInDirection(
        _narrow ? TraversalDirection.up : TraversalDirection.down,
      );
      if (moved) return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Phones (and other narrow windows) get the search field at the bottom,
  /// right above the on-screen keyboard, with the results stacked upwards.
  bool get _narrow => MediaQuery.sizeOf(context).width <= 700;

  void _submit([String? preset]) {
    if (preset != null) _controller.text = preset;
    ref.read(searchControllerProvider.notifier).search(_controller.text);
    ref.read(searchHistoryProvider.notifier).record(_controller.text);
    // The results are the point of pressing Search: drop the keyboard (the
    // built-in panel, or the IME) and hand the remote back to them.
    if (_builtinKeyboard) {
      _setKeyboardOpen(false);
    } else if (_tv) {
      _searchFocus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final narrow = _narrow;
    final mode =
        ref.watch(tvKeyboardModeProvider).value ?? TvKeyboardMode.system;
    final builtinKeyboard = _tv && mode == TvKeyboardMode.builtin;

    final searchBar = Padding(
      padding: EdgeInsets.fromLTRB(16, narrow ? 4 : 16, 16, narrow ? 10 : 8),
      child: Row(
        children: [
          // TV only: switch between the system IME and the app's own keyboard.
          // Left from the field focuses it (see _onSearchKey), so a remote can
          // always get back to the fallback if its IME will not cooperate.
          if (_tv) ...[
            DpadIconButton(
              focusNode: _keyboardModeFocus,
              tooltip: builtinKeyboard
                  ? 'Use the system keyboard'
                  : 'Use the built-in keyboard',
              icon: builtinKeyboard
                  ? Icons.keyboard_hide_outlined
                  : Icons.keyboard_outlined,
              filled: builtinKeyboard,
              onPressed: _toggleKeyboardMode,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              // Only the built-in keyboard needs a read-only field: read-only
              // means no input connection, which is what stops the system IME
              // from appearing behind the panel. TVs on the system IME (the
              // default) use an ordinary editable field.
              readOnly: builtinKeyboard,
              autofocus: !builtinKeyboard,
              focusNode: _searchFocus,
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search game soundtracks…',
              ),
            ),
          ),
          const SizedBox(width: 8),
          DpadIconButton(
            tooltip: 'Search',
            filled: true,
            icon: Icons.arrow_forward,
            onPressed: _submit,
          ),
        ],
      ),
    );

    return PopScope(
      // With the built-in keyboard up, Back means "hide it" before it means
      // "leave search". With the system IME, Android dismisses the IME itself
      // on the first Back, so this must not also swallow the pop.
      canPop: !(builtinKeyboard && _keyboardOpen),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setKeyboardOpen(false, focusField: true);
      },
      child: Scaffold(
        body: SafeArea(child: _buildStack(narrow, state, searchBar)),
      ),
    );
  }

  Widget _buildStack(bool narrow, SearchState state, Widget searchBar) {
    return Column(
      children: [
        if (!narrow) searchBar,
        Expanded(
          child: _buildBody(
            context,
            state,
            reverse: narrow,
            // Narrow layouts keep the history next to the search field below
            // instead (see _RecentSearchesStrip): on a phone the field is at
            // the bottom, so a history list at the top is a screen away from
            // the thing it belongs to.
            hideHistory: narrow,
          ),
        ),
        if (narrow && !state.hasSearched) const _RecentSearchesStrip(),
        if (narrow) searchBar,
        if (_builtinKeyboard && _keyboardOpen)
          TvKeyboard(
            onKey: _append,
            onBackspace: _backspace,
            onClear: () => _controller.clear(),
            onSubmit: _submit,
            onClose: () => _setKeyboardOpen(false, focusField: true),
          ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    SearchState state, {
    bool reverse = false,
    bool hideHistory = false,
  }) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return _Message(icon: Icons.error_outline, text: state.error!);
    }
    if (!state.hasSearched) {
      return _IdleHome(showHistory: !hideHistory);
    }
    if (state.results.isEmpty) {
      return const _Message(icon: Icons.search_off, text: 'No albums found.');
    }
    return _AlbumGrid(albums: state.results, reverse: reverse);
  }
}

/// The narrow layout's recent searches: one scrollable row of chips sitting
/// directly on top of the (bottom-anchored) search field, so the history is
/// where the typing happens instead of a screen away at the top.
class _RecentSearchesStrip extends ConsumerWidget {
  const _RecentSearchesStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider).value ?? const [];
    if (history.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 2),
      child: Row(
        children: [
          Icon(
            Icons.history,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: history.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final q = history[i];
                  return Center(
                    child: DpadTile(
                      borderRadius: 18,
                      onSelect: () =>
                          ref.read(searchControllerProvider.notifier).search(q),
                      child: Chip(
                        label: Text(q),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          DpadIconButton(
            tooltip: 'Clear history',
            iconSize: 20,
            icon: Icons.delete_outline,
            onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
          ),
        ],
      ),
    );
  }
}

/// Idle state: search history + favorites + recently viewed.
class _IdleHome extends ConsumerWidget {
  const _IdleHome({this.showHistory = true});

  /// False on the narrow layout, where [_RecentSearchesStrip] owns the history.
  final bool showHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider).value ?? const [];
    final favorites = ref.watch(favoritesProvider).value ?? const [];
    final recents = ref.watch(recentAlbumsProvider).value ?? const [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (showHistory && history.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.history, size: 18),
              const SizedBox(width: 6),
              Text(
                'Recent searches',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              DpadIconButton(
                tooltip: 'Clear history',
                iconSize: 20,
                icon: Icons.delete_outline,
                onPressed: () =>
                    ref.read(searchHistoryProvider.notifier).clear(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in history)
                DpadTile(
                  borderRadius: 18,
                  onSelect: () => _searchAndRecord(context, ref, q),
                  child: Chip(
                    label: Text(q),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (favorites.isNotEmpty)
          _AlbumRow(
            title: 'Favorites',
            icon: Icons.favorite,
            albums: favorites,
          ),
        if (recents.isNotEmpty)
          _AlbumRow(
            title: 'Recently viewed',
            icon: Icons.history,
            albums: recents,
          ),
        if ((!showHistory || history.isEmpty) &&
            favorites.isEmpty &&
            recents.isEmpty)
          const _Message(
            icon: Icons.music_note,
            text:
                'Search KHInsider for game soundtracks.\n'
                'Tip: navigate with the D-Pad / gamepad.',
          ),
      ],
    );
  }

  void _searchAndRecord(BuildContext context, WidgetRef ref, String q) {
    ref.read(searchControllerProvider.notifier).search(q);
    ref.read(searchHistoryProvider.notifier).record(q);
  }
}

/// Horizontal scrollable album card row (favorites / recents).
class _AlbumRow extends ConsumerWidget {
  const _AlbumRow({
    required this.title,
    required this.icon,
    required this.albums,
  });

  final String title;
  final IconData icon;
  final List<AlbumSummary> albums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(
              width: 140,
              child: DpadTile(
                autofocus: i == 0,
                onSelect: () => Navigator.pushNamed(
                  context,
                  '/album',
                  arguments: albums[i],
                ),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: albums[i].imageUrl != null
                            ? CachedNetworkImage(
                                // `imageUrl`, not `thumbUrl`: the search page
                                // only hands out a 60×60 file.
                                imageUrl: albums[i].imageUrl!,
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.album, size: 48),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          albums[i].title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({required this.albums, this.reverse = false});

  final List<AlbumSummary> albums;

  /// Narrow layouts stack the grid from the bottom up, so the first hit sits
  /// directly above the (bottom-anchored) search field.
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 720;
        final columns = (constraints.maxWidth / (wide ? 220 : 160))
            .floor()
            .clamp(2, 8);

        return GridView.builder(
          key: const ValueKey('album-grid'),
          reverse: reverse,
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemCount: albums.length,
          itemBuilder: (context, i) => _AlbumCard(
            album: albums[i],
            autofocus: i == 0,
            cardKey: ValueKey('album-card-$i'),
          ),
        );
      },
    );
  }
}

class _AlbumCard extends ConsumerWidget {
  const _AlbumCard({required this.album, this.autofocus = false, this.cardKey});

  final AlbumSummary album;
  final bool autofocus;
  final Key? cardKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DpadTile(
      key: cardKey,
      autofocus: autofocus,
      onSelect: () {
        ref.read(recentAlbumsProvider.notifier).record(album);
        Navigator.pushNamed(context, '/album', arguments: album);
      },
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: album.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: album.imageUrl!,
                      fit: BoxFit.cover,
                    )
                  : const Icon(Icons.album, size: 56),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (album.platforms.isNotEmpty)
                          album.platforms.join(', '),
                        if (album.year != null) album.year!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
