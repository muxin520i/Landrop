import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/app_settings.dart';
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

  /// 正在搜索附近设备。
  bool get scanning => _discovery?.isScanning ?? false;

  /// 传输服务与设备发现已就绪。UI 不依赖它，只用于「连接码」等功能的前置判断。
  bool initialized = false;

  /// 历史记录已读完。用于区分「确实没有记录」与「还在读」。
  bool historyLoaded = false;

  bool _initStarted = false;
  bool _disposed = false;

  /// 系统型号生成的默认设备名，用户清空自定义名时回到它。
  String? _systemAlias;

  /// 每个正在传输的消息的速度采样。
  final Map<String, _SpeedMeter> _speed = {};

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

    // 设置读得很快，但设备名要用它覆盖系统型号名，所以先起一个 future
    final settingsFuture = AppSettings.instance.load();
    // 三件事互不依赖，一起发起，避免平台通道调用串行累加
    final identityFuture = DeviceIdentity.load();
    final historyFuture = _store.load();
    final ipFuture = DeviceIdentity.localIpv4();

    // 历史记录先落地：首帧之后几十毫秒就渲染出来，不必等服务和扫描
    messages = await historyFuture;
    historyLoaded = true;
    _syncActivePeer();
    notifyListeners();

    await settingsFuture;
    final loaded = await identityFuture;
    _systemAlias = loaded.alias;
    final custom = AppSettings.instance.customAlias;
    identity = (custom == null || custom == loaded.alias)
        ? loaded
        : DeviceIdentity(
            id: loaded.id,
            alias: custom,
            platform: loaded.platform,
          );

    final server = TransferServer(
      identity: identity,
      onIncomingCreated: _onIncomingCreated,
      onProgress: _onProgress,
      onCompleted: _onCompleted,
      onFailed: _onFailed,
      webEnabled: AppSettings.instance.webAccess,
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
    // 搜索开始/结束都要刷新界面：按钮转圈、副标题文案都依赖它
    discovery.scanning.addListener(_onScanStateChanged);

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

  /// 改设备名。传空字符串表示恢复系统默认名。
  /// 传输服务持有同一个 identity 引用，改完对端下次探测就能看到新名字。
  Future<void> renameDevice(String name) async {
    final trimmed = name.trim();
    await AppSettings.instance.setAlias(trimmed.isEmpty ? null : trimmed);
    final alias = trimmed.isEmpty ? (_systemAlias ?? identity.alias) : trimmed;
    identity = DeviceIdentity(
      id: identity.id,
      alias: alias,
      platform: identity.platform,
    );
    _server?.identity = identity;
    notifyListeners();
  }

  Future<void> setAutoSavePhotos(bool value) async {
    await AppSettings.instance.setAutoSavePhotos(value);
    notifyListeners();
  }

  bool get autoSavePhotos => AppSettings.instance.autoSavePhotos;

  /// 电脑浏览器能不能访问本机。
  bool get webAccessEnabled => AppSettings.instance.webAccess;

  Future<void> setWebAccess(bool value) async {
    await AppSettings.instance.setWebAccess(value);
    _server?.webEnabled = value;
    notifyListeners();
  }

  /// 电脑浏览器访问地址，没连 Wi-Fi 时为 null。
  String? get webAddress {
    final ip = localIp;
    if (ip == null || ip.isEmpty) return null;
    return 'http://$ip:$port';
  }

  /// 手动搜索一次附近设备（界面上「搜索」按钮）。
  Future<void> rescan() async {
    await _discovery?.scan();
  }

  void _onScanStateChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  // ---------------------------------------------------------------- 发送

  Future<void> _sendQueue = Future<void>.value();

  /// 当前传输速度（字节/秒），没在传或还没采到样本时返回 null。
  double? speedOf(String messageId) {
    final bps = _speed[messageId]?.bps;
    return (bps == null || bps <= 0) ? null : bps;
  }

  /// 发一条文本消息（链接、验证码、地址）。
  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final peer = activePeer;
    if (peer == null) {
      throw TransferException('请先在上方选择接收设备');
    }

    final message = ChatMessage(
      id: const Uuid().v4(),
      peerId: peer.id,
      peerAlias: peer.alias,
      direction: MessageDirection.outgoing,
      kind: MessageKind.text,
      text: trimmed,
      fileName: '文本消息',
      fileSize: utf8.encode(trimmed).length,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: MessageStatus.transferring,
    );
    messages.add(message);
    notifyListeners();

    try {
      await _client.sendText(
        peer: peer,
        text: trimmed,
        messageId: message.id,
        senderAlias: identity.alias,
        senderId: identity.id,
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
      unawaited(_store.save(messages));
    }
  }

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

    // 文本消息：按原内容重发，不新建一条
    if (message.isText) {
      final text = message.text;
      if (text == null || text.isEmpty) return;
      PeerDevice? target;
      for (final p in peers) {
        if (p.id == message.peerId) {
          target = p;
          break;
        }
      }
      if (target == null) {
        _replaceMessage(
          message.id,
          (m) => m.copyWith(error: '对方已不在线，请重新选择设备'),
        );
        return;
      }
      _replaceMessage(
        message.id,
        (m) => m.copyWith(status: MessageStatus.transferring, error: ''),
      );
      try {
        await _client.sendText(
          peer: target,
          text: text,
          messageId: message.id,
          senderAlias: identity.alias,
          senderId: identity.id,
        );
        _replaceMessage(
          message.id,
          (m) => m.copyWith(status: MessageStatus.success),
        );
      } catch (e) {
        _replaceMessage(
          message.id,
          (m) => m.copyWith(
            status: MessageStatus.failed,
            error: e is TransferException ? e.message : '$e',
          ),
        );
      }
      unawaited(_store.save(messages));
      return;
    }

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
    // 文本消息到手即完成，不计入活跃传输，避免 wakelock 永远不释放
    if (!message.isText) _beginTransfer();
    notifyListeners();
    unawaited(_store.save(messages));
  }

  void _onProgress(String id, double progress) {
    final clamped = progress.clamp(0.0, 1.0);
    final index = messages.indexWhere((m) => m.id == id);
    if (index >= 0 && messages[index].fileSize > 0) {
      final size = messages[index].fileSize;
      _speed.putIfAbsent(id, () => _SpeedMeter()).update(
            (clamped * size).round(),
          );
    }
    _replaceMessage(
      id,
      (m) => m.copyWith(
        progress: clamped,
        status: m.isDone ? MessageStatus.success : MessageStatus.transferring,
      ),
      throttle: true,
    );
  }

  void _onCompleted(String id, String path, int size) {
    _speed.remove(id);
    unawaited(_maybeSaveToGallery(path));
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
    _speed.remove(id);
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

  /// 收到的图片/视频自动写进系统相册。开关关着就直接返回，零开销。
  Future<void> _maybeSaveToGallery(String path) async {
    if (!AppSettings.instance.autoSavePhotos) return;
    final dot = path.lastIndexOf('.');
    if (dot < 0) return;
    final ext = path.substring(dot + 1).toLowerCase();
    const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp'};
    const videos = {'mp4', 'mov', 'm4v', '3gp', 'mkv', 'avi'};
    final isImage = images.contains(ext);
    final isVideo = videos.contains(ext);
    if (!isImage && !isVideo) return;

    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) return;
      }
      if (isImage) {
        await Gal.putImage(path);
      } else {
        await Gal.putVideo(path);
      }
    } catch (_) {
      // 没授权、相册写不进去都不该影响接收本身
    }
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

  /// 清掉单条聊天记录。只动记录，不删文件——
  /// 发送方的源文件在用户自己的相册/文件里，接收方的文件由「管理文件」页负责删。
  Future<void> deleteMessage(String id) async {
    _speed.remove(id);
    final before = messages.length;
    messages.removeWhere((m) => m.id == id);
    if (messages.length == before) return;
    notifyListeners();
    await _store.save(messages);
  }

  Future<void> clearHistory() async {
    messages.clear();
    notifyListeners();
    await _store.save(messages);
  }

  @override
  void dispose() {
    _disposed = true;
    _discovery?.scanning.removeListener(_onScanStateChanged);
    _peerSub?.cancel();
    _discovery?.dispose();
    _server?.stop();
    super.dispose();
  }
}

/// 指数滑动平均的速度采样：单次抖动不会让「MB/s」乱跳。
class _SpeedMeter {
  int _lastBytes = 0;
  int _lastMs = 0;
  double bps = 0;

  void update(int bytes) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastMs == 0) {
      _lastBytes = bytes;
      _lastMs = now;
      return;
    }
    final seconds = (now - _lastMs) / 1000.0;
    if (seconds < 0.15) return;
    final delta = bytes - _lastBytes;
    if (delta < 0) {
      _lastBytes = bytes;
      _lastMs = now;
      return;
    }
    final instant = delta / seconds;
    bps = bps <= 0 ? instant : bps * 0.65 + instant * 0.35;
    _lastBytes = bytes;
    _lastMs = now;
  }
}
