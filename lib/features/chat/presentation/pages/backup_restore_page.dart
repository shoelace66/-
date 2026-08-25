import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/providers/chat_provider.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key, required this.provider});

  final ChatProvider provider;

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final TextEditingController _importController = TextEditingController();
  bool _restoring = false;

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  Future<void> _copyBackup() async {
    final backup = await widget.provider.exportBackupJson();
    await Clipboard.setData(ClipboardData(text: backup));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('备份已复制（${backup.length} 个字符）')),
    );
  }

  Future<void> _pasteBackup() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    _importController.text = data!.text!;
  }

  Future<void> _restore() async {
    final source = _importController.text.trim();
    if (source.isEmpty || _restoring) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('覆盖本地角色与对话？'),
        content: const Text(
          '恢复会用备份中的角色、消息和记忆完整替换当前数据。API、模型与应用设置不会改变。建议先复制一份当前备份。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _restoring = true);
    final ok = await widget.provider.restoreBackupJson(source);
    if (!mounted) return;
    setState(() => _restoring = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '备份恢复完成' : '备份无效或恢复失败')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '备份包含角色卡、全部消息、三级事件与关系图；不包含 API 密钥、模型配置和应用设置。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _copyBackup,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('复制完整备份到剪贴板'),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  '从备份恢复',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: _pasteBackup,
                icon: const Icon(Icons.content_paste),
                label: const Text('粘贴'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _importController,
            minLines: 8,
            maxLines: 16,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: '粘贴 ai-roleplay-chat-backup JSON',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _restoring ? null : _restore,
            icon: _restoring
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restore),
            label: Text(_restoring ? '正在恢复…' : '校验并恢复备份'),
          ),
        ],
      ),
    );
  }
}
