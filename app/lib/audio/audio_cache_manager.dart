import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:khinsider_api/khinsider_api.dart';
import 'package:path_provider/path_provider.dart';

import 'android_storage.dart';
import 'base_audio_player.dart';

/// Where the user-visible cache lives.
///
/// The whole point of this layout is that **the user can see it**: cached
/// tracks land inside the OS music folder, one folder per album, with the
/// media sorted into `mp3` / `flac` / `image` / `other`, so they can be found,
/// deleted or played by any other player without going through this app.
///
/// ```text
/// <Music>/KHInsider/<Album name>/
///   mp3/    01 Track Name.mp3
///   flac/   01 Track Name.flac
///   image/  cover.jpg
///   other/  album.json + anything that is neither mp3 nor flac
/// ```
///
/// Notes:
///  * File names are derived from the track number + title (NOT a hash), so
///    they stay readable outside the app. The album id is only used to detect
///    two different albums that happen to share a title.
///  * `just_audio`'s `LockCachingAudioSource` appends to `<file>.part` while
///    downloading and renames it to `<file>` when the download completes; it
///    also keeps a `<file>.mime` sidecar. Both are dot-suffixed, so the folder
///    stays tidy for the user, and `.part` tells us a download is still in
///    flight (see [TrackCacheStatus.downloading]).
class AudioCacheManager {
  // Private field, so an initializing formal is not possible here.
  // ignore: prefer_initializing_formals
  AudioCacheManager({
    Directory? rootOverride,
    AndroidStorage? androidStorage,
    bool? isAndroid,
  }) : _androidStorage = androidStorage ?? const MethodChannelAndroidStorage(),
       _isAndroid = isAndroid ?? Platform.isAndroid {
    if (rootOverride != null) {
      _rootOverride = rootOverride;
      _resolvedRoot = rootOverride;
    }
  }

  /// Test / advanced-use escape hatch: pin the cache root instead of resolving
  /// the system music folder.
  Directory? _rootOverride;

  /// Android "all files access" + the platform music directory.
  final AndroidStorage _androidStorage;

  /// Injected for tests; Android needs its own root resolution because scoped
  /// storage hides `Music/` behind a special permission.
  final bool _isAndroid;

  Directory? _resolvedRoot;

  /// albumId -> resolved album folder (saves repeated disk lookups while
  /// playback is appending tracks).
  final Map<String, Directory> _albumDirs = {};

  /// Namespace folder inside the user's Music directory.
  static const String appFolderName = 'KHInsider';

  /// Media category folders inside an album folder.
  static const String mp3Folder = 'mp3';
  static const String flacFolder = 'flac';
  static const String imageFolder = 'image';
  static const String otherFolder = 'other';

  static const List<String> categoryFolders = [
    mp3Folder,
    flacFolder,
    imageFolder,
    otherFolder,
  ];

  static final String _sep = Platform.pathSeparator;

  // ---------------------------------------------------------------- paths

  /// Human-readable location of the cache root, e.g. `Music/KHInsider`.
  /// Only used for UI hints; never for file math.
  Future<String> get displayRoot async {
    final dir = await root();
    return dir.path;
  }

  /// The cache root (`<Music>/KHInsider`), created on demand.
  ///
  /// Resolved once, then memoized: every later call is free (and synchronous
  /// work can safely build on top of it).
  Future<Directory> root() async {
    final memo = _resolvedRoot;
    if (memo != null) return memo;
    final override = _rootOverride;
    if (override != null) {
      await override.create(recursive: true);
      return _resolvedRoot = override;
    }
    final base = await _resolveRoot();
    if (base == null) {
      // No music folder: fall back to Application Support so playback and
      // resuming still work.
      final support = await getApplicationSupportDirectory();
      return _resolvedRoot = _createSync(
        Directory('${support.path}$_sep$appFolderName'),
      );
    }
    try {
      return _resolvedRoot = _createSync(
        Directory('${base.path}$_sep$appFolderName'),
      );
    } on FileSystemException {
      // macOS sandbox / read-only home: keep playback working even when the
      // user-visible Music folder cannot be created.
      final support = await getApplicationSupportDirectory();
      return _resolvedRoot = _createSync(
        Directory('${support.path}$_sep$appFolderName'),
      );
    }
  }

