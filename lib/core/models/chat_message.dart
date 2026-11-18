enum MessageDirection { incoming, outgoing }

enum MessageStatus { waiting, transferring, success, failed }

/// 一条消息是文件还是纯文本（链接、验证码、地址等）。
enum MessageKind { file, text }

/// 聊天流里的一条文件消息。
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.peerId,
    required this.peerAlias,
    required this.direction,
    required this.fileName,
    required this.fileSize,
    required this.timestamp,
    this.kind = MessageKind.file,
    this.text,
    this.localPath,
    this.status = MessageStatus.waiting,
    this.progress = 0,
    this.error,
    this.waitingWeb = false,
  });

  final String id;
  final String peerId;
  final String peerAlias;
  final MessageDirection direction;
  final String fileName;
  final int fileSize;

  final MessageKind kind;

  /// 文本消息的正文，文件消息为 null。
  final String? text;

  /// 毫秒时间戳。
  final int timestamp;

  /// 落盘路径：发送方是源文件路径，接收方是保存后的路径。
  final String? localPath;

  final MessageStatus status;

  /// 0.0 ~ 1.0
  final double progress;

  final String? error;

  /// 发给「电脑网页」的文件：已放进待收队列，等网页那边点下载。
  final bool waitingWeb;

  bool get isOutgoing => direction == MessageDirection.outgoing;

  bool get isText => kind == MessageKind.text;

  bool get isDone => status == MessageStatus.success;

  bool get isFailed => status == MessageStatus.failed;

  ChatMessage copyWith({
    String? localPath,
    MessageStatus? status,
    double? progress,
    String? error,
    String? peerAlias,
    bool? waitingWeb,
  }) {
    return ChatMessage(
      id: id,
      peerId: peerId,
      peerAlias: peerAlias ?? this.peerAlias,
      direction: direction,
      fileName: fileName,
      fileSize: fileSize,
      timestamp: timestamp,
      kind: kind,
      text: text,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      waitingWeb: waitingWeb ?? this.waitingWeb,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'peerId': peerId,
        'peerAlias': peerAlias,
        'direction': direction.name,
        'fileName': fileName,
        'fileSize': fileSize,
        'timestamp': timestamp,
        'kind': kind.name,
        'text': text,
        'localPath': localPath,
        'status': status.name,
        'progress': progress,
        'error': error,
        'waitingWeb': waitingWeb,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      peerId: (json['peerId'] as String?) ?? '',
      peerAlias: (json['peerAlias'] as String?) ?? '',
      direction: MessageDirection.values.firstWhere(
        (e) => e.name == json['direction'],
        orElse: () => MessageDirection.incoming,
      ),
      fileName: (json['fileName'] as String?) ?? '未命名文件',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      kind: MessageKind.values.firstWhere(
        (e) => e.name == json['kind'],
        orElse: () => MessageKind.file,
      ),
      text: json['text'] as String?,
      localPath: json['localPath'] as String?,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.failed,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      error: json['error'] as String?,
      waitingWeb: (json['waitingWeb'] as bool?) ?? false,
    );
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond >= 1024 * 1024) {
    return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSecond >= 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }
  return '${bytesPerSecond.toStringAsFixed(0)} B/s';
}
