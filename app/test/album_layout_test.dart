import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/audio/base_audio_player.dart';
import 'package:khinsider/state/album_controller.dart';
import 'package:khinsider/state/player_controller.dart';
import 'package:khinsider/ui/album/album_screen.dart';
import 'package:khinsider/ui/shared/player_bar.dart';
import 'package:khinsider_api/khinsider_api.dart';

/// No-op player double so PlayerBar can render without platform audio.
class FakeAudioPlayer implements BaseAudioPlayer {
  @override
  Stream<AudioPlayerSnapshot> get snapshotStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  int get queueLength => 1;
  @override
  Future<void> loadQueue(
    List<PlayableItem> items, {
    int startIndex = 0,
  }) async {}
  @override
  Future<void> append(List<PlayableItem> items) async {}
  @override
  Future<void> swapCurrentSource(String url) async {}
  @override
  Future<void> stop() async {}
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
  Future<void> dispose() async {}
}

/// Player controller seeded with an active playback session.
class SeededPlayerController extends PlayerController {
  @override
  PlayerState build() {
    ref.watch(audioPlayerProvider); // keep provider dependency
    final album = longTitleAlbum();
    final entry = QueueEntry(track: album.tracks.first, album: album)
      ..resolvedMp3Url = 'https://example.com/audio.mp3';
    return PlayerState(
      entries: [entry],
      currentIndex: 0,
      playing: true,
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 2),
    );
  }
}

Album longTitleAlbum() {
  const summary = AlbumSummary(
    id: 'long-title-album',
    title:
        'A Very Long Original Soundtrack Album Title That Definitely Wraps '
        'Onto Multiple Lines When Rendered In The Side Panel',
    urlPath: '/game-soundtracks/album/long-title-album',
  );
  final tracks = List.generate(
    12,
    (i) => AlbumTrack(
      index: i + 1,
      name: 'Track ${i + 1} — Some Fairly Long Track Name Here',
      trackPagePath: '/game-soundtracks/album/long-title-algram/0$i.mp3',
      duration: '2:0$i',
    ),
  );
  return Album(summary: summary, tracks: tracks); // coverUrl: null (offline)
}

void main() {
  testWidgets('Favorite button stays fully visible while player bar is shown '
      '(small window, long title)', (tester) async {
    for (final size in [const Size(820, 480), const Size(820, 400)]) {
      tester.view.physicalSize = size;
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

      // The favorite button must exist…
      final buttonFinder = find.byType(FilledButton);
      expect(
        buttonFinder,
        findsOneWidget,
        reason: 'size $size: favorite button missing',
      );

      // …and sit entirely above the player bar (not clipped / covered).
      final buttonRect = tester.getRect(buttonFinder);
      final barRect = tester.getRect(find.byType(PlayerBar));
      expect(
        buttonRect.bottom,
        lessThanOrEqualTo(barRect.top + 0.5),
        reason:
            'size $size: favorite button ($buttonRect) extends into '
            'the player bar (top ${barRect.top})',
      );
      expect(buttonRect.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('metadata panel and related albums render on album screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1.0;

    final base = longTitleAlbum();
    final richAlbum = Album(
      summary: base.summary,
      tracks: base.tracks,
      metadata: const AlbumMetadata(
        alternativeTitles: ['きまぐれオレンジ☆ロード'],
        platforms: ['PC-98'],
        year: '1988',
        developedBy: 'Microcabin',
        publishedBy: 'Microcabin',
        fileCount: 6,
        totalFilesize: '27 MB',
        dateAdded: 'Sep 16th, 2025',
        albumType: 'Gamerip',
        uploadedBy: 'eet4649',
      ),
      relatedAlbums: const [
        AlbumSummary(
          id: 'kor-loving-heart',
          title: 'KIMAGURE ORANGE☆ROAD Loving Heart',
          urlPath: '/game-soundtracks/album/kor-loving-heart',
          year: '1989',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
          albumDetailProvider((
            base.summary.id,
            0,
          )).overrideWith((ref) async => richAlbum),
        ],
        child: const MaterialApp(
          home: AlbumScreen(albumId: 'long-title-album'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Details'), findsOneWidget);
    expect(find.text('PC-98'), findsOneWidget);
    expect(find.text('Microcabin'), findsNWidgets(2)); // dev + publisher
    expect(find.text('27 MB'), findsOneWidget);
    expect(find.text('Sep 16th, 2025'), findsOneWidget);
    expect(find.text('eet4649'), findsOneWidget);

    // Related row sits at the end of the (lazy) track list — scroll to it.
    await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(find.text('People who viewed this also viewed'), findsOneWidget);
    expect(find.text('KIMAGURE ORANGE☆ROAD Loving Heart'), findsOneWidget);
  });
}
