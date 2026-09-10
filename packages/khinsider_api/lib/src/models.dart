/// Data models for the KHInsider API.
///
/// All models are immutable and Flutter-free (pure Dart) so they can be
/// consumed by any frontend (Flutter app, CLI, embedded device, ...).
library;

/// A lightweight album descriptor returned by search / listing pages.
///
/// This is the "phase 1" object: it does NOT contain the track list.
/// Use [KhinsiderClient.getAlbum] to lazily load full album details.
class AlbumSummary {
  const AlbumSummary({
    required this.id,
    required this.title,
    required this.urlPath,
    this.thumbUrl,
    this.platforms = const [],
    this.type,
    this.year,
  });

  /// Album id, e.g. `mario-luigi-rpg-sound-selection`.
  final String id;

  final String title;

  /// Site-relative path, e.g. `/game-soundtracks/album/<id>`.
  final String urlPath;

  /// Small thumbnail (search list size).
  final String? thumbUrl;

  /// Platform names, e.g. `['DS', 'GBA']`.
  final List<String> platforms;

  /// e.g. `Soundtrack`, `Gamerip`, `Inspired By`.
  final String? type;

  /// Release year, e.g. `2009`.
  final String? year;

  /// Fully-qualified page URL.
  String get pageUrl => 'https://downloads.khinsider.com$urlPath';

  @override
  String toString() => 'AlbumSummary($id, $title)';
}

/// A single track row inside an album page ("phase 1").
///
/// Contains no playable URL. Call [KhinsiderClient.getTrackSources] with
/// [trackPagePath] to resolve the direct media URL ("phase 2").
class AlbumTrack {
  const AlbumTrack({
    required this.index,
    required this.name,
    required this.trackPagePath,
    this.songId,
    this.duration,
    this.mp3SizeMb,
    this.flacSizeMb,
  });

  /// 1-based track number as shown on the site.
  final int index;

  final String name;

  /// Site-relative path of the track's own page, e.g.
  /// `/game-soundtracks/album/<id>/01.%2520Preparing....mp3`.
  final String trackPagePath;

  /// Internal song id (used by the site's playlist widget).
  final String? songId;

  /// Duration as displayed, e.g. `1:35`.
  final String? duration;

  /// MP3 file size in megabytes, if shown.
  final double? mp3SizeMb;

  /// FLAC file size in megabytes, if shown.
  final double? flacSizeMb;

  @override
  String toString() => 'AlbumTrack(#$index $name)';
}

/// Descriptive metadata shown on an album page (phase 1).
///
/// Example: alternative titles, platforms, year, developer/publisher,
/// file counts, upload info. All fields nullable — the site omits them
/// variably depending on album type.
class AlbumMetadata {
  const AlbumMetadata({
    this.alternativeTitles = const [],
    this.platforms = const [],
    this.year,
    this.developedBy,
    this.publishedBy,
    this.fileCount,
    this.totalFilesize,
    this.dateAdded,
    this.albumType,
    this.uploadedBy,
  });

  /// Native/alternate titles, e.g. `きまぐれオレンジ☆ロード`.
  final List<String> alternativeTitles;

  /// Platform names, e.g. `['PC-98']`.
  final List<String> platforms;

  /// Release year, e.g. `1988`.
  final String? year;

  final String? developedBy;
  final String? publishedBy;

  /// `Number of Files`, e.g. `6`.
  final int? fileCount;

  /// `Total Filesize`, e.g. `27 MB`.
  final String? totalFilesize;

  /// `Date Added`, e.g. `Sep 16th, 2025`.
  final String? dateAdded;

  /// `Album type`, e.g. `Gamerip`, `Soundtrack`.
  final String? albumType;

  /// `Uploaded by`, e.g. `eet4649`.
  final String? uploadedBy;
}

/// Full album details ("phase 1" complete): metadata + track list.
class Album {
  const Album({
    required this.summary,
    this.coverUrl,
    this.tracks = const [],
    this.metadata,
    this.relatedAlbums = const [],
  });

  final AlbumSummary summary;

  /// Large album cover.
  final String? coverUrl;

  final List<AlbumTrack> tracks;

  /// Descriptive metadata from the album page, if present.
  final AlbumMetadata? metadata;

  /// "People who viewed this also viewed" recommendations.
  final List<AlbumSummary> relatedAlbums;

  int get trackCount => tracks.length;
}

/// Direct media URLs resolved from a track page ("phase 2").
class TrackSource {
  const TrackSource({required this.trackPagePath, this.mp3Url, this.flacUrl});

  /// The track page path this source was resolved from.
  final String trackPagePath;

  /// Direct MP3 CDN URL — the default streaming format.
  final String? mp3Url;

  /// Direct FLAC CDN URL — lossless, much larger.
  final String? flacUrl;

  /// Best streaming URL ([mp3Url] preferred).
  String? get bestUrl => mp3Url ?? flacUrl;

  bool get isEmpty => bestUrl == null;
}
