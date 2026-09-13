import 'dart:io';

import 'package:khinsider_api/khinsider_api.dart';

import 'android_storage.dart';
import 'audio_cache_manager.dart';

/// What one [MusicExporter.exportAlbum] run did.
class MusicExportReport {
  const MusicExportReport({
    this.folder,
    this.exported = 0,
    this.alreadyThere = 0,
    this.unsupported = 0,
    this.failed = 0,
  });

  /// Where the copies went, e.g. `Music/KHInsider/Album Name`. Null when there
  /// was nothing to export.
  final String? folder;

  final int exported;
  final int alreadyThere;
  final int unsupported;
  final int failed;

  /// Tracks that had a cached file and were therefore looked at.
  int get considered => exported + alreadyThere + unsupported + failed;

  bool get isEmpty => considered == 0;

  /// One-line summary for the UI.
  String get summary {
    if (isEmpty) return 'Nothing cached yet.';
    final parts = <String>[];
    if (exported > 0) {
      parts.add(
        'Exported $exported track${exported == 1 ? '' : 's'} to '
        '${folder ?? 'the Music folder'}',
      );
    }
    if (alreadyThere > 0) {
      parts.add('$alreadyThere already there');
    }
    if (failed > 0) {
      parts.add('$failed failed');
    }
    if (unsupported > 0) {
      parts.add('$unsupported need Android 10+');
    }
    return parts.join(' · ');
  }
}

/// Copies cached tracks into the system `Music/` folder.
///
/// The download cache stays where it is and keeps working exactly as before
/// (see [AudioCacheManager]); this only *adds* a user-visible copy, written
/// through MediaStore so it needs no permission on Android 10+ — the point
/// being that the user does not have to grant "all files access" for their
/// music to show up in the system music library.
///
/// A track is exported from its best cached copy (lossless when the lossless
/// file is on disk, otherwise MP3), and an existing copy of the same file name
/// is left alone, so exporting twice does not pile up duplicates.
class MusicExporter {
  MusicExporter(this._cache, {AndroidStorage? storage})
    : _storage = storage ?? const MethodChannelAndroidStorage();

  final AudioCacheManager _cache;
  final AndroidStorage _storage;

  /// Root folder inside the public music directory (matches the cache layout).
  static const String musicFolder = 'Music/${AudioCacheManager.appFolderName}';

  /// Exports every cached track of [album], one file at a time.
  ///
  /// [onProgress] is called with `(done, total)` after each file, so a dialog
  /// can show how far along the run is.
  Future<MusicExportReport> exportAlbum(
    Album album, {
    void Function(int done, int total)? onProgress,
  }) async {
    final storage = _storage;
    // The cache root has to be resolved before the album folder can be located
    // synchronously (that is also what the cache scan does).
    await _cache.root();
    final dir = _cache.locateAlbumDirSync(
      album.summary.id,
      album.summary.title,
    );
    final folder = '$musicFolder/${_albumFolderName(album, dir)}';

    final exports = _collect(album);
    if (exports.isEmpty) return const MusicExportReport();

    var exported = 0;
    var alreadyThere = 0;
    var unsupported = 0;
    var failed = 0;
    var done = 0;
    for (final export in exports) {
      final status = await storage.exportToMusic(
        relativePath: folder,
        displayName: export.fileName,
        sourcePath: export.path,
        mimeType: export.mimeType,
        title: export.title,
        album: album.summary.title,
      );
      switch (status) {
        case MusicExportStatus.exported:
          exported++;
        case MusicExportStatus.alreadyThere:
          alreadyThere++;
        case MusicExportStatus.unsupported:
          unsupported++;
        case MusicExportStatus.failed:
          failed++;
      }
      onProgress?.call(++done, exports.length);
    }
    return MusicExportReport(
      folder: folder,
      exported: exported,
      alreadyThere: alreadyThere,
      unsupported: unsupported,
      failed: failed,
    );
  }

  /// One file per cached track: the lossless copy when it is on disk, otherwise
  /// the MP3. Tracks that are not cached (or are still downloading) are skipped.
  List<_PendingExport> _collect(Album album) {
    final result = <_PendingExport>[];
    for (final track in album.tracks) {
      final base = CacheLookupKey(
        albumId: album.summary.id,
        albumTitle: album.summary.title,
        trackIndex: track.index,
        trackTitle: track.name,
      );
      for (final key in [base.withLossless[1], base]) {
        final status = _cache.statusForSync(key);
        final uri = status.bytes == null ? null : _cache.cachedFileUri(key);
        final path = uri?.toFilePath();
        if (path == null) continue;
        result.add(
          _PendingExport(
            fileName: AudioCacheManager.trackFileName(
              trackIndex: track.index,
              title: track.name,
              ext: key.extension,
            ),
            path: path,
            mimeType: key.extension == '.flac' ? 'audio/flac' : 'audio/mpeg',
            title: track.name,
          ),
        );
        break;
      }
    }
    return result;
  }

  /// The album's folder name inside the export root.
  ///
  /// Reuses the cache folder's name when the album already has one (it may be
  /// disambiguated with an id hash when two albums share a title), so one album
  /// always maps to one folder in `Music/`.
  String _albumFolderName(Album album, Directory? cacheDir) {
    final name = cacheDir?.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .lastOrNull;
    return name ?? AudioCacheManager.sanitizeFolderName(album.summary.title);
  }
}

class _PendingExport {
  const _PendingExport({
    required this.fileName,
    required this.path,
    required this.mimeType,
    required this.title,
  });

  final String fileName;
  final String path;
  final String mimeType;
  final String title;
}
