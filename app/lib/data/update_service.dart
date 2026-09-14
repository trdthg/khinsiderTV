import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub release update check.
///
/// Looks at the latest published release of the repo and compares it with
/// the running app version. Pure data — UI decides how to present it.
class UpdateService {
  UpdateService({required this.repoSlug});

  /// e.g. `trdthg/khinsiderTV`
  final String repoSlug;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/vnd.github+json',
        // Unauthenticated API: 60 req/h per IP — one check per launch is fine.
      },
      validateStatus: (code) => code != null && code < 500,
    ),
  );

  /// Returns info about a release newer than [currentVersion], or null.
  Future<UpdateInfo?> latestRelease({required String currentVersion}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/$repoSlug/releases/latest',
    );
    final data = res.data;
    if (data == null) return null;

    final tag = data['tag_name'] as String?;
    final url = data['html_url'] as String?;
    if (tag == null || url == null) return null;

    final latest = _versionOf(tag);
    if (!_isNewer(latest, _versionOf(currentVersion))) return null;

    final assets = <UpdateAsset>[];
    final rawAssets = data['assets'];
    if (rawAssets is List) {
      for (final a in rawAssets) {
        if (a is Map<String, dynamic>) {
          final name = a['name'] as String?;
          final download = a['browser_download_url'] as String?;
          if (name != null && download != null) {
            assets.add(UpdateAsset(name: name, url: download));
          }
        }
      }
    }

    return UpdateInfo(
      version: latest,
      url: url,
      notes: (data['body'] as String?) ?? '',
      assets: assets,
    );
  }

  /// Picks the right asset for the current desktop platform.
  /// Returns null on platforms without auto-download (mobile: keep "View").
  UpdateAsset? assetForPlatform(List<UpdateAsset> assets) {
    if (Platform.isWindows) {
      for (final a in assets) {
        if (a.name.contains('windows') && a.name.endsWith('.zip')) return a;
      }
    }
    if (Platform.isMacOS) {
      for (final a in assets) {
        if (a.name.contains('macos') && a.name.endsWith('.zip')) return a;
      }
    }
    if (Platform.isLinux) {
      for (final a in assets) {
        if (a.name.endsWith('.flatpak')) return a;
      }
    }
    if (Platform.isAndroid) {
      for (final a in assets) {
        if (a.name.endsWith('-universal.apk')) return a;
      }
      for (final a in assets) {
        if (a.name.endsWith('.apk')) return a;
      }
    }
    return null;
  }

  /// Downloads [asset] into [saveDir], reporting progress 0..1.
  Future<File> downloadAsset(
    UpdateAsset asset, {
    required Directory saveDir,
    void Function(double progress)? onProgress,
  }) async {
    final file = File('${saveDir.path}${Platform.pathSeparator}${asset.name}');
    await _dropOlderDownloads(saveDir, keep: asset.name);
    await _dio.download(
      asset.url,
      file.path,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) onProgress(received / total);
      },
    );
    return file;
  }

  /// Deletes previously downloaded installers of the same kind, so a TV with
  /// very little free space is not asked to hold two 40 MB APKs. Directories
  /// (the unpacked `pending` update among them) are never touched.
  static Future<void> _dropOlderDownloads(
    Directory saveDir, {
    required String keep,
  }) async {
    final extension = keep.contains('.')
        ? keep.substring(keep.lastIndexOf('.'))
        : '';
    if (extension.isEmpty) return;
    try {
      await for (final entity in saveDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name == keep || !name.endsWith(extension)) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  static const MethodChannel _updateChannel = MethodChannel(
    'dev.khinsider/update',
  );

  /// Ask the Android host to open the system package installer for [path].
  Future<void> installApk(String path) async {
    if (!Platform.isAndroid) return;
    await _updateChannel.invokeMethod<void>('installApk', {'path': path});
  }

  /// Whether the OS will let this app hand an APK to its installer. Android 8+
  /// needs the user to allow "install unknown apps" first, and without it the
  /// installer opens and silently does nothing.
  Future<bool> canInstallPackages() async {
    if (!Platform.isAndroid) return true;
    try {
      final allowed = await _updateChannel.invokeMethod<bool>(
        'canInstallPackages',
      );
      return allowed ?? true;
    } on PlatformException {
      return true; // older host: let the installer decide
    }
  }

  /// Opens the system screen where "install unknown apps" is granted.
  Future<void> openInstallSettings() async {
    if (!Platform.isAndroid) return;
    await _updateChannel.invokeMethod<void>('openInstallSettings');
  }

  /// Reveals [path] in the platform file manager (Finder / Explorer / xdg).
  Future<void> revealInFileManager(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', path]);
    } else {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  }

  /// `v0.1.2` / `0.1.2` -> `0.1.2`
  static String _versionOf(String tag) =>
      tag.trim().replaceFirst(RegExp('^v'), '');

  /// Numeric segment comparison; `1.2.10` > `1.2.9`.
  ///
  /// Pre-release (`-rc1`) and build (`+12`) suffixes are stripped so they do
  /// not silently parse as `0` and invert the comparison.
  static bool _isNewer(String a, String b) {
    final a1 = _parseVersion(a), b1 = _parseVersion(b);
    final len = a1.length > b1.length ? a1.length : b1.length;
    for (var i = 0; i < len; i++) {
      final x = i < a1.length ? a1[i] : 0;
      final y = i < b1.length ? b1[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// `0.1.4-rc1+12` -> `[0, 1, 4]`; unparseable segments become 0.
  static List<int> _parseVersion(String version) {
    final core = version
        .split('-')
        .first
        .split('+')
        .first
        .replaceAll(RegExp(r'[^0-9.]'), '');
    return core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  }
}

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    this.notes = '',
    this.assets = const [],
  });

  final String version;
  final String url;
  final String notes;
  final List<UpdateAsset> assets;
}

class UpdateAsset {
  const UpdateAsset({required this.name, required this.url});

  final String name;
  final String url;
}

/// Walks up from [exePath] to the enclosing `.app` bundle, or null when the
/// binary is not packaged in one (a plain `parent` walk would never stop,
/// because `Directory('/').parent` is `/` itself).
Directory? _macOSAppBundle(String exePath) {
  var dir = File(exePath).parent;
  while (true) {
    if (dir.path.endsWith('.app')) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return null; // reached the filesystem root
    dir = parent;
  }
}

/// The updates working directory (downloads + pending extraction).
Future<Directory> updatesDirectory() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}updates');
  await dir.create(recursive: true);
  return dir;
}

