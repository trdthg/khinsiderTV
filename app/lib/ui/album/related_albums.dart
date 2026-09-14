import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../core/widgets/dpad_nav.dart';
import '../../data/preferences_store.dart';

/// "People who viewed this also viewed" — horizontally scrolling grid with
/// two rows, shown at the bottom of the album screen.
///
/// [exitT] drives the zen morph: 0 = fully visible, 1 = gone. The whole
/// related-albums row slides away and fades as one unit, and the row
/// collapses. Reversing the morph brings it back the same way.
class RelatedAlbumsRow extends ConsumerWidget {
  const RelatedAlbumsRow({super.key, required this.albums, this.exitT = 0.0});

  final List<AlbumSummary> albums;

  /// 0 = album layout, 1 = zen layout.
  final double exitT;

  static const double _tileWidth = 220;
  static const double _rowHeight = 170;
  static const double _rowGap = 12;
  static const double _gridHeight = 2 * _rowHeight + _rowGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fully out: keep the tree honest and drop the (now invisible) tiles.
    if (exitT >= 1.0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final t = Curves.easeInOut.transform(exitT);
    final collapse = (1 - t).clamp(0.0, 1.0);

    return ClipRect(
      child: Align(
        alignment: Alignment.topLeft,
        heightFactor: collapse,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: 1 - t,
                child: Text(
                  'People who viewed this also viewed',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              // The whole row is one unit: it slides away and fades as a group.
              SizedBox(
                height: _gridHeight,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minHeight: 0,
                  maxHeight: _gridHeight,
                  child: Transform.translate(
                    offset: Offset(0, 110 * t),
                    child: Opacity(
                      opacity: 1 - t,
                      child: SizedBox(
                        height: _gridHeight,
                        child: GridView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.zero,
                          physics: t > 0
                              ? const NeverScrollableScrollPhysics()
                              : null,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: _rowGap,
                                mainAxisSpacing: _rowGap,
                                mainAxisExtent: _tileWidth,
                              ),
                          itemCount: albums.length,
                          itemBuilder: (context, i) {
                            final album = albums[i];
                            return DpadNav(
                              // The track list's tail stops at its own
                              // horizontal ends for the same reason.
                              stopLeft: i == 0,
                              stopRight: i == albums.length - 1,
                              child: DpadTile(
                                autofocus: false,
                                onSelect: () {
                                  ref
                                      .read(recentAlbumsProvider.notifier)
                                      .record(album);
                                  Navigator.pushNamed(
                                    context,
                                    '/album',
                                    arguments: album,
                                  );
                                },
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: album.imageUrl == null
                                            ? const Icon(Icons.album, size: 40)
                                            : CachedNetworkImage(
                                                imageUrl: album.imageUrl ?? '',
                                                fit: BoxFit.cover,
                                              ),
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
                              ),
                            );
                          },
                        ),
                      ),
                    ),
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
