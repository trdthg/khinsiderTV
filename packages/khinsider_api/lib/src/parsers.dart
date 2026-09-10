import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

import 'models.dart';

/// Pure-DOM parsers for KHInsider pages.
///
/// The site markup is stable and dependency-free to parse, which keeps the
/// whole API layer pure Dart (no native bindings) for maximum portability.
abstract final class KhinsiderParsers {
  /// Parse the search results page (`/search?search=...`).
  static List<AlbumSummary> parseSearchResults(String html) {
    final doc = parse(html);
    final table = doc.querySelector('table.albumList');
    if (table == null) return const [];

    final results = <AlbumSummary>[];
    for (final row in table.querySelectorAll('tr')) {
      if (row.querySelector('th') != null) continue; // header row

      final iconCell = row.querySelector('td.albumIcon');
      final link =
          iconCell?.querySelector('a[href]') ??
          row.querySelectorAll('td')[1].querySelector('a[href]');
      if (link == null) continue;

      final path = link.attributes['href'];
      if (path == null || !path.contains('/album/')) continue;

      final img = iconCell?.querySelector('img[src]');
      final cells = row.querySelectorAll('td');

      // Title cell may carry a trailing catalog-number span, e.g. [NTD-17189].
      final titleCell = cells.length > 1 ? cells[1] : null;
      final titleNode = titleCell?.querySelector('a[href]');
      final title = titleNode?.text.trim() ?? '';

      final platformCell = cells.length > 2 ? cells[2] : null;
      final platforms = platformCell == null
          ? const <String>[]
          : platformCell
                .querySelectorAll('a')
                .map((a) => a.text.trim())
                .where((t) => t.isNotEmpty)
                .toList();

      final type = cells.length > 3 ? cells[3].text.trim() : null;
      final year = cells.length > 4 ? cells[4].text.trim() : null;

      results.add(
        AlbumSummary(
          id: _albumIdFromPath(path),
          title: title,
          urlPath: path,
          thumbUrl: img?.attributes['src'],
          platforms: platforms,
          type: (type == null || type.isEmpty) ? null : type,
          year: (year == null || year.isEmpty) ? null : year,
        ),
      );
    }
    return results;
  }

  /// Parse an album page (`/game-soundtracks/album/<id>`): metadata + tracks.
  static Album parseAlbumPage(String html, {AlbumSummary? summary}) {
    final doc = parse(html);

    final title = doc.querySelector('h2')?.text.trim() ?? summary?.title ?? '';

    // Large cover: first img under /thumbs/ (not thumbs_small).
    String? coverUrl;
    for (final img in doc.querySelectorAll('img[src]')) {
      final src = img.attributes['src'] ?? '';
      if (src.contains('/thumbs/')) {
        coverUrl = src;
        break;
      }
    }

    final metadata = _parseMetadata(doc);
    final relatedAlbums = _parseRelatedAlbums(doc);

    final tracks = <AlbumTrack>[];
    final table =
        doc.querySelector('table#songlist') ?? doc.querySelector('#songlist');
    if (table != null) {
      var index = 0;
      for (final row in table.querySelectorAll('tr')) {
        if (row.querySelector('th') != null) continue; // header

        final link = row.querySelector('td.clickable-row a[href]');
        if (link == null) continue;
        final path = link.attributes['href'];
        if (path == null || !path.contains('/album/')) continue;

        index++;
        final name = link.text.trim();

        // Column layout: [#] [Song Name] [MP3: duration] [FLAC: size] ...
        String? duration;
        double? mp3SizeMb;
        double? flacSizeMb;
        final clickable = row.querySelectorAll('td.clickable-row');
        if (clickable.length >= 2) {
          duration = _durationOrNull(clickable[1].text.trim());
        }
        if (clickable.length >= 3) {
          mp3SizeMb = _sizeMbOrNull(clickable[2].text.trim());
        }
        if (clickable.length >= 4) {
          flacSizeMb = _sizeMbOrNull(clickable[3].text.trim());
        }

        final songId = row
            .querySelector('.playlistAddTo')
            ?.attributes['songid'];

        tracks.add(
          AlbumTrack(
            index: index,
            name: name,
            trackPagePath: path,
            songId: songId,
            duration: duration,
            mp3SizeMb: mp3SizeMb,
            flacSizeMb: flacSizeMb,
          ),
        );
      }
    }

    return Album(
      summary:
          summary ??
          AlbumSummary(id: _albumIdFromPath('/x'), title: title, urlPath: ''),
      coverUrl: coverUrl,
      tracks: tracks,
      metadata: metadata,
      relatedAlbums: relatedAlbums,
    );
  }

