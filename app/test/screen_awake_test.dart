import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/core/platform/device.dart';
import 'package:khinsider/core/widgets/keep_screen_awake.dart';
import 'package:khinsider/state/player_controller.dart';

import 'album_layout_test.dart' show FakeAudioPlayer, SeededPlayerController;

const MethodChannel _channel = MethodChannel('dev.khinsider/platform');

/// Lets the test drive the `playing` flag the way the snapshot stream would.
class ControllablePlayerController extends SeededPlayerController {
  void setPlaying(bool value) => state = state.copyWith(playing: value);
}

void main() {
  testWidgets('the screen is held on while playing and released on pause', (
    tester,
  ) async {
    final calls = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      call,
    ) async {
      if (call.method == 'setKeepScreenOn') calls.add(call.arguments as bool);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      ),
    );

    final container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
        playerControllerProvider.overrideWith(ControllablePlayerController.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: KeepScreenAwake(child: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();

    // A Chromecast that lets its screen time out goes to standby and takes the
    // music with it, so playing has to hold the screen on.
    expect(
      calls,
      [true],
      reason:
          'playing must keep the device awake, even when it is already '
          'playing as the widget mounts',
    );

    final controller =
        container.read(playerControllerProvider.notifier)
            as ControllablePlayerController;
    controller.setPlaying(false);
    await tester.pump();

    expect(calls, [
      true,
      false,
    ], reason: 'a paused player must let the device sleep again');

    controller.setPlaying(true);
    await tester.pump();
    expect(calls, [true, false, true]);
  });

  testWidgets('a missing or failing platform handler is swallowed', (
    tester,
  ) async {
    // Desktop has no dev.khinsider/platform implementation. A real engine
    // answers "not implemented" (MissingPluginException) rather than doing
    // nothing at all, which is what this stands in for - a call that never
    // came back would leave a test (and a plugin-less platform) hanging.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      call,
    ) async {
      throw MissingPluginException('no handler for ${call.method}');
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      ),
    );

    await setScreenAwake(true);
    await setScreenAwake(false);
  });
}
