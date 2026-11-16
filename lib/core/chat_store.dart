import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models/chat_message.dart';

/// 聊天记录持久化：一个 JSON 文件，最多保留最近 300 条。
class ChatStore {
  static const int maxMessages = 300;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/chat_messages.json');
  }

  Future<List<ChatMessage>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ChatMessage> messages) async {
    try {
      final file = await _file();
      final trimmed = messages.length > maxMessages
          ? messages.sublist(messages.length - maxMessages)
          : messages;
      final json = jsonEncode(trimmed.map((e) => e.toJson()).toList());
      // 先写临时文件再 rename，避免传输中途被杀进程写坏记录
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // 记录持久化失败不应影响传输本身
    }
  }
}
