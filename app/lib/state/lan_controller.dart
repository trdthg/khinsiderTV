import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:khinsider_api/khinsider_api.dart';

import '../data/lan/lan_device.dart';
import '../data/lan/lan_service.dart';
import '../data/preferences_store.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import 'locale_controller.dart';
import 'update_controller.dart';

const _kLanEnabled = 'lan_enabled';
const _kLanDeviceId = 'lan_device_id';
const _kLanDeviceName = 'lan_device_name';
const _kLanManualHosts = 'lan_manual_hosts';

/// What the LAN screen shows.
class LanState {
  const LanState({
    required this.deviceId,
    required this.name,
    this.enabled = true,
    this.running = false,
    this.devices = const [],
    this.manualHosts = const {},
    this.busy = false,
    this.status,
    this.error,
    this.localAddress,
    this.localPort,
  });

  /// This device, as others see it.
  final String deviceId;
  final String name;

  /// The user's switch: off means no sockets are open at all.
  final bool enabled;
  final bool running;

  final List<LanDevice> devices;
  final Set<String> manualHosts;

  /// A sync or a discovery is in flight.
  final bool busy;

  /// Last outcome, shown under the list (never a popup).
  final String? status;
  final String? error;

  /// This device's own address, for comparing the two ends of a sync.
  final String? localAddress;
  final int? localPort;

  static const _unset = Object();

  LanState copyWith({
    String? name,
    bool? enabled,
    bool? running,
    List<LanDevice>? devices,
    Set<String>? manualHosts,
    bool? busy,
    Object? status = _unset,
    Object? error = _unset,
    Object? localAddress = _unset,
    Object? localPort = _unset,
  }) => LanState(
    deviceId: deviceId,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    running: running ?? this.running,
    devices: devices ?? this.devices,
    manualHosts: manualHosts ?? this.manualHosts,
    busy: busy ?? this.busy,
    status: identical(status, _unset) ? this.status : status as String?,
    error: identical(error, _unset) ? this.error : error as String?,
    localAddress: identical(localAddress, _unset)
        ? this.localAddress
        : localAddress as String?,
    localPort: identical(localPort, _unset)
        ? this.localPort
        : localPort as int?,
  );
}

/// A name that means something in another device's list. `Platform.localHostname`
/// is a real name on desktop and useless ("localhost") on Android, so phones
/// and TVs get a platform label plus a slice of their id — two devices of the
/// same kind must not look identical in the list.
String defaultLanDeviceName(String id, [AppLocalizations? strings]) {
  final l = strings ?? stringsFor(null);
  final suffix = id.length >= 4 ? id.substring(0, 4) : id;
  final host = Platform.localHostname;
  if (host.isNotEmpty && host != 'localhost' && host != 'android') return host;
  if (Platform.isAndroid) return l.lanDeviceAndroid(suffix);
  if (Platform.isIOS) return l.lanDeviceApple(suffix);
  if (Platform.isMacOS) return 'Mac $suffix';
  if (Platform.isWindows) return 'Windows $suffix';
  if (Platform.isLinux) return 'Linux $suffix';
  return 'KHInsider $suffix';
}

/// Owns the running [LanService] and everything the LAN screen does with it.
class LanController extends AsyncNotifier<LanState> {
  LanService? _service;
  StreamSubscription<List<LanDevice>>? _devicesSub;

  /// The strings for the language in effect right now. Read lazily at each call
  /// so a language change is picked up without rebuilding the service.
  AppLocalizations get _strings =>
      stringsFor(ref.read(localeControllerProvider));

  @override
  Future<LanState> build() async {
    final store = await ref.watch(jsonKvStoreProvider.future);
    var id = store.read<String>(_kLanDeviceId);
    if (id == null || id.isEmpty) {
      id = LanService.newDeviceId();
      store.write(_kLanDeviceId, id);
    }
    final name =
        store.read<String>(_kLanDeviceName) ??
        defaultLanDeviceName(
          id,
          stringsFor(ref.read(localeControllerProvider)),
        );
    final manual = store.readList<String>(_kLanManualHosts).toSet();
    final enabled = store.read<bool>(_kLanEnabled) ?? true;

    final initial = LanState(
      deviceId: id,
      name: name,
      enabled: enabled,
      manualHosts: manual,
    );
    ref.onDispose(() {
      _devicesSub?.cancel();
      unawaited(_service?.stop());
      _service = null;
    });
    if (enabled) unawaited(_start(initial));
    return initial;
  }

