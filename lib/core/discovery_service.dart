import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'device_identity.dart';
import 'models/peer_device.dart';
import 'protocol.dart';

/// 设备发现。
///
/// 不使用 UDP 组播 / Bonjour：iOS 上组播需要向 Apple 单独申请的
/// `com.apple.developer.networking.multicast` entitlement，未签名的 ipa 拿不到；
/// 这里改为「对本机所在 /24 网段的 254 个地址并发发一次 HTTP 探测」，
/// 纯 TCP 单播，两端行为一致，在 iOS 上只需要「本地网络」权限。
///
/// **只搜一次，不常驻轮询**：App 打开时自动扫一轮（约 2~4 秒），扫完即停；
/// 之后再想找设备，由用户点界面上的「搜索」按钮手动触发。
/// 这样长时间停留在界面上不会反复扫整个网段，省电，也不会让路由器觉得异常。
class DiscoveryService {
  DiscoveryService({required this.selfId, required this.port});

  final String selfId;
  final int port;

  final Map<String, PeerDevice> _devices = {};
  final StreamController<List<PeerDevice>> _controller =
      StreamController<List<PeerDevice>>.broadcast();

  /// 是否正在搜索。UI 用它显示按钮转圈与副标题文案。
  final ValueNotifier<bool> scanning = ValueNotifier<bool>(false);

  bool _disposed = false;
  bool _dirty = false;
  String? _localIp;

  Stream<List<PeerDevice>> get stream => _controller.stream;

  bool get isScanning => scanning.value;

  List<PeerDevice> get devices {
    final list = _devices.values.toList();
    list.sort((a, b) {
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      return a.alias.compareTo(b.alias);
    });
    return list;
  }

  /// App 启动时调用：自动搜一轮，**不等待结果**，首屏不会被网络探测拖住。
  Future<void> start() => scan();

  /// 搜一轮。启动时自动调用一次，之后由用户点「搜索」调用。
  ///
  /// 一轮约 2~4 秒（254 个地址 / 32 并发 / 420ms 超时）。边扫边推，
  /// 设备一被发现就出现在列表里，不用等整轮结束。
  Future<void> scan() async {
    if (_disposed || scanning.value) return;
    scanning.value = true;
    _dirty = false;
    try {
      // 每次都重新读网卡：手动搜索的常见场景就是刚换了 Wi-Fi 或网段
      _localIp = await DeviceIdentity.localIpv4();
      if (_disposed) return;

      final hosts = <String>[];

      // 已知设备先复探，保证旧条目的在线状态是新的
      for (final device in _devices.values) {
        hosts.add(device.host);
      }

      if (_localIp != null) {
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

      try {
        for (var i = 0; i < hosts.length; i += Protocol.probeConcurrency) {
          if (_disposed) break;
          final end =
              (i + Protocol.probeConcurrency).clamp(0, hosts.length).toInt();
          final batch = hosts.sublist(i, end);
          await Future.wait(batch.map((h) => _probe(h, client)));
          // 边扫边推：设备一被发现就出现在列表里，不用等 254 个地址扫完
          if (_dirty) {
            _dirty = false;
            _emit();
          }
        }
      } finally {
        client.close(force: true);
      }

      // 超过阈值没探测到的设备从列表移除
      final before = _devices.length;
      _devices.removeWhere(
        (_, d) => DateTime.now().difference(d.lastSeen) > Protocol.offlineAfter,
      );
      if (_devices.length != before) _dirty = true;
      if (_dirty) {
        _dirty = false;
        _emit();
      }
    } finally {
      if (!_disposed) scanning.value = false;
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
      final previous = _devices[id];
      if (previous == null || !previous.isOnline) _dirty = true;
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
    scanning.dispose();
    _controller.close();
  }
}
