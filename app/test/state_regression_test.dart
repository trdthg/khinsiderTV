import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/audio/audio_cache_manager.dart';
import 'package:khinsider/audio/base_audio_player.dart';
import 'package:khinsider/core/keyboard/global_media_keys.dart';
import 'package:khinsider/data/khinsider_client.dart';
import 'package:khinsider/core/widgets/seek_bar.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider/state/search_controller.dart';
import 'package:khinsider/state/track_cache_controller.dart';
import 'package:khinsider/state/update_controller.dart';
import 'package:khinsider_api/khinsider_api.dart';

/// No-op player double so controllers can be driven without platform audio.
class FakeAudioPlayer implements BaseAudioPlayer {
  final _snaps = StreamController<AudioPlayerSnapshot>.broadcast();

  @override
  Stream<AudioPlayerSnapshot> get snapshotStream => _snaps.stream;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  int get queueLength => 0;
  @override
  Future<void> loadQueue(List<PlayableItem> items, {int startIndex = 0}) async {
    _snaps.add(AudioPlayerSnapshot(playing: true, currentIndex: 0));
  }

  @override
  Future<void> append(List<PlayableItem> items) async {}
  @override
  Future<void> swapCurrentSource(String url) async {}
  @override
  Future<void> stop() async {
    _snaps.add(const AudioPlayerSnapshot(playing: false, currentIndex: null));
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> skipToIndex(int index) async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  void setSystemCommandHandler(SystemMediaCommandHandler? handler) {}
  @override
  Future<void> dispose() async {}
}

class RecordingQueuePlayer extends FakeAudioPlayer {
  final List<List<PlayableItem>> loaded = [];
  final List<List<PlayableItem>> appended = [];

  @override
  Future<void> loadQueue(List<PlayableItem> items, {int startIndex = 0}) async {
    loaded.add(items);
    await super.loadQueue(items, startIndex: startIndex);
  }

  @override
  Future<void> append(List<PlayableItem> items) async {
    appended.add(items);
  }
}

class _StopPlayer extends FakeAudioPlayer {
  int stops = 0;
  @override
  Future<void> stop() async {
    stops++;
    await super.stop();
  }
}

/// Deterministic client stub: no network, and the search response can be
/// held back so out-of-order replies can be reproduced.
class StubClient extends KhinsiderClient {
  StubClient() : super(dio: Dio());

  final Map<String, Completer<List<AlbumSummary>>> pendingSearches = {};
  bool flacAvailable = true;
  int trackSourceRequests = 0;

  @override
  Future<List<AlbumSummary>> searchAlbums(
    String query, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) {
    final completer = Completer<List<AlbumSummary>>();
    pendingSearches[query] = completer;
    return completer.future;
  }

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
  }) async {
    trackSourceRequests++;
    return TrackSource(
      trackPagePath: trackPagePath,
      mp3Url: 'https://example.com/audio.mp3',
      flacUrl: flacAvailable ? 'https://example.com/audio.flac' : null,
    );
  }

  void complete(String query, String result) =>
      pendingSearches[query]!.complete([_album().summary]);
}

