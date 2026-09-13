import 'dart:io' as dart_io;

import 'package:audio_service/audio_service.dart'; // supported: android/ios/macos/web
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'audio/audio_cache_manager.dart';
import 'audio/audio_service_handler.dart';
import 'audio/base_audio_player.dart';
import 'audio/just_audio_player_impl.dart';
import 'core/platform/device.dart';
import 'data/update_service.dart';
import 'state/player_controller.dart';
import 'state/track_cache_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // just_audio's LockCachingAudioSource can race when a prefetched source is
  // replaced; the resulting PathNotFoundException is logged as an unhandled
  // async error even though playback is already continuing on another source.
  // Keep the page responsive instead of letting that incidental cache race
  // surface as a crash/dialog.
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    if (error is dart_io.PathNotFoundException) {
      debugPrint('Ignoring cache-file race: $error');
      return true;
    }
    return false;
  };

  // Apply a pending update extracted in a previous session (desktop only):
  // the files on disk are swapped and THIS session continues as-is — the
  // NEXT launch uses the new version.
  if (!kDebugMode) {
    try {
      await applyPendingUpdate();
    } catch (_) {}
  }

  // Windows/Linux playback backend for just_audio (never initialise it on
  // Android/iOS/macOS where the native just_audio backend is used).
  if (dart_io.Platform.isWindows || dart_io.Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized();
  }
  // Gamepad support: register common game controllers as raw key sources so
  // D-Pad / A / B map to arrows / select / back on TV boxes.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // The one cache manager for the whole app: the UI (cache badges, the
  // "cached in ..." hint) and the player must agree on the cache root, and
  // `forgetRoot()` (used after the user grants all-files access on Android)
  // has to apply to both.
  final AudioCacheManager cache = AudioCacheManager();

  // The transport every play/pause/queue command goes to. It is created first
  // because the media session (below) mirrors it.
  final BaseAudioPlayer transport = JustAudioPlayerImpl(cacheManager: cache);

  // Media session (macOS Now-Playing / media keys, Android notification &
  // lock-screen controls). audio_service only ships platform channels for
  // android/ios/macos/web — on Windows/Linux `AudioService.init` NEVER
  // completes (no window would ever appear!), so those platforms run without
  // a session (no system media integration).
  //
  // The session is deliberately NOT what the state layer plays through: its
  // play/pause/stop are the system's entry points and forward back into
  // PlayerController, so handing it to audioPlayerProvider would make every
  // transport command recurse into itself until the app hung. It only gets the
  // transport to read state from and to seek.
  MediaSession? session;
  if (dart_io.Platform.isAndroid ||
      dart_io.Platform.isIOS ||
      dart_io.Platform.isMacOS) {
    session = await AudioService.init<KhinsiderAudioHandler>(
      builder: () => KhinsiderAudioHandler(player: transport),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.khinsider.app.playback',
        androidNotificationChannelName: 'KHInsider playback',
        // Keep the foreground service alive while paused.
        //
        // With `androidStopForegroundOnPause: true` (what this used to be) the
        // service leaves the foreground on pause. The next notification press
        // (play / pause / next) then has to START the foreground service again
        // from the background, and Android 12+ refuses that with
        // `ForegroundServiceStartNotAllowedException`. The result is dead
        // system controls: the button stays on "play" and "next" does nothing,
        // even though the audio may keep playing. Staying in the foreground
        // avoids the restart entirely — this is the workaround audio_service
        // documents for Android 12+.
        androidStopForegroundOnPause: false,
        // `androidNotificationOngoing` is only honoured together with
        // `androidStopForegroundOnPause: true` (see AudioServiceConfig's
        // assert), so it must stay off here.
        androidNotificationOngoing: false,
        androidNotificationClickStartsActivity: true,
      ),
    );
    // The failure mode above surfaces asynchronously; log it instead of
    // letting it take the app down.
    AudioService.asyncError.listen((Object e) {
      debugPrint('audio_service async error: $e');
    });
  }

  // Resolved before the first frame: a TV must not open the system keyboard
  // even once, so the search screen cannot start out believing it is a phone.
  final isTelevision = await resolveIsTelevision();

  runApp(
    ProviderScope(
      overrides: [
        audioPlayerProvider.overrideWithValue(transport),
        mediaSessionProvider.overrideWithValue(session),
        audioCacheManagerProvider.overrideWithValue(cache),
        isTelevisionProvider.overrideWithValue(isTelevision),
      ],
      child: const KhinsiderApp(),
    ),
  );
}
