import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';
import 'package:path_provider/path_provider.dart';

import 'storage/json_kv_store.dart';

/// Keys
const _kFavorites = 'favorites';
const _kSearchHistory = 'search_history';
const _kRecentAlbums = 'recent_albums';

const _maxSearchHistory = 20;
const _maxRecentAlbums = 24;

/// The app-wide [JsonKvStore], opened lazily from Application Support.
final jsonKvStoreProvider = FutureProvider<JsonKvStore>((ref) async {
  final dir = await getApplicationSupportDirectory();
  final store = await JsonKvStore.open(dir);
  ref.onDispose(store.close);
  return store;
});

/// Favorite albums (persisted). Order = insertion order.
class FavoritesController extends AsyncNotifier<List<AlbumSummary>> {
  @override
  Future<List<AlbumSummary>> build() async {
    final store = await ref.watch(jsonKvStoreProvider.future);
    final raw = store.readList<Object?>(_kFavorites);
    return raw.map(tryAlbumSummaryFromJson).whereType<AlbumSummary>().toList();
  }

  bool isFavorite(String albumId) =>
      state.value?.any((a) => a.id == albumId) ?? false;

  /// Union-merge [incoming] into the favorites, newest first, and report how
  /// many were new. Used by the LAN sync, which must never drop local entries:
  /// the merge only ever adds.
  ///
  /// Reads the persisted list when the provider has not loaded yet — the sync
  /// can arrive before the first screen ever watched favorites, and writing
  /// `state.value` (null) would replace the stored list with just the incoming
  /// ones.
  /// Overwrites the whole list with [incoming]. Used by the forced LAN sync:
  /// unlike [mergeAll] this really does delete what the other side does not
  /// have, so it is only ever called from an explicitly confirmed action.
  Future<int> replaceAll(Iterable<AlbumSummary> incoming) async {
    final store = await ref.read(jsonKvStoreProvider.future);
    final seen = <String>{};
    final list = incoming.where((a) => seen.add(a.id)).toList();
    store.write(_kFavorites, list.map(albumSummaryToJson).toList());
    state = AsyncData(list);
    return list.length;
  }

  Future<int> mergeAll(Iterable<AlbumSummary> incoming) async {
    final store = await ref.read(jsonKvStoreProvider.future);
    final current =
        state.value ??
        store
            .readList<Object?>(_kFavorites)
            .map(tryAlbumSummaryFromJson)
            .whereType<AlbumSummary>()
            .toList();
    final known = current.map((a) => a.id).toSet();
    final fresh = incoming.where((a) => known.add(a.id)).toList();
    if (fresh.isEmpty) {
      state = AsyncData(current);
      return 0;
    }
    final merged = [...fresh, ...current];
    store.write(_kFavorites, merged.map(albumSummaryToJson).toList());
    state = AsyncData(merged);
    return fresh.length;
  }

  Future<void> toggle(AlbumSummary album) async {
    final store = await ref.read(jsonKvStoreProvider.future);
    final current = [...?state.value];
    final existing = current.indexWhere((a) => a.id == album.id);
    if (existing >= 0) {
      current.removeAt(existing);
    } else {
      current.insert(0, album);
    }
    store.write(_kFavorites, current.map(albumSummaryToJson).toList());
    state = AsyncData(current);
  }
}

final favoritesProvider =
    AsyncNotifierProvider<FavoritesController, List<AlbumSummary>>(
      FavoritesController.new,
    );

/// Recent search queries (persisted, newest first).
class SearchHistoryController extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final store = await ref.watch(jsonKvStoreProvider.future);
    return store.readList<String>(_kSearchHistory);
  }

  Future<void> record(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final store = await ref.read(jsonKvStoreProvider.future);
    final current = [q, ...?state.value?.where((s) => s != q)];
    final trimmed = current.take(_maxSearchHistory).toList();
    store.write(_kSearchHistory, trimmed);
    state = AsyncData(trimmed);
  }

  Future<void> clear() async {
    final store = await ref.read(jsonKvStoreProvider.future);
    store.remove(_kSearchHistory);
    state = const AsyncData([]);
  }
}

final searchHistoryProvider =
    AsyncNotifierProvider<SearchHistoryController, List<String>>(
      SearchHistoryController.new,
    );

/// Recently opened albums (persisted, newest first) — quick resume row.
class RecentAlbumsController extends AsyncNotifier<List<AlbumSummary>> {
  @override
  Future<List<AlbumSummary>> build() async {
    final store = await ref.watch(jsonKvStoreProvider.future);
    final raw = store.readList<Object?>(_kRecentAlbums);
    return raw.map(tryAlbumSummaryFromJson).whereType<AlbumSummary>().toList();
  }

  Future<void> record(AlbumSummary album) async {
    final store = await ref.read(jsonKvStoreProvider.future);
    final current = [album, ...?state.value?.where((a) => a.id != album.id)];
    final trimmed = current.take(_maxRecentAlbums).toList();
    store.write(_kRecentAlbums, trimmed.map(albumSummaryToJson).toList());
    state = AsyncData(trimmed);
  }
}

final recentAlbumsProvider =
    AsyncNotifierProvider<RecentAlbumsController, List<AlbumSummary>>(
      RecentAlbumsController.new,
    );

// -- (de)serialization -------------------------------------------------------

Map<String, dynamic> albumSummaryToJson(AlbumSummary a) => {
  'id': a.id,
  'title': a.title,
  'urlPath': a.urlPath,
  'thumbUrl': a.thumbUrl,
  'platforms': a.platforms,
  'type': a.type,
  'year': a.year,
};

/// Tolerant decode: persisted entries come straight from a JSON file the
/// user (or a schema change) can hand-edit, so a malformed record must be
/// skipped rather than poison the whole favorites/recents provider.
AlbumSummary? tryAlbumSummaryFromJson(Object? value) {
  if (value is! Map) return null;
  final j = value;
  // `id`/`title`/`urlPath` are the load-bearing fields; without them the
  // album cannot be opened again.
  final id = j['id'];
  final title = j['title'];
  final urlPath = j['urlPath'];
  if (id is! String || title is! String || urlPath is! String) return null;
  return AlbumSummary(
    id: id,
    title: title,
    urlPath: urlPath,
    thumbUrl: j['thumbUrl'] is String ? j['thumbUrl'] as String : null,
    platforms:
        (j['platforms'] as List?)?.whereType<String>().toList() ??
        const <String>[],
    type: j['type'] is String ? j['type'] as String : null,
    year: j['year'] is String ? j['year'] as String : null,
  );
}

/// Strict decode kept for callers that already validated the payload.
AlbumSummary albumSummaryFromJson(Map<String, dynamic> j) =>
    tryAlbumSummaryFromJson(j)!;
