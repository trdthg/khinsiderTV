import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/player_controller.dart';

/// App-wide media key handling (TV remote / gamepad media buttons).
///
/// Wraps the whole app at the lowest priority (autofocused ancestor), so
/// MediaPlayPause / MediaTrackNext / MediaTrackPrevious / MediaStop work
/// from ANY screen while leaving regular shortcuts to deeper widgets.
class GlobalMediaKeys extends ConsumerWidget {
  const GlobalMediaKeys({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(playerControllerProvider.notifier);
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
            notifier.togglePlayPause(),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
