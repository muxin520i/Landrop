import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../core/received_files.dart';

/// 管理已接收的文件：查看、打开、删除。
class FilesPage extends StatefulWidget {
  const FilesPage({super.key});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  List<ReceivedFile>? _files;
  bool _busy = false;

  /// 多选模式：长按任意文件进入，标题栏变成「已选 N 项」。
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await listReceivedFiles();
    if (!mounted) return;
    setState(() => _files = files);
  }

  int get _totalBytes =>
      (_files ?? const <ReceivedFile>[]).fold(0, (sum, f) => sum + f.size);

  Rect _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return const Rect.fromLTWH(0, 0, 1, 1);
    final size = box.size;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 1,
      height: 1,
    );
  }

  Future<void> _open(ReceivedFile file) async {
    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: file.name,
        sharePositionOrigin: _shareOrigin(),
      );
    } catch (e) {
      _snack('打开失败：$e');
    }
  }

  Future<void> _delete(ReceivedFile file) async {
    final ok = await _confirm(
      '删除文件',
      '「${file.name}」会从本机磁盘上删掉，无法恢复。',
      '删除',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final done = await deleteReceivedFile(file);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (done) {
        _files = [...?_files?.where((e) => e.path != file.path)];
      }
    });
    _snack(done ? '已删除' : '删除失败，请重试');
  }

  Future<void> _clearAll() async {
    final count = _files?.length ?? 0;
    final ok = await _confirm(
      '清空全部',
      '将删除 $count 个文件，共 ${formatBytes(_totalBytes)}，无法恢复。',
      '全部删除',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final removed = await deleteAllReceivedFiles();
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    if (!mounted) return;
    _snack('已删除 $removed 个文件');
  }

  void _enterSelect(ReceivedFile file) {
    setState(() {
      _selecting = true;
      _selected.add(file.path);
    });
  }

  void _toggle(ReceivedFile file) {
    setState(() {
      if (!_selected.remove(file.path)) {
        _selected.add(file.path);
      }
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelectAll() {
    final all = _files ?? const <ReceivedFile>[];
    setState(() {
      if (_selected.length == all.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all.map((e) => e.path));
      }
    });
  }

  Future<void> _deleteSelected() async {
    final targets = (_files ?? const <ReceivedFile>[])
        .where((f) => _selected.contains(f.path))
        .toList();
    if (targets.isEmpty) return;

    final bytes = targets.fold<int>(0, (sum, f) => sum + f.size);
    final ok = await _confirm(
      '删除 ${targets.length} 个文件',
      '共 ${formatBytes(bytes)}，会从本机磁盘上删掉，无法恢复。',
      '删除',
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final paths = targets.map((f) => f.path).toSet();
    var removed = 0;
    for (final file in targets) {
      if (await deleteReceivedFile(file)) removed++;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selecting = false;
      _selected.clear();
      _files = _files?.where((f) => !paths.contains(f.path)).toList();
    });
    _snack('已删除 $removed 个文件');
  }

  Future<bool?> _confirm(String title, String content, String action) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    final scheme = Theme.of(context).colorScheme;

    final total = files?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                tooltip: '退出多选',
                icon: const Icon(Icons.close_rounded),
                onPressed: _exitSelect,
              )
            : null,
        title: Text(_selecting ? '已选 ${_selected.length} 项' : '管理文件'),
        actions: [
          if (_selecting)
            TextButton(
              onPressed: total == 0 ? null : _toggleSelectAll,
              child: Text(_selected.length == total ? '取消全选' : '全选'),
            ),
          if (!_selecting && total > 0)
            IconButton(
              tooltip: '清空全部',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _busy ? null : _clearAll,
            ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: (_selected.isEmpty || _busy)
                      ? null
                      : _deleteSelected,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  label: Text('删除 ${_selected.length} 个文件'),
                ),
              ),
            )
          : null,
      body: files == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : files.isEmpty
              ? const _EmptyFiles()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                    itemCount: files.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 2),
                          child: Text(
                            '${files.length} 个文件 · 共 ${formatBytes(_totalBytes)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }
                      final file = files[index - 1];
                      final selected = _selected.contains(file.path);
                      return _FileTile(
                        file: file,
                        selecting: _selecting,
                        selected: selected,
                        onTap: _selecting
                            ? () => _toggle(file)
                            : () => _open(file),
                        onLongPress: _selecting
                            ? () => _toggle(file)
                            : () => _enterSelect(file),
                        onDelete: (_busy || _selecting)
                            ? null
                            : () => _delete(file),
                      );
                    },
                  ),
                ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.onTap,
    required this.onDelete,
    required this.selecting,
    required this.selected,
    required this.onLongPress,
  });

  final ReceivedFile file;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool selecting;
  final bool selected;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat('MM-dd HH:mm').format(file.modified);

    return Material(
      color: selected
          ? scheme.primary.withOpacity(0.10)
          : scheme.surfaceContainerHighest.withOpacity(0.5),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.fromLTRB(selecting ? 8 : 12, 10, 4, 10),
          child: Row(
            children: [
              if (selecting) ...[
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 21,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 10),
              ],
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  _iconFor(file.extension),
                  color: scheme.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formatBytes(file.size)} · $time',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!selecting)
                IconButton(
                  tooltip: '删除',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: scheme.error,
                  ),
                  onPressed: onDelete,
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFiles extends StatelessWidget {
  const _EmptyFiles();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withOpacity(0.09),
            ),
            child: Icon(
              Icons.folder_open_rounded,
              size: 36,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '还没有接收过文件',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '收到的文件会出现在这里\n可以在这里直接删除',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconFor(String ext) {
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
    case 'webm':
      return Icons.movie_outlined;
    case 'mp3':
    case 'm4a':
    case 'wav':
    case 'flac':
    case 'aac':
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
      return Icons.android_rounded;
    case 'doc':
    case 'docx':
      return Icons.description_outlined;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return Icons.table_chart_outlined;
    case 'ppt':
    case 'pptx':
      return Icons.slideshow_outlined;
    case 'txt':
    case 'md':
      return Icons.article_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}
