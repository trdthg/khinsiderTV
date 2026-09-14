import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_cache_manager.dart';
import '../../core/dir_size.dart';
import '../../core/widgets/dpad_tile.dart';
import '../../data/image_cache.dart';
import '../../data/khinsider_client.dart';
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
    setState(() {
      _busy = true;
      _status = '正在清除…';
    });
    try {
      await _cache.clear();
      await ref.read(httpCacheProvider).clear();
      await _clearImageCache();
      await _reload();
      setState(() {
        _busy = false;
        _status = freed > 0 ? '已清除 ${formatBytes(freed)}' : '没有可清除的缓存';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '清除失败：$e';
      });
    }
  }

  Future<void> _clearPages() async {
    final freed = _pageBytes;
    setState(() {
      _busy = true;
      _status = '正在清除搜索缓存…';
    });
    try {
      await ref.read(httpCacheProvider).clear();
      await _reload();
      setState(() {
        _busy = false;
        _status = freed > 0 ? '已清除搜索缓存 ${formatBytes(freed)}' : '搜索缓存本来就是空的';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '清除失败：$e';
      });
    }
  }

  Future<void> _clearImages() async {
    final freed = _imageBytes;
    setState(() {
      _busy = true;
      _status = '正在清除图片缓存…';
    });
    try {
      await _clearImageCache();
      await _reload();
      setState(() {
        _busy = false;
        _status = freed > 0 ? '已清除图片缓存 ${formatBytes(freed)}' : '图片缓存本来就是空的';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '清除失败：$e';
      });
    }
  }

  Future<void> _delete(CachedAlbum album) async {
    setState(() {
      _busy = true;
      _status = '正在删除《${album.title}》…';
    });
    try {
      await _cache.deleteCachedAlbum(album.path);
      await _reload();
      setState(() {
        _busy = false;
        _status = '已删除《${album.title}》(${formatBytes(album.bytes)})';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '删除失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final albums = _albums;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SettingsHeader(title: '缓存'),
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
                          title: '位置',
                          children: [
                            SettingsRow(
                              icon: _publicMusic
                                  ? Icons.library_music_outlined
                                  : Icons.folder_outlined,
                              title: _root ?? '',
                              subtitle: _publicMusic
                                  ? '公开的 Music 目录：这里的文件同时是导出到 Music 的专辑'
                                  : '应用私有目录',
                            ),
                          ],
                        ),
                        SettingsSection(
                          title: '占用',
                          children: [
                            SettingsRow(
                              icon: Icons.sd_storage_outlined,
                              title: formatBytes(_totalBytes),
                              subtitle: [
                                albums.isEmpty
                                    ? '还没有缓存任何专辑'
                                    : '${albums.length} 张专辑 ${formatBytes(_albumBytes)}',
                                if (_pageBytes > 0)
                                  '搜索 ${formatBytes(_pageBytes)}',
                                if (_imageBytes > 0)
                                  '图片 ${formatBytes(_imageBytes)}',
                              ].join(' · '),
                            ),
                            SettingsRow(
                              icon: Icons.delete_sweep_outlined,
                              title: '清除全部缓存',
                              subtitle: _publicMusic
                                  ? '一键删除 Music/KHInsider 下的全部内容（包括已导出的专辑）'
                                  : '一键删除已下载的全部专辑文件',
                              danger: true,
                              onSelect: _busy ? null : _clearAll,
                            ),
                          ],
                        ),
                        SettingsSection(
                          title: '其它缓存',
                          children: [
                            SettingsRow(
                              icon: Icons.travel_explore_outlined,
                              title: '搜索与网页缓存',
                              subtitle:
                                  '${formatBytes(_pageBytes)} · 搜索结果和专辑页面的 HTML',
                              trailing: DpadIconButton(
                                icon: Icons.delete_outline,
                                tooltip: '清除搜索缓存',
                                onPressed: _busy ? null : _clearPages,
                              ),
                            ),
                            SettingsRow(
                              icon: Icons.image_outlined,
                              title: '图片缓存',
                              subtitle: '${formatBytes(_imageBytes)} · 封面缩略图',
                              trailing: DpadIconButton(
                                icon: Icons.delete_outline,
                                tooltip: '清除图片缓存',
                                onPressed: _busy ? null : _clearImages,
                              ),
                            ),
                          ],
                        ),
                        if (albums.isNotEmpty)
                          SettingsSection(
                            title: '已缓存的专辑',
                            children: [
                              for (final album in albums)
                                SettingsRow(
                                  icon: Icons.album_outlined,
                                  title: album.title,
                                  subtitle: [
                                    if (album.tracks > 0) '${album.tracks} 个文件',
                                    formatBytes(album.bytes),
                                    if (album.downloading) '下载中',
                                  ].join(' · '),
                                  trailing: DpadIconButton(
                                    icon: Icons.delete_outline,
                                    tooltip: '删除《${album.title}》的缓存',
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
