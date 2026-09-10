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

    return UpdateInfo(
      version: latest,
      url: url,
      notes: (data['body'] as String?) ?? '',
    );
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
  const UpdateInfo({required this.version, required this.url, this.notes = ''});

  final String version;
  final String url;
  final String notes;
}