  Future<void> _start(LanState from) async {
    final service = LanService(
      deviceId: from.deviceId,
      deviceName: from.name,
      appVersion: ref.read(appVersionProvider).value ?? '',
      readFavorites: () async {
        final favorites = await ref.read(favoritesProvider.future);
        return favorites.map(albumSummaryToJson).toList();
      },
      mergeFavorites: _mergeIncoming,
      replaceFavorites: _replaceIncoming,
      strings: () => stringsFor(ref.read(localeControllerProvider)),
      onRemoteSync: (result) {
        if (!ref.mounted) return;
        final l = _strings;
        _patch(
          (s) => s.copyWith(
            status: result.replaced
                ? l.lanStatusOverwrittenByPeer(result.peer, result.total)
                : l.lanStatusMergedFromPeer(
                    result.peer,
                    result.added,
                    result.total,
                  ),
          ),
        );
      },
    );
    _service = service;
    await _devicesSub?.cancel();
    _devicesSub = service.deviceStream.listen((devices) {
      if (ref.mounted) _patch((s) => s.copyWith(devices: devices));
    });
    try {
      await service.start();
      for (final host in from.manualHosts) {
        try {
          await service.addManual(host);
        } catch (_) {
          // A saved address that is not there right now is normal.
        }
      }
      final local = await service.localAddress();
      if (!ref.mounted) return;
      _patch(
        (s) => s.copyWith(
          running: true,
          error: null,
          localAddress: local,
          localPort: service.httpPort,
        ),
      );
    } catch (e) {
      if (!ref.mounted) return;
      _patch((s) => s.copyWith(running: false, error: '$e'));
    }
  }

  Future<void> _stop() async {
    await _devicesSub?.cancel();
    _devicesSub = null;
    await _service?.stop();
    _service = null;
    if (ref.mounted) {
      _patch((s) => s.copyWith(running: false, devices: const [], busy: false));
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final store = await ref.read(jsonKvStoreProvider.future);
    store.write(_kLanEnabled, enabled);
    _patch((s) => s.copyWith(enabled: enabled, error: null));
    if (enabled) {
      await _start(state.value!);
    } else {
      await _stop();
    }
  }

  /// Probes one device and then calls its API, and says which half worked.
  /// This is the answer to "it says it cannot connect", and it names the fix.
  Future<void> testConnection(LanDevice device) async {
    final l = _strings;
    final service = _service;
    if (service == null) {
      _patch((s) => s.copyWith(error: l.lanServiceNotRunning));
      return;
    }
    _patch(
      (s) => s.copyWith(
        busy: true,
        status: l.lanTestingDevice(device.name),
        error: null,
      ),
    );
    final result = await service.diagnose(device);
    if (!ref.mounted) return;
    _patch(
      (s) => s.copyWith(
        busy: false,
        status: result.describe(device.name, l),
        error: result.ok ? null : ' ',
      ),
    );
  }

  /// Re-broadcast the discovery probe.
  /// Called by the device-list screen: keeps discovery running while it is
  /// open (peers expire after 20s) and stops it again on the way out.
  void setWatching(bool watching) => _service?.setWatching(watching);

  Future<void> refresh() async {
    final l = _strings;
    final service = _service;
    if (service == null) return;
    _patch((s) => s.copyWith(busy: true, status: l.lanSearchingDevices));
    await service.refresh();
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!ref.mounted) return;
    final count = state.value?.devices.length ?? 0;
    _patch(
      (s) => s.copyWith(
        busy: false,
        status: count == 0 ? l.lanNoOtherDevices : l.lanFoundDevices(count),
      ),
    );
  }

