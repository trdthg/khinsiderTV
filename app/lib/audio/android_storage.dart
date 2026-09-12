import 'package:flutter/services.dart';

/// Android's "all files access" (`MANAGE_EXTERNAL_STORAGE`) and the platform's
/// public music directory.
///
/// Android 11+ enforces scoped storage: an app cannot write into `Music/`
/// unless the user grants all-files access. That grant is not a runtime
/// permission dialog but a toggle on a system settings screen, so the app has
/// to send the user there and re-check on resume. When it is missing the cache
/// stays in the app documents folder (see [AudioCacheManager]).
///
/// Abstract so the cache manager can be driven off-device in tests.
abstract class AndroidStorage {
  /// Whether the public music folder can be written right now.
  Future<bool> canWritePublicMusic();

  /// Absolute path of the public music folder (`/storage/emulated/0/Music`),
  /// or null when the platform cannot tell us.
  Future<String?> publicMusicPath();

  /// Sends the user to the system screen that grants all-files access. Returns
  /// once the intent has been dispatched; the user may still be in Settings.
  Future<void> requestAllFilesAccess();
}

/// The production implementation: a method channel into `MainActivity`.
class MethodChannelAndroidStorage implements AndroidStorage {
  const MethodChannelAndroidStorage();

  static const MethodChannel _channel = MethodChannel('dev.khinsider/storage');

  @override
  Future<bool> canWritePublicMusic() async {
    try {
      return await _channel.invokeMethod<bool>('canWritePublicMusic') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Not Android (or a unit test without a handler): no public music dir.
      return false;
    }
  }

  @override
  Future<String?> publicMusicPath() async {
    try {
      return await _channel.invokeMethod<String>('publicMusicPath');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> requestAllFilesAccess() async {
    try {
      await _channel.invokeMethod<void>('requestAllFilesAccess');
    } on PlatformException {
      // The settings screen could not be opened; the user can still reach it
      // from the system settings app.
    } on MissingPluginException {
      // Not Android: nothing to grant.
    }
  }
}
