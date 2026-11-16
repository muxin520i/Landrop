

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/models/chat_message.dart';
import '../state/app_state.dart';
import 'manual_connect_sheet.dart';
import 'my_qr_sheet.dart';
import 'scan_page.dart';
import 'widgets/device_bar.dart';
import 'widgets/message_bubble.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ScrollController _scrollController = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
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
    if (!app.initialized) return const _BootScreen();

    if (app.messages.length != _lastCount) {
      _lastCount = app.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    final scheme = Theme.of(context).colorScheme;
    final online = app.peers.where((p) => p.isOnline).length;

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
              app.peers.isEmpty
                  ? '正在搜索附近设备…'
                  : (online == 0 ? '设备已离线' : '$online 台设备在线'),
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
            tooltip: '我的连接码',
            icon: const Icon(Icons.qr_code_2_rounded),
            onPressed: () => showMyQrSheet(context),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) => _onMenu(value, app),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'scan', child: Text('扫码连接')),
              PopupMenuItem(value: 'manual', child: Text('手动输入 IP')),
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
            onScan: () => _openScan(app),
          ),
          Expanded(
            child: app.messages.isEmpty
                ? _EmptyState(
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
        peer == null ? '未发现设备，点击二维码扫码连接' : '发送到 ${peer.alias}';
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
              child: GestureDetector(
                onTap: _pickAndSend,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: peer == null
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _CircleButton(
              icon: Icons.arrow_upward_rounded,
              background:
                  canSend ? scheme.primary : scheme.surfaceContainerHighest,
              foreground: canSend
                  ? scheme.onPrimary
                  : scheme.onSurfaceVariant.withOpacity(0.45),
              onTap: _pickAndSend,
            ),
          ],
        ),
      ),
    );
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
    if (!message.isDone) return;

    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? Rect.zero : box.localToGlobal(Offset.zero) & box.size;
    final error = await app.openMessage(message, origin);
    if (error != null) _snack(error);
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
      case 'scan':
        await _openScan(app);
      case 'manual':
        await showManualConnectSheet(context, app);
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

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.primary.withOpacity(0.65)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.swap_horiz_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '近传',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onScan, required this.onQr});

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
              '同一 Wi-Fi 下自动发现',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '让对方也打开「近传」，\n设备会出现在上方，选中后即可发送文件。',
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
