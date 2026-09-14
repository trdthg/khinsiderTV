import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'lan_device.dart';

/// Thrown when a peer cannot be reached or answers with something unexpected.
/// The UI turns this into a message; nothing in here ever talks to the user.
class LanException implements Exception {
  const LanException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a sync did, for the "已合并 N 首" line.
class LanSyncResult {
  const LanSyncResult({
    required this.peer,
    required this.added,
    required this.total,
    required this.incoming,
  });

  /// Name of the other device.
  final String peer;

  /// How many albums were new to the receiving side.
  final int added;

  /// How many favorites the receiving side has now.
  final int total;

  /// True when this device was the receiver (the other one pushed).
  final bool incoming;
}

typedef JsonMap = Map<String, Object?>;

/// LAN discovery + the small HTTP API this app's devices use to talk to each
/// other. No plugin, no cloud, no account: every device broadcasts a UDP
/// beacon, answers the same broadcast from others, and then speaks plain HTTP
/// to the address it heard about.
///
/// Why a custom protocol instead of mDNS: mDNS needs platform DNS-SD APIs
/// (Android NsdManager, Bonjour) and therefore a plugin per platform, while
/// this needs nothing but `dart:io`. Broadcasting to the subnet's directed
/// broadcast address plus 255.255.255.255 covers every home network, and a
/// device whose network filters broadcasts can still be added by address.
///
/// Security: discovery and the favorites API are unauthenticated, on the
/// assumption that this is a home LAN and that the only operation offered is a
/// union merge, which cannot delete anything. See `doc/lan.md`.
class LanService {
  LanService({
    required this.deviceId,
    required this.deviceName,
    required this.appVersion,
    required this.readFavorites,
    required this.mergeFavorites,
    this.onRemoteSync,
    this.discoveryPort = defaultDiscoveryPort,
  });

  final String deviceId;
  final String deviceName;
  final String appVersion;

  /// Local favorites as JSON (see `albumSummaryToJson`).
  final Future<List<JsonMap>> Function() readFavorites;

  /// Merge an incoming list into the local favorites, returning how many were
  /// new and how many there are now.
  final Future<({int added, int total})> Function(List<JsonMap> incoming)
  mergeFavorites;

  /// Called when another device pushes its favorites here, so the UI can say
  /// so without the receiver having to be on the LAN screen.
  final void Function(LanSyncResult result)? onRemoteSync;

  /// Fixed port for discovery. The HTTP port is assigned by the OS, so it is
  /// carried in the beacon rather than guessed.
  static const int defaultDiscoveryPort = 41234;

  /// Injectable so two services can run inside one test process (they would
  /// otherwise fight over the same UDP port).
  final int discoveryPort;

  static const int _protocol = 1;
  static const Duration _peerTtl = Duration(seconds: 20);
  static const Duration _requestTimeout = Duration(seconds: 5);

  RawDatagramSocket? _udp;
  HttpServer? _http;
  Timer? _sweeper;
  Timer? _prober;
  bool _watching = false;
  bool _running = false;

  final _devices = <String, LanDevice>{};
  final _manualHosts = <String>{};
  final _controller = StreamController<List<LanDevice>>.broadcast();

  /// Peers currently known, most recently seen first.
  List<LanDevice> get devices {
    final list = _devices.values.toList()
      ..sort((a, b) {
        final at = a.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
    return list;
  }

  Stream<List<LanDevice>> get deviceStream => _controller.stream;

  bool get isRunning => _running;

  /// The port the HTTP API listens on, once [start] succeeded.
  int? get httpPort => _http?.port;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _http!.listen(_handleRequest, onError: (_) {});
      _udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _udp!.broadcastEnabled = true;
      _udp!.listen((event) {
        if (event == RawSocketEvent.read) _handleDatagram();
      });
    } catch (e) {
      // A device with no network, or a blocked port: the feature is simply
      // unavailable there, which must not take the app down.
      await stop();
      throw LanException('无法启动局域网服务：$e');
    }
    _sweeper = Timer.periodic(const Duration(seconds: 5), (_) => _sweep());
    await refresh();
  }