/// Extracts the newest downloaded .zip into `<root>/pending`.
///
/// [root] defaults to [updatesDirectory]; it is injectable so the
/// extraction logic (and its path-traversal guard) can be unit-tested.
/// Returns the pending directory, or null when there is nothing to extract.
Future<Directory?> extractPendingUpdate({Directory? root}) async {
  final dir = root ?? await updatesDirectory();
  final zips =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.zip'))
          .toList()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
  if (zips.isEmpty) return null;

  final pending = Directory('${dir.path}${Platform.pathSeparator}pending');
  if (await pending.exists()) {
    await pending.delete(recursive: true);
  }
  await pending.create(recursive: true);

  final bytes = await zips.first.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final entry in archive) {
    final name = _safeEntryName(entry.name);
    if (name == null) continue; // traversal / absolute path: skip
    final outPath = '${pending.path}${Platform.pathSeparator}$name';
    if (entry.isFile) {
      final out = File(outPath);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(entry.content as List<int>, flush: true);
    } else {
      await Directory(outPath).create(recursive: true);
    }
  }
  // The downloaded zip is no longer needed.
  await zips.first.delete();
  return pending;
}

/// Resolves [name] inside the extraction root, or null if it would escape.
///
/// Archive entries are attacker-controlled: a zip shipped as a release asset
/// must never be able to write outside the extraction directory (Zip Slip).
String? _safeEntryName(String name) {
  // Normalise separators so Windows-style entries are handled identically.
  final normalised = name.replaceAll('\\', '/');
  final segments = <String>[];
  for (final seg in normalised.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') return null; // parent traversal
    segments.add(seg);
  }
  if (segments.isEmpty) return null;
  // Absolute paths (leading drive letter / root) are rejected above only if
  // they traverse; strip any leading root here to stay inside the sandbox.
  return segments.join(Platform.pathSeparator);
}

