import 'package:flutter/material.dart';

import '../../data/models/message.dart';
import 'message_bubble.dart';

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.controller,
    required this.isTyping,
    required this.hasOlderMessages,
    required this.isLoadingOlderMessages,
    required this.totalMessageCount,
    required this.canRegenerateLastTurn,
    required this.onLoadOlder,
    required this.onRetry,
    required this.onGenerateImage,
    required this.onRegenerate,
    required this.canCreateBranch,
    required this.onCreateBranch,
    required this.onSpeak,
    required this.onStopSpeak,
    required this.isSpeaking,
    required this.onEdit,
    required this.onDelete,
    required this.onQuote,
    required this.onGenerateCandidate,
    required this.onShowCandidates,
    this.assistantLabel,
  });

  final List<Message> messages;
  final ScrollController controller;
  final bool isTyping;
  final bool hasOlderMessages;
  final bool isLoadingOlderMessages;
  final int totalMessageCount;
  final bool canRegenerateLastTurn;
  final VoidCallback onLoadOlder;
  final ValueChanged<Message> onRetry;
  final ValueChanged<Message> onGenerateImage;
  final VoidCallback onRegenerate;
  final bool Function(Message) canCreateBranch;
  final ValueChanged<Message> onCreateBranch;
  final ValueChanged<Message> onSpeak;
  final VoidCallback onStopSpeak;
  final bool Function(Message) isSpeaking;
  final ValueChanged<Message> onEdit;
  final ValueChanged<Message> onDelete;
  final ValueChanged<Message> onQuote;
  final ValueChanged<Message> onGenerateCandidate;
  final ValueChanged<Message> onShowCandidates;
  final String? assistantLabel;

  @override
  Widget build(BuildContext context) {
    final entries = _entries(messages);
    final historyOffset = hasOlderMessages ? 1 : 0;
    final latestAssistantId = messages.reversed
        .where((message) =>
            message.role == MessageRole.assistant && !message.isImageMessage)
        .firstOrNull
        ?.id;
    return ListView.builder(
      key: const PageStorageKey<String>('chat-message-list'),
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      cacheExtent: 900,
      addAutomaticKeepAlives: false,
      itemCount: historyOffset + entries.length + (isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (historyOffset == 1 && index == 0) {
          return Center(
            child: TextButton.icon(
              key: const ValueKey('load-older-messages'),
              onPressed: isLoadingOlderMessages ? null : onLoadOlder,
              icon: isLoadingOlderMessages
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_less),
              label: Text(
                isLoadingOlderMessages
                    ? '正在加载更早消息…'
                    : '加载更早消息（已显示 ${messages.length}/$totalMessageCount）',
              ),
            ),
          );
        }
        final messageIndex = index - historyOffset;
        if (isTyping && messageIndex == entries.length) {
          return const TypingBubble(key: ValueKey('typing-bubble'));
        }
        final entry = entries[messageIndex];
        final message = entry.message;
        return RepaintBoundary(
          key: ValueKey('${message.id}-${entry.image ? "image" : "text"}'),
          child: entry.image
              ? ImageMessageBubble(message: message)
              : MessageBubble(
                  message: message,
                  onRetry: () => onRetry(message),
                  onGenerateImage: () => onGenerateImage(message),
                  onRegenerate:
                      canRegenerateLastTurn && message.id == latestAssistantId
                          ? onRegenerate
                          : null,
                  onCreateBranch: canCreateBranch(message)
                      ? () => onCreateBranch(message)
                      : null,
                  onSpeak: () => onSpeak(message),
                  onStopSpeak: onStopSpeak,
                  isSpeaking: isSpeaking(message),
                  onEdit: () => onEdit(message),
                  onDelete: () => onDelete(message),
                  onQuote: () => onQuote(message),
                  onGenerateCandidate: () => onGenerateCandidate(message),
                  authorLabel: message.role == MessageRole.assistant
                      ? assistantLabel
                      : null,
                  onShowCandidates: message.alternatives.isEmpty
                      ? null
                      : () => onShowCandidates(message),
                ),
        );
      },
    );
  }
}

List<_MessageEntry> _entries(List<Message> messages) {
  return <_MessageEntry>[
    for (final message in messages) ...[
      _MessageEntry(message, image: false),
      if (message.isImageMessage) _MessageEntry(message, image: true),
    ],
  ];
}

class _MessageEntry {
  const _MessageEntry(this.message, {required this.image});

  final Message message;
  final bool image;
}
