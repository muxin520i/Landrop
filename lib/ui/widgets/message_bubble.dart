import 'package:flutter/material.dart';

import '../../core/models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onTap,
    this.onLongPress,
    this.speedBps,
  });

  final ChatMessage message;
  final VoidCallback onTap;

  /// 长按回调，带上手指位置——用来把操作浮层弹在消息旁边。
  final void Function(Offset globalPosition)? onLongPress;

  /// 当前传输速度（字节/秒），仅文件传输中有值。
  final double? speedBps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final outgoing = message.isOutgoing;
    final isLight = theme.brightness == Brightness.light;

    final bubbleColor = outgoing
        ? scheme.primary
        : (isLight ? Colors.white : scheme.surfaceContainerHigh);
    final fgColor = outgoing ? scheme.onPrimary : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment:
            outgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!outgoing) ...[
            _PeerAvatar(platform: message.peerId, color: scheme.primary),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onTap: onTap,
              onLongPressStart: onLongPress == null
                  ? null
                  : (details) => onLongPress!(details.globalPosition),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                padding: EdgeInsets.fromLTRB(
                  13,
                  message.isText ? 10 : 11,
                  13,
                  message.isText ? 10 : 11,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(outgoing ? 16 : 5),
                    bottomRight: Radius.circular(outgoing ? 5 : 16),
                  ),
                  boxShadow: outgoing
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(isLight ? 0.05 : 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.isText)
                      Text(
                        message.text ?? '',
                        maxLines: 12,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fgColor,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _iconFor(message.fileName),
                            size: 19,
                            color: fgColor.withOpacity(0.75),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              message.fileName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: fgColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    SizedBox(height: message.isText ? 5 : 8),
                    _StatusLine(
                      message: message,
                      fgColor: fgColor,
                      speedBps: speedBps,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (outgoing) ...[
            const SizedBox(width: 8),
            _PeerAvatar(platform: 'me', color: scheme.primary),
          ],
        ],
      ),
    );
  }

  static IconData _iconFor(String name) {
    final ext = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'heic':
      case 'bmp':
        return Icons.image_outlined;
      case 'mp4':
      case 'mov':
      case 'mkv':
      case 'avi':
        return Icons.videocam_outlined;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'm4a':
        return Icons.audiotrack_outlined;
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip_outlined;
      case 'apk':
        return Icons.android_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.message,
    required this.fgColor,
    this.speedBps,
  });

  final ChatMessage message;
  final Color fgColor;
  final double? speedBps;

  @override
  Widget build(BuildContext context) {
    final muted = fgColor.withOpacity(0.75);
    final text = message.isText;

    switch (message.status) {
      case MessageStatus.transferring:
        if (text) {
          return Text(
            '发送中…',
            style: TextStyle(fontSize: 11, color: muted, height: 1.2),
          );
        }
        final percent = (message.progress * 100).toStringAsFixed(0);
        final speed = speedBps;
        final detail = _detail(speed);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 1),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: message.progress <= 0 ? null : message.progress,
                minHeight: 4,
                backgroundColor: fgColor.withOpacity(0.18),
                valueColor: AlwaysStoppedAnimation<Color>(
                  fgColor.withOpacity(0.85),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail == null
                  ? '$percent%  ·  ${formatBytes(message.fileSize)}'
                  : '$percent%  ·  $detail',
              style: TextStyle(fontSize: 11, color: muted, height: 1.2),
            ),
          ],
        );

      case MessageStatus.waiting:
        if (message.waitingWeb) {
          return Text(
            '等待电脑下载  ·  ${formatBytes(message.fileSize)}',
            style: TextStyle(fontSize: 11, color: muted, height: 1.2),
          );
        }
        return Text(
          text
              ? '发送中…'
              : '排队中  ·  ${formatBytes(message.fileSize)}',
          style: TextStyle(fontSize: 11, color: muted, height: 1.2),
        );

      case MessageStatus.success:
        if (text) {
          return Text(
            message.isOutgoing ? '已发送  ·  点击复制' : '已接收  ·  点击复制',
            style: TextStyle(fontSize: 11, color: muted, height: 1.2),
          );
        }
        final label = message.isOutgoing
            ? '已送达  ·  ${formatBytes(message.fileSize)}'
            : '已接收  ·  ${formatBytes(message.fileSize)}  ·  点击打开';
        return Text(
          label,
          style: TextStyle(fontSize: 11, color: muted, height: 1.2),
        );

      case MessageStatus.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.error?.isNotEmpty == true ? message.error! : '传输失败',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFFF8A80),
                height: 1.25,
              ),
            ),
            if (message.isOutgoing)
              Text(
                '点击重试',
                style: TextStyle(fontSize: 11, color: muted, height: 1.3),
              ),
          ],
        );
    }
  }

  /// 「3.2 MB/s · 剩余 12 秒」。速度还没采到样本时返回 null，只显示百分比。
  String? _detail(double? speed) {
    if (speed == null || speed <= 0) return null;
    final text = formatSpeed(speed);
    final remain = message.fileSize * (1 - message.progress);
    if (remain <= 0) return text;
    final seconds = remain / speed;
    if (seconds.isNaN || seconds.isInfinite || seconds > 7200) return text;
    if (seconds < 1) return '$text  ·  即将完成';
    if (seconds < 60) return '$text  ·  剩余 ${seconds.round()} 秒';
    final m = seconds ~/ 60;
    final s = (seconds % 60).round();
    return '$text  ·  剩余 $m 分 $s 秒';
  }
}

class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({required this.platform, required this.color});

  final String platform;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        platform == 'me' ? Icons.person_outline : Icons.smartphone,
        size: 17,
        color: color,
      ),
    );
  }
}
