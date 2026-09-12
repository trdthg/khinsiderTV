import 'package:khinsider_api/khinsider_api.dart';
import 'package:test/test.dart';

void main() {
  group('KhinsiderImage.large', () {
    test('upgrades every size folder the site uses', () {
      const base =
          'https://nu.vgmtreasurechest.com/soundtracks/'
          'mario-luigi-rpg-sound-selection';

      // What a search result actually carries.
      expect(
        KhinsiderImage.large('$base/thumbs_small/00%20Cover.jpg'),
        '$base/thumbs_large/00%20Cover.jpg',
      );
      // What an album page actually carries.
      expect(
        KhinsiderImage.large('$base/thumbs/00%20Cover.jpg'),
        '$base/thumbs_large/00%20Cover.jpg',
      );
    });

    test('is idempotent', () {
      const url =
          'https://nu.vgmtreasurechest.com/soundtracks/'
          'mario-luigi-rpg-sound-selection/thumbs_large/00%20Cover.jpg';
      expect(KhinsiderImage.large(url), url);
      expect(KhinsiderImage.large(KhinsiderImage.large(url)), url);
    });

    test('adds the folder to an original URL', () {
      const base = 'https://vgmtreasurechest.com/soundtracks/sonic-boom-arcade';
      expect(
        KhinsiderImage.large('$base/cover.jpg'),
        '$base/thumbs_large/cover.jpg',
      );
    });

    test('keeps host, album directory and file name untouched', () {
      // Mirrors (jetta./lambda./nu.) and percent/unicode-heavy names must
      // survive the rewrite verbatim — only the folder segment changes.
      const url =
          'https://jetta.vgmtreasurechest.com/soundtracks/'
          'treasure-garden-ponchi%E2%99%AA-feat-hatsune-miku-2025/'
          'thumbs_small/00%20Front.png';
      expect(
        KhinsiderImage.large(url),
        'https://jetta.vgmtreasurechest.com/soundtracks/'
        'treasure-garden-ponchi%E2%99%AA-feat-hatsune-miku-2025/'
        'thumbs_large/00%20Front.png',
      );
    });

    test('leaves non-album images alone', () {
      // Page chrome (icons, avatars) is not an album image and has no size
      // variants; rewriting it would 404.
      expect(
        KhinsiderImage.large(
          'https://downloads.khinsider.com/images/nsfw_small.png',
        ),
        'https://downloads.khinsider.com/images/nsfw_small.png',
      );
      expect(
        KhinsiderImage.large('https://example.com/cover.jpg'),
        'https://example.com/cover.jpg',
      );
    });

    test('handles null and empty input', () {
      expect(KhinsiderImage.large(null), isNull);
      expect(KhinsiderImage.large(''), isNull);
    });
  });
}
