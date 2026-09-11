import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

  /// Auto-download the platform asset; then the banner offers to reveal it.
  Future<void> download() async {
    final info = state.available;
    if (info == null ||
        state.downloadPhase == UpdateDownloadPhase.downloading) {
      return;
    }
    final service = ref.read(updateServiceProvider);
    final asset = service.assetForPlatform(info.assets);
    if (asset == null) return; // mobile: banner keeps the View link

    state = state.copyWith(
      downloadPhase: UpdateDownloadPhase.downloading,
      downloadProgress: 0,
    );
    try {
      final base = await getApplicationSupportDirectory();
      final saveDir = Directory('${base.path}${Platform.pathSeparator}updates');
      await saveDir.create(recursive: true);
      await service.downloadAsset(
        asset,
        saveDir: saveDir,
        onProgress: (p) {
          if (ref.mounted) {
            state = state.copyWith(downloadProgress: p.clamp(0.0, 1.0));
          }
        },
      );
      if (!ref.mounted) return;
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        downloadPhase: UpdateDownloadPhase.failed,
        errorMessage: 'Download failed: $e',
      );
      return;
    }
    // Auto-extract right after the download so the update is ready to
    // apply (at startup or via Restart & update).
    state = state.copyWith(downloadPhase: UpdateDownloadPhase.extracting);
    try {
      await extractPendingUpdate();
      if (!ref.mounted) return;
      state = state.copyWith(downloadPhase: UpdateDownloadPhase.ready);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        downloadPhase: UpdateDownloadPhase.failed,
        errorMessage: 'Extract failed: $e',
      );
    }
  }

  /// Reset to idle and re-download.
  Future<void> retryDownload() async {
    state = state.copyWith(
      downloadPhase: UpdateDownloadPhase.idle,
      errorMessage: null,
      downloadProgress: 0,
    );
    await download();
  }

  /// Reveal the downloaded file in the platform file manager.
  Future<void> revealDownload() async {
    final path = state.downloadedFile;
    if (path == null) return;
    await ref.read(updateServiceProvider).revealInFileManager(path);
  }

  /// Windows: restarts via a detached batch script (wait -> swap -> relaunch).
  /// macOS: replaces the running bundle then relaunches the new instance.
  /// Linux: installs the flatpak bundle; the user relaunches from the Deck UI.
  Future<void> restartAndUpdate() async {
    await restartAndApply();
  }
}

enum UpdateDownloadPhase {
  idle,
  downloading,
  downloaded,
  extracting,
  ready,
  failed,
}

class UpdateState {
  const UpdateState({
    this.available,
    this.checking = false,
    this.dismissed = false,
    this.downloadPhase = UpdateDownloadPhase.idle,
    this.downloadProgress = 0,
    this.downloadedFile,
    this.errorMessage,
  });

  /// Non-null when a newer release exists.
  final UpdateInfo? available;
  final bool checking;
  final bool dismissed;

  final UpdateDownloadPhase downloadPhase;
  final double downloadProgress;
  final String? downloadedFile;
  final String? errorMessage;

  bool get showBanner => available != null && !dismissed;

  UpdateState copyWith({
    UpdateInfo? available,
    bool? checking,
    bool? dismissed,
    UpdateDownloadPhase? downloadPhase,
    double? downloadProgress,
    String? downloadedFile,
    String? errorMessage,
  }) => UpdateState(
    available: available ?? this.available,
    checking: checking ?? this.checking,
    dismissed: dismissed ?? this.dismissed,
    downloadPhase: downloadPhase ?? this.downloadPhase,
    downloadProgress: downloadProgress ?? this.downloadProgress,
    downloadedFile: downloadedFile ?? this.downloadedFile,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(repoSlug: UpdateController.repoSlug),
);
