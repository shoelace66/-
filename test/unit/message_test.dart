import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/features/chat/data/models/message.dart';

void main() {
  group('Message.isImageMessage', () {
    test('普通消息不算图片消息', () {
      final m = Message(
        id: 'm1',
        role: MessageRole.assistant,
        content: '你好',
        createdAt: DateTime(2024),
      );
      expect(m.isImageMessage, isFalse);
    });

    test('imageUrl 非空时算图片消息', () {
      final m = Message(
        id: 'm1',
        role: MessageRole.assistant,
        content: '描述',
        createdAt: DateTime(2024),
        imageUrl: 'https://example.com/a.png',
        imagePrompt: '描述',
      );
      expect(m.isImageMessage, isTrue);
    });

    test('imageUrl 为空字符串时不算图片消息', () {
      final m = Message(
        id: 'm1',
        role: MessageRole.assistant,
        content: '描述',
        createdAt: DateTime(2024),
        imageUrl: '',
      );
      expect(m.isImageMessage, isFalse);
    });
  });

  group('Message toJson/fromJson', () {
    test('图片消息往返保留 imageUrl/imagePrompt', () {
      final m = Message(
        id: 'm1',
        role: MessageRole.assistant,
        content: '夕阳',
        createdAt: DateTime(2024),
        imageUrl: 'https://example.com/a.png',
        imagePrompt: '夕阳下的城市',
      );
      final restored = Message.fromJson(m.toJson());
      expect(restored.imageUrl, 'https://example.com/a.png');
      expect(restored.imagePrompt, '夕阳下的城市');
    });

    test('普通消息往返不写入 imageUrl/imagePrompt', () {
      final m = Message(
        id: 'm1',
        role: MessageRole.assistant,
        content: '你好',
        createdAt: DateTime(2024),
      );
      final json = m.toJson();
      expect(json.containsKey('imageUrl'), isFalse);
      expect(json.containsKey('imagePrompt'), isFalse);
    });

    test('fromJson 在缺 imageUrl/imagePrompt 时使用 null', () {
      final restored = Message.fromJson(<String, dynamic>{
        'id': 'm1',
        'role': 'assistant',
        'content': 'hi',
        'createdAt': DateTime(2024).toIso8601String(),
        'status': 'sent',
      });
      expect(restored.imageUrl, isNull);
      expect(restored.imagePrompt, isNull);
      expect(restored.isImageMessage, isFalse);
    });

    test('copyWith 不影响 imageUrl/imagePrompt', () {
      final m = Message(
        id: 'm1',
        role: MessageRole.assistant,
        content: 'hi',
        createdAt: DateTime(2024),
        imageUrl: 'https://x',
        imagePrompt: 'p',
      );
      final updated = m.copyWith(status: MessageStatus.failed);
      expect(updated.status, MessageStatus.failed);
      expect(updated.imageUrl, 'https://x');
      expect(updated.imagePrompt, 'p');
    });
  });

  group('Message.originalPrompt（图片消息的原文 prompt）', () {
    test('图片消息往返保留 originalPrompt', () {
      final m = Message(
        id: 'm1',
        role: MessageRole.assistant,
        content: 'cinematic sunset',
        createdAt: DateTime(2024),
        imageUrl: 'https://x.png',
        imagePrompt: 'cinematic sunset, warm light',
        originalPrompt: '夕阳下的城市',
      );
      final restored = Message.fromJson(m.toJson());
      expect(restored.originalPrompt, '夕阳下的城市');
      expect(restored.imagePrompt, 'cinematic sunset, warm light');
    });

    test('未设置 originalPrompt 时 toJson 不写入字段', () {
      final m = Message(
        id: 'm1',
        role: MessageRole.assistant,
        content: 'x',
        createdAt: DateTime(2024),
        imagePrompt: 'x',
      );
      final json = m.toJson();
      expect(json.containsKey('originalPrompt'), isFalse);
    });

    test('fromJson 在缺 originalPrompt 时使用 null', () {
      final restored = Message.fromJson(<String, dynamic>{
        'id': 'm1',
        'role': 'assistant',
        'content': 'x',
        'createdAt': DateTime(2024).toIso8601String(),
        'status': 'sent',
        'imagePrompt': 'x',
      });
      expect(restored.originalPrompt, isNull);
    });
  });
}
