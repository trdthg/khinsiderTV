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
  @override
  SearchState build() => const SearchState();

  Future<void> search(String query, {bool forceRefresh = false}) async {
    final q = query.trim();
    if (q.isEmpty) return;

    state = state.copyWith(query: q, loading: true);
    try {
      final results = await ref
          .read(khinsiderClientProvider)
          .searchAlbums(q, forceRefresh: forceRefresh);
      state = SearchState(query: q, results: results);
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Search failed: $e');
    }
  }

  /// Re-runs the last query bypassing the page cache.
  Future<void> refresh() => search(state.query, forceRefresh: true);
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);
