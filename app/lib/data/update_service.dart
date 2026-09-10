import 'dart:io';

import 'package:dio/dio.dart';

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
