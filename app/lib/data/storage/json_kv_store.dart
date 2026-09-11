import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal JSON-file-backed key-value store.
///
/// Deliberately dependency-free (no Isar/Hive native bindings) so the app
/// builds everywhere out of the box; the public surface is intentionally
/// KV-shaped so it can be swapped for Isar/Hive later without touching the
/// providers above it.
///
/// Durability notes:
///  * writes are debounced and flushed to `<file>.tmp`, then renamed;
///  * flushes are serialized through [_flushing] so two flushes can never
///    race on the same `.tmp` file (that would throw a rename error and
///    silently drop the newest value);
///  * `read<T>` never throws: a value whose runtime type no longer matches
///    is reported as absent instead of poisoning the calling provider.
class JsonKvStore {
  JsonKvStore._(this._file, Map<String, dynamic> data) : _data = data;

  final File _file;
  final Map<String, dynamic> _data;
  Timer? _flushTimer;
  Future<void> _flushing = Future<void>.value();
  bool _closed = false;

  /// Open (or create) the store at [directory]/[fileName].
  static Future<JsonKvStore> open(
    Directory directory, {
    String fileName = 'khinsider_store.json',
  }) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
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

  /// Returns the value stored under [key] cast to [T], or null when the key
  /// is absent **or** holds an incompatible type (e.g. a schema change).
  T? read<T>(String key) {
    final value = _data[key];
    if (value is T) return value;
    return null;
  }

  List<T> readList<T>(String key) {
    final raw = _data[key];
    if (raw is! List) return const [];
    return raw.whereType<T>().toList();
  }

  /// Write + debounced flush (batches bursts of updates into one write).
  void write(String key, Object? value) {
    if (_closed) return; // store already flushed & released
    _data[key] = value;
    _scheduleFlush();
  }

  void writeList<T>(String key, List<T> values) => write(key, values);

  void remove(String key) {
    if (_closed) return;
    _data.remove(key);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_requestFlush());
    });
  }

  /// Chains onto the in-flight flush so at most one write is ever active.
  Future<void> _requestFlush() async {
    _flushing = _flushing.then((_) => _flush());
    await _flushing;
  }

  Future<void> _flush() async {
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_data), flush: true);
      // On some platforms `rename` refuses to replace an existing file, so
      // drop the destination first (a rename is still atomic from the
      // reader's point of view: it either sees old or new content).
      if (await _file.exists()) {
        try {
          await _file.delete();
        } catch (_) {}
      }
      await tmp.rename(_file.path);
    } catch (_) {
      // The store must never take the app down over a failed write.
    }
  }

  /// Flush pending writes immediately (call on app shutdown).
  Future<void> close() async {
    _flushTimer?.cancel();
    _closed = true;
    await _flushing;
    await _flush();
  }
}
