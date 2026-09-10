import 'package:dio/dio.dart';

import 'http_cache.dart';
import 'models.dart';
import 'parsers.dart';

/// Lightweight, transparent HTTP client for KHInsider.
///
/// Implements a **two-phase lazy loading** strategy to stay gentle on the
/// site and avoid triggering anti-bot protection:
///
///  * **Phase 1** — search / album listing: exactly **one** HTML request.
///  * **Phase 2** — direct media URLs are only resolved when a track is
///    actually about to be played or downloaded (one request per track).
///
/// UI-agnostic and Flutter-free: depends only on `dio` + `html`.
class KhinsiderClient {
  KhinsiderClient({
    Dio? dio,
    String userAgent = defaultUserAgent,
    HttpCache? cache,
  }) : _dio = dio ?? _buildDio(userAgent),
       // Private named params can't use initializing formals.
       // ignore: prefer_initializing_formals
       _cache = cache;

  /// Optional disk cache. When provided, search/album pages are served
  /// cache-first; pass `forceRefresh` to bypass and overwrite the entry.
  /// Track pages are never cached (their CDN tokens rotate).
  final HttpCache? _cache;

  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const String baseUrl = 'https://downloads.khinsider.com';

  /// NOTE: the path segment is **plural** (`game-soundtracks`).
  /// The singular variant returns a Cloudflare 403 WAF block.
  static const String albumBasePath = '/game-soundtracks/album';

  /// Track pages are cached briefly (CDN tokens rotate eventually).
  static const Duration trackPageTtl = Duration(minutes: 30);

  final Dio _dio;

  static Dio _buildDio(String userAgent) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
        // Follow redirects (e.g. http->https, canonical paths).
        followRedirects: true,
        validateStatus: (code) => code != null && code < 400,
      ),
    );
    return dio;
  }

  /// Cached HTML fetch helper.
  ///
  /// * [ttl] null = entry never expires (page cache, force-refresh only).
  /// * [ttl] set  = serve from cache within the window, refetch after.
  Future<String> _getHtml(
    String path, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
    Duration? ttl,
  }) async {
    final cache = _cache;
    if (cache == null) {
      final res = await _dio.get<String>(path, cancelToken: cancelToken);
      return res.data ?? '';
    }
    if (!forceRefresh) {
      final cached = await cache.get(path, ttl: ttl);
      if (cached != null) return cached;
    }
    final res = await _dio.get<String>(path, cancelToken: cancelToken);
    await cache.put(path, res.data ?? '', ttl: ttl);
    return res.data ?? '';
  }

  /// Phase 1 — search albums by keyword.
  Future<List<AlbumSummary>> searchAlbums(
    String query, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    final html = await _getHtml(
      '/search?search=${Uri.encodeQueryComponent(query)}',
      forceRefresh: forceRefresh,
      cancelToken: cancelToken,
    );
    return KhinsiderParsers.parseSearchResults(html);
  }

  /// Phase 1 — load full album details (cover + ordered track list).
  Future<Album> getAlbum(
    String albumId, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    final html = await _getHtml(
      '$albumBasePath/$albumId',
      forceRefresh: forceRefresh,
      cancelToken: cancelToken,
    );
    final album = KhinsiderParsers.parseAlbumPage(html);
    // Enrich the placeholder summary with the id/url we already know.
    return Album(
      summary: AlbumSummary(
        id: albumId,
        title: album.summary.title,
        urlPath: '$albumBasePath/$albumId',
        thumbUrl: album.coverUrl,
      ),
      coverUrl: album.coverUrl,
      tracks: album.tracks,
      metadata: album.metadata,
      relatedAlbums: album.relatedAlbums,
    );
  }

  /// Phase 2 — resolve direct media URLs for one track.
  ///
  /// Called only when a track is added to the playback queue / downloaded.
  /// Pass the [AlbumTrack.trackPagePath] exactly as returned in phase 1.
  Future<TrackSource> getTrackSources(
    String trackPagePath, {
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    // The track page itself is cached for a short window: CDN tokens
    // rotate eventually, so a TTL beats infinite caching here.
    final html = await _getHtml(
      trackPagePath,
      forceRefresh: forceRefresh,
      cancelToken: cancelToken,
      ttl: trackPageTtl,
    );
    return KhinsiderParsers.parseTrackPage(html, trackPagePath: trackPagePath);
  }

  /// Convenience: resolve sources for several tracks sequentially.
  /// (Kept sequential on purpose — parallel bursts look bot-like.)
  Future<List<TrackSource>> getAlbumTrackSources(
    Album album, {
    CancelToken? cancelToken,
  }) async {
    final out = <TrackSource>[];
    for (final track in album.tracks) {
      out.add(
        await getTrackSources(track.trackPagePath, cancelToken: cancelToken),
      );
    }
    return out;
  }

  /// Release underlying resources.
  void close() => _dio.close();
}
