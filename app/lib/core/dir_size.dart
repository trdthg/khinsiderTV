import 'dart:io';

/// Total size of the files under [dir], 0 when it does not exist.
///
/// Synchronous on purpose: it only runs when the Settings cache screen opens,
/// the trees it walks are small, and synchronous filesystem calls are the only
/// kind that also work inside a widget test (where real async IO cannot make
/// progress). Never throws — a settings screen that fails to open because one
/// file vanished mid-walk is worse than a number that is a few bytes off.
int directorySize(Directory dir) {
  var total = 0;
  try {
    if (!dir.existsSync()) return 0;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        total += entity.lengthSync();
      } catch (_) {}
    }
  } catch (_) {}
  return total;
}
