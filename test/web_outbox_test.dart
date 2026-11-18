import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landrop/core/device_identity.dart';
import 'package:landrop/core/transfer_server.dart';

/// 手机 → 电脑网页：入队、心跳、列举、下载、取走。
void main() {
  test('网页待收队列：心跳 / 列表 / 下载 / 取走', () async {
    final tmp = Directory.systemTemp.createTempSync('landrop_outbox_');
    final doneIds = <String>[];

    final server = TransferServer(
      identity: const DeviceIdentity(
        id: 'demo',
        alias: '我的 iPhone',
        platform: 'ios',
      ),
      directoryProvider: () async => tmp,
      onWebOutboxDone: doneIds.add,
    );
    await server.start();
    final base = 'http://127.0.0.1:${server.port}';
    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
      server.stop();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<HttpClientResponse> get(String path) async {
      final req = await client.getUrl(Uri.parse('$base$path'));
      return req.close();
    }

    Future<String> body(HttpClientResponse r) =>
        r.transform(utf8.decoder).join();

    // 一开始没有网页在线
    expect(server.hasWebClient, isFalse);

    // 心跳后认为在线
    var r = await get('/api/web/ping?cid=pc-1');
    expect(r.statusCode, 200);
    expect(server.hasWebClient, isTrue);
    await r.drain<void>();

    // 空队列
    r = await get('/api/web/outbox?cid=pc-1');
    var data = jsonDecode(await body(r)) as Map<String, dynamic>;
    expect((data['items'] as List).length, 0);

    // 手机发一个文件
    final src = File('${tmp.path}/photo.bin')
      ..writeAsBytesSync(List<int>.generate(3 * 1024 * 1024, (i) => i % 251));
    final itemId = server.enqueueWebFile(
      messageId: 'msg-1',
      path: src.path,
      name: '假期照片.jpg',
      size: 3 * 1024 * 1024,
    );

    // 再发一条文本
    final textId = server.enqueueWebText(
      messageId: 'msg-2',
      text: 'https://example.com/a?b=1&c=2',
      size: 33,
    );
    expect(itemId, isNot(textId));

    // 网页看到两条
    r = await get('/api/web/outbox?cid=pc-1');
    data = jsonDecode(await body(r)) as Map<String, dynamic>;
    final items = data['items'] as List;
    expect(items.length, 2);
    final file = items.firstWhere((e) => e['id'] == itemId) as Map;
    expect(file['name'], '假期照片.jpg');
    expect(file['size'], 3 * 1024 * 1024);
    expect(file['text'], isNull);
    final text = items.firstWhere((e) => e['id'] == textId) as Map;
    expect(text['text'], 'https://example.com/a?b=1&c=2');

    // 下载文件，逐字节比对
    r = await get('/api/web/outbox?id=$itemId');
    expect(r.statusCode, 200);
    expect(r.headers.value('content-disposition'), contains('attachment'));
    final bytes = await r.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    expect(bytes.length, 3 * 1024 * 1024);
    expect(bytes.first, 0);
    expect(bytes[1], 1);

    // 文本不能当文件下载
    r = await get('/api/web/outbox?id=$textId');
    expect(r.statusCode, 400);
    await r.drain<void>();

    // 网页取走后：回调带 messageId，列表变空
    final post = await client.postUrl(Uri.parse('$base/api/web/outbox?id=$itemId'));
    r = await post.close();
    expect(r.statusCode, 200);
    await r.drain<void>();
    expect(doneIds, ['msg-1']);

    r = await get('/api/web/outbox?cid=pc-1');
    data = jsonDecode(await body(r)) as Map<String, dynamic>;
    expect((data['items'] as List).length, 1, reason: '只剩文本');

    // 关掉网页访问后一律 403
    server.webEnabled = false;
    r = await get('/api/web/outbox?cid=pc-1');
    expect(r.statusCode, 403);
    await r.drain<void>();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
