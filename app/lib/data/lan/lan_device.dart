/// A peer on the local network: another copy of this app, found either by the
/// UDP discovery broadcast or by typing its address in by hand.
class LanDevice {
  const LanDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.version = '',
    this.favorites = 0,
    this.lastSeen,
    this.manual = false,
    this.playbackHost = false,
  });

  /// Stable per-install id: the only thing that identifies a device across
  /// address changes, so the same peer is never listed twice.
  final String id;

  /// What the other device calls itself (its user-editable name).
  final String name;

  /// Its address on the network, and the port its HTTP API listens on. The
  /// port is assigned by the OS (and therefore different every launch), which
  /// is why it travels in the discovery reply.
  final String host;
  final int port;

  final String version;

  /// How many albums the peer has favorited — shown in the list, and the first
  /// thing that changes when a sync worked.
  final int favorites;

  final DateTime? lastSeen;

  /// Added by hand (an address typed in) rather than discovered: such a peer
  /// is never dropped just because it stopped broadcasting.
  final bool manual;

  /// Whether the peer currently offers its playback for others to follow
  /// ("sync playback" is on). Advertised in the beacon, so the device list can
  /// offer the row before anything is contacted.
  final bool playbackHost;

  Uri get baseUri => Uri.parse('http://$host:$port');

  LanDevice copyWith({
    String? name,
    String? host,
    int? port,
    String? version,
    int? favorites,
    DateTime? lastSeen,
    bool? manual,
    bool? playbackHost,
  }) => LanDevice(
    id: id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    version: version ?? this.version,
    favorites: favorites ?? this.favorites,
    lastSeen: lastSeen ?? this.lastSeen,
    manual: manual ?? this.manual,
    playbackHost: playbackHost ?? this.playbackHost,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'v': version,
    'fav': favorites,
    if (playbackHost) 'pb': 1,
  };

  /// Discovery traffic is unauthenticated, so nothing here may be trusted
  /// beyond its type: a malformed or hostile packet is dropped, not thrown.
  static LanDevice? tryFromJson(
    Object? value, {
    String? host,
    bool manual = false,
  }) {
    if (value is! Map) return null;
    final id = value['id'];
    final port = value['port'];
    if (id is! String || id.isEmpty || port is! int) return null;
    final address = host ?? value['host'];
    if (address is! String || address.isEmpty) return null;
    return LanDevice(
      id: id,
      name: value['name'] is String && (value['name'] as String).isNotEmpty
          ? value['name'] as String
          : address,
      host: address,
      port: port,
      version: value['v'] is String ? value['v'] as String : '',
      favorites: value['fav'] is int ? value['fav'] as int : 0,
      lastSeen: DateTime.now(),
      manual: manual,
      playbackHost: value['pb'] == 1,
    );
  }

  @override
  String toString() => 'LanDevice($name @ $host:$port)';
}
