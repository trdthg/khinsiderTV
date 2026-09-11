import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../data/khinsider_client.dart';

/// Search state: idle → loading → results / error.
class SearchState {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.loading = false,
    this.error,
  });

  final String query;
  final List<AlbumSummary> results;
  final bool loading;
  final String? error;

  bool get hasSearched => query.isNotEmpty;

  SearchState copyWith({
    String? query,
    List<AlbumSummary>? results,
    bool? loading,
    String? error,
  }) => SearchState(
    query: query ?? this.query,
    results: results ?? this.results,
    loading: loading ?? this.loading,
    error: error,
  );
}

class SearchController extends Notifier<SearchState> {
  /// Increments on every [search] call so a slow earlier request can never
  /// overwrite the results of a newer one (out-of-order responses).
  int _generation = 0;

  @override
  SearchState build() => const SearchState();

  Future<void> search(String query, {bool forceRefresh = false}) async {
    final q = query.trim();
    if (q.isEmpty) return;

    final generation = ++_generation;
    state = state.copyWith(query: q, loading: true);
    try {
      final results = await ref
          .read(khinsiderClientProvider)
          .searchAlbums(q, forceRefresh: forceRefresh);
      if (!ref.mounted || generation != _generation) return; // superseded
      state = SearchState(query: q, results: results);
    } catch (e) {
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(loading: false, error: 'Search failed: $e');
    }
  }

  /// Re-runs the last query bypassing the page cache.
  Future<void> refresh() => search(state.query, forceRefresh: true);
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);
