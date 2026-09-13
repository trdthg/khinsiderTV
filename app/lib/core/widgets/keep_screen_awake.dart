import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/player_controller.dart';
import '../platform/device.dart';

/// Holds the screen awake exactly while audio is playing.
///
/// On Android TV / Google TV the screen is what keeps the device out of ambient
/// mode and standby, and standby takes playback with it — so a Chromecast that
/// is left playing stops on its own after the system's screen timeout. This
/// widget mirrors the player's `playing` flag onto `FLAG_KEEP_SCREEN_ON`
/// (see [setScreenAwake]).
///
/// It only holds the screen while something is *playing*: paused or finished
/// playback lets the device sleep as usual. On phones the flag costs nothing
/// extra — the screen was on anyway — and on desktop it is a no-op.
class KeepScreenAwake extends ConsumerStatefulWidget {
  const KeepScreenAwake({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<KeepScreenAwake> createState() => _KeepScreenAwakeState();
}

class _KeepScreenAwakeState extends ConsumerState<KeepScreenAwake> {
  @override
  void initState() {
    super.initState();
    // `fireImmediately` matters: playback can already be running when this
    // mounts (a hot restart, or a track that was started before the root was
    // rebuilt), and a missed `true` would leave the TV to fall asleep.
    ref.listenManual<bool>(
      playerControllerProvider.select((state) => state.playing),
      (_, playing) => setScreenAwake(playing),
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
