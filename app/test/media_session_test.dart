import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider/audio/audio_service_handler.dart';
import 'package:khinsider/audio/base_audio_player.dart';
import 'package:khinsider/data/khinsider_client.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider_api/khinsider_api.dart';

/// Inner player double: records every command and lets the test drive the
/// streams that [KhinsiderAudioHandler] mirrors to the system media session.
class RecordingPlayer implements BaseAudioPlayer {
  final snapshots = StreamController<AudioPlayerSnapshot>.broadcast();
  final durations = StreamController<Duration?>.broadcast();
  final positions = StreamController<Duration>.broadcast();

  final List<String> calls = [];
  SystemMediaCommandHandler? systemHandler;
  int _queueLength = 0;

  @override
  Stream<AudioPlayerSnapshot> get snapshotStream => snapshots.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration?> get durationStream => durations.stream;
  @override
  int get queueLength => _queueLength;

  @override
  Future<void> loadQueue(List<PlayableItem> items, {int startIndex = 0}) async {
    calls.add('loadQueue');
    _queueLength = items.length;
    // The real player reports the index as soon as the queue is loaded; the
    // controller maps its state from exactly this snapshot.
    snapshots.add(AudioPlayerSnapshot(playing: true, currentIndex: startIndex));
  }

  @override
  Future<void> append(List<PlayableItem> items) async {
    calls.add('append');
    _queueLength += items.length;
  }

  @override
  Future<void> swapCurrentSource(String url) async =>
      calls.add('swapCurrentSource');

  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> seek(Duration position) async => calls.add('seek');
  @override
  Future<void> skipToIndex(int index) async => calls.add('skipToIndex');
  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> previous() async => calls.add('previous');

  @override
  void setSystemCommandHandler(SystemMediaCommandHandler? handler) {
    systemHandler = handler;
  }

  @override
  Future<void> dispose() async {
    await snapshots.close();
    await durations.close();
    await positions.close();
  }
}

/// Stand-in for the app layer ([PlayerController] plays this role in the
/// running app).
class RecordingCommands implements SystemMediaCommandHandler {
  final List<String> calls = [];

  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> previous() async => calls.add('previous');
  @override
  Future<void> stop() async => calls.add('stop');
}

const _item = PlayableItem(
  id: 'album/1',
  title: 'Track 1',
  url: 'https://cdn.example/1.mp3',
  artist: 'Album',
  albumTitle: 'Album',
  albumId: 'album',
  trackIndex: 1,
);

Album _album({int trackCount = 3}) {
  const summary = AlbumSummary(
    id: 'test-album',
    title: 'Test Album',
    urlPath: '/game-soundtracks/album/test-album',
  );
  return Album(
    summary: summary,
    tracks: List.generate(
      trackCount,
      (i) => AlbumTrack(
        index: i + 1,
        name: 'Track ${i + 1}',
        trackPagePath: '/game-soundtracks/album/test-album/0$i.mp3',
      ),
    ),
  );
}

/// Client stub whose track-page replies are held until the test releases
/// them, so "the successor is not resolved yet" can be reproduced.
class HoldableClient extends KhinsiderClient {
  HoldableClient() : super(dio: Dio());

  final Map<String, Completer<TrackSource>> _pending = {};
  final List<String> requested = [];

