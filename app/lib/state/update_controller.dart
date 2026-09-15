import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/update_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import 'locale_controller.dart';

/// Checks GitHub Releases for a version newer than the running app.
///
/// The result is shown in Settings (and as a dot on the settings button) — the
/// app deliberately has no popup or banner for updates any more.
class UpdateController extends Notifier<UpdateState> {
  UpdateController({AppLocalizations Function()? strings})
    : _stringsOverride = strings;

  static const repoSlug = 'trdthg/khinsiderTV';

  /// An explicitly supplied lookup, if any. Without one (the app's case) the
  /// live locale is read through [ref], so a language change needs no restart.
  final AppLocalizations Function()? _stringsOverride;

  AppLocalizations Function() get _strings =>
      _stringsOverride ?? () => stringsFor(ref.read(localeControllerProvider));

  @override
  UpdateState build() {
    final service = ref.watch(updateServiceProvider);
    // Learn the ABI up front so the settings row can name the exact package
    // ("armv7" vs "universal") before anything is downloaded.
    unawaited(service.androidAbi());
    final results = service.installResults.listen(_onInstallResult);
    ref.onDispose(results.cancel);
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
        checkError: _strings().updateCheckFailed('$e'),
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
    // Android: ask which ABI this installation runs before choosing, so a TV
    // downloads the 17MB armv7 build instead of the 37MB universal one.
    if (Platform.isAndroid) await service.androidAbi();
    final asset = service.assetForPlatform(info.assets);
    if (asset == null) return; // mobile: the release page link stays

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
        // The file is on disk either way, so an install the OS refuses must
        // not look like a failed download (the user would re-download 40MB).
        state = state.copyWith(
          downloadPhase: UpdateDownloadPhase.downloaded,
          downloadedFile: file.path,
        );
        await installDownloaded();
        return;
      }
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        downloadPhase: UpdateDownloadPhase.failed,
        errorMessage: _strings().updateDownloadFailed('$e'),
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
        errorMessage: _strings().updateExtractFailed('$e'),
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

  /// Hands the downloaded file to the platform: on Android the package
  /// installer, elsewhere the file manager.
  Future<void> revealDownload() async {
    if (Platform.isAndroid) {
      await installDownloaded();
      return;
    }
    final path = state.downloadedFile;
    if (path == null) return;
    await ref.read(updateServiceProvider).revealInFileManager(path);
  }

  /// Android only: opens the system installer for the downloaded APK, after
  /// checking the one permission Android 8+ adds on top of the manifest entry
  /// (`REQUEST_INSTALL_PACKAGES`). Without that grant the installer opens and
  /// does nothing at all, which is exactly the "it just fails" report this
  /// exists to explain.
  Future<void> installDownloaded({bool forceIntent = false}) async {
    final path = state.downloadedFile;
    if (path == null) return;
    final service = ref.read(updateServiceProvider);
    if (Platform.isAndroid && !await service.canInstallPackages()) {
      if (!ref.mounted) return;
      state = state.copyWith(
        installError: _strings().updateNeedInstallPermission,
        installNeedsPermission: true,
        installFailed: false,
      );
      return;
    }
    state = state.copyWith(installError: null, installNeedsPermission: false);
    try {
      await service.installApk(path, forceIntent: forceIntent);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        installError: _strings().updateOpenInstallerFailed('$e'),
        installFailed: true,
      );
    }
  }

  /// The installer reports back after the session is committed; that verdict is
  /// the only way to know *why* an install was refused (bad signature, no
  /// space, blocked by the OS, ...).
  void _onInstallResult(InstallResult result) {
    if (!ref.mounted) return;
    if (result.succeeded) {
      state = state.copyWith(
        installError: null,
        installNeedsPermission: false,
        installFailed: false,
      );
      return;
    }
    if (result.pendingUserAction) {
      state = state.copyWith(
        installError: _strings().updateHandedToInstaller,
        installNeedsPermission: false,
        installFailed: false,
      );
      return;
    }
    state = state.copyWith(
      installError: result.explanation,
      installNeedsPermission: result.blocked,
      installFailed: true,
    );
  }

  /// Opens the Android setting that [installDownloaded] is waiting for.
  Future<void> openInstallSettings() async {
    await ref.read(updateServiceProvider).openInstallSettings();
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
    this.installError,
    this.installNeedsPermission = false,
    this.installFailed = false,
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

  /// The APK is on disk but the OS would not open its installer (no "install
  /// unknown apps" grant, no installer activity, ...). Separate from
  /// [errorMessage] so the UI can offer "retry the install" instead of
  /// "download again".
  final String? installError;

  /// True when [installError] is the missing Android permission, which has a
  /// one-tap fix ([UpdateController.openInstallSettings]).
  final bool installNeedsPermission;

  /// True when [installError] is a refusal: only then does the alternative
  /// installer get offered.
  final bool installFailed;

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
    Object? installError = _unset,
    bool? installNeedsPermission,
    bool? installFailed,
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
    installError: identical(installError, _unset)
        ? this.installError
        : installError as String?,
    installNeedsPermission:
        installNeedsPermission ?? this.installNeedsPermission,
    installFailed: installFailed ?? this.installFailed,
  );
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(
    repoSlug: UpdateController.repoSlug,
    // The getter, not a snapshot: a language change must take effect at once.
    strings: () => stringsFor(ref.read(localeControllerProvider)),
  ),
);

/// The running app version, for the About section (independent of whether an
/// update check has ever run).
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});
