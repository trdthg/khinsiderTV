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
