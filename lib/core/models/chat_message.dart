enum MessageDirection { incoming, outgoing }

enum MessageStatus { waiting, transferring, success, failed }

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
    this.localPath,
    this.status = MessageStatus.waiting,
    this.progress = 0,
    this.error,
  });

  final String id;
  final String peerId;
  final String peerAlias;
  final MessageDirection direction;
  final String fileName;
  final int fileSize;

  /// 毫秒时间戳。
  final int timestamp;

  /// 落盘路径：发送方是源文件路径，接收方是保存后的路径。
  final String? localPath;

  final MessageStatus status;

  /// 0.0 ~ 1.0
  final double progress;

  final String? error;

  bool get isOutgoing => direction == MessageDirection.outgoing;

  bool get isDone => status == MessageStatus.success;

  bool get isFailed => status == MessageStatus.failed;

  ChatMessage copyWith({
    String? localPath,
    MessageStatus? status,
    double? progress,
    String? error,
    String? peerAlias,
  }) {
    return ChatMessage(
      id: id,
      peerId: peerId,
      peerAlias: peerAlias ?? this.peerAlias,
      direction: direction,
      fileName: fileName,
      fileSize: fileSize,
      timestamp: timestamp,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
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
        'localPath': localPath,
        'status': status.name,
        'progress': progress,
        'error': error,
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
      localPath: json['localPath'] as String?,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.failed,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      error: json['error'] as String?,
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
