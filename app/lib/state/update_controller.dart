import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/update_service.dart';

/// Checks GitHub Releases for a version newer than the running app.
///
/// The result is shown in Settings (and as a dot on the settings button) — the
/// app deliberately has no popup or banner for updates any more.
class UpdateController extends Notifier<UpdateState> {
  static const repoSlug = 'trdthg/khinsiderTV';

  @override
  UpdateState build() {
    // One silent check per launch. Nothing pops up; Settings shows the result
    // and the settings button gets a dot when there is something to install.
    // Deferred: reading/writing state must happen after build() returns.
    Future.microtask(() {
      if (ref.mounted) unawaited(check());
    });
    return const UpdateState();
  }

  /// Also the "check for updates" button in Settings: it reports what it found
  /// (including "already up to date") instead of staying silent.
  Future<void> check() async {
    state = state.copyWith(checking: true, checkError: null);
    try {
      final pkg = await PackageInfo.fromPlatform();
      final service = ref.read(updateServiceProvider);
      final available = await service.latestRelease(
        currentVersion: pkg.version,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        available: available,
        checking: false,
        hasChecked: true,
        currentVersion: pkg.version,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        checking: false,
        hasChecked: true,
        checkError: '检查更新失败：$e',
      );
    }
  }

  /// Auto-download the platform asset; then the banner offers to reveal it.
  Future<void> download() async {
    final info = state.available;
    if (info == null ||
        state.downloadPhase == UpdateDownloadPhase.downloading ||
        state.downloadPhase == UpdateDownloadPhase.extracting) {
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
      final saveDir = await updatesDirectory();
      final file = await service.downloadAsset(
        asset,
        saveDir: saveDir,
        onProgress: (p) {
          if (ref.mounted) {
            state = state.copyWith(downloadProgress: p.clamp(0.0, 1.0));
          }
        },
      );
      if (!ref.mounted) return;
      if (Platform.isAndroid) {
        state = state.copyWith(
          downloadPhase: UpdateDownloadPhase.downloaded,
          downloadedFile: file.path,
        );
        await service.installApk(file.path);
        return;
      }
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
      // Dropping the zip is intentional: it is unpacked into `pending`, so
      // keeping the archive would only waste disk (and confuse the "newest
      // zip wins" rule next time).
      final pending = await extractPendingUpdate();
      if (!ref.mounted) return;
      state = state.copyWith(
        downloadPhase: UpdateDownloadPhase.ready,
        downloadedFile: pending?.path,
      );
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
    // errorMessage: null clears the field (copyWith uses a sentinel for its
    // nullable arguments), so a stale failure message cannot survive a retry.
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
    final service = ref.read(updateServiceProvider);
    if (Platform.isAndroid) {
      await service.installApk(path);
      return;
    }
    await service.revealInFileManager(path);
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
    this.hasChecked = false,
    this.currentVersion,
    this.checkError,
    this.downloadPhase = UpdateDownloadPhase.idle,
    this.downloadProgress = 0,
    this.downloadedFile,
    this.errorMessage,
  });

  /// Non-null when a newer release exists.
  final UpdateInfo? available;
  final bool checking;

  /// True once a check finished, successfully or not: a finished check with no
  /// [available] means "already up to date", which is worth saying out loud.
  final bool hasChecked;

  /// The running version, filled in by [UpdateController.check].
  final String? currentVersion;

  /// A check that failed (no network, GitHub rate limit, ...). Kept apart from
  /// [errorMessage], which belongs to the download.
  final String? checkError;

  final UpdateDownloadPhase downloadPhase;
  final double downloadProgress;
  final String? downloadedFile;
  final String? errorMessage;

  /// Whether there is an update the user should be told about (the dot on the
  /// settings button).
  bool get updateReady => available != null;

  /// Sentinel: lets [copyWith] tell an explicitly passed `null` apart from
  /// "leave this field alone", so an error/file can actually be cleared.
  static const _unset = Object();

  UpdateState copyWith({
    Object? available = _unset,
    bool? checking,
    bool? hasChecked,
    Object? currentVersion = _unset,
    Object? checkError = _unset,
    UpdateDownloadPhase? downloadPhase,
    double? downloadProgress,
    Object? downloadedFile = _unset,
    Object? errorMessage = _unset,
  }) => UpdateState(
    available: identical(available, _unset)
        ? this.available
        : available as UpdateInfo?,
    checking: checking ?? this.checking,
    hasChecked: hasChecked ?? this.hasChecked,
    currentVersion: identical(currentVersion, _unset)
        ? this.currentVersion
        : currentVersion as String?,
    checkError: identical(checkError, _unset)
        ? this.checkError
        : checkError as String?,
    downloadPhase: downloadPhase ?? this.downloadPhase,
    downloadProgress: downloadProgress ?? this.downloadProgress,
    downloadedFile: identical(downloadedFile, _unset)
        ? this.downloadedFile
        : downloadedFile as String?,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
  );
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(repoSlug: UpdateController.repoSlug),
);

/// The running app version, for the About section (independent of whether an
/// update check has ever run).
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});
