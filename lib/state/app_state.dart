import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/chat_store.dart';
import '../core/device_identity.dart';
import '../core/discovery_service.dart';
import '../core/models/chat_message.dart';
import '../core/models/peer_device.dart';
import '../core/transfer_client.dart';
import '../core/transfer_server.dart';

/// 全局状态：设备发现、消息流、收发调度。
class AppState extends ChangeNotifier {
  late DeviceIdentity identity;
  TransferServer? _server;
  DiscoveryService? _discovery;
  StreamSubscription<List<PeerDevice>>? _peerSub;

  final ChatStore _store = ChatStore();
  final TransferClient _client = TransferClient();

  List<PeerDevice> peers = [];
  List<ChatMessage> messages = [];
  String? activePeerId;
  String? localIp;

  /// 本机 IP 已解析完成（无论有没有解析到），用于区分「还没查」与「确实没有 Wi-Fi」
  bool localIpResolved = false;

  /// 传输服务与设备发现已就绪。UI 不依赖它，只用于「连接码」等功能的前置判断。
  bool initialized = false;

  /// 历史记录已读完。用于区分「确实没有记录」与「还在读」。
  bool historyLoaded = false;

  bool _initStarted = false;
  bool _disposed = false;

  int _activeTransfers = 0;
  int _lastNotifyAt = 0;

  int get port => _server?.port ?? 0;

  PeerDevice? get activePeer {
    if (activePeerId == null) return null;
    for (final peer in peers) {
      if (peer.id == activePeerId) return peer;
    }
    return null;
  }

  bool get hasOnlinePeer => peers.any((p) => p.isOnline);

  Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;

    // 三件事互不依赖，一起发起，避免平台通道调用串行累加
    final identityFuture = DeviceIdentity.load();
    final historyFuture = _store.load();
    final ipFuture = DeviceIdentity.localIpv4();

    // 历史记录先落地：首帧之后几十毫秒就渲染出来，不必等服务和扫描
    messages = await historyFuture;
    historyLoaded = true;
    _syncActivePeer();
    notifyListeners();

    identity = await identityFuture;

    final server = TransferServer(
      identity: identity,
      onIncomingCreated: _onIncomingCreated,
      onProgress: _onProgress,
      onCompleted: _onCompleted,
      onFailed: _onFailed,
    );
    _server = server;
    await server.start();
    if (_disposed) {
      server.stop();
      return;
    }

    final discovery = DiscoveryService(selfId: identity.id, port: server.port);
    _discovery = discovery;
    _peerSub = discovery.stream.listen((list) {
      peers = list;
      _syncActivePeer();
      notifyListeners();
    });

    initialized = true;
    _syncActivePeer();
    notifyListeners();

    // 设备发现是纯后台行为，绝不能挡住首屏：这里只发起，不等待
    unawaited(discovery.start());

