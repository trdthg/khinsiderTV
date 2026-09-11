import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/player_controller.dart';

/// App-wide media key handling (TV remote / gamepad media buttons).
///
/// Wraps the whole app at the lowest priority (autofocused ancestor), so
/// MediaPlayPause / MediaTrackNext / MediaTrackPrevious / MediaStop work
/// from ANY screen while leaving regular shortcuts to deeper widgets.
///
/// Esc is handled here as a last resort: when a screen holds NO focused
/// widget, key events bubble up from the route's focus scope, so a handler
/// *inside* the screen never sees them (this used to make Esc feel dead).
/// Screens that do care about Esc (album page, OSD menu) handle it first and
/// stop the propagation; this binding only fires when nobody else did.
class GlobalMediaKeys extends ConsumerWidget {
  const GlobalMediaKeys({super.key, required this.child, this.navigatorKey});

  final Widget child;

  /// The app navigator. It has to be handed in because this widget sits ABOVE
  /// the navigator in the tree (`MaterialApp.builder`), so `Navigator.of`
  /// cannot look it up.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // watch() (not read()) so a replaced controller keeps working, and so
    // this widget rebuilds its bindings together with the notifier.
    final notifier = ref.watch(playerControllerProvider.notifier);

    void onEscape() {
      final navigator = navigatorKey?.currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.maybePop();
      }
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
            notifier.togglePlayPause(),
        const SingleActivator(LogicalKeyboardKey.mediaPlay): () =>
            notifier.togglePlayPause(),
        const SingleActivator(LogicalKeyboardKey.mediaPause): () =>
            notifier.togglePlayPause(),
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () =>
            notifier.next(),
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () =>
            notifier.previous(),
        const SingleActivator(LogicalKeyboardKey.mediaStop): () =>
            notifier.stop(),
        const SingleActivator(LogicalKeyboardKey.escape): onEscape,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
