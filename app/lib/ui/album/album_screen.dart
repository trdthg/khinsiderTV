import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../data/preferences_store.dart';
import '../../state/album_controller.dart';
import '../../state/player_controller.dart';
import '../../state/ui_state.dart';
import 'album_metadata.dart';
import '../shared/player_bar.dart';
import 'related_albums.dart';

/// Album detail screen: cover + full track list.
/// Track rows are D-Pad focusable; Select plays the album from that track
/// (phase 2 resolves only the clicked URL immediately — lazy loading).
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key, required this.albumId});

  final String albumId;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  /// Incremented by the refresh button to force a cache-bypassing reload.
  int _refreshNonce = 0;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(
      albumDetailProvider((widget.albumId, _refreshNonce)),
    );

    return Scaffold(
      bottomNavigationBar: const PlayerBar(),
      appBar: AppBar(
        title: const Text('Album'),
        actions: [
          IconButton(
            tooltip: 'Force refresh (bypass cache)',
            onPressed: () => setState(() => _refreshNonce++),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Failed to load album:\n$e', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => setState(() => _refreshNonce++),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (album) => _AlbumBody(album: album),
      ),
    );
  }
}

class _AlbumBody extends ConsumerWidget {
  const _AlbumBody({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav =
        ref
            .watch(favoritesProvider)
            .value
            ?.any((a) => a.id == album.summary.id) ??
        false;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 700;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wide)
              SizedBox(
                width: 300,
                child: LayoutBuilder(
                  builder: (context, lc) {
                    // Reserve room for title / track count / favorite button;
                    // cover shrinks when the player bar eats vertical space.
                    final coverSize = (lc.maxHeight - 190).clamp(140.0, 300.0);
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (album.coverUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: coverSize,
                                height: coverSize,
                                child: CachedNetworkImage(
                                  imageUrl: album.coverUrl!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            album.summary.title,
                            maxLines: 3, // bounds the reserved vertical space
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${album.trackCount} tracks',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: () => ref
                                .read(favoritesProvider.notifier)
                                .toggle(album.summary),
                            icon: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                            ),
                            label: Text(isFav ? 'In favorites' : 'Favorite'),
                          ),
                          if (album.metadata != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Details',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            AlbumMetadataPanel(metadata: album.metadata!),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            Expanded(
              child: Builder(
                builder: (context) {
                  final showHeader = !wide && album.metadata != null;
                  final hasRelated = album.relatedAlbums.isNotEmpty;
                  final headerCount = showHeader ? 1 : 0;
                  final itemCount =
                      headerCount + album.tracks.length + (hasRelated ? 1 : 0);

                  return ListView.builder(
                    padding: EdgeInsets.fromLTRB(wide ? 0 : 12, 12, 12, 120),
                    itemCount: itemCount,
                    itemBuilder: (context, i) {
                      // Narrow layout: collapsible details block on top.
                      if (showHeader && i == 0) {
                        return Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              12,
                              0,
                              12,
                              8,
                            ),
                            title: Text(
                              'Details',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: AlbumMetadataPanel(
                                  metadata: album.metadata!,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final j = i - headerCount;
                      // Tail item: "People who viewed this also viewed".
                      if (j == album.tracks.length) {
                        return RelatedAlbumsRow(albums: album.relatedAlbums);
                      }
                      final track = album.tracks[j];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: DpadTile(
                          autofocus: j == 0 && !showHeader,
                          borderRadius: 8,
                          onSelect: () {
                            unawaited(
                              ref
                                  .read(playerControllerProvider.notifier)
                                  .playAlbum(album, startIndex: j),
                            );
                            ref.read(fullscreenProvider.notifier).show();
                            Navigator.of(
                              context,
                            ).pushNamed('/now-playing', arguments: (album, j));
                          },
                          child: ListTile(
                            leading: SizedBox(
                              width: 36,
                              child: Text(
                                '${track.index}.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            title: Text(track.name, maxLines: 1),
                            subtitle: track.duration != null
                                ? Text(track.duration!)
                                : null,
                            trailing: const Icon(Icons.play_arrow),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
