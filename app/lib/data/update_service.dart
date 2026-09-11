import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
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
    return null;
  }

  /// Downloads [asset] into [saveDir], reporting progress 0..1.
  Future<File> downloadAsset(
    UpdateAsset asset, {
    required Directory saveDir,
    void Function(double progress)? onProgress,
  }) async {
    final file = File('${saveDir.path}${Platform.pathSeparator}${asset.name}');
    await _dio.download(
      asset.url,
      file.path,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) onProgress(received / total);
      },
    );
    return file;
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
  static bool _isNewer(String a, String b) {
    List<int> parse(String v) =>
        v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final a1 = parse(a), b1 = parse(b);
    final len = a1.length > b1.length ? a1.length : b1.length;
    for (var i = 0; i < len; i++) {
      final x = i < a1.length ? a1[i] : 0;
      final y = i < b1.length ? b1[i] : 0;
      if (x != y) return x > y;
    }
    return false;
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

/// The updates working directory (downloads + pending extraction).
Future<Directory> updatesDirectory() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}updates');
  await dir.create(recursive: true);
  return dir;
}

/// Extracts the newest downloaded .zip into `updates/pending`.
/// Returns the pending directory, or null when there is nothing to extract.
Future<Directory?> extractPendingUpdate() async {
  final dir = await updatesDirectory();
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
    final outPath = '${pending.path}${Platform.pathSeparator}${entry.name}';
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
        .firstWhere((d) => d.path.endsWith('.app'));
    var cur = File(exePath).parent; // .../Contents/MacOS
    while (!cur.path.endsWith('.app')) {
      cur = cur.parent;
    }
    await Process.run('rm', ['-rf', cur.path]);
    await Process.run('cp', ['-R', appBundle.path, cur.parent.path]);
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
        .firstWhere((d) => d.path.endsWith('.app'));
    var cur = File(Platform.resolvedExecutable).parent;
    while (!cur.path.endsWith('.app')) {
      cur = cur.parent;
    }
    await Process.run('rm', ['-rf', cur.path]);
    await Process.run('cp', ['-R', appBundle.path, cur.parent.path]);
    await Process.run('open', ['-n', cur.path]);
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