  Future<void> addManual(String host) async {
    final l = _strings;
    final service = _service;
    if (service == null) return;
    _patch((s) => s.copyWith(busy: true, error: null));
    try {
      final device = await service.addManual(host);
      final store = await ref.read(jsonKvStoreProvider.future);
      final hosts = {...?state.value?.manualHosts, device.host};
      store.write(_kLanManualHosts, hosts.toList());
      _patch(
        (s) => s.copyWith(
          busy: false,
          manualHosts: hosts,
          status: l.lanAddedDevice(device.name),
        ),
      );
    } catch (e) {
      _patch((s) => s.copyWith(busy: false, error: '$e'));
    }
  }

  Future<void> removeManual(String host) async {
    final l = _strings;
    _service?.removeManual(host);
    final store = await ref.read(jsonKvStoreProvider.future);
    final hosts = {...?state.value?.manualHosts}..remove(host);
    store.write(_kLanManualHosts, hosts.toList());
    _patch(
      (s) => s.copyWith(manualHosts: hosts, status: l.lanRemovedHost(host)),
    );
  }

  /// Send this device's favorites to [device]; it merges them into its own.
  /// With [replace] the other side ends up with exactly this list.
  Future<void> pushFavorites(LanDevice device, {bool replace = false}) async {
    final l = _strings;
    final service = _service;
    if (service == null) return;
    _patch(
      (s) => s.copyWith(
        busy: true,
        status: replace
            ? l.lanOverwritingDevice(device.name)
            : l.lanSendingToDevice(device.name),
        error: null,
      ),
    );
    try {
      final local = await ref.read(favoritesProvider.future);
      final result = await service.pushFavorites(device, replace: replace);
      if (!ref.mounted) return;
      _patch(
        (s) => s.copyWith(
          busy: false,
          status: replace
              ? l.lanPushedOverwrite(result.peer, local.length, result.total)
              : l.lanPushedMerge(
                  result.peer,
                  local.length,
                  result.added,
                  result.total,
                ),
        ),
      );
    } catch (e) {
      _patch((s) => s.copyWith(busy: false, error: '$e'));
    }
  }

  /// Pull [device]'s favorites into this device. With [replace] the local list
  /// is overwritten, so anything the other device does not have is dropped.
  Future<void> pullFavorites(LanDevice device, {bool replace = false}) async {
    final l = _strings;
    final service = _service;
    if (service == null) return;
    _patch(
      (s) => s.copyWith(
        busy: true,
        status: replace
            ? l.lanOverwritingLocal(device.name)
            : l.lanReadingFromDevice(device.name),
        error: null,
      ),
    );
    try {
      final result = await service.pullFavorites(device, replace: replace);
      if (!ref.mounted) return;
      _patch(
        (s) => s.copyWith(
          busy: false,
          status: replace
              ? l.lanPulledOverwrite(result.peer, result.total)
              : l.lanPulledMerge(result.peer, result.added, result.total),
        ),
      );
    } catch (e) {
      _patch((s) => s.copyWith(busy: false, error: '$e'));
    }
  }

  Future<({int added, int total})> _mergeIncoming(
    List<JsonMap> incoming,
  ) async {
    final albums = incoming
        .map(tryAlbumSummaryFromJson)
        .whereType<AlbumSummary>()
        .toList();
    final added = await ref.read(favoritesProvider.notifier).mergeAll(albums);
    final total = await ref.read(favoritesProvider.future);
    return (added: added, total: total.length);
  }

  /// The service calls this when another device overwrites this one's list.
  Future<({int added, int total})> _replaceIncoming(
    List<JsonMap> incoming,
  ) async {
    final albums = incoming
        .map(tryAlbumSummaryFromJson)
        .whereType<AlbumSummary>()
        .toList();
    final total = await ref.read(favoritesProvider.notifier).replaceAll(albums);
    // "added" is what the receiving UI should count: for an overwrite every
    // album now in the list came from the other device.
    return (added: total, total: total);
  }

  void _patch(LanState Function(LanState) change) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(change(current));
  }
}

final lanControllerProvider = AsyncNotifierProvider<LanController, LanState>(
  LanController.new,
);
