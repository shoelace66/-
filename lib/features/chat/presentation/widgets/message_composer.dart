import 'package:flutter/material.dart';

class MessageComposer extends StatelessWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.isGenerating,
    required this.canCancel,
    required this.onSend,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isGenerating;
  final bool canCancel;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = isGenerating ? onCancel : onSend;
    final actionEnabled = enabled && (!isGenerating || canCancel);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('message-composer-input'),
                controller: controller,
                enabled: enabled && !isGenerating,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (enabled && !isGenerating) onSend();
                },
                decoration: InputDecoration(
                  hintText: enabled ? '输入消息…' : '请先创建对象',
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                key: const ValueKey('message-composer-action'),
                onPressed: actionEnabled ? action : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: isGenerating
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                icon: Icon(isGenerating ? Icons.stop : Icons.send, size: 18),
                label: Text(isGenerating ? '停止' : '发送'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
