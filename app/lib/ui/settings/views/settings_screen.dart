import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/l10n.dart';
import '../../../state/locale_controller.dart';
import '../../../state/update_controller.dart';
import '../../../data/update_service.dart';
import 'cache_screen.dart';
import 'lan_screen.dart';
import 'settings_widgets.dart';

/// The app's settings: updates, cache and about.
///
/// Updates live here rather than in a banner: the app used to pin a bar across
/// the top of every screen when a new version existed, which is exactly the
/// popup the user asked to get rid of. The launch check still runs silently —
/// its result shows up as a dot on the settings button and as a row here.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const repoUrl = 'https://github.com/trdthg/khinsiderTV';

  /// English first: it is the default, and the two are only ever a tap apart.
  List<Widget> _languageRows(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final current = ref.watch(localeControllerProvider) ?? defaultLanguage;
    return [
      for (final (locale, label) in [
        (const Locale('en'), l.languageEnglish),
        (const Locale('zh'), l.languageChinese),
      ])
        SettingsRow(
          icon: Icons.translate,
          title: label,
          trailing: current.languageCode == locale.languageCode
              ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
              : null,
          onSelect: () =>
              ref.read(localeControllerProvider.notifier).set(locale),
        ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateControllerProvider);
    final notifier = ref.read(updateControllerProvider.notifier);
    final service = ref.watch(updateServiceProvider);
    final version =
        ref.watch(appVersionProvider).value ?? update.currentVersion ?? '…';

    final info = update.available;
    final asset = info == null ? null : service.assetForPlatform(info.assets);
    final l = l10n(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SettingsHeader(title: l.settingsTitle),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  SettingsSection(
                    title: AppLocalizations.of(context).settingsLanguage,
                    children: _languageRows(context, ref),
                  ),
                  SettingsSection(
                    title: l.settingsUpdate,
                    children: [
                      SettingsRow(
                        icon: Icons.system_update_alt,
                        title: l.settingsCheckUpdate,
                        subtitle: _checkSubtitle(l, update, info),
                        trailing: update.checking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onSelect: update.checking ? null : notifier.check,
                      ),
                      if (info != null) ...[
                        SettingsRow(
                          icon: Icons.new_releases_outlined,
                          title: l.settingsNewVersion(info.version),
                          subtitle: info.notes.trim().isEmpty
                              ? null
                              : info.notes.trim().split('\n').first,
                        ),
                        ..._downloadRows(context, update, notifier, asset),
                        SettingsRow(
                          icon: Icons.open_in_new,
                          title: l.settingsOpenReleasePage,
                          subtitle: info.url,
                          onSelect: () => launchUrl(
                            Uri.parse(info.url),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SettingsSection(
                    title: l.settingsStorage,
                    children: [
                      SettingsRow(
                        icon: Icons.sd_storage_outlined,
                        title: l.settingsCache,
                        subtitle: l.settingsCacheSubtitle,
                        onSelect: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CacheScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: l.settingsLan,
                    children: [
                      SettingsRow(
                        icon: Icons.devices_other,
                        title: l.settingsLanSubtitle,
                        subtitle: l.settingsLanSubtitleLong,
                        onSelect: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const LanScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: l.settingsAbout,
                    children: [
                      SettingsRow(
                        icon: Icons.info_outline,
                        title: 'KHInsider',
                        subtitle: l.settingsVersion(version),
                      ),
                      SettingsRow(
                        icon: Icons.code,
                        title: l.settingsGitHubRepo,
                        subtitle: 'github.com/trdthg/khinsiderTV',
                        onSelect: () => launchUrl(
                          Uri.parse(repoUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _checkSubtitle(
    AppLocalizations l,
    UpdateState update,
    UpdateInfo? info,
  ) {
    if (update.checking) return l.settingsChecking;
    if (update.checkError != null) return update.checkError!;
    if (info != null) return l.settingsUpdateFound(info.version);
    if (update.hasChecked) return l.settingsUpToDate;
    return l.settingsFromReleases;
  }

  /// Size of the downloaded installer, for the row that says it is ready.
  /// Best effort: a missing file must not break the whole screen.
  String? _fileSize(String? path) {
    if (path == null) return null;
    try {
      final file = File(path);
      return file.existsSync() ? formatBytes(file.lengthSync()) : null;
    } catch (_) {
      return null;
    }
  }

  /// The one row that moves an update along, whichever phase it is in.
  List<Widget> _downloadRows(
    BuildContext context,
    UpdateState update,
    UpdateController notifier,
    UpdateAsset? asset,
  ) {
    final phase = update.downloadPhase;
    final l = l10n(context);
    switch (phase) {
      case UpdateDownloadPhase.downloading:
        return [
          SettingsRow(
            icon: Icons.downloading,
            title: l.settingsDownloading(
              (update.downloadProgress * 100).toStringAsFixed(0),
            ),
            subtitle: [
              if (asset != null) asset.name,
              l.settingsWillOpenInstaller,
            ].join(' · '),
            trailing: SizedBox(
              width: 72,
              child: LinearProgressIndicator(
                value: update.downloadProgress > 0
                    ? update.downloadProgress
                    : null,
              ),
            ),
          ),
        ];
      case UpdateDownloadPhase.extracting:
        return [
          SettingsRow(
            icon: Icons.inventory_2_outlined,
            title: l.settingsExtracting,
            subtitle: l.settingsReadyToRestart,
            trailing: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ];
      case UpdateDownloadPhase.ready:
        return [
          SettingsRow(
            icon: Icons.restart_alt,
            title: l.settingsRestartAndUpdate,
            subtitle: l.settingsReadySubtitle,
            onSelect: notifier.restartAndUpdate,
          ),
        ];
      case UpdateDownloadPhase.downloaded:
        final size = _fileSize(update.downloadedFile);
        return [
          SettingsRow(
            icon: Icons.install_mobile_outlined,
            title: update.installError == null
                ? l.settingsInstall
                : l.settingsRetryInstall,
            subtitle:
                update.installError ??
                (size == null
                    ? l.settingsDownloaded
                    : l.settingsDownloadedWithSize(size)),
            danger: update.installError != null,
            onSelect: notifier.revealDownload,
          ),
          // The session API is the better mechanism, but a device can refuse
          // it in ways it never explains (a TV that aborts the confirmation).
          // This is the older content:// hand-off: the same APK, a different
          // door, offered only after something actually failed.
          if (update.installFailed) ...[
            SettingsRow(
              icon: Icons.open_in_new,
              title: l.settingsUseSystemInstaller,
              subtitle: l.settingsUseSystemInstallerSubtitle,
              onSelect: () => notifier.installDownloaded(forceIntent: true),
            ),
          ],
          // Android 8+ wants "install unknown apps" granted to this app on top
          // of REQUEST_INSTALL_PACKAGES; without it the installer opens and
          // does nothing, so offer the one screen that fixes it.
          if (update.installNeedsPermission)
            SettingsRow(
              icon: Icons.settings_applications_outlined,
              title: l.settingsAllowUnknownSources,
              subtitle: l.settingsAllowUnknownSourcesSubtitle,
              onSelect: notifier.openInstallSettings,
            ),
        ];
      case UpdateDownloadPhase.failed:
        return [
          SettingsRow(
            icon: Icons.error_outline,
            title: l.settingsDownloadFailed,
            subtitle: update.errorMessage ?? l.settingsPleaseRetry,
            danger: true,
          ),
          SettingsRow(
            icon: Icons.refresh,
            title: l.settingsRetry,
            onSelect: notifier.retryDownload,
          ),
        ];
      case UpdateDownloadPhase.idle:
        if (asset == null) {
          return [
            SettingsRow(
              icon: Icons.open_in_new,
              title: l.settingsUseReleasePage,
              subtitle: l.settingsNoAutoUpdate,
            ),
          ];
        }
        return [
          SettingsRow(
            icon: Icons.download_outlined,
            title: l.settingsDownloadAndInstall,
            subtitle: [
              asset.name,
              if (Platform.isAndroid) l.settingsUniversalPackage,
              l.settingsAutoInstallNote,
            ].join(' · '),
            onSelect: update.checking ? null : notifier.download,
          ),
        ];
    }
  }
}
