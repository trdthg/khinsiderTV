import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the immersive fullscreen Now Playing screen is active.
/// While true, the bottom PlayerBar hides itself (immersion).
class FullscreenController extends Notifier<bool> {
  @override
  bool build() => false;

  void show() {
    if (!ref.mounted) return;
    state = true;
  }

  void hide() {
    if (!ref.mounted) return;
    state = false;
  }
}

final fullscreenProvider = NotifierProvider<FullscreenController, bool>(
  FullscreenController.new,
);