  Future<void> stop() async {
    _running = false;
    _sweeper?.cancel();
    _sweeper = null;
    _prober?.cancel();
    _prober = null;
    _watching = false;
    try {
      _udp?.send(
        utf8.encode(jsonEncode({'kh': 'bye', 'id': deviceId})),
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
    } catch (_) {}
    _udp?.close();
    _udp = null;
    await _http?.close(force: true);
    _http = null;
    _devices.clear();
    _emit();
  }

  /// Broadcast a probe; every peer answers with its address and HTTP port.
  Future<void> refresh() async {
    final socket = _udp;
    if (socket == null) return;
    await refreshFavoriteCount();
    final probe = _beacon('probe');
    for (final target in await _broadcastTargets()) {
      try {
        socket.send(probe, target, discoveryPort);
      } catch (_) {}
    }
  }

  /// Add a device by address (typed in by hand), for networks that filter
  /// broadcasts. Throws when nothing answers.
  Future<LanDevice> addManual(String host) async {
    final address = host.trim();
    if (address.isEmpty) throw const LanException('请输入地址');
    final found = await _probeHost(address);
    if (found == null) {
      throw LanException('$address 上没有回应');
    }
    _manualHosts.add(address);
    _devices[found.id] = found.copyWith(lastSeen: DateTime.now());
    _emit();
    return found;
  }

  void removeManual(String host) {
    _manualHosts.remove(host);
    _devices.removeWhere((_, d) => d.host == host && d.manual);
    _emit();
  }

  Set<String> get manualHosts => {..._manualHosts};

  /// Favorites count advertised in beacons. Refreshed on [start], on every
  /// [refresh] and whenever the UI knows the list changed; until then peers see
  /// 0, which is the documented "never said" value.
  int favoriteCount = 0;

  /// Peers are dropped 20s after their last beacon, so whoever is showing a
  /// device list has to keep asking; nobody else pays for the traffic.
  void setWatching(bool watching) {
    if (_watching == watching) return;
    _watching = watching;
    _prober?.cancel();
    _prober = null;
    if (!watching || _udp == null) return;
    unawaited(refresh());
    _prober = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(refresh()),
    );
  }

  bool get isWatching => _watching;

  Future<int> refreshFavoriteCount() async {
    try {
      favoriteCount = (await readFavorites()).length;
    } catch (_) {
      // Keep the last known number rather than dropping to 0 on a hiccup.
    }
    return favoriteCount;
  }

  /// Read a peer's favorites and merge them into this device's.
  Future<LanSyncResult> pullFavorites(LanDevice peer) async {
    final body = await _getJson(peer, '/kh/favorites');
    final raw = body['favorites'];
    if (raw is! List) throw const LanException('对方返回的数据无法识别');
    final incoming = raw.whereType<Map>().map(JsonMap.from).toList();
    final outcome = await mergeFavorites(incoming);
    return LanSyncResult(
      peer: peer.name,
      added: outcome.added,
      total: outcome.total,
      incoming: true,
    );
  }

  /// Send this device's favorites to a peer, which merges them into its own.
  Future<LanSyncResult> pushFavorites(LanDevice peer) async {
    final favorites = await readFavorites();
    final body = await _postJson(peer, '/kh/favorites', {
      'favorites': favorites,
    });
    return LanSyncResult(
      peer: peer.name,
      added: body['added'] is int ? body['added'] as int : 0,
      total: body['total'] is int ? body['total'] as int : 0,
      incoming: false,
    );
  }

  // -- discovery -------------------------------------------------------------

