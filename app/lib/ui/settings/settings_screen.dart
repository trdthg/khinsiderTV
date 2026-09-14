import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/update_controller.dart';
import '../../data/update_service.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateControllerProvider);
    final notifier = ref.read(updateControllerProvider.notifier);
    final service = ref.watch(updateServiceProvider);
    final version =
        ref.watch(appVersionProvider).value ?? update.currentVersion ?? '…';

    final info = update.available;
    final asset = info == null ? null : service.assetForPlatform(info.assets);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SettingsHeader(title: '设置'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  SettingsSection(
                    title: '更新',
                    children: [
                      SettingsRow(
                        icon: Icons.system_update_alt,
                        title: '检查更新',
                        subtitle: _checkSubtitle(update, info),
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
                          title: '新版本 v${info.version}',
                          subtitle: info.notes.trim().isEmpty
                              ? null
                              : info.notes.trim().split('\n').first,
                        ),
                        ..._downloadRows(
                          context,
                          update,
                          notifier,
                          asset != null,
                        ),
                        SettingsRow(
                          icon: Icons.open_in_new,
                          title: '打开发布页',
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
                    title: '存储',
                    children: [
                      SettingsRow(
                        icon: Icons.sd_storage_outlined,
                        title: '缓存',
                        subtitle: '查看占用、清除全部缓存、删除单张专辑',
                        onSelect: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CacheScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: '局域网',
                    children: [
                      SettingsRow(
                        icon: Icons.devices_other,
                        title: '跨设备同步',
                        subtitle: '同一 WiFi 下的设备之间同步收藏、一起播放',
                        onSelect: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const LanScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SettingsSection(
                    title: '关于',
                    children: [
                      SettingsRow(
                        icon: Icons.info_outline,
                        title: 'KHInsider',
                        subtitle: '版本 v$version',
                      ),
                      SettingsRow(
                        icon: Icons.code,
                        title: 'GitHub 仓库',
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

  String _checkSubtitle(UpdateState update, UpdateInfo? info) {
    if (update.checking) return '正在检查…';
    if (update.checkError != null) return update.checkError!;
    if (info != null) return '发现新版本 v${info.version}';
    if (update.hasChecked) return '已是最新版本';
    return '从 GitHub Releases 获取最新版本';
  }

  /// The one row that moves an update along, whichever phase it is in.
  List<Widget> _downloadRows(
    BuildContext context,
    UpdateState update,
    UpdateController notifier,
    bool hasAsset,
  ) {
    final phase = update.downloadPhase;
    switch (phase) {
      case UpdateDownloadPhase.downloading:
        return [
          SettingsRow(
            icon: Icons.downloading,
            title: '下载中 ${(update.downloadProgress * 100).toStringAsFixed(0)}%',
            subtitle: '下载完成后会自动开始安装',
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
          const SettingsRow(
            icon: Icons.inventory_2_outlined,
            title: '正在解压…',
            subtitle: '完成后即可重启更新',
            trailing: SizedBox(
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
            title: '重启并更新',
            subtitle: '新版本已下载完成，重启后生效',
            onSelect: notifier.restartAndUpdate,
          ),
        ];
      case UpdateDownloadPhase.downloaded:
        return [
          SettingsRow(
            icon: Icons.install_mobile_outlined,
            title: '安装',
            subtitle: '安装包已下载，再次打开系统安装界面',
            onSelect: notifier.revealDownload,
          ),
        ];
      case UpdateDownloadPhase.failed:
        return [
          SettingsRow(
            icon: Icons.error_outline,
            title: '下载失败',
            subtitle: update.errorMessage ?? '请重试',
            danger: true,
          ),
          SettingsRow(
            icon: Icons.refresh,
            title: '重试',
            onSelect: notifier.retryDownload,
          ),
        ];
      case UpdateDownloadPhase.idle:
        if (!hasAsset) {
          return const [
            SettingsRow(
              icon: Icons.open_in_new,
              title: '此平台请从发布页下载',
              subtitle: '没有适用于当前平台的自动更新包',
            ),
          ];
        }
        return [
          SettingsRow(
            icon: Icons.download_outlined,
            title: '下载并安装',
            subtitle: '下载完成后直接安装，不再询问',
            onSelect: update.checking ? null : notifier.download,
          ),
        ];
    }
  }
}
