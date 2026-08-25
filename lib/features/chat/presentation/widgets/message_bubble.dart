import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onGenerateImage,
    required this.onSpeak,
    required this.onStopSpeak,
    required this.isSpeaking,
    required this.onEdit,
    required this.onDelete,
    required this.onQuote,
    required this.onGenerateCandidate,
    required this.onShowCandidates,
    this.onRegenerate,
    this.onCreateBranch,
  });

  final Message message;
  final VoidCallback onRetry;
  final VoidCallback onGenerateImage;
  final VoidCallback? onRegenerate;
  final VoidCallback? onCreateBranch;
  final VoidCallback onSpeak;
  final VoidCallback onStopSpeak;
  final bool isSpeaking;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onQuote;
  final VoidCallback onGenerateCandidate;
  final VoidCallback? onShowCandidates;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final isDebug = message.content.startsWith('【调试信息】');
    final theme = Theme.of(context);
    return Semantics(
      label: '${isUser ? "用户" : "AI"}消息：${message.content}',
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isUser) const _Avatar(label: 'AI'),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: isDebug
                        ? Colors.amber.shade50
                        : isUser
                            ? message.status == MessageStatus.failed
                                ? Colors.red.shade50
                                : theme.colorScheme.primary
                                    .withValues(alpha: 0.15)
                            : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                  ),
                  child: GestureDetector(
                    onLongPress: () => _showActions(context, isUser, isDebug),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          message.content,
                          style: const TextStyle(fontSize: 15, height: 1.4),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _time(message.createdAt),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                            if (!isUser && !isDebug)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                onPressed: isSpeaking ? onStopSpeak : onSpeak,
                                tooltip: isSpeaking ? '停止朗读' : '朗读',
                                icon: Icon(
                                  isSpeaking
                                      ? Icons.stop_circle_outlined
                                      : Icons.volume_up_outlined,
                                  size: 18,
                                ),
                              ),
                            if (isUser) _MessageStatusIcon(message.status),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isUser) const _Avatar(label: '我'),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    bool isUser,
    bool isDebug,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: message.content));
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('文本已复制到剪贴板')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.format_quote_outlined),
              title: const Text('引用'),
              onTap: () {
                Navigator.pop(sheetContext);
                onQuote();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(sheetContext);
                onEdit();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_fix_high_outlined),
              title: const Text('生成候选回复'),
              onTap: () {
                Navigator.pop(sheetContext);
                onGenerateCandidate();
              },
            ),
            if (onShowCandidates != null)
              ListTile(
                leading: const Icon(Icons.library_books_outlined),
                title: Text('查看候选（${message.alternatives.length}）'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onShowCandidates!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              textColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              onTap: () {
                Navigator.pop(sheetContext);
                onDelete();
              },
            ),
            if (!isUser && !isDebug)
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('生成图片'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onGenerateImage();
                },
              ),
            if (onRegenerate != null)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('修改并重新生成'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onRegenerate!();
                },
              ),
            if (onCreateBranch != null)
              ListTile(
                leading: const Icon(Icons.call_split_outlined),
                title: const Text('从此处创建分支'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onCreateBranch!();
                },
              ),
            if (isUser)
              ListTile(
                leading: const Icon(Icons.replay_outlined),
                title: const Text('重发'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onRetry();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class ImageMessageBubble extends StatefulWidget {
  const ImageMessageBubble({super.key, required this.message});

  final Message message;

  @override
  State<ImageMessageBubble> createState() => _ImageMessageBubbleState();
}

class _ImageMessageBubbleState extends State<ImageMessageBubble> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final imageUrl = message.imageUrl;
    final polished = message.imagePrompt ?? message.content;
    final original = message.originalPrompt;
    final hasBoth =
        original != null && original.isNotEmpty && original != polished;
    return Align(
      alignment: message.role == MessageRole.user
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _ImagePlaceholder(prompt: polished),
                      )
                    : _ImagePlaceholder(prompt: polished),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _showOriginal && hasBoth ? original : polished,
                      maxLines: _showOriginal && hasBoth ? 6 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (hasBoth)
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _showOriginal = !_showOriginal),
                        icon: Icon(
                          _showOriginal ? Icons.arrow_back : Icons.translate,
                          size: 14,
                        ),
                        label: Text(
                          _showOriginal ? '查看英文 prompt' : '查看原文',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'AI 正在输入',
      liveRegion: true,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text('●  ●  ●'),
          ),
        ),
      ),
    );
  }
}

class AnimatedMessageBubble extends StatelessWidget {
  const AnimatedMessageBubble({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
}

class _MessageStatusIcon extends StatelessWidget {
  const _MessageStatusIcon(this.status);

  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      MessageStatus.sending => const Padding(
          padding: EdgeInsets.only(left: 8),
          child: SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      MessageStatus.sent => const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(Icons.check, size: 16),
        ),
      MessageStatus.failed => const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(Icons.error_outline, size: 16, color: Colors.red),
        ),
      MessageStatus.cancelled => const Padding(
          padding: EdgeInsets.only(left: 8),
          child:
              Icon(Icons.stop_circle_outlined, size: 16, color: Colors.orange),
        ),
    };
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        child: Text(
          '图片生成结果不可用\n$prompt',
          textAlign: TextAlign.center,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
      );
}

String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
