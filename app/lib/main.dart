import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
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
  // lock-screen controls). The handler implements BaseAudioPlayer, so the
  // rest of the app is unchanged; on platforms where audio_service is not
  // wanted, the default audioPlayerProvider (JustAudioPlayerImpl) applies.
  final audioHandler = await AudioService.init(
    builder: () => KhinsiderAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.khinsider.app.playback',
      androidNotificationChannelName: 'KHInsider playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [audioPlayerProvider.overrideWithValue(audioHandler)],
      child: const KhinsiderApp(),
    ),
  );
}
