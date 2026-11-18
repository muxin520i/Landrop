import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';
import 'device_identity.dart';
import 'models/chat_message.dart';
import 'received_files.dart';
import 'web_share.dart';

typedef IncomingCreated = void Function(ChatMessage message);
typedef TransferProgress = void Function(String messageId, double progress);
typedef TransferCompleted = void Function(
    String messageId, String path, int size);
typedef TransferFailed = void Function(String messageId, String error);

/// 网页把手机发来的某一项下载完了。
typedef WebOutboxDone = void Function(String messageId);

/// 手机发给电脑网页、等待网页来取的文件或文本。
class _WebOutboxItem {
  _WebOutboxItem({
    required this.id,
    required this.messageId,
    required this.name,
    required this.size,
    required this.createdAt,
    this.path,
    this.text,
  });

  final String id;
  final String messageId;
  final String name;
  final int size;
  final DateTime createdAt;

  /// 文件路径；文本消息为 null。
  final String? path;

  /// 文本内容；文件为 null。
  final String? text;

  bool get isText => text != null;
}

class _Incoming {
  _Incoming({
    required this.fileId,
    required this.fileName,
    required this.totalSize,
    required this.partFile,
  });

  final String fileId;
  final String fileName;
  final int totalSize;
  final File partFile;

  RandomAccessFile? raf;
  int received = 0;
  bool completed = false;

  /// 同一文件的分片请求串行落盘，避免并发写乱序。
  Future<void> queue = Future.value();
}

/// 接收端 HTTP 服务。
///
/// 接口：
///   GET  /                               电脑浏览器访问页（内联 HTML）
///   GET  /api/web/files                  文件列表 JSON
///   GET  /api/web/download?name=         下载单个文件
///   POST /api/web/upload?name&size       浏览器上传（请求体为原始字节）
///   GET  /api/web/ping?cid=              网页心跳，同时报告待收数量
///   GET  /api/web/outbox?cid=            手机发给网页的待收列表
///   GET  /api/web/outbox?id=             下载某一项
///   POST /api/web/outbox?id=             标记某一项已取走
///   GET  /api/info                       设备信息（发现探测用）
///   GET  /api/upload/init?fileId&name&size&sender&senderId
///                                        返回服务端已收到的字节数，用于续传
///   POST /api/upload/chunk?fileId&offset  请求体为原始分片字节
///
/// 收到的分片按顺序追加写入 `<fileId>.part`，字节数达到 total 后自动改名落盘。
class TransferServer {
  TransferServer({
    required this.identity,
    this.onIncomingCreated,
    this.onProgress,
    this.onCompleted,
    this.onFailed,
    this.onWebOutboxDone,
    this.webEnabled = true,
    this.directoryProvider,
  });

  DeviceIdentity identity;
  final IncomingCreated? onIncomingCreated;
  final TransferProgress? onProgress;
  final TransferCompleted? onCompleted;
  final TransferFailed? onFailed;
  final WebOutboxDone? onWebOutboxDone;

  /// 是否允许电脑浏览器访问。关闭后根路径与 /api/web/* 一律拒绝。
  bool webEnabled;

  /// 落盘目录。默认与「管理文件」页共用；冒烟测试时可注入临时目录。
  final Future<Directory> Function()? directoryProvider;

  final Map<String, _Incoming> _incoming = {};
  HttpServer? _server;

  /// 打开着的网页：cid -> 最后一次心跳时间。
  final Map<String, DateTime> _webClients = {};

  /// 手机发给网页、等网页来取的东西。
  final List<_WebOutboxItem> _outbox = [];

  int _outboxSeq = 0;

  static const Duration _webTimeout = Duration(seconds: 20);

  /// 是否有网页正开着（心跳 20 秒内有效）。
  bool get hasWebClient {
    final cutoff = DateTime.now().subtract(_webTimeout);
    _webClients.removeWhere((_, seen) => seen.isBefore(cutoff));
    return _webClients.isNotEmpty;
  }

  int get webOutboxCount => _outbox.length;

  /// 把手机上的文件排进「等网页下载」队列。返回队列项 id。
  String enqueueWebFile({
    required String messageId,
    required String path,
    required String name,
    required int size,
  }) {
    final id = _nextOutboxId();
    _outbox.add(_WebOutboxItem(
      id: id,
      messageId: messageId,
      name: name,
      size: size,
      createdAt: DateTime.now(),
      path: path,
    ));
    return id;
  }

