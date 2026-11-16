/// 局域网内发现的一台设备。
class PeerDevice {
  const PeerDevice({
    required this.id,
    required this.alias,
    required this.platform,
    required this.host,
    required this.port,
    required this.lastSeen,
  });

  /// 设备持久化标识（由对端生成并保存在本地文件里，重装 App 才会变）。
  final String id;

  /// 展示名称，例如「张三的 iPhone」「Xiaomi 14」。
  final String alias;

  /// android / ios / unknown
  final String platform;

  final String host;
  final int port;
  final DateTime lastSeen;

  bool get isOnline =>
      DateTime.now().difference(lastSeen) < const Duration(seconds: 40);

  bool get isIos => platform == 'ios';

  String get endpoint => '$host:$port';

  PeerDevice copyWith({
    String? alias,
    String? platform,
    String? host,
    int? port,
    DateTime? lastSeen,
  }) {
    return PeerDevice(
      id: id,
      alias: alias ?? this.alias,
      platform: platform ?? this.platform,
      host: host ?? this.host,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  /// 解析对端 /api/info 的响应。
  factory PeerDevice.fromInfo(
    Map<String, dynamic> json, {
    required String host,
    required int port,
    required DateTime lastSeen,
  }) {
    return PeerDevice(
      id: (json['id'] as String?) ?? '$host:$port',
      alias: (json['alias'] as String?)?.trim().isNotEmpty == true
          ? json['alias'] as String
          : host,
      platform: (json['platform'] as String?) ?? 'unknown',
      host: host,
      port: port,
      lastSeen: lastSeen,
    );
  }

  /// 扫码连接使用的编码。
  String toQrPayload() => 'landrop://connect?host=$host&port=$port&id=$id';

  static PeerDevice? fromQrPayload(String payload) {
    try {
      final uri = Uri.parse(payload.trim());
      if (uri.scheme != 'landrop' || uri.host != 'connect') return null;
      final host = uri.queryParameters['host'];
      final port = int.tryParse(uri.queryParameters['port'] ?? '');
      if (host == null || port == null) return null;
      return PeerDevice(
        id: uri.queryParameters['id'] ?? '$host:$port',
        alias: host,
        platform: 'unknown',
        host: host,
        port: port,
        lastSeen: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}
