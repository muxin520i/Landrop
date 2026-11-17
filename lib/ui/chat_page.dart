

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/models/chat_message.dart';
import '../state/app_state.dart';
import 'files_page.dart';
import 'manual_connect_sheet.dart';
import 'my_qr_sheet.dart';
import 'scan_page.dart';
import 'settings_page.dart';
import 'widgets/device_bar.dart';
import 'widgets/message_bubble.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _input = TextEditingController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    _input.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (app.messages.length != _lastCount) {
      _lastCount = app.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    final scheme = Theme.of(context).colorScheme;
    final online = app.peers.where((p) => p.isOnline).length;
    final subtitle = app.scanning
        ? (app.peers.isEmpty
            ? '正在搜索附近设备…'
            : '正在搜索 · $online 台设备在线')
        : app.peers.isEmpty
            ? '未发现设备，点「搜索」'
            : online == 0
                ? '设备已离线，点「搜索」重试'
                : '$online 台设备在线';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('近传'),
            const SizedBox(height: 1),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w400,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '扫码连接',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => _openScan(app),
          ),
          IconButton(
            tooltip: '我的连接码',
            icon: const Icon(Icons.qr_code_2_rounded),
            onPressed: () => showMyQrSheet(context),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) => _onMenu(value, app),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('设置')),
              PopupMenuItem(value: 'manual', child: Text('手动输入 IP')),
              PopupMenuItem(value: 'files', child: Text('管理文件')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'clear', child: Text('清空记录')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          DeviceBar(
            peers: app.peers,
            activeId: app.activePeerId,
            onSelect: app.selectPeer,
            onSearch: () => _search(app),
            scanning: app.scanning,
          ),
          Expanded(
            child: !app.historyLoaded
                // 记录还在读，先留白：不要用「空状态」占位，否则会闪一下
                ? const SizedBox.expand()
                : app.messages.isEmpty
                    ? _EmptyState(
                        onSearch: () => _search(app),
                        scanning: app.scanning,
                        onScan: () => _openScan(app),
                        onQr: () => showMyQrSheet(context),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                        itemCount: app.messages.length,
                        itemBuilder: (context, index) {
                          final message = app.messages[index];
                          final prev =
                              index > 0 ? app.messages[index - 1] : null;
                          final showTime = prev == null ||
                              (message.timestamp - prev.timestamp).abs() >
                                  5 * 60 * 1000;
                          return Column(
                            children: [
                              if (showTime)
                                _TimeDivider(timestamp: message.timestamp),
                              MessageBubble(
                                message: message,
                                onTap: () => _onBubbleTap(app, message),
                                onLongPress: (pos) =>
                                    _onBubbleLongPress(app, message, pos),
                                speedBps: app.speedOf(message.id),
                              ),
                            ],
                          );
                        },
                      ),
          ),
          _buildComposer(app),
        ],
      ),
    );
  }

  Widget _buildComposer(AppState app) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final peer = app.activePeer;
    final hint =
        peer == null ? '未发现设备，先在上方点「搜索」' : '发送到 ${peer.alias}';
    final canSend = peer != null && peer.isOnline;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withOpacity(0.4),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            _CircleButton(
              icon: Icons.add_rounded,
              background: scheme.surfaceContainerHighest,
              foreground: scheme.onSurfaceVariant,
              onTap: _pickAndSend,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(app),
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: hint,
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant.withOpacity(0.85),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                final enabled = hasText || canSend;
                return _CircleButton(
                  icon: Icons.arrow_upward_rounded,
                  background:
                      enabled ? scheme.primary : scheme.surfaceContainerHighest,
                  foreground: enabled
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant.withOpacity(0.45),
                  onTap: () => _send(app),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 有文字就发文本，没文字就走选文件——和聊天 App 的输入框习惯一致。
  Future<void> _send(AppState app) async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      await _pickAndSend();
      return;
    }
    if (app.activePeer == null) {
      _snack('请先在上方选择接收设备');
      return;
    }
    _input.clear();
    try {
      await app.sendText(text);
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _pickAndSend() async {
    final app = context.read<AppState>();
    if (app.activePeer == null) {
      _snack('请先在上方选择接收设备');
      return;
    }

    final choice = await showModalBottomSheet<FileType>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                _PickerTile(
                  icon: Icons.insert_drive_file_rounded,
                  title: '选择文件',
                  subtitle: '任意类型，可多选',
                  onTap: () => Navigator.of(ctx).pop(FileType.any),
                ),
                const SizedBox(height: 8),
                _PickerTile(
                  icon: Icons.photo_library_rounded,
                  title: '照片或视频',
                  subtitle: '从相册选择，可多选',
                  onTap: () => Navigator.of(ctx).pop(FileType.media),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: choice,
        allowMultiple: true,
      );
    } catch (e) {
      _snack('打开选择器失败：$e');
      return;
    }
    if (result == null) return;

    final paths = result.paths.whereType<String>().toList();
    if (paths.isEmpty) {
      _snack('没有读取到文件，请重试');
      return;
    }

    try {
      await app.sendFiles(paths);
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _onBubbleTap(AppState app, ChatMessage message) async {
    if (message.isFailed && message.isOutgoing) {
      await app.retryMessage(message);
      return;
    }

    // 文本消息不做「打开」，点一下就是复制
    if (message.isText) {
      final text = message.text;
      if (text == null || text.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: text));
      _snack('已复制');
      return;
    }

    if (!message.isDone) return;

    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? Rect.zero : box.localToGlobal(Offset.zero) & box.size;
    final error = await app.openMessage(message, origin);
    if (error != null) _snack(error);
  }

  Future<void> _search(AppState app) async {
    if (app.scanning) return;
    await app.rescan();
  }

  /// 长按文件气泡：贴着消息弹一个小浮层，点「清除记录」就删掉这一条。
  /// 只删记录不删文件——发送方的源文件在用户自己的相册里，接收方的文件在「管理文件」页处理。
  Future<void> _onBubbleLongPress(
    AppState app,
    ChatMessage message,
    Offset globalPosition,
  ) async {
    if (message.status == MessageStatus.transferring ||
        message.status == MessageStatus.waiting) {
      _snack('传输还没结束，稍后再清除');
      return;
    }
    HapticFeedback.mediumImpact();

    final scheme = Theme.of(context).colorScheme;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final selected = await showMenu<String>(
      context: context,
      // 锚点就是手指按下的位置：菜单排在它下面，下方空间不够会自动翻到上面
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: scheme.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      constraints: const BoxConstraints(minWidth: 132),
      items: [
        if (message.isText)
          PopupMenuItem<String>(
            value: 'copy',
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.copy_rounded, size: 20, color: scheme.onSurface),
                const SizedBox(width: 10),
                Text(
                  '复制',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline_rounded, size: 20, color: scheme.error),
              const SizedBox(width: 10),
              Text(
                '清除记录',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (selected == 'copy') {
      final text = message.text;
      if (text != null && text.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: text));
        _snack('已复制');
      }
      return;
    }
    if (selected != 'delete') return;
    await app.deleteMessage(message.id);
    _snack('已清除这条记录');
  }

  Future<void> _openScan(AppState app) async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const ScanPage(),
        fullscreenDialog: true,
      ),
    );
    if (raw == null) return;
    final peer = app.addPeerFromQr(raw);
    if (peer == null) {
      _snack('二维码无法识别，请让对方显示「我的连接码」');
    } else {
      _snack('正在连接 ${peer.host}…');
    }
  }

  Future<void> _onMenu(String value, AppState app) async {
    switch (value) {
      case 'settings':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
      case 'manual':
        await showManualConnectSheet(context, app);
      case 'files':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FilesPage()),
        );
      case 'clear':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('清空记录'),
            content: const Text('只清除聊天记录，已接收的文件不会被删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('清空'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await app.clearHistory();
        }
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onSearch,
    required this.scanning,
    required this.onScan,
    required this.onQr,
  });

  final VoidCallback onSearch;
  final bool scanning;
  final VoidCallback onScan;
  final VoidCallback onQr;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary.withOpacity(0.16),
                    scheme.primary.withOpacity(0.03),
                  ],
                ),
              ),
              child: Icon(
                Icons.wifi_tethering_rounded,
                size: 42,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '同一 Wi-Fi 下互传文件',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '让对方也打开「近传」，点上方「搜索」，\n设备出现后选中即可发送文件。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.65,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '首次使用请在系统弹窗中允许「本地网络」\n传输时请让两台手机都停留在本界面',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.55,
                color: scheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: scanning ? null : onSearch,
                  icon: scanning
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              scheme.onPrimary,
                            ),
                          ),
                        )
                      : const Icon(Icons.radar_rounded, size: 18),
                  label: Text(scanning ? '搜索中…' : '搜索附近设备'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onScan,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: const Text('扫码连接'),
                ),
                OutlinedButton.icon(
                  onPressed: onQr,
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: const Text('我的连接码'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeDivider extends StatelessWidget {
  const _TimeDivider({required this.timestamp});

  final int timestamp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat('HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(timestamp));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          time,
          style: TextStyle(
            fontSize: 10.5,
            color: scheme.onSurfaceVariant,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: foreground, size: 22),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withOpacity(0.55),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
