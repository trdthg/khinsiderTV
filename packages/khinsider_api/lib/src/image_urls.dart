/// KHInsider serves every cover in several pre-rendered sizes, all at the same
/// path with a different folder in between:
///
/// ```
/// https://<host>/soundtracks/<album>/<file>                original (up to ~10 MB)
/// https://<host>/soundtracks/<album>/thumbs_large/<file>   200×200
/// https://<host>/soundtracks/<album>/thumbs/<file>         117×117
/// https://<host>/soundtracks/<album>/thumbs_small/<file>    60×60
/// ```
///
/// The pages hand out the *smallest* variant they can get away with: search
/// results embed `thumbs_small` (60×60) and the album page embeds `/thumbs/`
/// (117×117), both of which are visibly soft once the app draws them at
/// 140–200 px (cards) or 250–320 px (cover / now playing).
///
/// Only the folder segment changes between variants — host, album directory,
/// file name and its percent-encoding are identical — so the size we want is
/// rewritten into the path instead of costing another request.
abstract final class KhinsiderImage {
  /// The 200×200 `thumbs_large` variant of [url].
  ///
  /// This is the size the app renders everywhere: still a ~15–80 KB download,
  /// but 3.3× the resolution the site hands out. Idempotent — passing an
  /// already-`thumbs_large` URL back in returns it unchanged.
  ///
  /// Returns `null` for `null`/empty input, and any URL that is not an album
  /// image (the page also carries icons and avatars under other paths) is
  /// returned untouched.
  static String? large(String? url) => _rebase(url);

  /// Any `thumbs*` folder the site may use, or the bare album directory.
  static final RegExp _sized = RegExp(
    r'^(.*?/soundtracks/[^/]+)/thumbs[a-z_]*/',
  );
  static final RegExp _plain = RegExp(r'^(.*?/soundtracks/[^/]+)/([^/]+)$');

  static String? _rebase(String? url) {
    if (url == null || url.isEmpty) return null;

    final sized = _sized.firstMatch(url);
    if (sized != null) {
      return '${sized.group(1)}/thumbs_large/${url.substring(sized.end)}';
    }

    // Already the original (no size folder): add one.
    final plain = _plain.firstMatch(url);
    if (plain != null) {
      return '${plain.group(1)}/thumbs_large/${plain.group(2)}';
    }

    return url;
  }
}
