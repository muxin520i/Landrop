import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';
import 'models/peer_device.dart';

class TransferException implements Exception {
  TransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 发送端：把文件切成固定大小的分片，逐片 POST 到对端。
///
/// 每片都带绝对偏移，链路抖动时重新向对端查询已收字节数并从该处续传，
/// 因此中断（切后台、Wi-Fi 闪断）后重试不会从头再来。
class TransferClient {
  Future<void> sendFile({
    required PeerDevice peer,
    required String filePath,
    required String fileName,
    required String transferId,
    required String senderAlias,
    required String senderId,
    required void Function(double progress) onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw TransferException('源文件已不存在');
    }
    final total = await file.length();
    if (total == 0) {
      throw TransferException('文件为空，无法传输');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 30);

    try {
      var offset = await _init(
        client: client,
        peer: peer,
        transferId: transferId,
        fileName: fileName,
        total: total,
        senderAlias: senderAlias,
        senderId: senderId,
      );

      if (offset >= total) {
        onProgress(1);
        return;
      }
      onProgress(offset / total);

      var retries = 0;
      while (offset < total) {
        final end = (offset + Protocol.chunkSize).clamp(0, total).toInt();
        try {
          final received = await _sendChunk(
            client: client,
            peer: peer,
            transferId: transferId,
            file: file,
            start: offset,
            end: end,
          );
          offset = received;
          onProgress((offset / total).clamp(0.0, 1.0));
          retries = 0;
        } catch (e) {
          retries++;
          if (retries > Protocol.maxRetries) {
            throw TransferException('传输中断：$e');
          }
          await Future<void>.delayed(Duration(milliseconds: 300 * retries));
          // 断链后重新握手，拿到对端真实已收字节数再续传
          offset = await _init(
            client: client,
            peer: peer,
            transferId: transferId,
            fileName: fileName,
            total: total,
            senderAlias: senderAlias,
            senderId: senderId,
          );
        }
      }
      onProgress(1);
    } finally {
      client.close(force: true);
    }
  }

  /// 发一条文本消息。几十个字节直接走 JSON，不进分片流程。
  Future<void> sendText({
    required PeerDevice peer,
    required String text,
    required String messageId,
    required String senderAlias,
    required String senderId,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 10);

    try {
      final uri = Uri.parse('http://${peer.host}:${peer.port}/api/text');
      final HttpClientRequest request;
      try {
        request =
            await client.postUrl(uri).timeout(const Duration(seconds: 8));
      } on SocketException {
        throw TransferException('无法连接对方，请确认两台手机在同一 Wi-Fi');
      } on TimeoutException {
        throw TransferException('连接对方超时');
      }

      final body = utf8.encode(jsonEncode({
        'id': messageId,
        'text': text,
        'sender': senderAlias,
        'senderId': senderId,
      }));
      request.headers.contentType = ContentType.json;
      request.contentLength = body.length;
      request.add(body);

      final response =
          await request.close().timeout(const Duration(seconds: 10));
      await response.drain<void>();
      if (response.statusCode != HttpStatus.ok) {
        throw TransferException('对方没有接收（${response.statusCode}）');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<int> _init({
    required HttpClient client,
    required PeerDevice peer,
    required String transferId,
    required String fileName,
    required int total,
    required String senderAlias,
    required String senderId,
  }) async {
    final uri = Uri.parse('http://${peer.host}:${peer.port}/api/upload/init')
        .replace(queryParameters: {
      'fileId': transferId,
      'name': fileName,
      'size': '$total',
      'sender': senderAlias,
      'senderId': senderId,
    });

    final response = await _get(client, uri);
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw TransferException('对方拒绝连接（${response.statusCode}）');
    }
    final map = jsonDecode(body) as Map<String, dynamic>;
    if (map['completed'] == true) return total;
    return (map['offset'] as num?)?.toInt() ?? 0;
  }

  Future<HttpClientResponse> _get(HttpClient client, Uri uri) async {
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 8));
      return await request.close().timeout(const Duration(seconds: 8));
    } on SocketException {
      throw TransferException('无法连接对方，请确认两台手机在同一 Wi-Fi');
    } on TimeoutException {
      throw TransferException('连接对方超时');
    }
  }

  Future<int> _sendChunk({
    required HttpClient client,
    required PeerDevice peer,
    required String transferId,
    required File file,
    required int start,
    required int end,
  }) async {
    final uri = Uri.parse('http://${peer.host}:${peer.port}/api/upload/chunk')
        .replace(queryParameters: {
      'fileId': transferId,
      'offset': '$start',
    });

    final HttpClientRequest request;
    try {
      request = await client.postUrl(uri).timeout(const Duration(seconds: 10));
    } on SocketException {
      throw TransferException('连接已断开');
    }

    request.headers.contentType = ContentType.binary;
    request.contentLength = end - start;
    await request.addStream(file.openRead(start, end));

    final response = await request.close().timeout(Protocol.chunkTimeout);
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode == HttpStatus.ok ||
        response.statusCode == HttpStatus.conflict) {
      try {
        final map = jsonDecode(body) as Map<String, dynamic>;
        return (map['received'] as num?)?.toInt() ?? end;
      } catch (_) {
        return end;
      }
    }
    throw TransferException('对方写入失败（${response.statusCode}）');
  }
}
