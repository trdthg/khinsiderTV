import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal JSON-file-backed key-value store.
///
/// Deliberately dependency-free (no Isar/Hive native bindings) so the app
/// builds everywhere out of the box; the public surface is intentionally
/// KV-shaped so it can be swapped for Isar/Hive later without touching the
/// providers above it.
class JsonKvStore {
  JsonKvStore._(this._file, Map<String, dynamic> data) : _data = data;

  final File _file;
  final Map<String, dynamic> _data;
  Timer? _flushTimer;
  Future<void>? _pendingFlush;

  /// Open (or create) the store at [directory]/[fileName].
  static Future<JsonKvStore> open(
    Directory directory, {
    String fileName = 'khinsider_store.json',
  }) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/$fileName');
    Map<String, dynamic> data = {};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // Corrupt file: start fresh rather than crash.
      }
    }
    return JsonKvStore._(file, data);
  }

  T? read<T>(String key) => _data[key] as T?;

  List<T> readList<T>(String key) {
    final raw = _data[key];
    if (raw is! List) return const [];
    return raw.whereType<T>().toList();
  }

  /// Write + debounced flush (batches bursts of updates into one write).
  void write(String key, Object? value) {
    _data[key] = value;
    _scheduleFlush();
  }

  void writeList<T>(String key, List<T> values) => write(key, values);

  void remove(String key) {
    _data.remove(key);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 400), () {
      _pendingFlush = _flush();
    });
  }

  Future<void> _flush() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_data), flush: true);
    await tmp.rename(_file.path);
  }

  /// Flush pending writes immediately (call on app shutdown).
  Future<void> close() async {
    _flushTimer?.cancel();
    await _pendingFlush;
    await _flush();
  }
}