  /// Limited broadcast plus the directed broadcast of every private /24 the
  /// device is on. `NetworkInterface` exposes no netmask, and a /24 is what
  /// every home network uses; the limited broadcast covers the rest.
  Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <String>{'255.255.255.255'};
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      )) {
        for (final address in interface.addresses) {
          final parts = address.address.split('.');
          if (parts.length == 4) {
            targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
          }
        }
      }
    } catch (_) {}
    return targets.map(InternetAddress.new).toList();
  }

  Future<LanDevice?> _probeHost(String host) async {
    final socket = _udp;
    if (socket == null) return null;
    await refreshFavoriteCount();
    final probe = _beacon('probe');
    // Subscribe before sending: the answer can arrive before `send` returns,
    // and a broadcast stream does not replay.
    final reply = deviceStream
        .expand((list) => list)
        .firstWhere((d) => d.host == host)
        .timeout(const Duration(seconds: 2));
    try {
      socket.send(probe, InternetAddress(host), discoveryPort);
    } catch (_) {
      return null;
    }
    try {
      return await reply;
    } on TimeoutException {
      return null;
    }
  }

  void _handleDatagram() {
    final socket = _udp;
    if (socket == null) return;
    Datagram? datagram;
    while ((datagram = socket.receive()) != null) {
      final data = datagram!.data;
      if (data.isEmpty) continue;
      Map<String, Object?> message;
      try {
        final decoded = jsonDecode(utf8.decode(data));
        if (decoded is! Map) continue;
        message = JsonMap.from(decoded);
      } catch (_) {
        continue; // not ours (or garbage)
      }
      if (message['kh'] == 'bye') {
        final id = message['id'];
        if (id is String && _devices.remove(id) != null) _emit();
        continue;
      }
      if (message['kh'] != 'probe') continue;
      final from = message['id'];
      if (from is String && from == deviceId) continue; // our own beacon
      // Answer the probe so the other side learns our HTTP port, then treat it
      // as a sighting of the peer as well.
      final peer = LanDevice.tryFromJson(
        message,
        host: datagram.address.address,
      );
      if (peer == null) continue;
      unawaited(_replyPong(datagram.address));
      _upsert(peer);
    }
  }

  /// A beacon carrying this device's address, HTTP port and favorites count,
  /// so one exchange is enough for the other side to show something real.
  ///
  /// Public because the payload is the contract between two devices and the
  /// list is otherwise only reachable through a broadcast.
  Map<String, Object?> beaconPayload(String kind) => {
    'kh': kind,
    'id': deviceId,
    'name': deviceName,
    'v': appVersion,
    'port': _http?.port ?? 0,
    'fav': favoriteCount,
  };

  List<int> _beacon(String kind) =>
      utf8.encode(jsonEncode(beaconPayload(kind)));

  /// Answers a probe. The count is read here rather than reused from the cache
  /// so the reply is never stale.
  Future<void> _replyPong(InternetAddress to) async {
    final socket = _udp;
    if (socket == null) return;
    await refreshFavoriteCount();
    try {
      socket.send(_beacon('pong'), to, discoveryPort);
    } catch (_) {}
  }

  void _upsert(LanDevice peer) {
    if (peer.id == deviceId) return;
    final existing = _devices[peer.id];
    final merged = existing == null
        ? peer
        : peer.copyWith(
            lastSeen: DateTime.now(),
            manual: existing.manual,
            // Beacons that carry no count send 0 ("never said"); a device with
            // no favorites at all would have to have synced them away.
            favorites: peer.favorites == 0 && existing.favorites > 0
                ? existing.favorites
                : peer.favorites,
          );
    _devices[peer.id] = merged;
    _emit();
  }

  void _sweep() {
    final now = DateTime.now();
    final stale = _devices.entries
        .where(
          (e) =>
              !e.value.manual &&
              !_manualHosts.contains(e.value.host) &&
              now.difference(e.value.lastSeen ?? now) > _peerTtl,
        )
        .map((e) => e.key)
        .toList();
    if (stale.isEmpty) return;
    for (final id in stale) {
      _devices.remove(id);
    }
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(devices);
  }

  // -- http ------------------------------------------------------------------

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.headers.value('x-khinsider') != '$_protocol') {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/kh/info') {
        final favorites = await readFavorites();
        _writeJson(response, {
          'id': deviceId,
          'name': deviceName,
          'v': appVersion,
          'fav': favorites.length,
        });
        return;
      }
      if (request.method == 'GET' && path == '/kh/favorites') {
        _writeJson(response, {'favorites': await readFavorites()});
        return;
      }
      if (request.method == 'POST' && path == '/kh/favorites') {
        final raw = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          response.statusCode = HttpStatus.badRequest;
          return;
        }
        final list = decoded['favorites'];
        if (list is! List) {
          response.statusCode = HttpStatus.badRequest;
          return;
        }
        final incoming = list.whereType<Map>().map(JsonMap.from).toList();
        final outcome = await mergeFavorites(incoming);
        final result = LanSyncResult(
          peer: request.headers.value('x-khinsider-name') ?? '另一台设备',
          added: outcome.added,
          total: outcome.total,
          incoming: true,
        );
        _writeJson(response, {'added': outcome.added, 'total': outcome.total});
        onRemoteSync?.call(result);
        return;
      }
      response.statusCode = HttpStatus.notFound;
    } catch (e) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        _writeJson(response, {'error': '$e'});
      } catch (_) {}
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  void _writeJson(HttpResponse response, Map<String, Object?> body) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
  }

  Future<JsonMap> _getJson(LanDevice peer, String path) async {
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    try {
      final request = await client
          .getUrl(peer.baseUri.replace(path: path))
          .timeout(_requestTimeout);
      request.headers.set('x-khinsider', '$_protocol');
      request.headers.set('x-khinsider-name', deviceName);
      final response = await request.close().timeout(_requestTimeout);
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw LanException('对方返回 ${response.statusCode}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const LanException('对方返回的数据无法识别');
      return JsonMap.from(decoded);
    } on LanException {
      rethrow;
    } catch (e) {
      throw LanException('连不上 ${peer.name}：$e');
    } finally {
      client.close(force: true);
    }
  }

  Future<JsonMap> _postJson(
    LanDevice peer,
    String path,
    Map<String, Object?> payload,
  ) async {
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    try {
      final request = await client
          .postUrl(peer.baseUri.replace(path: path))
          .timeout(_requestTimeout);
      request.headers.set('x-khinsider', '$_protocol');
      request.headers.set('x-khinsider-name', deviceName);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(_requestTimeout);
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw LanException('对方返回 ${response.statusCode}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const LanException('对方返回的数据无法识别');
      return JsonMap.from(decoded);
    } on LanException {
      rethrow;
    } catch (e) {
      throw LanException('连不上 ${peer.name}：$e');
    } finally {
      client.close(force: true);
    }
  }

  /// A random, stable-per-install id (32 hex chars).
  static String newDeviceId([Random? random]) {
    final rng = random ?? Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
