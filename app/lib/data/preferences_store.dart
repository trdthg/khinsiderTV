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
    final raw = store.readList<Map<String, dynamic>>(_kFavorites);
    return raw.map(albumSummaryFromJson).toList();
  }

  bool isFavorite(String albumId) =>
      state.value?.any((a) => a.id == albumId) ?? false;

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
    final raw = store.readList<Map<String, dynamic>>(_kRecentAlbums);
    return raw.map(albumSummaryFromJson).toList();
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

AlbumSummary albumSummaryFromJson(Map<String, dynamic> j) => AlbumSummary(
  id: j['id'] as String,
  title: j['title'] as String,
  urlPath: j['urlPath'] as String,
  thumbUrl: j['thumbUrl'] as String?,
  platforms: (j['platforms'] as List?)?.cast<String>() ?? const [],
  type: j['type'] as String?,
  year: j['year'] as String?,
);
