enum MessageRole { user, assistant }

enum MessageStatus {
  sending,
  sent,
  failed,
  cancelled,
}

class Message {
  const Message({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.sent,
    this.imageUrl,
    this.imagePrompt,
    this.originalPrompt,
    this.alternatives = const <String>[],
  });

  final String id;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final MessageStatus status;
  final String? imageUrl;
  final String? imagePrompt;

  /// 用户最初输入的原文 prompt（区别于 [imagePrompt] 润色/翻译后的版本）。
  /// 仅在图片消息里使用；为空时 UI 退回到 [imagePrompt] 展示。
  final String? originalPrompt;
  final List<String> alternatives;

  bool get isImageMessage => imageUrl != null && imageUrl!.isNotEmpty;

  factory Message.fromJson(Map<String, dynamic> json) {
    final roleText = (json['role'] ?? '').toString();
    final statusText = (json['status'] ?? '').toString();
    final imageUrlRaw = (json['imageUrl'] ?? '').toString();
    final imagePromptRaw = (json['imagePrompt'] ?? '').toString();
    final originalPromptRaw = (json['originalPrompt'] ?? '').toString();
    return Message(
      id: (json['id'] ?? '').toString(),
      role: roleText == MessageRole.assistant.name
          ? MessageRole.assistant
          : MessageRole.user,
      content: (json['content'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(
            (json['createdAtMs'] is num)
                ? (json['createdAtMs'] as num).toInt()
                : 0,
          ),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == statusText,
        orElse: () => MessageStatus.sent,
      ),
      imageUrl: imageUrlRaw.isEmpty ? null : imageUrlRaw,
      imagePrompt: imagePromptRaw.isEmpty ? null : imagePromptRaw,
      originalPrompt: originalPromptRaw.isEmpty ? null : originalPromptRaw,
      alternatives: (json['alternatives'] as List?)
              ?.map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'role': role.name,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'createdAtMs': createdAt.millisecondsSinceEpoch,
      'status': status.name,
    };
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      json['imageUrl'] = imageUrl;
    }
    if (imagePrompt != null && imagePrompt!.isNotEmpty) {
      json['imagePrompt'] = imagePrompt;
    }
    if (originalPrompt != null && originalPrompt!.isNotEmpty) {
      json['originalPrompt'] = originalPrompt;
    }
    if (alternatives.isNotEmpty) json['alternatives'] = alternatives;
    return json;
  }

  Message copyWith({
    String? content,
    MessageStatus? status,
    List<String>? alternatives,
  }) {
    return Message(
      id: id,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      status: status ?? this.status,
      imageUrl: imageUrl,
      imagePrompt: imagePrompt,
      originalPrompt: originalPrompt,
      alternatives: alternatives ?? this.alternatives,
    );
  }
}
