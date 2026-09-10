import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Local audio cache: one file per media URL, stored under
/// Application Support/audio_cache.
///
/// Filenames are stable hashes of the source URL, so:
///  * partial downloads resume across restarts (LockCachingAudioSource
///    appends with HTTP range requests),
///  * a re-queued track never downloads twice.
///
/// Files are written progressively by just_audio's LockCachingAudioSource —
/// playback streams while the file fills on disk (边缓存边播放).
class AudioCacheManager {
  Directory? _dir;

  Future<Directory> cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}audio_cache');
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// Stable cache file for [url] (hash + proper extension).
  Future<File> fileFor(String url) async {
    final dir = await cacheDir();
    final hash = sha1.convert(utf8.encode(url)).toString();
    return File('${dir.path}${Platform.pathSeparator}$hash${_extOf(url)}');
  }

  static String _extOf(String url) {
    final path = url.split('?').first.toLowerCase();
    if (path.endsWith('.flac')) return '.flac';
    if (path.endsWith('.ogg') || path.endsWith('.oga')) return '.ogg';
    if (path.endsWith('.m4a') || path.endsWith('.mp4')) return '.m4a';
    if (path.endsWith('.wav')) return '.wav';
    if (path.endsWith('.opus')) return '.opus';
    return '.mp3';
  }

  /// Total cached bytes (for a future settings entry).
  Future<int> totalSize() async {
    final dir = await cacheDir();
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  /// Wipe the whole cache.
  Future<void> clear() async {
    final dir = await cacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
  }
}
