import 'dart:io';

import 'package:khinsider_api/khinsider_api.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('KhinsiderParsers.parseSearchResults', () {
    test('parses album rows from a real search page', () {
      final results = KhinsiderParsers.parseSearchResults(
        fixture('search.html'),
      );

      expect(results, isNotEmpty);

      final first = results.firstWhere((a) => a.id == 'new-super-luigi-u-2019');
      expect(first.title, 'Mario & Luigi For Nintendo Switch (Fan OST)');
      expect(first.urlPath, '/game-soundtracks/album/new-super-luigi-u-2019');
      expect(first.platforms, contains('Switch'));
      expect(first.year, '2019');
      expect(first.thumbUrl, isNotNull);
      // The search page only carries a 60×60 file; what the UI draws is the
      // 200×200 variant of the very same path.
      expect(first.thumbUrl, contains('/thumbs_small/'));
      expect(first.imageUrl, contains('/thumbs_large/'));
      expect(
        first.imageUrl,
        first.thumbUrl!.replaceFirst('/thumbs_small/', '/thumbs_large/'),
      );
      expect(
        first.pageUrl,
        'https://downloads.khinsider.com/game-soundtracks/album/new-super-luigi-u-2019',
      );
    });

    test('strips catalog-number spans from titles', () {
      final results = KhinsiderParsers.parseSearchResults(
        fixture('search.html'),
      );
      final album = results.firstWhere(
        (a) => a.id == 'mario-luigi-rpg-sound-selection',
      );
      expect(album.title, 'Mario & Luigi RPG Sound Selection');
      expect(album.platforms, containsAll(['DS', 'GBA']));
      expect(album.type, 'Soundtrack');
    });
  });

  group('KhinsiderParsers.parseAlbumPage', () {
    test('parses title, cover and full track list', () {
      final album = KhinsiderParsers.parseAlbumPage(fixture('album4.html'));

      expect(album.summary.title, 'Mario & Luigi RPG Sound Selection');
      // The page embeds `/thumbs/` (117×117); the model carries the 200×200
      // variant the UI renders.
      expect(
        album.coverUrl,
        'https://nu.vgmtreasurechest.com/soundtracks/'
        'mario-luigi-rpg-sound-selection/thumbs_large/00%20Cover.jpg',
      );
      expect(album.imageUrl, album.coverUrl);

      expect(album.tracks, isNotEmpty);
      expect(album.trackCount, greaterThan(5));

      final t1 = album.tracks.first;
      expect(t1.index, 1);
      expect(t1.name, 'Preparing for the Journey');
      expect(
        t1.trackPagePath,
        startsWith('/game-soundtracks/album/mario-luigi-rpg-sound-selection/'),
      );
      expect(t1.duration, '1:35');
      expect(t1.mp3SizeMb, closeTo(5.79, 0.001));
      expect(t1.flacSizeMb, closeTo(10.81, 0.001));
      expect(t1.songId, '648573');

      // Indices are sequential.
      for (var i = 0; i < album.tracks.length; i++) {
        expect(album.tracks[i].index, i + 1);
      }
    });

    test('parses metadata and related albums (Kimagure fixture)', () {
      final album = KhinsiderParsers.parseAlbumPage(fixture('kimagure.html'));

      final md = album.metadata;
      expect(md, isNotNull);
      expect(md!.alternativeTitles, [
        'きまぐれオレンジ☆ロード',
        'きまぐれオレンジロード',
        '夏のミラージュ',
        'Kimagure☆Orange Road',
      ]);
      expect(md.platforms, ['PC-98']);
      expect(md.year, '1988');
      expect(md.developedBy, 'Microcabin');
      expect(md.publishedBy, 'Microcabin');
      expect(md.fileCount, 6);
      expect(md.totalFilesize, '27 MB');
      expect(md.dateAdded, 'Sep 16th, 2025');
      expect(md.albumType, 'Gamerip');
      expect(md.uploadedBy, 'eet4649');

      expect(album.relatedAlbums, isNotEmpty);
      final first = album.relatedAlbums.first;
      expect(first.id, 'kor-loving-heart');
      expect(first.title, 'KIMAGURE ORANGE☆ROAD Loving Heart');
      expect(first.year, '1989');
      expect(first.thumbUrl, isNotNull);
      // Sanity: all related entries point at album pages.
      for (final r in album.relatedAlbums) {
        expect(r.urlPath, startsWith('/game-soundtracks/album/'));
        expect(r.title, isNotEmpty);
      }
    });

    test('mario album also parses metadata without crashing', () {
      final album = KhinsiderParsers.parseAlbumPage(fixture('album4.html'));
      expect(album.metadata, isNotNull);
      expect(album.metadata!.platforms, contains('DS'));
    });
  });

  group('KhinsiderParsers.parseTrackPage', () {
    test('resolves direct MP3 and FLAC URLs', () {
      final src = KhinsiderParsers.parseTrackPage(
        fixture('track.html'),
        trackPagePath:
            '/game-soundtracks/album/mario-luigi-rpg-sound-selection/01.mp3',
      );

      expect(src.mp3Url, isNotNull);
      expect(src.mp3Url, startsWith('https://'));
      expect(src.mp3Url, endsWith('.mp3'));
      expect(src.mp3Url, contains('vgmtreasurechest.com'));
      expect(src.flacUrl, endsWith('.flac'));
      expect(src.bestUrl, same(src.mp3Url));
      expect(src.isEmpty, isFalse);
    });
  });

  group('KhinsiderClient (static contract)', () {
    test('uses the plural game-soundtracks path (singular is WAF-blocked)', () {
      expect(KhinsiderClient.albumBasePath, '/game-soundtracks/album');
    });
  });
  group('malformed / unexpected markup must not crash the parser', () {
    test('search row with a single <td> and no albumIcon cell', () {
      final html = """
      <table class="albumList">
        <tr><th>Icon</th><th>Title</th></tr>
        <tr><td><img src="/thumbs/x.jpg"></td></tr>
      </table>""";
      expect(KhinsiderParsers.parseSearchResults(html), isEmpty);
    });

    test('search row with no <td> at all', () {
      final html = '<table class="albumList"><tr></tr></table>';
      expect(KhinsiderParsers.parseSearchResults(html), isEmpty);
    });

    test('valid rows are still parsed alongside malformed ones', () {
      final html = """
      <table class="albumList">
        <tr><th>Icon</th><th>Title</th></tr>
        <tr><td></td></tr>
        <tr>
          <td class="albumIcon"><a href="/game-soundtracks/album/ok.html"><img src="/t.jpg"></a></td>
          <td><a href="/game-soundtracks/album/ok.html">OK Album</a></td>
          <td><a>DS</a></td><td>Soundtrack</td><td>2009</td>
        </tr>
      </table>""";
      final rows = KhinsiderParsers.parseSearchResults(html);
      expect(rows, hasLength(1));
      expect(rows.single.id, 'ok.html');
      expect(rows.single.title, 'OK Album');
    });
  });

  group('album page placeholder summary', () {
    test(
      'an album page without a summary yields a blank id, not a bogus path',
      () {
        final html =
            '<h2>Some Album</h2><table id="songlist"><tr><th>#</th></tr></table>';
        final album = KhinsiderParsers.parseAlbumPage(html);
        expect(album.summary.id, isNot(contains('/')));
        expect(album.summary.title, 'Some Album');
      },
    );
  });
}
