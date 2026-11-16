import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/protocol.dart';
import '../state/app_state.dart';

/// 扫码之外的兜底入口：手动输入对方 IP。
Future<void> showManualConnectSheet(BuildContext context, AppState app) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ManualConnectSheet(app: app),
  );
}

class _ManualConnectSheet extends StatefulWidget {
  const _ManualConnectSheet({required this.app});

  final AppState app;

  @override
  State<_ManualConnectSheet> createState() => _ManualConnectSheetState();
}

class _ManualConnectSheetState extends State<_ManualConnectSheet> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    var raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请输入对方地址');
      return;
    }
    if (raw.startsWith('landrop://')) {
      final peer = widget.app.addPeerFromQr(raw);
      if (peer == null) {
        setState(() => _error = '地址格式不正确');
        return;
      }
      Navigator.of(context).pop();
      return;
    }

    var host = raw;
    var port = Protocol.transferPort;
    if (raw.contains(':')) {
      final parts = raw.split(':');
      host = parts[0];
      final parsed = int.tryParse(parts[1]);
      if (parsed != null) port = parsed;
    }
    host = host.replaceAll('http://', '').replaceAll('/', '');

    final valid = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
    if (!valid) {
      setState(() => _error = '格式不对，例如 192.168.1.5');
      return;
    }

    final peer = widget.app.addPeerFromQr(
      'landrop://connect?host=$host&port=$port',
    );
    if (peer == null) {
      setState(() => _error = '地址无法解析');
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        10,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '手动连接',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '输入对方设备「我的连接码」上方显示的地址',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9\.:]')),
            ],
            decoration: InputDecoration(
              hintText: '192.168.1.5',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              child: const Text('连接'),
            ),
          ),
        ],
      ),
    );
  }
}
