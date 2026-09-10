import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../../core/widgets/dpad_tile.dart';
import '../../data/preferences_store.dart';
import '../../state/album_controller.dart';
import '../../state/player_controller.dart';
import '../now_playing/zen_view.dart';
import 'album_metadata.dart';
import 'related_albums.dart';

/// Album detail screen with two modes on ONE page:
///
///  * normal — header, metadata panel, related albums, full track list;
///  * zen — immersive now-playing mode (art + track list only).
///
/// Activating a track starts playback and morphs the page into zen mode:
/// the surrounding elements fade / fly away, the art and track list settle
/// into their now-playing positions, and the zen layer fades in.
/// Esc reverses the whole transition back to the normal layout.
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key, required this.albumId});

  final String albumId;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen>
    with TickerProviderStateMixin {
  int _refreshNonce = 0;
  bool _zen = false;
  int _zenStartIndex = 0;
  late final AnimationController _zenCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _zenT = CurvedAnimation(
    parent: _zenCtrl,
    curve: Curves.easeInOutCubic,
  );

  void _enterZen(int trackIndex) {
    setState(() {
      _zenStartIndex = trackIndex;
      _zen = true;
    });
    _zenCtrl.forward();
  }

  void _exitZen() {
    setState(() => _zen = false);
    _zenCtrl.reverse();
  }

  @override
  void dispose() {
    _zenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(
      albumDetailProvider((widget.albumId, _refreshNonce)),
    );

    return Scaffold(
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
        data: (album) => _AlbumPage(
          album: album,
          zen: _zen,
          zenT: _zenT,
          zenCtrl: _zenCtrl,
          zenStartIndex: _zenStartIndex,
          onTrackActivated: (index) {
            unawaited(
              ref
                  .read(playerControllerProvider.notifier)
                  .playAlbum(album, startIndex: index),
            );
            _enterZen(index);
          },
          onExitZen: _exitZen,
          onRefresh: () => setState(() => _refreshNonce++),
        ),
      ),
    );
  }
}

class _AlbumPage extends ConsumerStatefulWidget {
  const _AlbumPage({
    required this.album,
    required this.zen,
    required this.zenT,
    required this.zenCtrl,
    required this.zenStartIndex,
    required this.onTrackActivated,
    required this.onExitZen,
    required this.onRefresh,
  });

  final Album album;
  final bool zen;

  /// 0 = album layout, 1 = zen layout.
  final Animation<double> zenT;
  final AnimationController zenCtrl;
  final int zenStartIndex;
  final ValueChanged<int> onTrackActivated;
  final VoidCallback onExitZen;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends ConsumerState<_AlbumPage> {
  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final scheme = Theme.of(context).colorScheme;
    final zenT = widget.zenT;

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 700;

        return AnimatedBuilder(
          animation: zenT,
          builder: (context, _) {
            final t = zenT.value;

            return Stack(
              fit: StackFit.expand,
              children: [
                _buildBackdrop(scheme, t),
                SafeArea(
                  child: Column(
                    children: [
                      _buildHeader(album, t),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildNormalLayer(album, t, wide),
                            // Mounted only while zen is (or was just) active.
                            if (widget.zen || widget.zenCtrl.isAnimating)
                              _buildZenLayer(album, t),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBackdrop(ColorScheme scheme, double t) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.55, -0.2),
            radius: 1.3,
            colors: [
              scheme.primary.withValues(alpha: 0.25 * t),
              scheme.surface.withValues(alpha: 0.92 * t),
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildHeader(Album album, double t) {
    return Opacity(
      opacity: (1 - t).clamp(0.0, 1.0),
      child: Row(
        children: [
          BackButton(onPressed: widget.zen ? null : () {}),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              album.summary.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: 'Force refresh (bypass cache)',
            onPressed: widget.zen ? null : widget.onRefresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildNormalLayer(Album album, double t, bool wide) {
    return IgnorePointer(
      ignoring: widget.zen,
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: wide ? _wideLayout(album, t) : _narrowLayout(album, t),
      ),
    );
  }

  Widget _wideLayout(Album album, double t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Transform.translate(
          offset: Offset(-360 * t, 120 * t),
          child: Opacity(
            opacity: (1 - t).clamp(0.0, 1.0),
            child: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _LeftPanel(album: album),
              ),
            ),
          ),
        ),
        Expanded(
          child: Transform.translate(
            offset: Offset(0, 480 * t),
            child: Opacity(
              opacity: (1 - t).clamp(0.0, 1.0),
              child: FocusTraversalGroup(
                child: _TrackListView(
                  album: album,
                  onTrackActivated: widget.onTrackActivated,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _narrowLayout(Album album, double t) {
    return Transform.translate(
      offset: Offset(0, 480 * t),
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: FocusTraversalGroup(
          child: _TrackListView(
            album: album,
            onTrackActivated: widget.onTrackActivated,
          ),
        ),
      ),
    );
  }

  Widget _buildZenLayer(Album album, double t) {
    return IgnorePointer(
      ignoring: !widget.zen,
      child: Opacity(
        opacity: Curves.easeIn.transform(t.clamp(0.0, 1.0)),
        child: ZenNowPlaying(
          album: album,
          active: widget.zen,
          initialTrackIndex: widget.zenStartIndex,
          onExitZen: widget.onExitZen,
        ),
      ),
    );
  }
}

class _LeftPanel extends StatelessWidget {
  const _LeftPanel({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (album.coverUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 252,
              height: 252,
              child: CachedNetworkImage(
                imageUrl: album.coverUrl!,
                fit: BoxFit.cover,
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          album.summary.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          '${album.trackCount} tracks',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _FavoriteButton(album: album),
        if (album.metadata != null) ...[
          const SizedBox(height: 16),
          Text('Details', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          AlbumMetadataPanel(metadata: album.metadata!),
        ],
      ],
    );
  }
}

class _TrackListView extends ConsumerWidget {
  const _TrackListView({required this.album, required this.onTrackActivated});

  final Album album;
  final ValueChanged<int> onTrackActivated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      type: MaterialType.transparency,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: album.tracks.length + 1,
        itemBuilder: (context, i) {
          // Tail: "People who viewed this also viewed".
          if (i == album.tracks.length) {
            return RelatedAlbumsRow(albums: album.relatedAlbums);
          }
          final track = album.tracks[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: DpadTile(
              autofocus: i == 0,
              borderRadius: 8,
              onSelect: () => onTrackActivated(i),
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
                subtitle: track.duration != null ? Text(track.duration!) : null,
                trailing: const Icon(Icons.play_arrow),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav =
        ref
            .watch(favoritesProvider)
            .value
            ?.any((a) => a.id == album.summary.id) ??
        false;
    return FilledButton.tonalIcon(
      onPressed: () =>
          ref.read(favoritesProvider.notifier).toggle(album.summary),
      icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
      label: Text(isFav ? 'In favorites' : 'Favorite'),
    );
  }
}
