import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/update_checker.dart';
import '../state/app_state.dart';

/// 设置页：设备名称、接收图片视频自动存相册、版本检查。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final UpdateChecker _checker = const UpdateChecker();

  UpdateInfo? _info;
  bool _checking = true;
  bool _failed = false;

  bool get _hasUpdate => _info?.hasUpdate ?? false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (_checking && _info != null) return;
    setState(() {
      _checking = true;
      _failed = false;
    });
    final info = await _checker.fetchLatest();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _failed = info == null;
      if (info != null) _info = info;
    });
  }

  String get _statusText {
    if (_hasUpdate) return '发现新版本 ${_info!.latestVersion}，点击查看';
    if (_checking) return '正在检查更新…';
    if (_failed) return '检查失败，点击重试';
    return '已是最新版本';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        children: [
          const _SectionLabel('设备'),
          _Card(
            children: [
              ListTile(
                title: const Text('设备名称', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  app.identity.alias,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                  size: 20,
                ),
                onTap: () => _rename(context, app),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile.adaptive(
                value: app.autoSavePhotos,
                onChanged: (v) => app.setAutoSavePhotos(v),
                title: const Text('图片视频自动存相册', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  '收到的照片和视频直接写入系统相册，不用再手动保存',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _SectionLabel('关于'),
          _Card(
            children: [
              ListTile(
                title: Row(
                  children: [
                    const Text('版本', style: TextStyle(fontSize: 14)),
                    if (_hasUpdate) ...[
                      const SizedBox(width: 6),
                      _UpdateBadge(color: _accent),
                    ],
                  ],
                ),
                subtitle: Text(
                  _statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: _hasUpdate ? _accent : scheme.onSurfaceVariant,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_checking)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (_checking) const SizedBox(width: 8),
                    Text(
                      kAppVersion,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (_hasUpdate) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: _accent,
                      ),
                    ],
                  ],
                ),
                onTap: _checking
                    ? null
                    : (_hasUpdate ? _showUpdateDialog : _check),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '传输全程在局域网内直连，没有服务器中转，也没有账号。'
              '两台设备必须连同一个 Wi-Fi。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: scheme.onSurfaceVariant.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color get _accent => const Color(0xFFE8890C);

  Future<void> _showUpdateDialog() async {
    final info = _info;
    if (info == null) return;
    final notes = _plainNotes(info.notes);
    final scheme = Theme.of(context).colorScheme;

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 ${info.latestVersion}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '当前版本 ${info.currentVersion}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  notes.isEmpty ? '本次更新包含体验优化与问题修复，建议升级。' : notes,
                  style: const TextStyle(fontSize: 13, height: 1.65),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('以后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('去下载'),
          ),
        ],
      ),
    );

    if (go != true) return;
    final uri = Uri.parse(info.releaseUrl);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: info.releaseUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('打不开浏览器，下载链接已复制')),
    );
  }

  /// Release 说明是 Markdown，这里压成可读纯文本。
  String _plainNotes(String raw) {
    final lines = <String>[];
    for (final line in raw.split('\n')) {
      var text = line.trim();
      text = text.replaceAll(RegExp(r'^#{1,6}\s*'), '');
      text = text.replaceAll(RegExp(r'^[-*+]\s+'), '· ');
      text = text.replaceAll('**', '').replaceAll('`', '');
      text = text.replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\(([^)]*)\)'),
        (m) => (m.group(1) ?? '').isEmpty ? (m.group(2) ?? '') : m.group(1)!,
      );
      text = text.replaceAll(RegExp(r'^\|?[-:\s|]+\|?$'), '');
      if (text.isEmpty) continue;
      lines.add(text);
    }
    var result = lines.join('\n').trim();
    if (result.length > 600) result = '${result.substring(0, 600)}…';
    return result;
  }

  Future<void> _rename(BuildContext context, AppState app) async {
    final controller = TextEditingController(text: app.identity.alias);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设备名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(
            hintText: '例如：我的手机',
            helperText: '对方在设备列表里看到的就是这个名字',
            counterText: '',
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(''),
            child: const Text('恢复默认'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await app.renameDevice(name);
  }
}

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '可更新',
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withOpacity(0.5),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
