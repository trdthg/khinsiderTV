import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/audio/audio_cache_manager.dart';
import 'package:khinsider/core/widgets/dpad_tile.dart';
import 'package:khinsider/l10n/generated/app_localizations.dart';
import 'package:khinsider/state/album_controller.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider/state/track_cache_controller.dart';
import 'package:khinsider/ui/album/views/album_screen.dart';

import 'album_layout_test.dart'
    show FakeAudioPlayer, SeededPlayerController, longTitleAlbum;

/// Stands in for the real transport: [SeededPlayerController] forwards every
/// command here (`PlayerController._player` is `audioPlayerProvider`), so this
/// is what the scrubber's seeks actually reach.
class RecordingSeekPlayer extends FakeAudioPlayer {
  final List<Duration> seeks = [];
  final List<String> calls = [];

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');
}

/// A seeded session whose duration never arrived — nothing to seek within.
class NoDurationController extends SeededPlayerController {
  @override
  PlayerState build() => super.build().copyWith(duration: null);
}

/// The first track of [longTitleAlbum] (the one [SeededPlayerController] has
/// queued, i.e. the row that carries the progress fill).
const _currentTrack = 'Track 1 — Some Fairly Long Track Name Here';
const _otherTrack = 'Track 2 — Some Fairly Long Track Name Here';

void main() {
  late Directory tempRoot;
  late AudioCacheManager testCache;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('khinsider-scrub-test');
    testCache = AudioCacheManager(rootOverride: tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  /// Pumps the album screen at [size] with a seeded playback session. 400 px
  /// wide is the phone layout (the one that scrubs), 1200 px the desktop/TV
  /// one (which must not change).
  Future<RecordingSeekPlayer> pumpAlbum(
    WidgetTester tester, {
    required Size size,
    PlayerController Function()? controller,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player = RecordingSeekPlayer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWithValue(player),
          audioCacheManagerProvider.overrideWithValue(testCache),
          playerControllerProvider.overrideWith(
            controller ?? SeededPlayerController.new,
          ),
          albumDetailProvider((
            'long-title-album',
            0,
          )).overrideWith((ref) async => longTitleAlbum()),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: AlbumScreen(albumId: 'long-title-album'),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    return player;
  }

  Finder rowOf(String title) => find
      .ancestor(of: find.text(title), matching: find.byType(DpadTile))
      .first;

  /// Puts a finger on [row] and moves it past the touch slop, so that the next
  /// [TestGesture.moveTo] is delivered as a drag update rather than being
  /// swallowed while the recognizer decides.
  Future<(TestGesture, Rect)> startRowDrag(
    WidgetTester tester,
    Finder row, {
    double at = 0.25,
  }) async {
    final rect = tester.getRect(row);
    final gesture = await tester.startGesture(
      Offset(rect.left + rect.width * at, rect.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump(const Duration(milliseconds: 20));
    return (gesture, rect);
  }

  testWidgets('dragging the now-playing row seeks once, on release', (
    tester,
  ) async {
    final player = await pumpAlbum(tester, size: const Size(400, 900));
    final (gesture, rect) = await startRowDrag(tester, rowOf(_currentTrack));

    await gesture.moveTo(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 20));

    // The readout says where the jump would land…
    expect(find.textContaining(' / 2:00'), findsOneWidget);
    // …and nothing has been committed yet: the audio is served through
    // just_audio's caching proxy, where a forward seek has to wait for the
    // download to reach the target, so seeking per update would stall.
    expect(player.seeks, isEmpty);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 20));

    expect(player.seeks, hasLength(1));
    // 75% of the seeded 2 minutes.
    expect(player.seeks.single.inSeconds, closeTo(90, 2));
    expect(
      find.textContaining(' / 2:00'),
      findsNothing,
      reason: 'the readout is only shown while the finger is down',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on the now-playing row still toggles playback', (
    tester,
  ) async {
    final player = await pumpAlbum(tester, size: const Size(400, 900));

    await tester.tap(rowOf(_currentTrack));
    await tester.pump();
    await tester.pump();

    expect(player.seeks, isEmpty, reason: 'a tap must not seek');
    expect(
      player.calls,
      contains('pause'),
      reason: 'the seeded session is playing, so a tap pauses it',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging a row that is not playing does nothing', (
    tester,
  ) async {
    final player = await pumpAlbum(tester, size: const Size(400, 900));
    final (gesture, rect) = await startRowDrag(tester, rowOf(_otherTrack));

    await gesture.moveTo(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 20));

    expect(player.seeks, isEmpty);
    expect(find.textContaining(' / 2:00'), findsNothing);
  });

  testWidgets('without a duration there is nothing to drag', (tester) async {
    final player = await pumpAlbum(
      tester,
      size: const Size(400, 900),
      controller: NoDurationController.new,
    );
    final (gesture, rect) = await startRowDrag(tester, rowOf(_currentTrack));

    await gesture.moveTo(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 20));

    expect(player.seeks, isEmpty);
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('the wide desktop/TV layout keeps its rows inert', (
    tester,
  ) async {
    final player = await pumpAlbum(tester, size: const Size(1200, 900));
    final (gesture, rect) = await startRowDrag(tester, rowOf(_currentTrack));

    await gesture.moveTo(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      player.seeks,
      isEmpty,
      reason: 'scrubbing is a phone-layout affordance only',
    );
    expect(find.textContaining(' / 2:00'), findsNothing);
  });
}
