import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_cache_manager.dart';
import '../../core/dir_size.dart';
import '../../core/widgets/dpad_tile.dart';
import '../../data/image_cache.dart';
import '../../data/khinsider_client.dart';
import '../../l10n/l10n.dart';
import '../../state/track_cache_controller.dart';
import 'settings_widgets.dart';

/// Cache management: what is taking up space, one-tap "clear everything", and
/// deleting a single album.
///
/// The cache root is `<Music>/KHInsider` on desktop and on Android once the
/// user granted access to the public Music folder; otherwise it is private. The
/// screen says which one it is, because "clear" means something different in
/// each case (see [_publicMusic]).
class CacheScreen extends ConsumerStatefulWidget {
  const CacheScreen({super.key});

  @override
  ConsumerState<CacheScreen> createState() => _CacheScreenState();
}

class _CacheScreenState extends ConsumerState<CacheScreen> {
  List<CachedAlbum>? _albums;
  String? _root;
  bool _publicMusic = false;
  bool _busy = false;
  String? _status;
  int _pageBytes = 0;
  int _imageBytes = 0;

  AudioCacheManager get _cache => ref.read(audioCacheManagerProvider);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final albums = await _cache.listCachedAlbums();
    final root = await _cache.displayRoot;
    final publicMusic = await _cache.isUsingPublicMusicFolder;
    final pageBytes = await _sizeOf(_pageCacheDir);
    final imageBytes = await _sizeOf(_images.directory);
    if (!mounted) return;
    setState(() {
      _albums = albums;
      _root = root;
      _publicMusic = publicMusic;
      _pageBytes = pageBytes;
      _imageBytes = imageBytes;
    });
  }

  /// Size of a cache folder, or 0 when it cannot even be located (no temp
  /// directory yet, a platform channel that is not there in tests, ...).
  Future<int> _sizeOf(Future<Directory> Function() locate) async {
    try {
      return directorySize(await locate());
    } catch (_) {
      return 0;
    }
  }

  /// Where the HTML page cache lives (same folder `httpCacheProvider` uses).
  Future<Directory> _pageCacheDir() => ref.read(httpCacheProvider).directory;

  ImageCacheStore get _images => ref.read(imageCacheProvider);

  int get _albumBytes =>
      (_albums ?? const <CachedAlbum>[]).fold(0, (sum, a) => sum + a.bytes);

  int get _totalBytes => _albumBytes + _pageBytes + _imageBytes;

  Future<void> _clearImageCache() => _images.clear();

  Future<void> _clearAll() async {
    final freed = _totalBytes;
    final l = l10n(context);
    setState(() {
      _busy = true;
      _status = l.cacheClearing;
    });
    try {
      await _cache.clear();
      await ref.read(httpCacheProvider).clear();
      await _clearImageCache();
      await _reload();
      setState(() {
        _busy = false;
        _status = freed > 0
            ? l.cacheCleared(formatBytes(freed))
            : l.cacheNothingToClear;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = l.cacheClearFailed('$e');
      });
    }
  }

  Future<void> _clearPages() async {
    final freed = _pageBytes;
    final l = l10n(context);
    setState(() {
      _busy = true;
      _status = l.cacheClearingSearch;
    });
    try {
      await ref.read(httpCacheProvider).clear();
      await _reload();
      setState(() {
        _busy = false;
        _status = freed > 0
            ? l.cacheSearchCleared(formatBytes(freed))
            : l.cacheSearchAlreadyEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = l.cacheClearFailed('$e');
      });
    }
  }

  Future<void> _clearImages() async {
    final freed = _imageBytes;
    final l = l10n(context);
    setState(() {
      _busy = true;
      _status = l.cacheClearingImages;
    });
    try {
      await _clearImageCache();
      await _reload();
      setState(() {
        _busy = false;
        _status = freed > 0
            ? l.cacheImagesCleared(formatBytes(freed))
            : l.cacheImagesAlreadyEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = l.cacheClearFailed('$e');
      });
    }
  }

  Future<void> _delete(CachedAlbum album) async {
    final l = l10n(context);
    setState(() {
      _busy = true;
      _status = l.cacheDeleting(album.title);
    });
    try {
      await _cache.deleteCachedAlbum(album.path);
      await _reload();
      setState(() {
        _busy = false;
        _status = l.cacheDeleted(album.title, formatBytes(album.bytes));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = l.cacheDeleteFailed('$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final albums = _albums;
    final theme = Theme.of(context);
    final l = l10n(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SettingsHeader(title: l.cacheTitle),
            // Keeps its height when idle so the list does not jump.
            SizedBox(
              height: 4,
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: LinearProgressIndicator(),
                    )
                  : null,
            ),
            Expanded(
              child: albums == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        SettingsSection(
                          title: l.cacheLocation,
                          children: [
                            SettingsRow(
                              icon: _publicMusic
                                  ? Icons.library_music_outlined
                                  : Icons.folder_outlined,
                              title: _root ?? '',
                              subtitle: _publicMusic
                                  ? l.cachePublicMusic
                                  : l.cacheAppPrivate,
                            ),
                          ],
                        ),
                        SettingsSection(
                          title: l.cacheUsage,
                          children: [
                            SettingsRow(
                              icon: Icons.sd_storage_outlined,
                              title: formatBytes(_totalBytes),
                              subtitle: [
                                albums.isEmpty
                                    ? l.cacheNoAlbums
                                    : l.cacheAlbumCount(
                                        albums.length,
                                        formatBytes(_albumBytes),
                                      ),
                                if (_pageBytes > 0)
                                  l.cacheSearchUsage(formatBytes(_pageBytes)),
                                if (_imageBytes > 0)
                                  l.cacheImageUsage(formatBytes(_imageBytes)),
                              ].join(' · '),
                            ),
                            SettingsRow(
                              icon: Icons.delete_sweep_outlined,
                              title: l.cacheClearAll,
                              subtitle: _publicMusic
                                  ? l.cacheClearAllMusicSubtitle
                                  : l.cacheClearAllSubtitle,
                              danger: true,
                              onSelect: _busy ? null : _clearAll,
                            ),
                          ],
                        ),
                        SettingsSection(
                          title: l.cacheOther,
                          children: [
                            SettingsRow(
                              icon: Icons.travel_explore_outlined,
                              title: l.cacheSearchAndPages,
                              subtitle: l.cacheSearchPagesSubtitle(
                                formatBytes(_pageBytes),
                              ),
                              trailing: DpadIconButton(
                                icon: Icons.delete_outline,
                                tooltip: l.cacheClearSearch,
                                onPressed: _busy ? null : _clearPages,
                              ),
                            ),
                            SettingsRow(
                              icon: Icons.image_outlined,
                              title: l.cacheImages,
                              subtitle: l.cacheImagesSubtitle(
                                formatBytes(_imageBytes),
                              ),
                              trailing: DpadIconButton(
                                icon: Icons.delete_outline,
                                tooltip: l.cacheClearImages,
                                onPressed: _busy ? null : _clearImages,
                              ),
                            ),
                          ],
                        ),
                        if (albums.isNotEmpty)
                          SettingsSection(
                            title: l.cacheCachedAlbums,
                            children: [
                              for (final album in albums)
                                SettingsRow(
                                  icon: Icons.album_outlined,
                                  title: album.title,
                                  subtitle: [
                                    if (album.tracks > 0)
                                      l.cacheFileCount(album.tracks),
                                    formatBytes(album.bytes),
                                    if (album.downloading) l.cacheDownloading,
                                  ].join(' · '),
                                  trailing: DpadIconButton(
                                    icon: Icons.delete_outline,
                                    tooltip: l.cacheDeleteAlbum(album.title),
                                    onPressed: _busy
                                        ? null
                                        : () => _delete(album),
                                  ),
                                ),
                            ],
                          ),
                        if (_status != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                            child: Text(
                              _status!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
