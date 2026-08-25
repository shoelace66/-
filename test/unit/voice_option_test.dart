import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';

void main() {
  group('VoiceOption', () {
    test('presets 至少包含若干常见音色', () {
      expect(VoiceOption.presets, isNotEmpty);
      expect(
        VoiceOption.presets.any((v) => v.id == 'zh-CN-XiaoxiaoNeural'),
        isTrue,
      );
    });

    test('findById 找到已注册音色', () {
      final v = VoiceOption.findById('zh-CN-XiaoxiaoNeural');
      expect(v, isNotNull);
      expect(v!.label, contains('晓晓'));
    });

    test('findById 对空 / 未知 id 返回 null', () {
      expect(VoiceOption.findById(null), isNull);
      expect(VoiceOption.findById(''), isNull);
      expect(VoiceOption.findById('not-exists'), isNull);
    });

    test('fallback 不为空', () {
      expect(VoiceOption.fallback.id, isNotEmpty);
    });
  });

  group('Contact.voice', () {
    test('默认值为空字符串', () {
      final c = Contact(
        id: 'c1',
        name: 'A',
        avatar: 'A',
        createdAt: DateTime.now(),
      );
      expect(c.voice, '');
    });

    test('toJson 不写入空 voice', () {
      final c = Contact(
        id: 'c1',
        name: 'A',
        avatar: 'A',
        createdAt: DateTime.now(),
      );
      expect(c.toJson().containsKey('voice'), isFalse);
    });

    test('toJson 在 voice 非空时写入', () {
      final c = Contact(
        id: 'c1',
        name: 'A',
        avatar: 'A',
        voice: 'zh-CN-XiaoxiaoNeural',
        createdAt: DateTime.now(),
      );
      expect(c.toJson()['voice'], 'zh-CN-XiaoxiaoNeural');
    });

    test('toJson/fromJson 往返保留 voice', () {
      final c = Contact(
        id: 'c1',
        name: 'A',
        avatar: 'A',
        voice: 'zh-CN-YunxiNeural',
        createdAt: DateTime.now(),
      );
      final restored = Contact.fromJson(c.toJson());
      expect(restored.voice, 'zh-CN-YunxiNeural');
    });

    test('fromJson 在缺 voice 字段时不抛错', () {
      final restored = Contact.fromJson(<String, dynamic>{
        'id': 'c1',
        'name': 'A',
        'avatar': 'A',
        'createdAt': DateTime.now().toIso8601String(),
      });
      expect(restored.voice, '');
    });

    test('deepCopy 保留 voice', () {
      final c = Contact(
        id: 'c1',
        name: 'A',
        avatar: 'A',
        voice: 'en-US-JennyNeural',
        createdAt: DateTime.now(),
      );
      expect(c.deepCopy().voice, 'en-US-JennyNeural');
    });
  });
}
