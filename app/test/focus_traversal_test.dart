import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/state/album_controller.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider/ui/album/album_screen.dart';
import 'package:khinsider/ui/shared/player_bar.dart';

import 'album_layout_test.dart'
    show FakeAudioPlayer, SeededPlayerController, longTitleAlbum;

/// D-Pad / keyboard focus traversal regression tests.
///
/// Guards the TV navigation contract:
///  * Arrow keys must be able to travel from the content area into the
///    persistent player bar (no FocusTraversalGroup walls).
///  * The seek bar lives in the OSD menu; its focus trap is covered by the
///    now_playing tests.
void main() {
  testWidgets('arrows reach the player bar and the seek bar is usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(820, 480);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
          playerControllerProvider.overrideWith(SeededPlayerController.new),
          albumDetailProvider((
            'long-title-album',
            0,
          )).overrideWith((ref) async => longTitleAlbum()),
        ],
        child: const MaterialApp(
          home: AlbumScreen(albumId: 'long-title-album'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    RenderBox rectOf(FocusNode? f) =>
        f!.context!.findRenderObject()! as RenderBox;

    bool insidePlayerBar(FocusNode? f) {
      final ro = rectOf(f);
      final barRo = tester.renderObject<RenderBox>(find.byType(PlayerBar));
      final barTop = barRo.localToGlobal(Offset.zero).dy;
      return ro.localToGlobal(Offset.zero).dy >= barTop - 1;
    }

    final barRo = tester.renderObject<RenderBox>(find.byType(PlayerBar));
    debugPrint(
      'player bar rect: ${barRo.localToGlobal(Offset.zero)} & ${barRo.size}',
    );
    debugPrint(
      'skip_next icons: ${find.byIcon(Icons.skip_next).evaluate().length}',
    );

    // 1. Walk down from the first track row into the player bar.
    var reachedBar = false;
    for (var i = 0; i < 16 && !reachedBar; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final f = FocusManager.instance.primaryFocus;
      final ro = f?.context?.findRenderObject();
      final rect = ro is RenderBox && ro.hasSize
          ? (ro.localToGlobal(Offset.zero) & ro.size)
          : null;
      debugPrint(
        'down #$i -> ${f?.debugLabel ?? "anon"} (${f?.context?.widget.runtimeType}) rect=$rect',
      );
      reachedBar = insidePlayerBar(f);
    }
    expect(reachedBar, isTrue, reason: 'arrows never reached the player bar');

    // 2. From the bar, arrows must walk BACK into the track list
    // (the seek bar now lives in the OSD menu, covered by now_playing tests).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      insidePlayerBar(FocusManager.instance.primaryFocus),
      isFalse,
      reason: 'ArrowUp should leave the player bar back into the list',
    );

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