  /// Parse a track page: resolve direct MP3 / FLAC media URLs ("phase 2").
  static TrackSource parseTrackPage(
    String html, {
    required String trackPagePath,
  }) {
    final doc = parse(html);

    String? mp3Url;
    String? flacUrl;

    // Primary source: <audio id="audio" src="...mp3">
    final audio =
        doc.querySelector('audio#audio[src]') ??
        doc.querySelector('audio[src]');
    final audioSrc = audio?.attributes['src'];
    if (audioSrc != null) {
      if (_hasFlacExt(audioSrc)) {
        flacUrl = audioSrc;
      } else {
        mp3Url = audioSrc;
      }
    }

    // Secondary sources: <a> links to media CDN files.
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'];
      if (href == null || !href.startsWith('http')) continue;
      final lower = href.toLowerCase();
      if (lower.endsWith('.flac') && flacUrl == null) {
        flacUrl = href;
      } else if (lower.endsWith('.mp3') && mp3Url == null) {
        mp3Url = href;
      }
    }

    return TrackSource(
      trackPagePath: trackPagePath,
      mp3Url: mp3Url,
      flacUrl: flacUrl,
    );
  }

  // ---------------------------------------------------------------------------
  // helpers
  // ---------------------------------------------------------------------------

  /// Parse the descriptive metadata block on an album page.
  static AlbumMetadata? _parseMetadata(Document doc) {
    final altEl = doc.querySelector('.albuminfoAlternativeTitles');
    final altTitles =
        altEl?.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];

    // The metadata <p align="left"> directly follows the alt-titles <p> when
    // present; fall back to a page-wide query.
    Element? p = altEl?.nextElementSibling;
    if (p == null || !(p.localName == 'p' && p.text.contains('Platforms:'))) {
      p = doc.querySelector('p[align="left"]');
    }
    if (p == null && altTitles.isEmpty) return null;

    // Walk child nodes: text nodes carry `Label:` markers, <a>/<b> elements
    // carry the values, appended to the most recent label.
    final map = <String, List<String>>{};
    String? key;
    if (p != null) {
      for (final node in p.nodes) {
        if (node is Element) {
          final text = node.text.trim();
          final href = node.attributes['href'] ?? '';
          if (text.isEmpty) continue;
          if (text == 'Change Log' || href.endsWith('/change_log')) continue;
          if (key != null) {
            map.update(key, (v) => [...v, text], ifAbsent: () => [text]);
          }
        } else {
          for (final m in RegExp(
            r'([A-Za-z][A-Za-z ]*?):',
          ).allMatches(node.text ?? '')) {
            key = m.group(1)!.trim();
            map.putIfAbsent(key, () => []);
          }
        }
      }
    }

    List<String> vals(String label) => map[label] ?? const [];
    String? first(String label) =>
        vals(label).isEmpty ? null : vals(label).first;

    return AlbumMetadata(
      alternativeTitles: altTitles,
      platforms: vals('Platforms'),
      year: first('Year'),
      developedBy: first('Developed by'),
      publishedBy: first('Published by'),
      fileCount: int.tryParse(first('Number of Files') ?? ''),
      totalFilesize: first('Total Filesize'),
      dateAdded: first('Date Added'),
      albumType: first('Album type'),
      uploadedBy: first('Uploaded by'),
    );
  }

  /// Parse the "People who viewed this also viewed" recommendation tables.
  static List<AlbumSummary> _parseRelatedAlbums(Document doc) {
    Element? h2;
    for (final h in doc.querySelectorAll('h2')) {
      if (h.text.toLowerCase().contains('also viewed')) {
        h2 = h;
        break;
      }
    }
    if (h2 == null) return const [];

    final results = <AlbumSummary>[];
    Element? sibling = h2.nextElementSibling;
    while (sibling != null) {
      if (sibling.localName == 'h2' || sibling.localName == 'h3') break;
      if (sibling.localName == 'table') {
        for (final td in sibling.querySelectorAll('td.albumIconLarge')) {
          final a = td.querySelector('a[href]');
          final path = a?.attributes['href'];
          if (path == null || !path.contains('/album/')) continue;

          var title = (td.querySelector('p')?.text ?? '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          String? year;
          final ym = RegExp(r'\((\d{4})\)\s*$').firstMatch(title);
          if (ym != null) {
            year = ym.group(1);
            title = title.substring(0, ym.start).trim();
          }

          results.add(
            AlbumSummary(
              id: _albumIdFromPath(path),
              title: title,
              urlPath: path,
              thumbUrl: td.querySelector('img[src]')?.attributes['src'],
              year: year,
            ),
          );
        }
      }
      sibling = sibling.nextElementSibling;
    }
    return results;
  }

  static bool _hasFlacExt(String url) =>
      url.toLowerCase().split('?').first.endsWith('.flac');

  static String _albumIdFromPath(String path) {
    final segs = path.split('/');
    final i = segs.indexOf('album');
    if (i >= 0 && i + 1 < segs.length) return segs[i + 1];
    return path;
  }

  static String? _durationOrNull(String text) {
    final m = RegExp(r'^\d{1,2}:\d{2}$').firstMatch(text.trim());
    return m == null ? null : text.trim();
  }

  static double? _sizeMbOrNull(String text) {
    final m = RegExp(r'([\d.]+)\s*MB', caseSensitive: false).firstMatch(text);
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
  }
}
