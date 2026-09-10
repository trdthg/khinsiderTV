import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';
import 'package:path_provider/path_provider.dart';

/// Shared [KhinsiderClient] (dio + html, two-phase lazy loading) with a
/// disk-backed page cache: search/album HTML is served cache-first and only
/// re-fetched on forced refresh.
final khinsiderClientProvider = Provider<KhinsiderClient>((ref) {
  final client = KhinsiderClient(
    cache: HttpCache(() async {
      final base = await getApplicationSupportDirectory();
      return Directory('${base.path}${Platform.pathSeparator}api_cache');
    }),
  );
  ref.onDispose(client.close);
  return client;
});