  Future<Directory?> _resolveRoot() async {
    if (_isAndroid) return _resolveAndroidRoot();
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home == null || home.isEmpty) return null;
      if (Platform.isLinux) {
        final xdg = _xdgMusicDir(home);
        if (xdg != null) return Directory(xdg);
      }
      return Directory('$home${_sep}Music');
    }
    // iOS: the app documents folder is the only place the Files app exposes
    // without MediaStore / photo-library plumbing.
    return getApplicationDocumentsDirectory();
  }

  /// Android: use the public `Music/` folder when the user granted all-files
  /// access, otherwise fall back to the app documents folder (scoped storage
  /// would make writes into `Music/` fail, or worse, silently land in a
  /// redirected per-app view).
  Future<Directory?> _resolveAndroidRoot() async {
    try {
      if (!await _androidStorage.canWritePublicMusic()) {
        return getApplicationDocumentsDirectory();
      }
      final music = await _androidStorage.publicMusicPath();
      if (music == null || music.isEmpty) {
        return getApplicationDocumentsDirectory();
      }
      return Directory(music);
    } on Exception {
      return getApplicationDocumentsDirectory();
    }
  }

  /// Whether the public music folder can be offered at all (Android only).
  bool get supportsPublicMusicFolder => _isAndroid;

  /// Opens the Android all-files-access screen. No-op on other platforms.
  Future<void> requestPublicMusicAccess() =>
      _androidStorage.requestAllFilesAccess();

  /// Whether the cache currently lives in the system music folder.
  Future<bool> get isUsingPublicMusicFolder async {
    if (!_isAndroid) return false;
    try {
      if (!await _androidStorage.canWritePublicMusic()) return false;
      final music = await _androidStorage.publicMusicPath();
      if (music == null || music.isEmpty) return false;
      final dir = _resolvedRoot ?? await root();
      return dir.path == '${Directory(music).path}$_sep$appFolderName';
    } on Exception {
      return false;
    }
  }

  /// Forgets the memoized root so the next [root] call resolves it again.
  ///
  /// Used after the user grants all-files access: the cache then moves to
  /// `Music/KHInsider` on the next write. Files already downloaded stay in the
  /// old folder (they remain playable from the file manager); the caller can
  /// point that out to the user.
  void forgetRoot() {
    if (_rootOverride != null) return;
    _resolvedRoot = null;
    _albumDirs.clear();
  }

  /// Parses `XDG_MUSIC_DIR` out of `~/.config/user-dirs.dirs`.
  String? _xdgMusicDir(String home) {
    try {
      final file = File(
        '$home$_sep.config$_sep user-dirs.dirs'.replaceFirst('$_sep ', _sep),
      );
      if (!file.existsSync()) return null;
      for (final raw in file.readAsLinesSync()) {
        final line = raw.trim();
        if (!line.startsWith('XDG_MUSIC_DIR')) continue;
        final match = RegExp(r'"([^"]*)"').firstMatch(line);
        if (match == null) continue;
        var value = match.group(1)!;
        if (value.startsWith(r'$HOME')) value = '$home${value.substring(5)}';
        if (value.startsWith('/')) return value;
        return '$home$_sep$value';
      }
    } catch (_) {
      // Malformed config: fall through to the default.
    }
    return null;
  }

  // --------------------------------------------------------------- albums

  /// The folder of [albumTitle], creating it (and the category folders) when
  /// [create] is set. Returns null when it does not exist and we must not
  /// create it — used by the read-only cache-status scan.
  ///
  /// Synchronous on purpose: it is a couple of `stat` calls, and the cache
  /// status of a whole album has to be readable from anywhere (including a
  /// build/test environment) without waiting on the event loop.
  Directory? locateAlbumDirSync(
    String albumId,
    String albumTitle, {
    bool create = false,
  }) {
    final memo = _albumDirs[albumId];
    if (memo != null && memo.existsSync()) return memo;

    final rootDir = _resolvedRoot;
    if (rootDir == null) return null;

    final base = sanitizeFolderName(albumTitle);
    var dir = Directory('${rootDir.path}$_sep$base');

    // Two different albums can share a title. `album.json` records who owns
    // the folder; if the title is taken, disambiguate with a short id hash.
    if (dir.existsSync()) {
      final owner = _manifestAlbumIdSync(dir);
      if (owner != null && owner != albumId) {
        dir = Directory('${rootDir.path}$_sep$base (${_shortHash(albumId)})');
      }
    }
    if (!create && !dir.existsSync()) return null;

    _createSync(dir);
    for (final name in categoryFolders) {
      _createSync(Directory('${dir.path}$_sep$name'));
    }
    if (create) {
      _writeManifestIdSync(dir, albumId, albumTitle);
    }
    return _albumDirs[albumId] = dir;
  }

  /// Alias used by the playback layer: always creates the folder.
  Future<Directory> albumDir(String albumId, String albumTitle) async {
    await root(); // make sure the root is resolved
    return locateAlbumDirSync(albumId, albumTitle, create: true)!;
  }

  // ---------------------------------------------------------------- files

  /// Cache file for [item]: `<album>/<category>/<NN Track Name><ext>`.
  Future<File> fileFor(PlayableItem item) async {
    await root();
    return fileForSync(item);
  }

  /// Synchronous twin of [fileFor].
  File fileForSync(PlayableItem item) {
    final dir = categoryDirSync(item);
    final name = trackFileName(
      trackIndex: item.trackIndex,
      title: item.title,
      ext: extensionOf(item.url),
    );
    return File('${dir.path}$_sep$name');
  }

  /// `mp3/`, `flac/` or `other/` inside the item's album folder, chosen from
  /// the media URL extension.
  Directory categoryDirSync(PlayableItem item) {
    final album = locateAlbumDirSync(
      item.albumId,
      item.albumTitle ?? 'Unknown album',
      create: true,
    )!;
    return Directory(
      '${album.path}$_sep${categoryForExtension(extensionOf(item.url))}',
    );
  }

  /// Category folder for a media extension.
  static String categoryForExtension(String ext) {
    switch (ext) {
      case '.mp3':
        return mp3Folder;
      case '.flac':
        return flacFolder;
      default:
        return otherFolder;
    }
  }

  /// Extension of a media URL (`.mp3` fallback, matching KHInsider URLs).
  static String extensionOf(String url) {
    final path = url.split('?').first.toLowerCase();
    for (final ext in const [
      '.mp3',
      '.flac',
      '.ogg',
      '.oga',
      '.m4a',
      '.mp4',
      '.wav',
      '.opus',
      '.webm',
    ]) {
      if (path.endsWith(ext)) return ext;
    }
    return '.mp3';
  }

  /// `01 Track Name.mp3` — stable, readable, sortable.
  static String trackFileName({
    int? trackIndex,
    required String title,
    required String ext,
  }) {
    final name = sanitizeFolderName(title);
    final number = trackIndex == null ? null : _padded(trackIndex);
    return number == null ? '$name$ext' : '$number $name$ext';
  }

  static String _padded(int index) => index < 10 ? '0$index' : '$index';

  /// Strips characters that are illegal (or merely annoying) in file names on
  /// the platforms this app ships to.
  static String sanitizeFolderName(String raw, {int maxLength = 96}) {
    var s = raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    while (s.startsWith('.')) {
      s = s.substring(1).trim();
    }
    while (s.endsWith('.')) {
      s = s.substring(0, s.length - 1).trim();
    }
    if (s.length > maxLength) s = s.substring(0, maxLength).trim();
    if (s.isEmpty) s = 'untitled';
    return s;
  }

  // ------------------------------------------------------- album sidecars

  /// Writes `image/cover.jpg` (skipped when already there).
  Future<File?> cacheAlbumCover(
    String albumId,
    String albumTitle,
    String? coverUrl,
  ) async {
    if (coverUrl == null || coverUrl.isEmpty) return null;
    try {
      final album = await albumDir(albumId, albumTitle);
      final uri = Uri.tryParse(coverUrl);
      if (uri == null) return null;
      final ext = uri.path.toLowerCase().endsWith('.png') ? '.png' : '.jpg';
      final file = File('${album.path}$_sep$imageFolder${_sep}cover$ext');
      if (file.existsSync()) return file;
      final client = HttpClient();
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode != 200) return null;
        final bytes = await response.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        );
        if (bytes.isEmpty) return null;
        await file.writeAsBytes(bytes, flush: true);
        return file;
      } finally {
        client.close();
      }
    } catch (_) {
      // A cover is a nice-to-have; never break playback over it.
      return null;
    }
  }

  /// Writes `other/album.json`: title, cover and the full track list with the
  /// original page URL, so the folder is self-describing once exported.
  Future<void> saveAlbumManifest(Album album) async {
    try {
      final dir = await albumDir(album.summary.id, album.summary.title);
      final file = File('${dir.path}$_sep$otherFolder${_sep}album.json');
      final data = {
        'id': album.summary.id,
        'title': album.summary.title,
        'source': album.summary.pageUrl,
        'coverUrl': album.imageUrl,
        if (album.metadata?.year != null) 'year': album.metadata!.year,
        if (album.metadata?.platforms.isNotEmpty ?? false)
          'platforms': album.metadata!.platforms,
        'tracks': [
          for (final t in album.tracks)
            {
              'index': t.index,
              'name': t.name,
              if (t.duration != null) 'duration': t.duration,
              if (t.mp3SizeMb != null) 'mp3SizeMb': t.mp3SizeMb,
              if (t.flacSizeMb != null) 'flacSizeMb': t.flacSizeMb,
              'page': 'https://downloads.khinsider.com${t.trackPagePath}',
            },
        ],
      };
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );
    } catch (_) {
      // Manifest is a nice-to-have; never break playback over it.
    }
  }

  String? _manifestAlbumIdSync(Directory albumDir) {
    try {
      final file = File('${albumDir.path}$_sep$otherFolder${_sep}album.json');
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) return decoded['id'] as String?;
    } catch (_) {
      return null;
    }
    return null;
  }

  void _writeManifestIdSync(Directory albumDir, String id, String title) {
    final file = File('${albumDir.path}$_sep$otherFolder${_sep}album.json');
    if (file.existsSync()) return; // a richer manifest wins
    try {
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({'id': id, 'title': title}),
        flush: true,
      );
    } catch (_) {}
  }

  // ---------------------------------------------------------- cache status

  /// Cache state of one track, read from disk.
  ///
  /// Synchronous: resolving the whole album's status is a handful of `stat`
  /// calls, and doing it without the event loop keeps it usable from the UI
  /// (and from widget tests).
  TrackCacheStatus statusForSync(CacheLookupKey key) {
    final album = locateAlbumDirSync(key.albumId, key.albumTitle);
    if (album == null) return TrackCacheStatus.absent;
    final name = trackFileName(
      trackIndex: key.trackIndex,
      title: key.trackTitle,
      ext: key.extension,
    );
    final dir = Directory(
      '${album.path}$_sep${categoryForExtension(key.extension)}',
    );
    return _readStatusSync(dir, name);
  }

  /// URI of a completed cached file for [key], or null when absent.
  ///
  /// Used to skip the KHInsider track-page round-trip when the audio file is
  /// already on disk.
  Uri? cachedFileUri(CacheLookupKey key) {
    final album = locateAlbumDirSync(key.albumId, key.albumTitle);
    if (album == null) return null;
    final name = trackFileName(
      trackIndex: key.trackIndex,
      title: key.trackTitle,
      ext: key.extension,
    );
    final file = File(
      '${album.path}$_sep${categoryForExtension(key.extension)}$_sep$name',
    );
    return file.existsSync() ? file.uri : null;
  }

  TrackCacheStatus _readStatusSync(Directory dir, String name) {
    final file = File('${dir.path}$_sep$name');
    final part = File('${file.path}.part');
    int? bytes;
    if (file.existsSync()) {
      try {
        final length = file.lengthSync();
        if (length > 0) bytes = length;
      } catch (_) {}
    }
    final downloading = part.existsSync();
    if (bytes == null && !downloading) return TrackCacheStatus.absent;
    return TrackCacheStatus(bytes: bytes, downloading: downloading);
  }

  // ------------------------------------------------------------ lifecycle

  /// Total cached bytes, recursively (for a future settings entry).
  Future<int> totalSize() async {
    final rootDir = await root();
    if (!rootDir.existsSync()) return 0;
    var total = 0;
    await for (final e in rootDir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  /// Remove one album folder (the user can of course also just delete it).
  Future<void> deleteAlbum(String albumId, String albumTitle) async {
    final dir = locateAlbumDirSync(albumId, albumTitle);
    _albumDirs.remove(albumId);
    if (dir != null && dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  /// Wipe the whole cache.
  Future<void> clear() async {
    _albumDirs.clear();
    final rootDir = await root();
    if (rootDir.existsSync()) {
      await rootDir.delete(recursive: true);
    }
    await rootDir.create(recursive: true);
  }

  // -------------------------------------------------------------- helpers

  Directory _createSync(Directory dir) {
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static String _shortHash(String id) =>
      sha1.convert(utf8.encode(id)).toString().substring(0, 8);
}

/// Identifies a track for a cache lookup: enough to rebuild the on-disk file
/// name **without** having resolved the media URL yet (the album page only
/// knows the track number and title).
class CacheLookupKey {
  const CacheLookupKey({
    required this.albumId,
    required this.albumTitle,
    required this.trackIndex,
    required this.trackTitle,
    this.extension = '.mp3',
  });

  final String albumId;
  final String albumTitle;
  final int trackIndex;
  final String trackTitle;
  final String extension;

  /// mp3 + lossless lookups in one call.
  List<CacheLookupKey> get withLossless => [
    this,
    CacheLookupKey(
      albumId: albumId,
      albumTitle: albumTitle,
      trackIndex: trackIndex,
      trackTitle: trackTitle,
      extension: '.flac',
    ),
  ];
}

/// Whether a track is cached, still downloading, or absent.
class TrackCacheStatus {
  const TrackCacheStatus({this.bytes, this.downloading = false});

  static const TrackCacheStatus absent = TrackCacheStatus();

  /// Size of the completed file in bytes, null while it is not there yet.
  final int? bytes;

  /// True while a partial download (`<file>.part`) is on disk.
  final bool downloading;

  bool get cached => bytes != null;

  bool get isEmpty => !cached && !downloading;

  @override
  bool operator ==(Object other) =>
      other is TrackCacheStatus &&
      other.bytes == bytes &&
      other.downloading == downloading;

  @override
  int get hashCode => Object.hash(bytes, downloading);

  @override
  String toString() =>
      'TrackCacheStatus(bytes: $bytes, downloading: $downloading)';
}
