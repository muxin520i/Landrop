import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:landrop/core/device_identity.dart';
import 'package:landrop/core/transfer_server.dart';

/// 网页接口冒烟测试：直接起服务，用真实 HTTP 走一遍上传、列表、下载。
void main() {
  test('网页接口：上传 / 列表 / 下载 / 关闭', () async {
    final dir = await Directory.systemTemp.createTemp('landrop_web_');
    final events = <String>[];

    final server = TransferServer(
      identity: const DeviceIdentity(
        id: 'smoke-test',
        alias: '我的 iPhone',
        platform: 'ios',
      ),
      directoryProvider: () async => dir,
      onIncomingCreated: (m) => events.add('created:${m.fileName}:${m.fileSize}'),
      onProgress: (id, p) => events.add('progress:${(p * 100).round()}'),
      onCompleted: (id, path, size) => events.add('completed:$size'),
      onFailed: (id, e) => events.add('failed:$e'),
    );
    await server.start();
    final base = 'http://127.0.0.1:${server.port}';
    final client = HttpClient();

    Future<(int, List<int>)> send(
      String method,
      String path, {
      List<int>? body,
      Map<String, String>? headers,
    }) async {
      final req = await client.openUrl(method, Uri.parse('$base$path'));
      headers?.forEach(req.headers.set);
      if (body != null) req.add(body);
      final resp = await req.close();
      final bytes = await resp.fold<List<int>>([], (a, b) => a..addAll(b));
      return (resp.statusCode, bytes);
    }

    var failures = 0;
    void check(String label, bool ok, [String extra = '']) {
      print('${ok ? "PASS" : "FAIL"}  $label${extra.isEmpty ? "" : "  $extra"}');
      if (!ok) failures++;
    }

    // 1. 首页
    var (code, bytes) = await send('GET', '/');
    final html = utf8.decode(bytes);
    check('GET /', code == 200 && html.contains('我的 iPhone') && html.contains('/api/web/files'),
        '${bytes.length}B');

    // 2. 上传 3 MB 随机数据（含中文名）
    final rnd = Random(7);
    final payload = List<int>.generate(3 * 1024 * 1024 + 137, (_) => rnd.nextInt(256));
    final name = '测试 文件 #1.bin';
    (code, bytes) = await send(
      'POST',
      '/api/web/upload?name=${Uri.encodeQueryComponent(name)}&size=${payload.length}',
      body: payload,
    );
    check('POST 上传（中文名 + 空格）', code == 200, utf8.decode(bytes));

    // 3. 列表
    (code, bytes) = await send('GET', '/api/web/files');
    final list = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final files = (list['files'] as List).cast<Map<String, dynamic>>();
    final found = files.any((f) => f['name'] == name && f['size'] == payload.length);
    check('GET 列表', code == 200 && found, '${files.length} 个文件');

    // 4. 下载并逐字节比对
    (code, bytes) = await send(
      'GET',
      '/api/web/download?name=${Uri.encodeQueryComponent(name)}',
    );
    var same = bytes.length == payload.length;
    if (same) {
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] != payload[i]) {
          same = false;
          break;
        }
      }
    }
    check('GET 下载完整性', code == 200 && same, '${bytes.length}B');

    // 5. 同名再传一次，应自动改名
    (code, bytes) = await send(
      'POST',
      '/api/web/upload?name=${Uri.encodeQueryComponent(name)}&size=5',
      body: [1, 2, 3, 4, 5],
    );
    (code, bytes) = await send('GET', '/api/web/files');
    final names = (jsonDecode(utf8.decode(bytes))['files'] as List)
        .map((e) => e['name'] as String)
        .toList();
    check('同名自动加序号', names.contains('测试 文件 #1 (1).bin'), names.join(', '));

    // 6. 路径穿越与隐藏文件
    (code, bytes) = await send(
      'POST',
      '/api/web/upload?name=${Uri.encodeQueryComponent('../../evil.txt')}&size=3',
      body: [65, 66, 67],
    );
    final escaped = File('${dir.parent.path}/evil.txt').existsSync();
    check('路径穿越被挡', code == 200 && !escaped, '落在临时目录内');
    (code, bytes) = await send('GET', '/api/web/download?name=..%2F..%2Fevil.txt');
    check('非法下载被拒', code == 400 || code == 404, 'HTTP $code');

    // 7. 关闭后一律拒绝
    server.webEnabled = false;
    (code, bytes) = await send('GET', '/api/web/files');
    check('关闭后接口 403', code == 403, 'HTTP $code');
    (code, bytes) = await send('GET', '/');
    check('关闭后首页提示页', code == 200 && utf8.decode(bytes).contains('电脑访问已关闭'));

    // 8. 回调事件
    check('消息回调齐全',
        events.any((e) => e.startsWith('created:') && e.contains(payload.length.toString())) &&
            events.any((e) => e.startsWith('completed:')),
        events.take(6).join(' | '));

    client.close(force: true);
    await server.stop();
    await dir.delete(recursive: true);

    print(failures == 0 ? '\n全部通过' : '\n$failures 项失败');
    expect(failures, 0, reason: '$failures 项检查未通过');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
