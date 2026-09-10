import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/audio/base_audio_player.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider/data/khinsider_client.dart';
import 'package:khinsider/ui/album/album_screen.dart';
import 'package:khinsider/ui/now_playing/zen_view.dart';
import 'package:khinsider_api/khinsider_api.dart';

import 'album_layout_test.dart' show FakeAudioPlayer, longTitleAlbum;

/// Fake player that emits impl snapshots (queue positions) so the
/// controller's album-index mapping can be observed.
class EmittingFakePlayer extends FakeAudioPlayer {
  final _snap = StreamController<AudioPlayerSnapshot>.broadcast();

  @override
  Stream<AudioPlayerSnapshot> get snapshotStream => _snap.stream;

  @override
  Future<void> loadQueue(List<PlayableItem> items, {int startIndex = 0}) async {
    _snap.add(const AudioPlayerSnapshot(playing: true, currentIndex: 0));
  }

  @override
  Future<void> append(List<PlayableItem> items) async {}

  @override
  Future<void> stop() async {
    _snap.add(const AudioPlayerSnapshot(playing: false, currentIndex: null));
  }
}

/// Records phase-2 resolution requests so tests can assert WHICH track was
/// requested after a row activation.
class RecordingClient extends KhinsiderClient {
  RecordingClient() : super(dio: Dio());

  final List<String> requestedTrackPages = [];
  Album album = longTitleAlbum();

  @override
  Future<List<AlbumSummary>> searchAlbums(
    String query, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    return [album.summary];
  }

  @override
  Future<Album> getAlbum(
    String albumId, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    return album;
  }

  @override
  Future<TrackSource> getTrackSources(
    String trackPagePath, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    requestedTrackPages.add(trackPagePath);
    return TrackSource(
      trackPagePath: trackPagePath,
      mp3Url: 'https://example.com/${requestedTrackPages.length}.mp3',
    );
  }
}

void main() {
  testWidgets('selecting tracks resolves the RIGHT track and the current-row '
      'highlight maps to the album index', (tester) async {
    final client = RecordingClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWithValue(EmittingFakePlayer()),
          khinsiderClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          onGenerateRoute: (settings) {
            if (settings.name == '/now-playing') {
              final (album, trackIndex) = settings.arguments as (Album, int);
              return MaterialPageRoute<void>(
                builder: (_) => ZenNowPlaying(
                  album: album,
                  active: true,
                  initialTrackIndex: trackIndex,
                  onExitZen: () {},
                ),
              );
            }
            return MaterialPageRoute<void>(
              builder: (_) => const AlbumScreen(albumId: 'long-title-album'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Click row "Track 5" on the album page. (No pumpAndSettle: the
    // now-playing screen has infinite cover animations.)
    await tester.tap(find.text('Track 5 — Some Fairly Long Track Name Here'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(
      client.requestedTrackPages.first,
      contains('04.mp3'),
      reason:
          'track 5 (1-based) -> 04.mp3; requested: ${client.requestedTrackPages}',
    );

    // 2. The Now Playing screen pushed; the current-row highlight must map
    // to album index 4 (track 5), NOT the impl queue index 0.
    expect(find.byType(ZenNowPlaying), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ZenNowPlaying)),
    );
    expect(
      container.read(playerControllerProvider).currentIndex,
      4,
      reason:
          'currentIndex must be the ALBUM track index (4), '
          'not the impl queue position (0)',
    );

    // 3. On the zen track list, scroll programmatically to Track 8 and tap.
    // (Scopes everything to the zen view: the hidden normal layer contains a
    // copy of every row text.)
    final zenList = find.descendant(
      of: find.byType(ZenNowPlaying),
      matching: find.byType(Scrollable),
    ).first;
    tester.state<ScrollableState>(zenList).position.jumpTo(320);
    await tester.pump(const Duration(milliseconds: 200));
    final track8 = find.descendant(
      of: find.byType(ZenNowPlaying),
      matching: find.text('Track 8 — Some Fairly Long Track Name Here'),
    );
    final countBefore = client.requestedTrackPages.length;
    await tester.tap(track8);
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(end) &&
        client.requestedTrackPages.length <= countBefore) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      client.requestedTrackPages[countBefore],
      contains('07.mp3'),
      reason:
          'clicking track 8 must resolve 07.mp3; requested: ${client.requestedTrackPages}',
    );
    expect(
      container.read(playerControllerProvider).currentIndex,
      7,
      reason: 'highlight must follow the clicked track (album index 7)',
    );
  });
}
