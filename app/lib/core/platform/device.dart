import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this device is a television (Android TV / Google TV / Fire TV).
///
/// Only the TV layouts differ: they type with the app's own on-screen keyboard
/// instead of the system IME (see `lib/ui/search/tv_keyboard.dart`). Every
/// other platform serves `false`, i.e. the pre-existing behaviour.
///
/// The value is resolved once, before the first frame, in `main.dart` — a
/// `false` default that later flipped to `true` would open the system keyboard
/// on a TV for one frame, which is exactly the thing TVs must not do.
final isTelevisionProvider = Provider<bool>((ref) => false);

const MethodChannel _channel = MethodChannel('dev.khinsider/platform');

/// Asks the platform whether it reports itself as a TV. Never throws: a failing
/// or missing channel (desktop, iOS) simply means "not a TV".
Future<bool> resolveIsTelevision() async {
  try {
    return await _channel.invokeMethod<bool>('isTelevision') ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Keeps the screen — and therefore the device — awake while audio plays.
///
/// Android TV / Google TV drop into ambient mode and then standby once the
/// screen has been idle for the system timeout, which also takes the audio
/// with it: a Chromecast stops playing after a while unless something holds
/// the screen on. `FLAG_KEEP_SCREEN_ON` is the supported way to do that, and it
/// only applies while the app is actually visible, so nothing has to be undone
/// when it goes to the background.
///
/// Never throws: on platforms without the handler (macOS, Windows, Linux, iOS)
/// the call simply lands nowhere.
Future<void> setScreenAwake(bool awake) async {
  try {
    await _channel.invokeMethod<void>('setKeepScreenOn', awake);
  } on PlatformException {
    // Nothing to do: worst case the screen sleeps as it did before.
  } on MissingPluginException {
    // Desktop / iOS: no such handler.
  }
}