    // 本机 IP 只给「连接码」二维码用，回来得晚也没关系
    unawaited(ipFuture.then((ip) {
      if (_disposed) return;
      localIp = ip;
      localIpResolved = true;
      notifyListeners();
    }));
  }

  void _syncActivePeer() {
    if (peers.isEmpty) {
      activePeerId = null;
      return;
    }
    final stillThere = peers.any((p) => p.id == activePeerId);
    if (stillThere) return;
    final online = peers.where((p) => p.isOnline).toList();
    activePeerId = online.isNotEmpty ? online.first.id : peers.first.id;
  }

  void selectPeer(String id) {
    activePeerId = id;
    notifyListeners();
  }

  Future<void> rescan() async {
    await _discovery?.rescan();
  }

  // ---------------------------------------------------------------- 发送

  Future<void> _sendQueue = Future<void>.value();

  Future<void> sendFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    final peer = activePeer;
    if (peer == null) {
      throw TransferException('请先在上方选择接收设备');
    }
    for (final path in paths) {
      final message = await _createOutgoingMessage(path, peer);
      if (message == null) continue;
      // 串行排队，避免多个大文件互相抢带宽
      _sendQueue = _sendQueue.then((_) => _runSend(message, peer));
    }
  }

  Future<ChatMessage?> _createOutgoingMessage(
    String path,
    PeerDevice peer,
  ) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final size = await file.length();
    if (size == 0) return null;
    final name = path.split(Platform.pathSeparator).last;

    final message = ChatMessage(
      id: const Uuid().v4(),
      peerId: peer.id,
      peerAlias: peer.alias,
      direction: MessageDirection.outgoing,
      fileName: name,
      fileSize: size,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      localPath: path,
      status: MessageStatus.waiting,
    );
    messages.add(message);
    notifyListeners();
    unawaited(_store.save(messages));
    return message;
  }

  Future<void> _runSend(ChatMessage message, PeerDevice peer) async {
    _replaceMessage(
      message.id,
      (m) => m.copyWith(status: MessageStatus.transferring, progress: 0),
    );
    _beginTransfer();
    try {
      await _client.sendFile(
        peer: peer,
        filePath: message.localPath!,
        fileName: message.fileName,
        transferId: message.id,
        senderAlias: identity.alias,
        senderId: identity.id,
        onProgress: (p) => _onProgress(message.id, p),
      );
      _replaceMessage(
        message.id,
        (m) => m.copyWith(status: MessageStatus.success, progress: 1),
      );
    } catch (e) {
      _replaceMessage(
        message.id,
        (m) => m.copyWith(
          status: MessageStatus.failed,
          error: e is TransferException ? e.message : '$e',
        ),
      );
    } finally {
      _endTransfer();
      unawaited(_store.save(messages));
    }
  }

  Future<void> retryMessage(ChatMessage message) async {
    if (!message.isOutgoing) return;
    final path = message.localPath;
    PeerDevice? peer;
    for (final p in peers) {
      if (p.id == message.peerId) {
        peer = p;
        break;
      }
    }
    if (path == null || peer == null) {
      _replaceMessage(
        message.id,
        (m) => m.copyWith(error: '对方已不在线，请重新选择设备'),
      );
      return;
    }
    _replaceMessage(
      message.id,
      (m) => m.copyWith(status: MessageStatus.transferring, progress: 0, error: ''),
    );
    await _runSend(messages.firstWhere((m) => m.id == message.id), peer);
  }

  // ---------------------------------------------------------------- 接收

  void _onIncomingCreated(ChatMessage message) {
    messages.add(message);
    _beginTransfer();
    notifyListeners();
    unawaited(_store.save(messages));
  }

  void _onProgress(String id, double progress) {
    _replaceMessage(
      id,
      (m) => m.copyWith(
        progress: progress.clamp(0.0, 1.0),
        status: m.isDone ? MessageStatus.success : MessageStatus.transferring,
      ),
      throttle: true,
    );
  }

  void _onCompleted(String id, String path, int size) {
    _replaceMessage(
      id,
      (m) => m.copyWith(
        status: MessageStatus.success,
        progress: 1,
        localPath: path,
      ),
    );
    _endTransfer();
    unawaited(_store.save(messages));
  }

  void _onFailed(String id, String error) {
    _replaceMessage(
      id,
      (m) => m.copyWith(status: MessageStatus.failed, error: error),
    );
    _endTransfer();
    unawaited(_store.save(messages));
  }

  // ---------------------------------------------------------------- 工具

  void _replaceMessage(
    String id,
    ChatMessage Function(ChatMessage) update, {
    bool throttle = false,
  }) {
    final index = messages.indexWhere((m) => m.id == id);
    if (index < 0) return;
    messages[index] = update(messages[index]);
    if (throttle) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastNotifyAt < 90) return;
      _lastNotifyAt = now;
    }
    notifyListeners();
  }

  void _beginTransfer() {
    _activeTransfers++;
    WakelockPlus.enable();
  }

  void _endTransfer() {
    _activeTransfers--;
    if (_activeTransfers <= 0) {
      _activeTransfers = 0;
      WakelockPlus.disable();
    }
  }

  PeerDevice? addPeerFromQr(String raw) {
    final discovery = _discovery;
    final peer = PeerDevice.fromQrPayload(raw);
    if (discovery == null || peer == null) return null;
    activePeerId = peer.id;
    discovery.addPeer(peer);
    unawaited(_refreshPeer(peer));
    notifyListeners();
    return peer;
  }

  Future<void> _refreshPeer(PeerDevice peer) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client
          .getUrl(Uri.parse('http://${peer.host}:${peer.port}/api/info'))
          .timeout(const Duration(seconds: 3));
      final response = await request.close().timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return;
      final body = await response.transform(utf8.decoder).join();
      final map = jsonDecode(body) as Map<String, dynamic>;
      final real = PeerDevice.fromInfo(
        map,
        host: peer.host,
        port: peer.port,
        lastSeen: DateTime.now(),
      );
      activePeerId = real.id;
      _discovery?.addPeer(real);
      notifyListeners();
    } catch (_) {
      // 扫码后对方可能已离线，保留二维码里的地址供重试
    } finally {
      client.close(force: true);
    }
  }

  /// 打开/导出接收到的文件。返回错误提示，null 表示成功。
  Future<String?> openMessage(ChatMessage message, Rect origin) async {
    final path = message.localPath;
    if (path == null) return '文件路径缺失';
    if (!await File(path).exists()) return '文件已被移动或删除';
    try {
      await Share.shareXFiles(
        [XFile(path)],
        subject: message.fileName,
        sharePositionOrigin: origin,
      );
      return null;
    } catch (e) {
      return '打开失败：$e';
    }
  }

  Future<void> clearHistory() async {
    messages.clear();
    notifyListeners();
    await _store.save(messages);
  }

  @override
  void dispose() {
    _disposed = true;
    _peerSub?.cancel();
    _discovery?.dispose();
    _server?.stop();
    super.dispose();
  }
}
