import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';

void main() {
  group('ContactCategory', () {
    test('包含三种类型', () {
      expect(ContactCategory.values.length, 3);
      expect(ContactCategory.values, contains(ContactCategory.contact));
      expect(ContactCategory.values, contains(ContactCategory.story));
      expect(ContactCategory.values, contains(ContactCategory.assistant));
    });
  });

  group('Contact', () {
    test('构造函数设置必填字段', () {
      final contact = Contact(
        id: 'test-1',
        name: '测试角色',
        avatar: '🤖',
        createdAt: DateTime(2024),
      );

      expect(contact.id, 'test-1');
      expect(contact.name, '测试角色');
      expect(contact.avatar, '🤖');
      expect(contact.category, ContactCategory.contact);
    });

    test('默认 category 为 contact', () {
      final contact = Contact(
        id: 'c1',
        name: 'A',
        avatar: 'A',
        createdAt: DateTime.now(),
      );

      expect(contact.category, ContactCategory.contact);
    });

    test('story 类型', () {
      final contact = Contact(
        id: 's1',
        name: 'Story',
        avatar: '📖',
        category: ContactCategory.story,
        createdAt: DateTime.now(),
      );

      expect(contact.category, ContactCategory.story);
    });

    test('assistant 类型', () {
      final contact = Contact(
        id: 'a1',
        name: 'Assistant',
        avatar: '🔧',
        category: ContactCategory.assistant,
        createdAt: DateTime.now(),
      );

      expect(contact.category, ContactCategory.assistant);
    });

    test('toJson/fromJson 往返序列化', () {
      final original = Contact(
        id: 'c1',
        name: '测试',
        avatar: '😊',
        category: ContactCategory.story,
        fixedInput: '固定输入',
        currentStates: {'mood': 'happy'},
        personality: ['温柔'],
        createdAt: DateTime(2024),
      );

      final json = original.toJson();
      final restored = Contact.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.avatar, original.avatar);
      expect(restored.category, original.category);
      expect(restored.fixedInput, original.fixedInput);
      expect(restored.currentStates, original.currentStates);
      expect(restored.personality, original.personality);
    });

    test('deepCopy 创建独立副本', () {
      final contact = Contact(
        id: 'c1',
        name: 'Test',
        avatar: 'A',
        currentStates: {'key': 'value'},
        createdAt: DateTime.now(),
      );

      final copy = contact.deepCopy();
      expect(copy.id, contact.id);
      expect(copy.name, contact.name);

      // 修改副本不影响原件
      copy.currentStates['key'] = 'changed';
      expect(contact.currentStates['key'], 'value');
    });
  });

  group('EventGraphMemory', () {
    test('默认构造包含三个空队列', () {
      const graph = EventGraphMemory();
      expect(graph.shortTermQueue, isEmpty);
      expect(graph.longTermQueue, isEmpty);
      expect(graph.ultraLongTermQueue, isEmpty);
    });

    test('copyWith 保留未指定字段', () {
      const graph = EventGraphMemory(turnCount: 5);
      final modified = graph.copyWith(turnCount: 10);
      expect(modified.turnCount, 10);
      expect(modified.shortTermQueue, isEmpty);
    });
  });
}
