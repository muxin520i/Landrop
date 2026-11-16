import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';
import 'device_identity.dart';
import 'models/peer_device.dart';

/// 设备发现。
///
/// 不使用 UDP 组播 / Bonjour：iOS 上组播需要向 Apple 单独申请的
/// `com.apple.developer.networking.multicast` entitlement，未签名的 ipa 拿不到；
/// 这里改为「对本机所在 /24 网段的 254 个地址并发发一次 HTTP 探测」，
/// 纯 TCP 单播，两端行为一致，在 iOS 上只需要「本地网络」权限。
///
/// 一轮全量扫描约 2~4 秒；后续轮次只复探已知设备，每 3 轮做一次全量发现。
class DiscoveryService {
  DiscoveryService({required this.selfId, required this.port});

  final String selfId;
  final int port;

  final Map<String, PeerDevice> _devices = {};
  final StreamController<List<PeerDevice>> _controller =
      StreamController<List<PeerDevice>>.broadcast();

  Timer? _timer;
  bool _scanning = false;
  bool _disposed = false;
  int _round = 0;
  String? _localIp;

  Stream<List<PeerDevice>> get stream => _controller.stream;

  List<PeerDevice> get devices {
    final list = _devices.values.toList();
    list.sort((a, b) {
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      return a.alias.compareTo(b.alias);
    });
    return list;
  }

  Future<void> start() async {
    _localIp = await DeviceIdentity.localIpv4();
    await _scanOnce(full: true);
    _timer = Timer.periodic(Protocol.scanInterval, (_) => _scanOnce(full: false));
  }

  /// 用户从扫码页回来时可主动触发一次。
  Future<void> rescan() => _scanOnce(full: true);

  Future<void> _scanOnce({required bool full}) async {
    if (_scanning || _disposed) return;
    _scanning = true;
    _round++;
    try {
      _localIp = await DeviceIdentity.localIpv4();
      final hosts = <String>[];

      // 已知在线设备每轮都复探，保证状态及时刷新
      for (final device in _devices.values) {
        hosts.add(device.host);
      }

      final doFull = full || _round % 3 == 1;
      if (doFull && _localIp != null) {
        final prefix = _localIp!.substring(0, _localIp!.lastIndexOf('.'));
        for (var i = 1; i <= 254; i++) {
          final ip = '$prefix.$i';
          if (ip == _localIp) continue;
          if (!hosts.contains(ip)) hosts.add(ip);
        }
      }

      final client = HttpClient()
        ..connectionTimeout = Protocol.probeTimeout
        ..idleTimeout = const Duration(seconds: 2);

      for (var i = 0; i < hosts.length; i += Protocol.probeConcurrency) {
        if (_disposed) break;
        final end =
            (i + Protocol.probeConcurrency).clamp(0, hosts.length).toInt();
        final batch = hosts.sublist(i, end);
        await Future.wait(batch.map((h) => _probe(h, client)));
      }
      client.close(force: true);

      // 超过阈值没探测到的设备从列表移除
      _devices.removeWhere(
        (_, d) => DateTime.now().difference(d.lastSeen) > Protocol.offlineAfter,
      );
      _emit();
    } finally {
      _scanning = false;
    }
  }

  Future<void> _probe(String host, HttpClient client) async {
    try {
      final request = await client
          .getUrl(Uri.parse('http://$host:$port/api/info'))
          .timeout(Protocol.probeTimeout);
      final response = await request.close().timeout(Protocol.probeTimeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        return;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(Protocol.probeTimeout);
      final map = jsonDecode(body) as Map<String, dynamic>;
      if (map['app'] != 'landrop') return;
      final id = map['id'] as String?;
      if (id == null || id == selfId) return;
      _devices[id] = PeerDevice.fromInfo(
        map,
        host: host,
        port: port,
        lastSeen: DateTime.now(),
      );
    } catch (_) {
      // 该地址没有近传服务，忽略
    }
  }

  /// 扫码得到的设备直接并入列表。
  void addPeer(PeerDevice peer) {
    _devices[peer.id] = peer.copyWith(lastSeen: DateTime.now());
    _emit();
  }

  void forgetPeer(String id) {
    _devices.remove(id);
    _emit();
  }

  void _emit() {
    if (_disposed) return;
    _controller.add(devices);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _controller.close();
  }
}
