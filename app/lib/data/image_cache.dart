import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// The cover-thumbnail cache that `cached_network_image` fills
/// (`DefaultCacheManager`, i.e. `<temp>/libCachedImageData`).
///
/// Behind a provider so Settings can report and empty it, and so tests can
/// substitute it: locating it needs path_provider, which does not answer inside
/// a widget test.
class ImageCacheStore {
  const ImageCacheStore();

  Future<Directory> directory() async {
    final tmp = await getTemporaryDirectory();
    return Directory(
      '${tmp.path}${Platform.pathSeparator}${DefaultCacheManager.key}',
    );
  }

  /// Empties the files *and* Flutter's decoded-bitmap cache: without the
  /// latter the thumbnails would keep showing (and holding memory) until the
  /// image cache evicted them on its own.
  Future<void> clear() async {
    await DefaultCacheManager().emptyCache();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }
}

final imageCacheProvider = Provider<ImageCacheStore>(
  (ref) => const ImageCacheStore(),
);
