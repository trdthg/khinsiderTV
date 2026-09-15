import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/platform/device.dart';
import '../../core/widgets/dpad_tile.dart';
import '../../core/widgets/dpad_nav.dart';
import '../../data/preferences_store.dart';
import '../../l10n/l10n.dart';
import '../../state/search_controller.dart';
import '../../state/update_controller.dart';
import '../settings/settings_screen.dart';
import 'tv_system_text_field.dart';

/// Search screen: text field + responsive album grid (list on narrow /
/// portrait layouts, grid on TV / landscape).
///
/// Every platform types with the system keyboard. TVs use a platform-view
/// `EditText` ([TvSystemTextField]) instead of a Flutter field, because
/// Flutter's own text input never hands the remote's D-pad to the platform
/// keyboard on Google TV / Chromecast (flutter/flutter#177360); phones and
/// desktops keep the ordinary [TextField]. This screen used to ship its own
/// D-pad keyboard as a fallback — it is gone now that the platform one works.
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

  /// Whether this is a TV: the layouts that type with the platform-view field.
  late final bool _tv;

  /// The Search button, used as the anchor for "leave the field downwards".
  final _searchButtonFocus = FocusNode(debugLabel: 'search-button');

  /// Settings: the last stop on the search bar's row.
  final _settingsFocus = FocusNode(debugLabel: 'settings-button');
  final FocusNode _nativeFieldAnchor = FocusNode(
    debugLabel: 'search-field-native',
  );

  /// State of the platform-view field, for focusing it and hiding its keyboard.
  final _systemFieldKey = GlobalKey<TvSystemTextFieldState>();

  @override
  void initState() {
    super.initState();
    _tv = ref.read(isTelevisionProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchFocus.dispose();
    _searchButtonFocus.dispose();
    _settingsFocus.dispose();
    _nativeFieldAnchor.dispose();
    super.dispose();
  }

  /// Moves the remote off the platform-view field.
  ///
  /// The native field owns the Android focus, so Flutter's own focus tree has
  /// no current node to move *from*: anchor it on the Search button (attached
  /// either way) and then step in [direction] from there.
  void _leaveSystemField(TraversalDirection direction) {
    _systemFieldKey.currentState?.blur();
    _searchButtonFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).focusInDirection(direction);
    });
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // A TV types into the platform-view field, which handles its own keys: this
    // node belongs to the ordinary field, i.e. phones and desktops.
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

  /// False until the remote/pointer has left the TV field once. The first
  /// focus is the one the screen sets up itself, and that one is silent.
  bool _leftFieldOnce = false;

  /// Opens Settings, dropping the keyboard first.
  ///
  /// The search field keeps the platform keyboard up otherwise, and the
  /// settings page has no field of its own to explain why it is there.
  void _openSettings() {
    _systemFieldKey.currentState?.blur();
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  void _submit([String? preset]) {
    if (preset != null) _controller.text = preset;
    ref.read(searchControllerProvider.notifier).search(_controller.text);
    ref.read(searchHistoryProvider.notifier).record(_controller.text);
    // The results are the point of pressing Search: drop the platform keyboard
    // and hand the remote back to them.
    if (_tv) _leaveSystemField(TraversalDirection.down);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final narrow = _narrow;
    final l = l10n(context);
    // The TV field is the platform's own EditText (see TvSystemTextField): that
    // is the only way the platform keyboard gets the remote's D-pad.
    final systemField = _tv;

    final searchBar = Padding(
      padding: EdgeInsets.fromLTRB(16, narrow ? 4 : 16, 16, narrow ? 10 : 8),
      child: Row(
        children: [
          Expanded(
            child: systemField
                ? Focus(
                    // Anchors the platform field in Flutter's focus tree: the
                    // native view owns the Android focus, so this node is how
                    // "up from the results" (and the update banner handing the
                    // remote back) can return to the field.
                    focusNode: _nativeFieldAnchor,
                    autofocus: true,
                    onFocusChange: (hasFocus) {
                      final state = _systemFieldKey.currentState;
                      if (hasFocus) {
                        // The start-up focus stays silent: raising the
                        // platform keyboard here would cover the screen before
                        // the user asked for anything. Coming back to the
                        // field later is a deliberate move, so that one gets
                        // the keyboard.
                        state?.requestFocus(showKeyboard: _leftFieldOnce);
                      } else {
                        _leftFieldOnce = true;
                        state?.blur();
                      }
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TvSystemTextField(
                        key: _systemFieldKey,
                        controller: _controller,
                        hintText: l.searchHint,
                        onSubmitted: _submit,
                        onMoveDown: () =>
                            _leaveSystemField(TraversalDirection.down),
                        onMoveUp: () =>
                            _leaveSystemField(TraversalDirection.up),
                      ),
                    ),
                  )
                : TextField(
                    // Deliberately not autofocused: an autofocused field pops
                    // the on-screen keyboard the moment the app opens. Tapping
                    // it (or navigating up to it) is enough.
                    autofocus: false,
                    focusNode: _searchFocus,
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l.searchHint,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          DpadIconButton(
            focusNode: _searchButtonFocus,
            tooltip: l.actionSearch,
            filled: true,
            icon: Icons.arrow_forward,
            onPressed: _submit,
          ),
          const SizedBox(width: 8),
          _SettingsButton(
            focusNode: _settingsFocus,
            onPressed: _openSettings,
            hasUpdate: ref.watch(
              updateControllerProvider.select((s) => s.updateReady),
            ),
          ),
        ],
      ),
    );

    // Back is left to the platform: it dismisses the platform keyboard first
    // and only pops the screen on the next press.
    return Scaffold(
      body: SafeArea(child: _buildStack(narrow, state, searchBar)),
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
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    SearchState state, {
    bool reverse = false,
    bool hideHistory = false,
  }) {
    final l = l10n(context);
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
      return _Message(icon: Icons.search_off, text: l.searchNoResults);
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
    final l = l10n(context);

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
            tooltip: l.searchClearHistory,
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
    final l = l10n(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (showHistory && history.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.history, size: 18),
              const SizedBox(width: 6),
              Text(
                l.searchRecentSearches,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              DpadIconButton(
                tooltip: l.searchClearHistory,
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
            title: l.searchFavorites,
            icon: Icons.favorite,
            albums: favorites,
          ),
        if (recents.isNotEmpty)
          _AlbumRow(
            title: l.searchRecentlyViewed,
            icon: Icons.history,
            albums: recents,
          ),
        if ((!showHistory || history.isEmpty) &&
            favorites.isEmpty &&
            recents.isEmpty)
          _Message(icon: Icons.music_note, text: l.searchIdleTip),
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
            itemBuilder: (context, i) => DpadNav(
              // A horizontal row stops at its own ends: pressing Right on the
              // last card used to hand the focus to the row underneath.
              stopLeft: i == 0,
              stopRight: i == albums.length - 1,
              child: SizedBox(
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

/// The settings entry point.
///
/// The search bar is the app's only permanent chrome (the album page is a
/// full-screen detail view), so this is the one place Settings can be without
/// first opening an album. The dot is the entire "an update is available"
/// signal now that the app no longer pops a banner up at launch.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({
    required this.focusNode,
    required this.onPressed,
    required this.hasUpdate,
  });

  final FocusNode focusNode;
  final VoidCallback onPressed;
  final bool hasUpdate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = l10n(context);
    return DpadTile(
      focusNode: focusNode,
      borderRadius: 24,
      onSelect: onPressed,
      child: Tooltip(
        message: hasUpdate ? l.searchSettingsWithUpdate : l.searchSettings,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.settings_outlined),
              if (hasUpdate)
                Positioned(
                  top: 9,
                  right: 9,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: scheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
