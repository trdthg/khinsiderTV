import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/update_service.dart';

/// Checks GitHub Releases for a version newer than the running app and
/// exposes the result for the update banner.
class UpdateController extends Notifier<UpdateState> {
  static const repoSlug = 'trdthg/khinsiderTV';

  @override
  UpdateState build() {
    // One silent check per launch; failures are invisible to the user.
    // Deferred: reading/writing state must happen after build() returns.
    Future.microtask(() {
      if (ref.mounted) unawaited(check());
    });
    return const UpdateState();
  }

  Future<void> check() async {
    state = state.copyWith(checking: true);
    try {
      final info = PackageInfo.fromPlatform();
      final service = ref.read(updateServiceProvider);
      final pkg = await info;
      final available = await service.latestRelease(
        currentVersion: pkg.version,
      );
      if (!ref.mounted) return;
      state = state.copyWith(available: available, checking: false);
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(checking: false);
    }
  }

  void dismiss() => state = state.copyWith(dismissed: true);
}

class UpdateState {
  const UpdateState({
    this.available,
    this.checking = false,
    this.dismissed = false,
  });

  /// Non-null when a newer release exists.
  final UpdateInfo? available;
  final bool checking;
  final bool dismissed;

  bool get showBanner => available != null && !dismissed;

  UpdateState copyWith({
    UpdateInfo? available,
    bool? checking,
    bool? dismissed,
  }) => UpdateState(
    available: available ?? this.available,
    checking: checking ?? this.checking,
    dismissed: dismissed ?? this.dismissed,
  );
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(repoSlug: UpdateController.repoSlug),
);
