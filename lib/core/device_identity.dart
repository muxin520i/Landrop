import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 本机身份：设备 ID 持久化在应用支持目录，卸载重装才会变化。
class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.alias,
    required this.platform,
  });

  final String id;
  final String alias;

  /// android / ios / desktop
  final String platform;

  static Future<DeviceIdentity> load() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/identity.json');

    String? savedId;
    if (await file.exists()) {
      try {
        final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        savedId = map['id'] as String?;
      } catch (_) {
        // 文件损坏则重新生成
      }
    }

    final id = savedId ?? const Uuid().v4();
    final alias = await _resolveAlias(id);
    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
            ? 'android'
            : 'desktop';

    final identity = DeviceIdentity(id: id, alias: alias, platform: platform);

    if (savedId == null) {
      await file.writeAsString(jsonEncode({
        'id': identity.id,
        'alias': identity.alias,
      }));
    }
    return identity;
  }

  static Future<String> _resolveAlias(String id) async {
    final suffix = id.replaceAll('-', '').substring(0, 4).toUpperCase();
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        final name = ios.name.trim();
        // iOS 16 起 UIDevice.name 普遍返回 "iPhone"，用短码保证两台同型号可区分
        final base = (name.isEmpty || name == 'iPhone' || name == 'iPad')
            ? (name.isEmpty ? 'iPhone' : name)
            : name;
        return '$base-$suffix';
      }
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        final brand = android.manufacturer.trim();
        final model = android.model.trim();
        final base = model.toLowerCase().startsWith(brand.toLowerCase())
            ? model
            : '$brand $model'.trim();
        return base.isEmpty ? 'Android-$suffix' : '$base-$suffix';
      }
    } catch (_) {
      // 取不到设备信息时退化为通用名称
    }
    return '${Platform.operatingSystem}-$suffix';
  }

  /// 取当前 Wi-Fi 网段的 IPv4 地址，优先 192.168.x.x。
  static Future<String?> localIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final candidates = <String>[];
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (ip.startsWith('127.')) continue;
          candidates.add(ip);
        }
      }
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) => _score(b) - _score(a));
      return candidates.first;
    } catch (_) {
      return null;
    }
  }

  static int _score(String ip) {
    if (ip.startsWith('192.168.')) return 4;
    if (ip.startsWith('10.')) return 3;
    if (ip.startsWith('172.')) return 2;
    return 1;
  }
}
