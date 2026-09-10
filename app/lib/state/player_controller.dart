import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../audio/base_audio_player.dart';
import '../audio/just_audio_player_impl.dart';
import '../data/khinsider_client.dart';

/// Preferred streaming format for the audio-quality switcher.
enum AudioFormat { mp3, flac }

/// One slot in the playback queue. Sources are resolved lazily (phase 2).
class QueueEntry {
  QueueEntry({required this.track, required this.album});

  final AlbumTrack track;
  final Album album;

  String? resolvedMp3Url;
  String? resolvedFlacUrl;

  /// URL for the currently preferred format, with fallback.
  String? urlFor(AudioFormat f) => f == AudioFormat.flac
      ? (resolvedFlacUrl ?? resolvedMp3Url)
      : (resolvedMp3Url ?? resolvedFlacUrl);
}

/// Everything the UI needs to render playback state.
class PlayerState {
  const PlayerState({
    this.entries = const [],
    this.currentIndex,
    this.playing = false,
    this.processing = false,
    this.resolvingAhead = false,
    this.position = Duration.zero,
    this.duration,
    this.error,
    this.preferredFormat = AudioFormat.mp3,
  });

  final List<QueueEntry> entries;
  final int? currentIndex;
  final bool playing;
  final bool processing;

  /// True while background prefetch (phase 2) is still filling the queue.
  final bool resolvingAhead;
  final Duration position;
  final Duration? duration;
  final String? error;

  /// User-selected audio quality (OSD menu switcher).
  final AudioFormat preferredFormat;

  QueueEntry? get current =>
      currentIndex != null && currentIndex! < entries.length
      ? entries[currentIndex!]
      : null;

  PlayerState copyWith({
    List<QueueEntry>? entries,
    int? currentIndex,
    bool clearIndex = false,
    bool? playing,
    bool? processing,
    bool? resolvingAhead,
    Duration? position,
    Duration? duration,
    String? error,
    AudioFormat? preferredFormat,
  }) {
    return PlayerState(
      entries: entries ?? this.entries,
      currentIndex: clearIndex ? null : (currentIndex ?? this.currentIndex),
      playing: playing ?? this.playing,
      processing: processing ?? this.processing,
      resolvingAhead: resolvingAhead ?? this.resolvingAhead,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      error: error,
      preferredFormat: preferredFormat ?? this.preferredFormat,
    );
  }
}

/// Bridges the UI to [BaseAudioPlayer] and performs lazy phase-2 URL
/// resolution: the clicked track is resolved immediately, remaining tracks
/// are resolved one-by-one in the background and appended to the queue.
class PlayerController extends Notifier<PlayerState> {
  BaseAudioPlayer get _player => ref.read(audioPlayerProvider);

  /// Cancellation for the in-flight phase-2 resolution of the current
  /// playAlbum call (the track-list spinner cancel button).
  CancelToken? _loadCancelToken;

  /// Maps impl-queue position -> album track index. The audio queue only
  /// contains tracks resolved so far, starting at the clicked track, so the
  /// impl's currentIndex must be translated before UI code uses it.
  final List<int> _albumIndexOfQueue = [];

  int? _implIndexToAlbumIndex(int? implIndex) {
    if (implIndex == null ||
        implIndex < 0 ||
        implIndex >= _albumIndexOfQueue.length) {
      return null;
    }
    return _albumIndexOfQueue[implIndex];
  }

  @override
  PlayerState build() {
    // Wire impl streams to UI state (kept for the lifetime of the app).
    final p = _player;
    p.snapshotStream.listen((snap) {
      state = state.copyWith(
        playing: snap.playing,
        processing: snap.processing,
        currentIndex: _implIndexToAlbumIndex(snap.currentIndex),
      );
    });
    // Throttled: positionStream can tick at up to 60 Hz, which would
    // otherwise rebuild every listening widget at 60 Hz and freeze the UI.
    p.positionStream.listen((pos) {
      if (!ref.mounted) return;
      final current = state.position;
      final wentBackwards = pos < current;
      final movedEnough =
          (pos - current).abs() >= const Duration(milliseconds: 250);
      final jumped = current == Duration.zero && pos > Duration.zero;
      if (movedEnough || wentBackwards || jumped) {
        state = state.copyWith(position: pos);
      }
    });
    p.durationStream.listen((d) => state = state.copyWith(duration: d));
    ref.onDispose(p.dispose);
    return const PlayerState();
  }