  String _nextOutboxId() =>
      'ob-${DateTime.now().microsecondsSinceEpoch}-${++_outboxSeq}';

  /// 把一段文本排进队列（电脑上点一下就能复制）。
  String enqueueWebText({
    required String messageId,
    required String text,
    required int size,
  }) {
    final id = _nextOutboxId();
    _outbox.add(_WebOutboxItem(
      id: id,
      messageId: messageId,
      name: '文本消息',
      size: size,
      createdAt: DateTime.now(),
      text: text,
    ));
    return id;
  }

  /// 撤销某个还没被取走的队列项（消息发送失败时用）。
  void cancelWebItem(String id) {
    _outbox.removeWhere((e) => e.id == id);
  }

  int get port => _server?.port ?? Protocol.transferPort;

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        Protocol.transferPort,
      );
    } on SocketException {
      // 端口被占用时退到系统随机端口，二维码里会带上真实端口
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server!.listen(
      _handle,
      onError: (_) {},
      cancelOnError: false,
    );
    unawaited(_cleanStaleParts());
  }

  Future<void> stop() async {
    for (final incoming in _incoming.values) {
      await incoming.raf?.close();
      incoming.raf = null;
    }
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/api/info') {
        await _handleInfo(request);
      } else if (path == '/api/upload/init') {
        await _handleInit(request);
      } else if (path == '/api/upload/chunk') {
        await _handleChunk(request);
      } else if (path == '/api/text') {
        await _handleText(request);
      } else if (path == '/' || path == '/index.html') {
        await _handleWebPage(request);
      } else if (path == '/favicon.ico') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      } else if (path == '/api/web/files') {
        await _handleWebFiles(request);
      } else if (path == '/api/web/download') {
        await _handleWebDownload(request);
      } else if (path == '/api/web/upload') {
        await _handleWebUpload(request);
      } else if (path == '/api/web/ping') {
        await _handleWebPing(request);
      } else if (path == '/api/web/outbox') {
        await _handleWebOutbox(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // 连接可能已经断开
      }
    }
  }

  Future<void> _handleInfo(HttpRequest request) async {
    final body = jsonEncode({
      'app': 'landrop',
      'v': Protocol.version,
      'id': identity.id,
      'alias': identity.alias,
      'platform': identity.platform,
    });
    request.response.headers.contentType = ContentType.json;
    request.response.write(body);
    await request.response.close();
  }

  /// 收一条文本消息（链接、验证码、地址）。
  ///
  /// 文本走 JSON 直传，不进分片流程——几十个字节的东西没必要建临时文件。
  /// 落库与展示交给 onIncomingCreated，直接给出完成态。
  Future<void> _handleText(HttpRequest request) async {
    if (request.method != 'POST') {
      await _json(request, HttpStatus.methodNotAllowed, {'error': 'POST only'});
      return;
    }
    final raw = await utf8.decoder.bind(request).join();
    if (raw.length > 64 * 1024) {
      await _json(request, HttpStatus.requestEntityTooLarge, {
        'error': 'text too long',
      });
      return;
    }
    Map<String, dynamic> map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await _json(request, HttpStatus.badRequest, {'error': 'invalid json'});
      return;
    }

    final id = (map['id'] as String?)?.trim();
    final text = (map['text'] as String?) ?? '';
    if (id == null || id.isEmpty || text.trim().isEmpty) {
      await _json(request, HttpStatus.badRequest, {'error': 'invalid params'});
      return;
    }

    onIncomingCreated?.call(ChatMessage(
      id: id,
      peerId: (map['senderId'] as String?) ?? '',
      peerAlias: ((map['sender'] as String?) ?? '附近设备').trim(),
      direction: MessageDirection.incoming,
      kind: MessageKind.text,
      text: text,
      fileName: '文本消息',
      fileSize: utf8.encode(text).length,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: MessageStatus.success,
    ));
    await _json(request, HttpStatus.ok, {'ok': true});
  }

  // ------------------------------------------------------------ 电脑网页访问

  Future<void> _handleWebPage(HttpRequest request) async {
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType =
        ContentType('text', 'html', charset: 'utf-8');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(webEnabled ? buildWebPage(alias: identity.alias) : webDisabledPage);
    await response.close();
  }

  Future<void> _handleWebFiles(HttpRequest request) async {
    if (!webEnabled) {
      await _json(request, HttpStatus.forbidden, {'error': 'web access disabled'});
      return;
    }
    final files = await listReceivedFiles(dir: await _receiveDir());
    await _json(request, HttpStatus.ok, {
      'alias': identity.alias,
      'files': [
        for (final f in files)
          {
            'name': f.name,
            'size': f.size,
            'mtime': f.modified.millisecondsSinceEpoch ~/ 1000,
          },
      ],
    });
  }

  Future<void> _handleWebDownload(HttpRequest request) async {
    if (!webEnabled) {
      await _json(request, HttpStatus.forbidden, {'error': 'web access disabled'});
      return;
    }
    final name = _webName(request.uri.queryParameters['name']);
    if (name == null) {
      await _json(request, HttpStatus.badRequest, {'error': 'invalid name'});
      return;
    }
    final dir = await _receiveDir();
    final file = File('${dir.path}/$name');
    if (!await file.exists()) {
      await _json(request, HttpStatus.notFound, {'error': 'not found'});
      return;
    }

    final stat = await file.stat();
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.parse(contentTypeFor(name));
    response.headers.set('Content-Disposition', _disposition(name));
    response.contentLength = stat.size;
    await response.addStream(file.openRead());
    await response.close();
  }

  /// 浏览器上传：请求体就是文件本身，文件名和大小走 query。
  /// 走流式落盘，不会把整个文件读进内存。
  Future<void> _handleWebUpload(HttpRequest request) async {
    if (!webEnabled) {
      await _json(request, HttpStatus.forbidden, {'error': 'web access disabled'});
      return;
    }
    if (request.method != 'POST') {
      await _json(request, HttpStatus.methodNotAllowed, {'error': 'POST only'});
      return;
    }

    final rawName = (request.uri.queryParameters['name'] ?? '').trim();
    final declared = int.tryParse(request.uri.queryParameters['size'] ?? '') ?? 0;
    if (rawName.isEmpty || declared <= 0) {
      await _json(request, HttpStatus.badRequest, {'error': 'invalid params'});
      return;
    }
    final name = _sanitizeName(rawName);

    final dir = await _receiveDir();
    final id = 'web-${DateTime.now().microsecondsSinceEpoch}';
    final part = File('${dir.path}/.$id.part');

    onIncomingCreated?.call(ChatMessage(
      id: id,
      peerId: 'web',
      peerAlias: '电脑网页',
      direction: MessageDirection.incoming,
      fileName: name,
      fileSize: declared,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: MessageStatus.transferring,
    ));

    RandomAccessFile? raf;
    var written = 0;
    var lastReport = 0;
    try {
      raf = await part.open(mode: FileMode.write);
      await for (final chunk in request) {
        await raf.writeFrom(chunk);
        written += chunk.length;
        if (written - lastReport >= 1024 * 1024) {
          lastReport = written;
          onProgress?.call(id, (written / declared).clamp(0.0, 1.0));
        }
      }
      await raf.close();
      raf = null;

      final target = await _uniqueTarget(dir, name);
      await part.rename(target.path);
      onProgress?.call(id, 1);
      onCompleted?.call(id, target.path, written);
      await _json(request, HttpStatus.ok, {
        'ok': true,
        'name': target.path.split(Platform.pathSeparator).last,
        'size': written,
      });
    } catch (_) {
      try {
        await raf?.close();
      } catch (_) {}
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      onFailed?.call(id, '上传中断，请重试');
      try {
        await _json(request, HttpStatus.internalServerError, {'error': 'upload failed'});
      } catch (_) {}
    }
  }

  /// 网页心跳。带着 cid 来一次就算「这台电脑还在」，顺便把待收数量带回去。
  Future<void> _handleWebPing(HttpRequest request) async {
    if (!webEnabled) {
      await _json(request, HttpStatus.forbidden, {'error': 'web access disabled'});
      return;
    }
    final cid = (request.uri.queryParameters['cid'] ?? '').trim();
    if (cid.isEmpty) {
      await _json(request, HttpStatus.badRequest, {'error': 'missing cid'});
      return;
    }
    _webClients[cid] = DateTime.now();
    await _json(request, HttpStatus.ok, {
      'ok': true,
      'alias': identity.alias,
      'outbox': _outbox.length,
    });
  }

  /// 手机 → 网页的待收队列：列表 / 下载 / 取走。
  Future<void> _handleWebOutbox(HttpRequest request) async {
    if (!webEnabled) {
      await _json(request, HttpStatus.forbidden, {'error': 'web access disabled'});
      return;
    }
    final q = request.uri.queryParameters;
    final cid = (q['cid'] ?? '').trim();
    if (cid.isNotEmpty) _webClients[cid] = DateTime.now();

    final id = (q['id'] ?? '').trim();

    // 取走：网页下载完通知一声，手机上那条消息才变成「已发送」
    if (request.method == 'POST') {
      if (id.isEmpty) {
        await _json(request, HttpStatus.badRequest, {'error': 'missing id'});
        return;
      }
      String? messageId;
      for (final item in _outbox) {
        if (item.id == id) {
          messageId = item.messageId;
          break;
        }
      }
      _outbox.removeWhere((e) => e.id == id);
      if (messageId != null) onWebOutboxDone?.call(messageId);
      await _json(request, HttpStatus.ok, {'ok': true});
      return;
    }

    if (request.method != 'GET') {
      await _json(request, HttpStatus.methodNotAllowed, {'error': 'GET or POST'});
      return;
    }

    // 列表
    if (id.isEmpty) {
      await _json(request, HttpStatus.ok, {
        'alias': identity.alias,
        'items': [
          for (final item in _outbox)
            {
              'id': item.id,
              'name': item.name,
              'size': item.size,
              'text': item.text,
              'mtime': item.createdAt.millisecondsSinceEpoch ~/ 1000,
            },
        ],
      });
      return;
    }

    // 下载某一项
    _WebOutboxItem? item;
    for (final candidate in _outbox) {
      if (candidate.id == id) {
        item = candidate;
        break;
      }
    }
    if (item == null) {
      await _json(request, HttpStatus.notFound, {'error': 'not found'});
      return;
    }
    if (item.isText || item.path == null) {
      await _json(request, HttpStatus.badRequest, {'error': 'text item'});
      return;
    }

    final file = File(item.path!);
    if (!await file.exists()) {
      _outbox.remove(item);
      await _json(request, HttpStatus.notFound, {'error': 'file missing'});
      return;
    }

    final stat = await file.stat();
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.parse(contentTypeFor(item.name));
    response.headers.set('Content-Disposition', _disposition(item.name));
    response.contentLength = stat.size;
    await response.addStream(file.openRead());
    await response.close();
  }

  /// 只接受接收目录下的普通文件名，挡掉路径穿越与隐藏的临时分片。
  String? _webName(String? raw) {
    final name = (raw ?? '').trim();
    if (name.isEmpty || name.length > 255) return null;
    if (name == '.' || name == '..') return null;
    if (name.contains('/') || name.contains('\\')) return null;
    if (name.startsWith('.')) return null;
    return name;
  }

  /// 中文文件名走 filename*，同时给老浏览器留一个 ASCII 兜底。
  String _disposition(String name) {
    final ascii = name
        .replaceAll(RegExp(r'[^\x20-\x7e]'), '_')
        .replaceAll('"', "'");
    return 'attachment; filename="$ascii"; filename*=UTF-8\'\'${Uri.encodeComponent(name)}';
  }

  Future<void> _handleInit(HttpRequest request) async {
    final q = request.uri.queryParameters;
    final fileId = q['fileId'];
    final totalSize = int.tryParse(q['size'] ?? '') ?? 0;
    final rawName = q['name'] ?? 'file';
    final senderAlias = (q['sender'] ?? '附近设备').trim();
    final senderId = q['senderId'] ?? '';

    if (fileId == null || fileId.isEmpty || totalSize <= 0) {
      await _json(request, HttpStatus.badRequest, {'error': 'invalid params'});
      return;
    }

    var incoming = _incoming[fileId];
    if (incoming == null) {
      final dir = await _receiveDir();
      final name = _sanitizeName(rawName);
      final partFile = File('${dir.path}/.$fileId.part');
      incoming = _Incoming(
        fileId: fileId,
        fileName: name,
        totalSize: totalSize,
        partFile: partFile,
      );
      _incoming[fileId] = incoming;

      if (await partFile.exists()) {
        incoming.received = await partFile.length();
      }

      final isNew = incoming.received == 0;
      if (isNew && !incoming.completed) {
        onIncomingCreated?.call(ChatMessage(
          id: fileId,
          peerId: senderId,
          peerAlias: senderAlias,
          direction: MessageDirection.incoming,
          fileName: name,
          fileSize: totalSize,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          status: MessageStatus.transferring,
        ));
      }
    }

    await _json(request, HttpStatus.ok, {
      'offset': incoming.received,
      'completed': incoming.completed,
    });
  }

  Future<void> _handleChunk(HttpRequest request) async {
    final q = request.uri.queryParameters;
    final fileId = q['fileId'];
    final offset = int.tryParse(q['offset'] ?? '');

    if (fileId == null || offset == null) {
      await _json(request, HttpStatus.badRequest, {'error': 'invalid params'});
      return;
    }

    final incoming = _incoming[fileId];
    if (incoming == null) {
      await _json(request, HttpStatus.conflict, {'error': 'unknown fileId'});
      return;
    }
    if (incoming.completed) {
      await _json(request, HttpStatus.ok, {'received': incoming.received});
      return;
    }

    // 客户端重发同一片（上一次响应丢失）时直接跳过，避免重复追加
    if (offset < incoming.received) {
      await _json(request, HttpStatus.ok, {'received': incoming.received});
      return;
    }
    if (offset > incoming.received) {
      // 中间缺块，要求客户端重新 init 取真实偏移
      await _json(request, HttpStatus.conflict, {'received': incoming.received});
      return;
    }

    final completer = Completer<void>();
    incoming.queue = incoming.queue.then((_) async {
      try {
        await _appendChunk(incoming, request);
        completer.complete();
      } catch (e) {
        completer.completeError(e);
      }
    });

    try {
      await completer.future;
    } catch (e) {
      onFailed?.call(incoming.fileId, '写入失败：$e');
      try {
        await _json(request, HttpStatus.internalServerError, {'error': '$e'});
      } catch (_) {}
      return;
    }

    await _json(request, HttpStatus.ok, {'received': incoming.received});
  }

  Future<void> _appendChunk(_Incoming incoming, HttpRequest request) async {
    final raf = incoming.raf ??=
        await incoming.partFile.open(mode: FileMode.append);

    await for (final data in request) {
      await raf.writeFrom(data);
      incoming.received += data.length;
    }
    await raf.flush();

    final progress = (incoming.received / incoming.totalSize).clamp(0.0, 1.0);
    onProgress?.call(incoming.fileId, progress);

    if (incoming.received >= incoming.totalSize) {
      await _finalize(incoming);
    }
  }

  Future<void> _finalize(_Incoming incoming) async {
    if (incoming.completed) return;
    incoming.completed = true;
    try {
      await incoming.raf?.close();
      incoming.raf = null;

      final dir = await _receiveDir();
      final target = await _uniqueTarget(dir, incoming.fileName);
      await incoming.partFile.rename(target.path);

      onProgress?.call(incoming.fileId, 1);
      onCompleted?.call(incoming.fileId, target.path, incoming.totalSize);
    } catch (e) {
      incoming.completed = false;
      onFailed?.call(incoming.fileId, '保存失败：$e');
    }
  }

  Future<void> _json(HttpRequest request, int status, Map<String, dynamic> data) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    await request.response.close();
  }

  /// 落盘目录与「管理文件」页共用同一套规则，避免两处各算一遍。
  Future<Directory> _receiveDir() async {
    final provider = directoryProvider;
    if (provider != null) return provider();
    return receiveDir();
  }

  Future<File> _uniqueTarget(Directory dir, String name) async {
    var target = File('${dir.path}/$name');
    if (!await target.exists()) return target;

    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var index = 1;
    while (await target.exists()) {
      target = File('${dir.path}/$base ($index)$ext');
      index++;
      if (index > 999) break;
    }
    return target;
  }

  String _sanitizeName(String raw) {
    var name = raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    if (name.isEmpty || name == '.' || name == '..') name = 'file';
    if (name.length > 120) {
      final dot = name.lastIndexOf('.');
      final ext = (dot > 0 && name.length - dot <= 10) ? name.substring(dot) : '';
      name = name.substring(0, 120 - ext.length) + ext;
    }
    return name;
  }

  /// 清理超过 7 天没续传的残留分片文件。
  Future<void> _cleanStaleParts() async {
    try {
      final dir = await _receiveDir();
      final now = DateTime.now();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (!name.startsWith('.') || !name.endsWith('.part')) continue;
        final stat = await entity.stat();
        if (now.difference(stat.modified).inDays >= 7) {
          await entity.delete();
        }
      }
    } catch (_) {
      // 清理失败不影响主流程
    }
  }
}
