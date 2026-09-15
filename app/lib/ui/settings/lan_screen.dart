import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/device.dart';
import '../../data/lan/lan_device.dart';
import '../../data/preferences_store.dart';
import '../../l10n/l10n.dart';
import '../../state/lan_controller.dart';
import '../../state/playback_sync_controller.dart';
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
  String? _confirm;
  Timer? _confirmTimer;

  /// Held in a field because `ref` must not be touched from [dispose]: Riverpod
  /// throws there, and the throw would skip the rest of the teardown (the
  /// "stop probing" call included).
  LanController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(lanControllerProvider.notifier);
    Future.microtask(() {
      if (!mounted) return;
      // Peers expire 20s after their last beacon, so discovery has to keep
      // running while this list is on screen (and only then).
      _controller?.setWatching(true);
      _controller?.refresh();
    });
  }

  @override
  void dispose() {
    _confirmTimer?.cancel();
    _controller?.setWatching(false);
    _host.dispose();
    _hostFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = l10n(context);
    final async = ref.watch(lanControllerProvider);
    final state = async.value;
    final notifier = ref.read(lanControllerProvider.notifier);
    final favorites = ref.watch(favoritesProvider).value?.length;
    final sync = ref.watch(playbackSyncControllerProvider);
    final syncNotifier = ref.read(playbackSyncControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SettingsHeader(title: l.lanTitle),
            // The bar keeps its 4px even when idle: swapping it in and out
            // made the whole list jump while a sync was running.
            SizedBox(
              height: 4,
              child: (state?.busy ?? false)
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: LinearProgressIndicator(),
                    )
                  : null,
            ),
            Expanded(
              child: state == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 28),
                      children: [
                        SettingsSection(
                          title: l.syncHostTitle,
                          children: [
                            SettingsRow(
                              icon: Icons.speaker_group,
                              title: sync.hosting
                                  ? l.syncHosting
                                  : l.syncHostTitle,
                              subtitle: sync.hosting
                                  ? l.syncFollowers(sync.followers)
                                  : l.syncHostSubtitle,
                              trailing: Switch(
                                value: sync.hosting,
                                onChanged: (on) => on
                                    ? syncNotifier.startHosting()
                                    : syncNotifier.stopHosting(),
                              ),
                              onSelect: sync.hosting
                                  ? syncNotifier.stopHosting
                                  : syncNotifier.startHosting,
                            ),
                            if (sync.following != null) ...[
                              SettingsRow(
                                icon: Icons.timer_outlined,
                                title: l.syncDelayMinus,
                                subtitle: sync.status,
                                onSelect: () => syncNotifier.nudgeDelay(
                                  const Duration(milliseconds: -10),
                                ),
                              ),
                              SettingsRow(
                                icon: Icons.timer,
                                title: l.syncDelayPlus,
                                onSelect: () => syncNotifier.nudgeDelay(
                                  const Duration(milliseconds: 10),
                                ),
                              ),
                              SettingsRow(
                                icon: Icons.close,
                                title: l.syncStopFollowing,
                                onSelect: syncNotifier.stopFollowing,
                              ),
                            ],
                          ],
                        ),
                        SettingsSection(
                          title: l.lanThisDevice,
                          children: [
                            SettingsRow(
                              icon: Icons.smartphone,
                              title: state.name,
                              subtitle:
                                  '${l.lanDeviceNameHint}'
                                  '${favorites == null ? '' : ' · ${l.lanThisDeviceFavorites(favorites)}'}',
                            ),
                            SettingsRow(
                              icon: state.enabled
                                  ? Icons.wifi_tethering
                                  : Icons.wifi_tethering_off,
                              title: state.enabled
                                  ? l.lanEnabled
                                  : l.lanDisabled,
                              subtitle: state.enabled
                                  ? state.running
                                        ? l.lanEnabledSubtitle
                                        : (state.error ?? l.lanStarting)
                                  : l.lanDisabledSubtitle,
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
                            title: l.lanDevicesOnWifi,
                            // Disabled rather than hidden: a button that
                            // vanishes mid-tap is worse than a grey one.
                            trailing: TextButton(
                              onPressed: state.busy ? null : notifier.refresh,
                              child: Text(l.lanRefresh),
                            ),
                            children: [
                              if (state.devices.isEmpty)
                                SettingsRow(
                                  icon: Icons.search,
                                  title: l.lanNoDevices,
                                  subtitle:
                                      '${l.lanBothDevicesNote} ${l.lanManualHint}',
                                ),
                              for (final device in state.devices)
                                ..._deviceRows(
                                  context,
                                  device,
                                  state,
                                  notifier,
                                  sync,
                                  syncNotifier,
                                ),
                            ],
                          ),
                        if (state.enabled)
                          SettingsSection(
                            title: l.lanAddManually,
                            children: [
                              SettingsRow(
                                icon: Icons.keyboard,
                                title: l.lanIpAddress,
                                subtitle: l.lanIpHint,
                                trailing: SizedBox(
                                  width: 160,
                                  child: _hostField(context),
                                ),
                              ),
                              SettingsRow(
                                icon: Icons.add_link,
                                title: l.lanAdd,
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
                              if (state.localAddress != null)
                                Text(
                                  l.lanLocalAddress(
                                    '${state.localAddress}'
                                    '${state.localPort == null ? '' : ':${state.localPort}'}',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Text(
                                '${l.lanMergeExplain}\n${l.lanOverwriteExplain}',
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
    PlaybackSyncState sync,
    PlaybackSyncController syncNotifier,
  ) {
    final expanded = _expanded == device.id;
    final l = l10n(context);
    return [
      SettingsRow(
        icon: Icons.devices,
        title: device.name,
        subtitle: [
          if (device.port == 0)
            l.lanAddressPending(device.host)
          else
            device.host,
          if (device.version.isNotEmpty) 'v${device.version}',
          l.lanFavoritesCount(device.favorites),
        ].join(' · '),
        trailing: Icon(
          expanded ? Icons.expand_less : Icons.expand_more,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onSelect: () {
          setState(() {
            _expanded = expanded ? null : device.id;
            _confirm = null;
          });
        },
      ),
      if (device.playbackHost && sync.following?.id != device.id)
        SettingsRow(
          icon: Icons.speaker_group,
          title: l.syncFollowDevice(device.name),
          subtitle: l.syncFollowSubtitle,
          onSelect: () => syncNotifier.follow(device),
        ),
      if (expanded) ...[
        SettingsRow(
          icon: Icons.wifi_tethering,
          title: l.lanTestConnection,
          subtitle: l.lanTestConnectionSubtitle,
          onSelect: state.busy ? null : () => notifier.testConnection(device),
        ),
        SettingsRow(
          icon: Icons.upload,
          title: l.lanSendToDevice(device.name),
          subtitle: l.lanMergeOnly,
          onSelect: state.busy
              ? null
              : () {
                  setState(() => _expanded = null);
                  notifier.pushFavorites(device);
                },
        ),
        SettingsRow(
          icon: Icons.download,
          title: l.lanPullFromDevice(device.name),
          subtitle: l.lanMergeOnly,
          onSelect: state.busy
              ? null
              : () {
                  setState(() => _expanded = null);
                  notifier.pullFavorites(device);
                },
        ),
        _overwriteRow(
          key: 'send:${device.id}',
          icon: Icons.upload_file,
          title: l.lanForcePush(device.name),
          confirmTitle: l.lanForcePushConfirm(device.name),
          subtitle: l.lanPeerLoses,
          busy: state.busy,
          onConfirmed: () {
            setState(() => _expanded = null);
            notifier.pushFavorites(device, replace: true);
          },
        ),
        _overwriteRow(
          key: 'pull:${device.id}',
          icon: Icons.download_for_offline,
          title: l.lanForcePull(device.name),
          confirmTitle: l.lanForcePullConfirm,
          subtitle: l.lanLocalLoses,
          busy: state.busy,
          onConfirmed: () {
            setState(() => _expanded = null);
            notifier.pullFavorites(device, replace: true);
          },
        ),
        if (state.manualHosts.contains(device.host))
          SettingsRow(
            icon: Icons.link_off,
            title: l.lanRemoveManual(device.host),
            danger: true,
            onSelect: () => notifier.removeManual(device.host),
          ),
      ],
    ];
  }

  /// A destructive row that needs a second tap: the first tap turns the row
  /// into its own confirmation, which avoids a dialog while still making an
  /// irreversible action deliberate.
  Widget _overwriteRow({
    required String key,
    required IconData icon,
    required String title,
    required String confirmTitle,
    required String subtitle,
    required bool busy,
    required VoidCallback onConfirmed,
  }) {
    final l = l10n(context);
    if (_confirm == key) {
      return SettingsRow(
        icon: Icons.warning_amber,
        title: confirmTitle,
        subtitle: l.lanTapToConfirm,
        danger: true,
        onSelect: () {
          _confirmTimer?.cancel();
          onConfirmed();
        },
      );
    }
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      danger: true,
      onSelect: busy ? null : () => _armConfirm(key),
    );
  }

  void _armConfirm(String key) {
    setState(() => _confirm = key);
    _confirmTimer?.cancel();
    _confirmTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _confirm = null);
    });
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
      // Reachable with the remote, but opening this page must not raise the
      // platform keyboard on its own (OK in the field does that).
      autoFocus: true,
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