  /// Start playback of [album] at [startIndex]. Resolves only the clicked
  /// track now (1 request); the rest is prefetched in the background.
  Future<void> playAlbum(Album album, {int startIndex = 0}) async {
    final tracks = album.tracks;
    if (tracks.isEmpty) return;

    // A new play request always invalidates the previous load/prefetch.
    _loadCancelToken?.cancel();
    final token = CancelToken();
    _loadCancelToken = token;

    state = const PlayerState(processing: true, resolvingAhead: true);
    final entries = tracks
        .map((t) => QueueEntry(track: t, album: album))
        .toList();

    try {
      // Phase 2 — just the clicked track (both formats come in one request).
      final src = await ref
          .read(khinsiderClientProvider)
          .getTrackSources(
            tracks[startIndex].trackPagePath,
            cancelToken: token,
          );
      if (!ref.mounted || token.isCancelled) return;
      if (src.isEmpty) {
        state = state.copyWith(
          processing: false,
          error: 'No audio stream found for "${tracks[startIndex].name}"',
        );
        return;
      }
      entries[startIndex]
        ..resolvedMp3Url = src.mp3Url
        ..resolvedFlacUrl = src.flacUrl;
      state = state.copyWith(entries: entries);

      final first = _toPlayable(entries[startIndex]);
      if (first != null) {
        _albumIndexOfQueue
          ..clear()
          ..add(startIndex);
        await _player.loadQueue([first], startIndex: 0);
      }
      if (!ref.mounted) return;

      // Background prefetch: remaining tracks, sequentially, in order.
      unawaited(_prefetchRest(album, entries, startIndex, token));
    } catch (e) {
      state = state.copyWith(processing: false, error: 'Playback failed: $e');
    }
  }

  /// Called from the track-row spinner button: abort the pending load and
  /// drop whatever was already queued, returning the row to its idle state.
  Future<void> cancelLoading() async {
    _loadCancelToken?.cancel();
    _loadCancelToken = null;
    _albumIndexOfQueue.clear();
    await _player.stop();
    if (!ref.mounted) return;
    state = PlayerState(preferredFormat: state.preferredFormat);
  }

  Future<void> _prefetchRest(
    Album album,
    List<QueueEntry> entries,
    int clickedIndex,
    CancelToken token,
  ) async {
    // Capture dependencies up-front: this runs in the background and the
    // provider may be disposed while it is still in flight.
    final client = ref.read(khinsiderClientProvider);
    // Order: everything after the clicked track, then wrap around the front.
    final order = <int>[
      for (var i = clickedIndex + 1; i < entries.length; i++) i,
      for (var i = 0; i < clickedIndex; i++) i,
    ];
    for (final i in order) {
      if (!ref.mounted || token.isCancelled) return;
      try {
        final src = await client.getTrackSources(
          entries[i].track.trackPagePath,
          cancelToken: token,
        );
        if (!ref.mounted || token.isCancelled) return;
        entries[i]
          ..resolvedMp3Url = src.mp3Url
          ..resolvedFlacUrl = src.flacUrl;
        final item = _toPlayable(entries[i]);
        if (item != null) {
          await _player.append([item]);
          _albumIndexOfQueue.add(i);
        }
      } catch (_) {
        // Skip unresolvable tracks; never break the queue.
      }
      if (!ref.mounted || token.isCancelled) return;
      state = state.copyWith(entries: List.of(entries));
    }
    if (!ref.mounted || token.isCancelled) return;
    state = state.copyWith(resolvingAhead: false);
  }

  PlayableItem? _toPlayable(QueueEntry e) {
    final url = e.urlFor(state.preferredFormat);
    if (url == null) return null;
    return PlayableItem(
      id: '${e.album.summary.id}/${e.track.index}',
      title: e.track.name,
      url: url,
      artist: e.album.summary.title,
      albumTitle: e.album.summary.title,
      artUri: e.album.coverUrl != null ? Uri.tryParse(e.album.coverUrl!) : null,
    );
  }

  Future<void> pause() => _player.pause();
  Future<void> play() => _player.play();

  Future<void> togglePlayPause() async {
    if (state.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> next() => _player.next();
  Future<void> previous() => _player.previous();
  Future<void> seek(Duration pos) => _player.seek(pos);

  /// Switch streaming quality; the current track re-loads at its position.
  Future<void> setPreferredFormat(AudioFormat format) async {
    final entry = state.current;
    if (entry == null) return;
    final url = entry.urlFor(format);
    if (url == null) return; // format unavailable for this track
    state = state.copyWith(preferredFormat: format);
    await _player.swapCurrentSource(url);
  }

  /// Whether the quality switcher can offer FLAC right now.
  bool get flacAvailable {
    final entry = state.current;
    return entry?.resolvedFlacUrl != null;
  }

  void clearError() => state = state.copyWith();
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);

/// The single [BaseAudioPlayer] instance for the whole app.
/// (Switch port: replace this provider's implementation only.)
final audioPlayerProvider = Provider<BaseAudioPlayer>((ref) {
  return JustAudioPlayerImpl();
});
