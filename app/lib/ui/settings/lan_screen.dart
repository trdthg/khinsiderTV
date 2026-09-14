import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/device.dart';
import '../../data/lan/lan_device.dart';
import '../../data/preferences_store.dart';
import '../../state/lan_controller.dart';
import '../search/tv_system_text_field.dart';
import 'settings_widgets.dart';

/// Cross-device sync over the local network: which devices are around, and
/// sending/pulling favorites. No account, no server — see `LanService`.
class LanScreen extends ConsumerStatefulWidget {
  const LanScreen({super.key});

  @override
  ConsumerState<LanScreen> createState() => _LanScreenState();
}

class _LanScreenState extends ConsumerState<LanScreen> {
  final _host = TextEditingController();
  final _hostFocus = FocusNode(debugLabel: 'lan-host');
  String? _expanded;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(lanControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _hostFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(lanControllerProvider);
    final state = async.value;
    final notifier = ref.read(lanControllerProvider.notifier);
    final favorites = ref.watch(favoritesProvider).value?.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SettingsHeader(title: '跨设备同步'),
            if (state?.busy ?? false)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: LinearProgressIndicator(),
              ),
            Expanded(
              child: state == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 28),
                      children: [
                        SettingsSection(
                          title: '本机',
                          children: [
                            SettingsRow(
                              icon: Icons.smartphone,
                              title: state.name,
                              subtitle:
                                  '别的设备会看到这个名字'
                                  '${favorites == null ? '' : ' · 本机收藏 $favorites 张'}',
                            ),
                            SettingsRow(
                              icon: state.enabled
                                  ? Icons.wifi_tethering
                                  : Icons.wifi_tethering_off,
                              title: state.enabled ? '局域网同步已开启' : '局域网同步已关闭',
                              subtitle: state.enabled
                                  ? state.running
                                        ? '同一 WiFi 下的设备可以互相发现'
                                        : (state.error ?? '正在启动…')
                                  : '关闭后不监听任何端口',
                              danger: state.enabled && !state.running,
                              trailing: Icon(
                                state.enabled
                                    ? Icons.toggle_on
                                    : Icons.toggle_off,
                                size: 30,
                                color: state.enabled
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              onSelect: () =>
                                  notifier.setEnabled(!state.enabled),
                            ),
                          ],
                        ),
                        if (state.enabled)
                          SettingsSection(
                            title: '同一 WiFi 下的设备',
                            trailing: state.busy
                                ? null
                                : TextButton(
                                    onPressed: notifier.refresh,
                                    child: const Text('刷新'),
                                  ),
                            children: [
                              if (state.devices.isEmpty)
                                const SettingsRow(
                                  icon: Icons.search,
                                  title: '还没有发现设备',
                                  subtitle:
                                      '两台设备都要打开本应用、连同一个 WiFi；'
                                      '如果网络禁止广播，可在下面手动填地址',
                                ),
                              for (final device in state.devices)
                                ..._deviceRows(
                                  context,
                                  device,
                                  state,
                                  notifier,
                                ),
                            ],
                          ),
                        if (state.enabled)
                          SettingsSection(
                            title: '手动添加地址',
                            children: [
                              SettingsRow(
                                icon: Icons.keyboard,
                                title: '对方的 IP 地址',
                                subtitle: '自动搜索不到时用这个（例如 192.168.1.23）',
                                trailing: SizedBox(
                                  width: 160,
                                  child: _hostField(context),
                                ),
                              ),
                              SettingsRow(
                                icon: Icons.add_link,
                                title: '添加',
                                onSelect: state.busy ? null : _addHost,
                              ),
                            ],
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (state.error != null)
                                Text(
                                  state.error!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              if (state.status != null)
                                Text(
                                  state.status!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              const SizedBox(height: 10),
                              Text(
                                '同步是「合并」：两边都没有的专辑会补上，'
                                '任何一边已有的收藏都不会被删除。',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _deviceRows(
    BuildContext context,
    LanDevice device,
    LanState state,
    LanController notifier,
  ) {
    final expanded = _expanded == device.id;
    return [
      SettingsRow(
        icon: Icons.devices,
        title: device.name,
        subtitle: [
          device.host,
          if (device.version.isNotEmpty) 'v${device.version}',
          '收藏 ${device.favorites} 张',
        ].join(' · '),
        trailing: Icon(
          expanded ? Icons.expand_less : Icons.expand_more,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onSelect: () => setState(() => _expanded = expanded ? null : device.id),
      ),
      if (expanded) ...[
        SettingsRow(
          icon: Icons.upload,
          title: '把本机收藏发送到 ${device.name}',
          onSelect: state.busy
              ? null
              : () {
                  setState(() => _expanded = null);
                  notifier.pushFavorites(device);
                },
        ),
        SettingsRow(
          icon: Icons.download,
          title: '把 ${device.name} 的收藏合并到本机',
          onSelect: state.busy
              ? null
              : () {
                  setState(() => _expanded = null);
                  notifier.pullFavorites(device);
                },
        ),
        if (state.manualHosts.contains(device.host))
          SettingsRow(
            icon: Icons.link_off,
            title: '移除手动地址 ${device.host}',
            danger: true,
            onSelect: () => notifier.removeManual(device.host),
          ),
      ],
    ];
  }

  /// On a TV the platform-view field is the only one a remote can type into
  /// (see `TvSystemTextField`); on a phone the ordinary field is better.
  Widget _hostField(BuildContext context) {
    final tv = ref.read(isTelevisionProvider);
    if (!tv) {
      return TextField(
        controller: _host,
        focusNode: _hostFocus,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _addHost(),
        decoration: const InputDecoration(
          isDense: true,
          hintText: '192.168.1.23',
        ),
      );
    }
    return TvSystemTextField(
      controller: _host,
      hintText: '192.168.1.23',
      height: 46,
      onSubmitted: (_) => _addHost(),
      // Down is the natural "done, go on": leave the field and add the address.
      onMoveDown: _addHost,
      onMoveUp: () =>
          FocusScope.of(context).focusInDirection(TraversalDirection.up),
    );
  }

  void _addHost() {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    ref.read(lanControllerProvider.notifier).addManual(host);
    _host.clear();
  }
}
