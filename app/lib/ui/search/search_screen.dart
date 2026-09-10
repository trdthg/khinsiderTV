import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../data/preferences_store.dart';
import '../../state/search_controller.dart';

/// Search screen: text field + responsive album grid (list on narrow /
/// portrait layouts, grid on TV / landscape).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? preset]) {
    if (preset != null) _controller.text = preset;
    ref.read(searchControllerProvider.notifier).search(_controller.text);
    ref.read(searchHistoryProvider.notifier).record(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
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
                  IconButton.filled(
                    onPressed: _submit,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(context, state)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, SearchState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return _Message(icon: Icons.error_outline, text: state.error!);
    }
    if (!state.hasSearched) {
      return const _IdleHome();
    }
    if (state.results.isEmpty) {
      return const _Message(icon: Icons.search_off, text: 'No albums found.');
    }
    return _AlbumGrid(albums: state.results);
  }
}

/// Idle state: search history + favorites + recently viewed.
class _IdleHome extends ConsumerWidget {
  const _IdleHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider).value ?? const [];
    final favorites = ref.watch(favoritesProvider).value ?? const [];
    final recents = ref.watch(recentAlbumsProvider).value ?? const [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (history.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.history, size: 18),
              const SizedBox(width: 6),
              Text(
                'Recent searches',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Clear history',
                onPressed: () =>
                    ref.read(searchHistoryProvider.notifier).clear(),
                icon: const Icon(Icons.delete_outline, size: 20),
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
        if (history.isEmpty && favorites.isEmpty && recents.isEmpty)
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
                        child: albums[i].thumbUrl != null
                            ? CachedNetworkImage(
                                imageUrl: albums[i].thumbUrl!,
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
  const _AlbumGrid({required this.albums});

  final List<AlbumSummary> albums;

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
              child: album.thumbUrl != null
                  ? CachedNetworkImage(
                      imageUrl: album.thumbUrl!,
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
