import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 接收目录：与 [TransferServer] 的落盘位置保持一致。
///
/// Android 走 App 专属外部存储（文件管理器里能看到），
/// iOS 走沙盒 Documents（已开启文件共享，可在「文件」App 里看到）。
Future<Directory> receiveDir() async {
  Directory base;
  if (Platform.isAndroid) {
    base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
  } else {
    base = await getApplicationDocumentsDirectory();
  }
  final dir = Directory('${base.path}/Received');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

class ReceivedFile {
  ReceivedFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modified;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  }
}

/// 已接收完成的文件，按修改时间倒序。未完成的 `.xxx.part` 不列出。
Future<List<ReceivedFile>> listReceivedFiles({Directory? dir}) async {
  final List<ReceivedFile> out = [];
  try {
    final target = dir ?? await receiveDir();
    await for (final entity in target.list()) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.') && name.endsWith('.part')) continue;
      try {
        final stat = await entity.stat();
        out.add(ReceivedFile(
          path: entity.path,
          name: name,
          size: stat.size,
          modified: stat.modified,
        ));
      } catch (_) {
        // 单个文件读不到就跳过，不影响整页
      }
    }
  } catch (_) {
    // 目录还建不出来时按空列表处理
  }
  out.sort((a, b) => b.modified.compareTo(a.modified));
  return out;
}

/// 直接删掉磁盘上的文件。返回是否删成功。
Future<bool> deleteReceivedFile(ReceivedFile file) async {
  try {
    final f = File(file.path);
    if (await f.exists()) {
      await f.delete();
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// 清空接收目录下所有已完成文件，返回删除成功的数量。
Future<int> deleteAllReceivedFiles() async {
  final files = await listReceivedFiles();
  var removed = 0;
  for (final f in files) {
    if (await deleteReceivedFile(f)) removed++;
  }
  return removed;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = bytes / 1024;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unit]}';
}
