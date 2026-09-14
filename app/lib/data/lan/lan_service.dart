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
    this.replaced = false,
  });

  /// Name of the other device.
  final String peer;

  /// How many albums were new to the receiving side.
  final int added;

  /// How many favorites the receiving side has now.
  final int total;

  /// True when this device was the receiver (the other one pushed).
  final bool incoming;

  /// True when the receiving side was overwritten instead of merged.
  final bool replaced;

  /// True when the receiving side emptied out everything the sender lacked.
  int get removed => replaced ? total - added : 0;
}

typedef JsonMap = Map<String, Object?>;

/// What a one-tap connection test found.
///
/// The two halves are reported separately on purpose: discovery (UDP) working
/// while the API (TCP) does not is a firewall or a router's client isolation,
/// and knowing that is the difference between "your network blocks it" and
/// "the other app went away".
class LanPeerDiagnosis {
  const LanPeerDiagnosis({
    required this.udp,
    required this.tcp,
    this.port,
    this.version = '',
    this.favorites = 0,
  });

  final bool udp;
  final bool tcp;
  final int? port;
  final String version;
  final int favorites;

  bool get ok => udp && tcp;

  String describe(String name) {
    final at = port == null
        ? ''
        : '（端口 $port${version.isEmpty ? '' : '，v$version'}）';
    if (!udp) {
      return '$name 的地址探测没有回应$at：对方可能已经退出、不在同一个网络里，'
          '或者路由器把 UDP 也挡了。';
    }
    if (!tcp) {
      return '$name 的地址探测有回应$at，但连不上它的 API：对方的防火墙、'
          '路由器的客户端隔离挡住了 TCP，或者对方的应用刚被系统挂起。';
    }
    return '$name 一切正常$at，收藏 $favorites 张。';
  }
}

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
/// assumption that this is a home LAN. The ordinary sync only ever merges, so
/// it cannot delete anything; the "overwrite" variants can, and are only sent
/// after an explicit confirmation in the UI. See `doc/lan.md`.
class LanService {
  LanService({
    required this.deviceId,
    required this.deviceName,
    required this.appVersion,
    required this.readFavorites,
    required this.mergeFavorites,
    required this.replaceFavorites,
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

  /// Overwrite the local favorites with an incoming list (the forced sync).
  /// Returns how many were sent and how many there are now, so the ordinary
  /// result type can describe it too.
  final Future<({int added, int total})> Function(List<JsonMap> incoming)
  replaceFavorites;

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

  /// This device's own address on the LAN, so the user can compare it with
  /// what the other side shows (and tell "same network" from "not same
  /// network" without guessing).
  Future<String?> localAddress() async {
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      )) {
        for (final address in interface.addresses) {
          return address.address;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Probes [peer] and then calls its API: one tap instead of a guess.
  Future<LanPeerDiagnosis> diagnose(LanDevice peer) async {
    final answered = await _probeHost(peer.host);
    final fresh = _devices[peer.id] ?? answered;
    if (fresh == null) return const LanPeerDiagnosis(udp: false, tcp: false);
    try {
      final info = await _requestOnce(fresh, 'GET', '/kh/info');
      return LanPeerDiagnosis(
        udp: true,
        tcp: true,
        port: fresh.port,
        version: info['v'] as String? ?? fresh.version,
        favorites: info['fav'] as int? ?? fresh.favorites,
      );
    } catch (_) {
      return LanPeerDiagnosis(
        udp: true,
        tcp: false,
        port: fresh.port,
        version: fresh.version,
        favorites: fresh.favorites,
      );
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
  /// Reads [peer]'s favorites. With [replace] this device's own list is
  /// overwritten rather than merged.
  Future<LanSyncResult> pullFavorites(
    LanDevice peer, {
    bool replace = false,
  }) async {
    final body = await _request(peer, 'GET', '/kh/favorites');
    final raw = body['favorites'];
    if (raw is! List) throw const LanException('对方返回的数据无法识别');
    final incoming = raw.whereType<Map>().map(JsonMap.from).toList();
    final outcome = replace
        ? await replaceFavorites(incoming)
        : await mergeFavorites(incoming);
    return LanSyncResult(
      peer: peer.name,
      added: outcome.added,
      total: outcome.total,
      incoming: true,
      replaced: replace,
    );
  }

  /// Send this device's favorites to a peer, which merges them into its own.
  /// Sends this device's favorites to [peer]. With [replace] the peer's own
  /// list is overwritten rather than merged, which is destructive and is why
  /// the UI asks first.
  Future<LanSyncResult> pushFavorites(
    LanDevice peer, {
    bool replace = false,
  }) async {
    final favorites = await readFavorites();
    final body = await _request(
      peer,
      'POST',
      '/kh/favorites',
      payload: {'favorites': favorites, 'mode': replace ? 'replace' : 'merge'},
    );
    return LanSyncResult(
      peer: peer.name,
      added: body['added'] is int ? body['added'] as int : 0,
      total: body['total'] is int ? body['total'] as int : 0,
      incoming: false,
      replaced: body['replaced'] == true,
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
      if (message['kh'] == 'pong') {
        // The answer to a unicast probe, and the only way a peer that is not
        // broadcasting can be learned at all: the manual address box, the
        // saved addresses at start-up, and the retry after a failed connection
        // all depend on it. Dropping it silently made every one of those paths
        // give up with "the peer answers broadcasts but its service port does
        // not answer" - a message that was then always wrong about the cause.
        // A pong is never answered with a pong: that would not terminate.
        final peer = LanDevice.tryFromJson(
          message,
          host: datagram.address.address,
        );
        if (peer != null) _upsert(peer);
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
        await _writeJson(response, const {
          'error': 'forbidden',
        }, status: HttpStatus.forbidden);
        return;
      }
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/kh/info') {
        final favorites = await readFavorites();
        await _writeJson(response, {
          'id': deviceId,
          'name': deviceName,
          'v': appVersion,
          'fav': favorites.length,
        });
        return;
      }
      if (request.method == 'GET' && path == '/kh/favorites') {
        await _writeJson(response, {'favorites': await readFavorites()});
        return;
      }
      if (request.method == 'POST' && path == '/kh/favorites') {
        final raw = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          await _writeJson(response, const {
            'error': 'bad request',
          }, status: HttpStatus.badRequest);
          return;
        }
        final list = decoded['favorites'];
        if (list is! List) {
          await _writeJson(response, const {
            'error': 'bad request',
          }, status: HttpStatus.badRequest);
          return;
        }
        // Only an explicit "replace" overwrites; anything else merges, which
        // is the safe default even if a future client forgets the field.
        final replace = decoded['mode'] == 'replace';
        final incoming = list.whereType<Map>().map(JsonMap.from).toList();
        final outcome = replace
            ? await replaceFavorites(incoming)
            : await mergeFavorites(incoming);
        final result = LanSyncResult(
          peer: request.headers.value('x-khinsider-name') ?? '另一台设备',
          added: outcome.added,
          total: outcome.total,
          incoming: true,
          replaced: replace,
        );
        await _writeJson(response, {
          'added': outcome.added,
          'total': outcome.total,
          'replaced': replace,
        });
        onRemoteSync?.call(result);
        return;
      }
      await _writeJson(response, const {
        'error': 'not found',
      }, status: HttpStatus.notFound);
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

  Future<void> _writeJson(
    HttpResponse response,
    Map<String, Object?> body, {
    int status = HttpStatus.ok,
  }) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    // Closing here matters: an unclosed response never reaches the client, and
    // the client can only report that as a timeout ("连不上"), which is exactly
    // the kind of guessing this app is trying not to do.
    await response.close();
  }

  /// One round trip to [peer], with one recovery attempt.
  ///
  /// A peer that answers the discovery broadcast but refuses the TCP
  /// connection is the failure this feature actually hits in the field: the
  /// address is right, but the port was learned from an older beacon, or the
  /// device (a TV especially) dropped off the network and its radio needs a
  /// packet to wake up. So a failed connection is followed by a unicast probe
  /// to the same address, which both refreshes the advertised port and gives a
  /// sleeping peer a reason to wake, and then the request is tried again.
  /// Says which of the two failures this is, because their fixes have nothing
  /// in common: an unreachable port is a firewall, a refused one is a peer
  /// whose service is not there any more.
  String _explain(Object error) {
    final text = error is SocketException
        ? '${error.osError?.message ?? ''} ${error.message}'.toLowerCase()
        : '$error'.toLowerCase();
    if (text.contains('refused')) {
      return '\n对方的端口拒绝连接：那个端口上没有服务在听（应用每次启动都会重新'
          '分配端口，对方可能刚重启过）。';
    }
    if (text.contains('timed out') || text.contains('timeout')) {
      return '\n对方没有回应 TCP：对方的应用可能已经不在前台（被系统挂起），'
          '也可能是防火墙或路由器的"客户端隔离"（AP 隔离）—— UDP 能通、TCP 不通'
          '正是这两种情况的特征。请在两边都打开这个页面再试。';
    }
    return '';
  }

  Future<JsonMap> _request(
    LanDevice peer,
    String method,
    String path, {
    Map<String, Object?>? payload,
  }) async {
    if (peer.port == 0) {
      // A peer whose HTTP port is unknown (an address added by hand, or a
      // beacon from a version that did not advertise one) can only be reached
      // after asking: `http://host:0` fails immediately and then looks like a
      // network problem when it is nothing of the sort.
      final resolved = await _probeHost(peer.host);
      if (resolved == null) {
        throw LanException(
          '连不上 ${peer.name}（${peer.host}）：它的地址还没有确认，'
          '地址探测也没有回应。请让对方的应用保持运行，并确认两台设备在同一个网络里。',
        );
      }
      peer = _devices[peer.id] ?? resolved;
    }
    try {
      return await _requestOnce(peer, method, path, payload: payload);
    } on LanException {
      // The peer answered and disliked something: the connection is fine.
      rethrow;
    } catch (first) {
      final fresh = await _refreshPeer(peer);
      if (fresh == null) {
        throw LanException(
          '连不上 ${peer.name}（${peer.host}:${peer.port}）：$first\n'
          '它在广播里能看到，但连它的服务端口没有回应。'
          '${_explain(first)}',
        );
      }
      try {
        return await _requestOnce(fresh, method, path, payload: payload);
      } catch (second) {
        throw LanException(
          '连不上 ${peer.name}（${fresh.host}:${fresh.port}）：$second'
          '${_explain(second)}',
        );
      }
    }
  }

  Future<JsonMap> _requestOnce(
    LanDevice peer,
    String method,
    String path, {
    Map<String, Object?>? payload,
  }) async {
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    try {
      final uri = peer.baseUri.replace(path: path);
      final request =
          await (method == 'POST' ? client.postUrl(uri) : client.getUrl(uri))
              .timeout(_requestTimeout);
      request.headers.set('x-khinsider', '$_protocol');
      request.headers.set('x-khinsider-name', deviceName);
      if (payload != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(payload));
      }
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
    } finally {
      client.close(force: true);
    }
  }

  /// Re-probes [peer] by address and returns its refreshed entry, or null when
  /// nothing answered.
  Future<LanDevice?> _refreshPeer(LanDevice peer) async {
    final answered = await _probeHost(peer.host);
    if (answered == null) return null;
    // The address may have changed hands, so prefer the entry we already know
    // by id (the probe's own upsert refreshed it if it is the same device).
    return _devices[peer.id] ?? answered;
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
