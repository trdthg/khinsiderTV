import 'dart:io' as dart_io;
import 'package:audio_service/audio_service.dart'; // supported: android/ios/macos/web
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'audio/base_audio_player.dart';
import 'audio/just_audio_player_impl.dart';
import 'audio/audio_service_handler.dart';
import 'state/player_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows/Linux playback backend for just_audio (no-op on macOS/Android).
  JustAudioMediaKit.ensureInitialized();
  // Gamepad support: register common game controllers as raw key sources so
  // D-Pad / A / B map to arrows / select / back on TV boxes.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Media session (macOS Now-Playing / media keys, Android notification &
  // lock-screen controls). audio_service only ships platform channels for
  // android/ios/macos/web — on Windows/Linux `AudioService.init` NEVER
  // completes (no window would ever appear!), so those platforms run with
  // the default audioPlayerProvider (JustAudioPlayerImpl) instead.
  final BaseAudioPlayer player;
  if (dart_io.Platform.isAndroid ||
      dart_io.Platform.isIOS ||
      dart_io.Platform.isMacOS) {
    // Media session: Now-Playing / media keys / notification controls.
    final handler = await AudioService.init<KhinsiderAudioHandler>(
      builder: KhinsiderAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.khinsider.app.playback',
        androidNotificationChannelName: 'KHInsider playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    player = handler;
  } else {
    // Windows/Linux: audio_service has no platform channels here — run the
    // plain player (playback still works, just no system media integration).
    player = JustAudioPlayerImpl();
  }

  runApp(
    ProviderScope(
      overrides: [audioPlayerProvider.overrideWithValue(player)],
      child: const KhinsiderApp(),
    ),
  );
}
