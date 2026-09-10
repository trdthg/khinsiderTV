import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../data/khinsider_client.dart';

/// Phase-1 album detail: loaded on demand when the user opens an album.
/// One HTML request per album, served from the disk cache when present.
/// The second tuple element is a refresh nonce: increment it to force a
/// network refresh (bypasses the page cache).
final albumDetailProvider = FutureProvider.family<Album, (String, int)>((
  ref,
  arg,
) async {
  final (albumId, nonce) = arg;
  return ref
      .read(khinsiderClientProvider)
      .getAlbum(albumId, forceRefresh: nonce > 0);
});