/// Applies a pending update extracted in a previous session. Called at app
/// startup BEFORE the UI — the files on disk are swapped and this session
/// continues running the old binary in memory; the NEXT launch uses the new
/// version. Returns true when an update was applied.
Future<bool> applyPendingUpdate() async {
  final dir = await updatesDirectory();
  final pending = Directory('${dir.path}${Platform.pathSeparator}pending');
  if (!await pending.exists()) return false;
  if (pending.listSync().isEmpty) return false;

  final exePath = Platform.resolvedExecutable;

  if (Platform.isMacOS) {
    // unix semantics: replacing a running bundle's files is safe.
    final appBundle = pending
        .listSync(recursive: true)
        .whereType<Directory>()
        .where((d) => d.path.endsWith('.app'))
        .toList();
    final target = _macOSAppBundle(exePath);
    if (appBundle.isEmpty || target == null) {
      // Not a packaged .app (dev build / bare binary): cannot self-swap.
      return false;
    }
    await Process.run('rm', ['-rf', target.path]);
    await Process.run('cp', ['-R', appBundle.first.path, target.parent.path]);
    await pending.delete(recursive: true);
    return true;
  }

  if (Platform.isWindows) {
    // Running exe/DLLs can't be overwritten but CAN be renamed — move the
    // old files aside, copy the new ones in, clean up .old on next run.
    final installDir = File(exePath).parent;

    // 1. clean up leftovers from a previous update (unlocked now).
    for (final e in installDir.listSync()) {
      if (e.path.endsWith('.old') || e.path.endsWith('.old.exe')) {
        try {
          await e.delete(recursive: true);
        } catch (_) {}
      }
    }

    // 2. rename conflicting targets aside (works for loaded exe/DLLs).
    for (final e in pending.listSync(recursive: true).whereType<File>()) {
      final rel = e.path.substring(pending.path.length + 1);
      final target = File('${installDir.path}${Platform.pathSeparator}$rel');
      if (await target.exists()) {
        try {
          await target.rename('${target.path}.old');
        } catch (_) {}
      }
    }

    // 3. copy the new files in.
    for (final e in pending.listSync(recursive: true).whereType<File>()) {
      final rel = e.path.substring(pending.path.length + 1);
      final target = File('${installDir.path}${Platform.pathSeparator}$rel');
      await target.parent.create(recursive: true);
      await e.copy(target.path);
    }

    await pending.delete(recursive: true);
    return true;
  }

  if (Platform.isLinux) {
    // Flatpak: install the bundle via the host's flatpak (requires the
    // org.freedesktop.Flatpak talk permission in the manifest).
    final flat = pending
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.flatpak'))
        .toList();
    if (flat.isEmpty) return false;
    await Process.run('flatpak-spawn', [
      '--host',
      'flatpak',
      'install',
      '--user',
      '-y',
      flat.first.path,
    ]);
    await pending.delete(recursive: true);
    return true;
  }

  return false;
}

/// Windows: restarts via a detached batch script (wait -> swap -> relaunch).
/// macOS: replaces the running bundle then relaunches the new instance.
/// Linux: installs the flatpak bundle; the user relaunches from the Deck UI.
Future<void> restartAndApply() async {
  final dir = await updatesDirectory();
  final pending = Directory('${dir.path}${Platform.pathSeparator}pending');
  if (!await pending.exists()) return;

  if (Platform.isWindows) {
    final installDir = File(Platform.resolvedExecutable).parent.path;
    final bat = File('${dir.path}${Platform.pathSeparator}update.bat');
    await bat.writeAsString('''
@echo off
timeout /t 2 /nobreak >nul
xcopy /E /Y /I "${pending.path}" "$installDir"
start "" "$installDir\\khinsider.exe"
del "%~f0"
''');
    await Process.start('cmd.exe', [
      '/c',
      bat.path,
    ], mode: ProcessStartMode.detached);
    exit(0);
  }

  if (Platform.isMacOS) {
    final appBundle = pending
        .listSync(recursive: true)
        .whereType<Directory>()
        .where((d) => d.path.endsWith('.app'))
        .toList();
    final target = _macOSAppBundle(Platform.resolvedExecutable);
    if (appBundle.isEmpty || target == null) return;
    await Process.run('rm', ['-rf', target.path]);
    await Process.run('cp', ['-R', appBundle.first.path, target.parent.path]);
    await Process.run('open', ['-n', target.path]);
    exit(0);
  }

  if (Platform.isLinux) {
    final flat = pending
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.flatpak'))
        .toList();
    if (flat.isNotEmpty) {
      await Process.run('flatpak-spawn', [
        '--host',
        'flatpak',
        'install',
        '--user',
        '-y',
        flat.first.path,
      ]);
    }
    exit(0);
  }
}