void main() {
  group('PlayerState.copyWith', () {
    test('an explicit null clears the index (nothing loaded)', () {
      const s = PlayerState(currentIndex: 3);
      expect(s.copyWith(currentIndex: null).currentIndex, isNull);
      // Omitting it still preserves the value.
      expect(s.copyWith(playing: true).currentIndex, 3);
    });

    test('an explicit null clears duration and error', () {
      const s = PlayerState(duration: Duration(seconds: 9), error: 'boom');
      expect(s.copyWith(duration: null).duration, isNull);
      expect(s.copyWith(error: null).error, isNull);
      expect(s.copyWith(duration: null, error: null).duration, isNull);
      // ...while unrelated fields survive.
      final kept = const PlayerState(
        duration: Duration(seconds: 9),
        error: 'boom',
        preferredFormat: AudioFormat.flac,
      ).copyWith(playing: true);
      expect(kept.duration, const Duration(seconds: 9));
      expect(kept.error, 'boom');
      expect(kept.preferredFormat, AudioFormat.flac);
    });
  });

  group('UpdateState.copyWith', () {
    test('retryDownload can clear the error message', () {
      const s = UpdateState(errorMessage: 'Download failed: boom');
      expect(
        s
            .copyWith(
              downloadPhase: UpdateDownloadPhase.idle,
              errorMessage: null,
            )
            .errorMessage,
        isNull,
      );
    });

    test('downloadedFile can be cleared', () {
      const s = UpdateState(downloadedFile: '/tmp/x.zip');
      expect(s.copyWith(downloadedFile: null).downloadedFile, isNull);
    });
  });

  group('PlayerController', () {
    /// Pumps the app and returns the container plus the loaded album.
    Future<(ProviderContainer, BaseAudioPlayer)> pump(
      WidgetTester tester, {
      BaseAudioPlayer? override,
    }) async {
      final player = override ?? FakeAudioPlayer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioPlayerProvider.overrideWithValue(player),
            khinsiderClientProvider.overrideWithValue(StubClient()),
          ],
          child: MaterialApp(
            // GlobalMediaKeys is installed by KhinsiderApp's `builder`, so it
            // has to be reproduced here for the media-key test to reach it.
            builder: (context, child) =>
                GlobalMediaKeys(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
      );
      addTearDown(container.dispose);
      return (container, player);
    }

    testWidgets('stop() reports no current track and drops the queue', (
      tester,
    ) async {
      final (container, _) = await pump(tester);
      final notifier = container.read(playerControllerProvider.notifier);

      await notifier.playAlbum(_album(), startIndex: 0);
      await tester.pump();
      expect(container.read(playerControllerProvider).currentIndex, 0);

      await notifier.stop();
      await tester.pump();

      final state = container.read(playerControllerProvider);
      expect(
        state.currentIndex,
        isNull,
        reason: 'after stop() no row may stay highlighted',
      );
      expect(state.entries, isEmpty);
      expect(state.playing, isFalse);
    });

    testWidgets('playing a new album keeps the chosen audio quality', (
      tester,
    ) async {
      final (container, _) = await pump(tester);
      final notifier = container.read(playerControllerProvider.notifier);

      await notifier.playAlbum(_album(), startIndex: 0);
      await tester.pump();

      await notifier.setPreferredFormat(AudioFormat.flac);
      expect(
        container.read(playerControllerProvider).preferredFormat,
        AudioFormat.flac,
      );

      // Starting a DIFFERENT album must not reset the quality choice.
      await notifier.playAlbum(_album(), startIndex: 1);
      await tester.pump();
      expect(
        container.read(playerControllerProvider).preferredFormat,
        AudioFormat.flac,
        reason:
            'the user picked FLAC in the OSD menu; a new album must '
            'not silently revert to MP3',
      );
    });

    testWidgets('an unavailable quality does not fake a successful switch', (
      tester,
    ) async {
      final (container, _) = await pump(tester);
      final client = container.read(khinsiderClientProvider) as StubClient;
      client.flacAvailable = false;
      final notifier = container.read(playerControllerProvider.notifier);

      await notifier.playAlbum(_album(), startIndex: 0);
      await tester.pump();

      await notifier.setPreferredFormat(AudioFormat.flac);
      expect(
        container.read(playerControllerProvider).preferredFormat,
        AudioFormat.mp3,
        reason: 'without a FLAC URL the selection must stay on MP3',
      );
    });

    testWidgets('MediaStop reaches the player as a stop, not a toggle', (
      tester,
    ) async {
      final (container, player) = await pump(tester, override: _StopPlayer());
      final stopPlayer = player as _StopPlayer;
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaStop);
      await tester.pump();
      expect(
        stopPlayer.stops,
        1,
        reason: 'the media Stop key must stop playback, not toggle it',
      );
      expect(container.read(playerControllerProvider).playing, isFalse);
    });
  });

  group('SearchController', () {
    test('a slow earlier response cannot overwrite newer results', () async {
      final client = StubClient();
      final container = ProviderContainer(
        overrides: [khinsiderClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(searchControllerProvider.notifier);

      final slow = notifier.search('slow query');
      // The second query is issued before the first one resolves.
      final fast = notifier.search('fast query');
      client.complete('fast query', 'fast query');
      await fast;
      expect(container.read(searchControllerProvider).query, 'fast query');
      expect(container.read(searchControllerProvider).loading, isFalse);

      // Only NOW does the stale first reply arrive: it must be discarded.
      client.complete('slow query', 'slow query');
      await slow;
      expect(container.read(searchControllerProvider).query, 'fast query');
      expect(
        container.read(searchControllerProvider).results.first.title,
        'Test Album',
      );
    });
  });

  group('SeekBar', () {
    testWidgets('renders empty (not full) while the duration is unknown', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeekBar(
              position: const Duration(seconds: 30),
              duration: Duration.zero, // nothing loaded / still buffering
              onSeek: (_) {},
            ),
          ),
        ),
      );
      final fraction = tester.widget<FractionallySizedBox>(
        find
            .descendant(
              of: find.byType(SeekBar),
              matching: find.byType(FractionallySizedBox),
            )
            .first,
      );
      expect(
        fraction.widthFactor,
        anyOf(isNull, lessThanOrEqualTo(0.0)),
        reason: 'an unknown duration must not be shown as fully played',
      );
    });

    testWidgets('tap-to-seek does not fire while the duration is unknown', (
      tester,
    ) async {
      double? sought;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: SeekBar(
                  position: Duration.zero,
                  duration: Duration.zero,
                  onSeek: (ms) => sought = ms,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SeekBar));
      await tester.pump();
      expect(sought, isNull);
    });
  });

  test('playAlbum prefetches at most one following track', () async {
    final player = RecordingQueuePlayer();
    final container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWithValue(player),
        khinsiderClientProvider.overrideWithValue(StubClient()),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(playerControllerProvider.notifier)
        .playAlbum(_album(), startIndex: 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(player.loaded, hasLength(1));
    expect(player.loaded.single, hasLength(1));
    expect(player.appended, hasLength(1));
    expect(player.appended.single, hasLength(1));
    expect(player.appended.single.single.id, 'test-album/2');
    expect(container.read(playerControllerProvider).resolvingAhead, false);
  });

  test('playAlbum uses a cached file without a track-page request', () async {
    final root = await Directory.systemTemp.createTemp('khinsider-cached-play');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final cache = AudioCacheManager(rootOverride: root);
    final base = _album();
    final album = Album(summary: base.summary, tracks: [base.tracks.first]);
    final track = album.tracks.first;
    final cached = cache.fileForSync(
      PlayableItem(
        id: '${album.summary.id}/${track.index}',
        title: track.name,
        url: 'https://example.com/audio.mp3',
        albumTitle: album.summary.title,
        albumId: album.summary.id,
        trackIndex: track.index,
      ),
    );
    await cached.create(recursive: true);
    await cached.writeAsBytes([1, 2, 3]);

    final player = RecordingQueuePlayer();
    final client = StubClient();
    final container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWithValue(player),
        khinsiderClientProvider.overrideWithValue(client),
        audioCacheManagerProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(playerControllerProvider.notifier)
        .playAlbum(album, startIndex: 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(client.trackSourceRequests, 0);
    expect(player.loaded, hasLength(1));
    expect(player.loaded.single.single.url, contains('file:'));
  });
}

Album _album() {
  const summary = AlbumSummary(
    id: 'test-album',
    title: 'Test Album',
    urlPath: '/game-soundtracks/album/test-album',
  );
  final tracks = List.generate(
    3,
    (i) => AlbumTrack(
      index: i + 1,
      name: 'Track ${i + 1}',
      trackPagePath: '/game-soundtracks/album/test-album/0$i.mp3',
    ),
  );
  return Album(summary: summary, tracks: tracks);
}
