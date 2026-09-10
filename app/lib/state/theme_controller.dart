import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/preferences_store.dart';

/// Accent theme selection (index into [AppTheme.seeds]), persisted.
class ThemeController extends AsyncNotifier<int> {
  static const _key = 'theme_seed';

  @override
  Future<int> build() async {
    final store = await ref.watch(jsonKvStoreProvider.future);
    return store.read<int>(_key) ?? 0;
  }

  Future<void> select(int index) async {
    final store = await ref.read(jsonKvStoreProvider.future);
    store.write(_key, index);
    state = AsyncData(index);
  }
}

final themeControllerProvider = AsyncNotifierProvider<ThemeController, int>(
  ThemeController.new,
);