  @override
  Future<Album> getAlbum(
    String albumId, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async => _album();

  @override
  Future<TrackSource> getTrackSources(
    String trackPagePath, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) {
    requested.add(trackPagePath);
    final completer = Completer<TrackSource>();
    _pending[trackPagePath] = completer;
    return completer.future;
  }

  void release(String trackPagePath) => _pending[trackPagePath]!.complete(
    TrackSource(
      trackPagePath: trackPagePath,
      mp3Url: 'https://cdn.example$trackPagePath.mp3',
    ),
  );
}

void main() {
  group('KhinsiderAudioHandler (system media controls)', () {
    test('play/pause/next/previous go through the app-level handler', () async {
      final inner = RecordingPlayer();
      final handler = KhinsiderAudioHandler(inner: inner);
      final commands = RecordingCommands();
      handler.setSystemCommandHandler(commands);
      addTearDown(handler.dispose);

      await handler.play();
      await handler.pause();
      await handler.skipToNext();
      await handler.skipToPrevious();
      await handler.stop();

      expect(commands.calls, ['play', 'pause', 'next', 'previous', 'stop']);
      expect(
        inner.calls,
        isEmpty,
        reason:
            'system controls must not bypass the controller: only it can '
            'resolve a successor that is not queued yet',
      );
    });

    test('falls back to the inner player when nothing is installed', () async {
      final inner = RecordingPlayer();
      final handler = KhinsiderAudioHandler(inner: inner);
      addTearDown(handler.dispose);

      await handler.play();
      await handler.pause();
      await handler.skipToNext();

      expect(inner.calls, ['play', 'pause', 'next']);
    });

    test(
      'publishes transport controls, compact order and queue index',
      () async {
        final inner = RecordingPlayer();
        final handler = KhinsiderAudioHandler(inner: inner);
        addTearDown(handler.dispose);

        await handler.loadQueue(const [_item], startIndex: 0);
        inner.snapshots.add(
          const AudioPlayerSnapshot(playing: true, currentIndex: 0),
        );
        inner.durations.add(const Duration(minutes: 3));
        await Future<void>.delayed(Duration.zero);

        final state = handler.playbackState.value;
        expect(state.playing, isTrue);
        expect(state.processingState, AudioProcessingState.ready);
        expect(state.controls.map((c) => c.action), [
          MediaAction.skipToPrevious,
          MediaAction.pause,
          MediaAction.skipToNext,
          MediaAction.stop,
        ]);
        expect(
          state.androidCompactActionIndices,
          [0, 1, 2],
          reason: 'the compact view keeps prev / play-pause / next only',
        );
        expect(state.queueIndex, 0);
        expect(state.systemActions, contains(MediaAction.seek));
        // The seek bar / lock-screen progress needs a duration on the item.
        expect(handler.mediaItem.value?.duration, const Duration(minutes: 3));
      },
    );

    test('the pause control replaces play once playback pauses', () async {
      final inner = RecordingPlayer();
      final handler = KhinsiderAudioHandler(inner: inner);
      addTearDown(handler.dispose);

      await handler.loadQueue(const [_item], startIndex: 0);
      inner.snapshots.add(
        const AudioPlayerSnapshot(playing: false, currentIndex: 0),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        handler.playbackState.value.controls.map((c) => c.action),
        contains(MediaAction.play),
      );
      expect(
        handler.playbackState.value.controls.map((c) => c.action),
        isNot(contains(MediaAction.pause)),
      );
    });
  });

  group('PlayerController as SystemMediaCommandHandler', () {
    test('installs itself on the player and uninstalls on dispose', () {
      final player = RecordingPlayer();
      final container = ProviderContainer(
        overrides: [audioPlayerProvider.overrideWithValue(player)],
      );

      final notifier = container.read(playerControllerProvider.notifier);
      expect(player.systemHandler, same(notifier));

      container.dispose();
      expect(
        player.systemHandler,
        isNull,
        reason: 'a disposed controller must not keep receiving commands',
      );
    });

    test(
      'next() resolves the successor when the prefetch is still running',
      () async {
        final player = RecordingPlayer();
        final client = HoldableClient();
        final album = _album();
        final container = ProviderContainer(
          overrides: [
            audioPlayerProvider.overrideWithValue(player),
            khinsiderClientProvider.overrideWithValue(client),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(playerControllerProvider.notifier);
        final play = controller.playAlbum(album, startIndex: 0);
        client.release(album.tracks[0].trackPagePath);
        await play;
        await Future<void>.delayed(Duration.zero);

        // Track 0 is playing; the prefetch of track 1 is in flight and held.
        expect(client.requested, [
          album.tracks[0].trackPagePath,
          album.tracks[1].trackPagePath,
        ]);
        expect(player.calls, isNot(contains('next')));

        // The notification / lock-screen "next" arrives right now.
        final next = controller.next();
        await Future<void>.delayed(Duration.zero);
        expect(
          player.calls,
          isNot(contains('next')),
          reason:
              'must wait for the successor instead of silently doing nothing',
        );

        client.release(album.tracks[1].trackPagePath);
        await next;

        expect(
          player.calls,
          contains('next'),
          reason: 'the system "next" button must really advance',
        );
      },
    );

    test('next() on the last track does not advance', () async {
      final player = RecordingPlayer();
      final client = HoldableClient();
      final album = _album();
      final container = ProviderContainer(
        overrides: [
          audioPlayerProvider.overrideWithValue(player),
          khinsiderClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(playerControllerProvider.notifier);
      final play = controller.playAlbum(album, startIndex: 2);
      client.release(album.tracks[2].trackPagePath);
      await play;

      await controller.next();
      expect(player.calls, isNot(contains('next')));
    });
  });
}
