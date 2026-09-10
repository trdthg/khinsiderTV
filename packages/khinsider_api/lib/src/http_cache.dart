import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Disk-backed HTML response cache.
///
/// Cache-first policy: if an entry exists it is served instantly and the
/// network is only hit on [forceRefresh] (which then overwrites the entry).
/// One file per URL (sha1 hash), so entries never rewrite each other.
///
/// Flutter-free: the host app supplies the cache directory, keeping this
/// package pure Dart.
class HttpCache {
  HttpCache(this._dirFactory);

  /// Lazily resolves (and creates) the cache directory.
  final Future<Directory> Function() _dirFactory;

  Directory? _dir;

  Future<Directory> _resolveDir() async {
    if (_dir != null) return _dir!;
    final dir = await _dirFactory();
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  String _key(String url) => sha1.convert(utf8.encode(url)).toString();

  File _bodyFile(Directory dir, String key) =>
      File('${dir.path}${Platform.pathSeparator}$key.html');

  /// Returns the cached body for [url], or null when absent or expired.
  /// [ttl] null means the entry never expires (forced refresh only).
  Future<String?> get(String url, {Duration? ttl}) async {
    try {
      final dir = await _resolveDir();
      final file = _bodyFile(dir, _key(url));
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      // Entries are stored as a JSON envelope {"t": epochMs, "b": body}.
      // Older raw-HTML entries fail to decode and are treated as a miss.
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final t = decoded['t'];
      final b = decoded['b'];
      if (t is! int || b is! String) return null;
      if (ttl != null &&
          DateTime.now().millisecondsSinceEpoch - t > ttl.inMilliseconds) {
        return null; // expired
      }
      return b;
    } catch (_) {
      return null; // cache must never break a request
    }
  }

  /// Stores [body] for [url], overwriting any previous entry.
  /// [ttl] null means the entry never expires.
  Future<void> put(String url, String body, {Duration? ttl}) async {
    try {
      final dir = await _resolveDir();
      final envelope = jsonEncode({
        't': DateTime.now().millisecondsSinceEpoch,
        'b': body,
      });
      await _bodyFile(dir, _key(url)).writeAsString(envelope, flush: true);
    } catch (_) {
      // ignore cache write failures
    }
  }

  /// Removes a single entry (used on forced refresh failures as safety).
  Future<void> remove(String url) async {
    try {
      final dir = await _resolveDir();
      final file = _bodyFile(dir, _key(url));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Wipes the whole cache.
  Future<void> clear() async {
    final dir = await _resolveDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
  }
}
