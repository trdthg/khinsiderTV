import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../data/preferences_store.dart';

/// "People who viewed this also viewed" — horizontally scrolling grid with
/// two rows, shown at the bottom of the album screen.
class RelatedAlbumsRow extends ConsumerWidget {
  const RelatedAlbumsRow({super.key, required this.albums});

  final List<AlbumSummary> albums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'People who viewed this also viewed',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 2 * 170 + 12, // two rows + row gap
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, // two rows
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 220, // tile width
              ),
              itemCount: albums.length,
              itemBuilder: (context, i) {
                final album = albums[i];
                return DpadTile(
                  autofocus: false,
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
                              ? Image.network(
                                  album.thumbUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.album, size: 40),
                                )
                              : const Icon(Icons.album, size: 40),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            album.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
