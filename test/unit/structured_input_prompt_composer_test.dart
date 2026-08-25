import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/data/models/app_settings.dart';
import 'package:flutter_chat_demo/core/utils/structured_input_prompt_composer.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/repositories/chat_repository.dart';

void main() {
  group('StructuredInputPromptComposer', () {
    test('结构化协议包含显式版本并位于 memoryPatch 之前', () {
      final composer = StructuredInputPromptComposer();
      final result = composer.composeSystemPromptWithContactObject(
        basePrompt: '',
        contact: Contact(
          id: 'role-protocol',
          name: '测试角色',
          avatar: '',
          createdAt: DateTime(2026),
        ),
      );

      expect(result, contains('roleplay-memory-v2'));
      expect(
        result.indexOf('"protocolVersion"'),
        lessThan(result.indexOf('"memoryPatch"')),
      );
    });

    test('composeStructuredOutputPrompt 包含用户输入', () {
      final composer = StructuredInputPromptComposer();
      final result = composer.composeStructuredOutputPrompt(
        userInput: '你好',
        outputSchema: '{"reply":"string"}',
      );

      expect(result, contains('你好'));
      expect(result, contains('【用户输入】'));
      expect(result, contains('【输出格式】'));
    });

    test('composeStructuredOutputPrompt 包含系统提示', () {
      final composer = StructuredInputPromptComposer();
      final result = composer.composeStructuredOutputPrompt(
        userInput: 'test',
        systemPrompt: '你是一个助手',
        outputSchema: '{}',
      );

      expect(result, contains('你是一个助手'));
      expect(result, contains('【系统提示】'));
    });

    test('composeStructuredOutputPrompt 无系统提示时省略该段', () {
      final composer = StructuredInputPromptComposer();
      final result = composer.composeStructuredOutputPrompt(
        userInput: 'test',
        outputSchema: '{}',
      );

      expect(result.contains('【系统提示】'), isFalse);
    });

    test('composeStructuredOutputPrompt 使用自定义 settings', () {
      final composer = StructuredInputPromptComposer(
        settings: const AppSettings(maxPromptLineLength: 50),
      );
      final result = composer.composeStructuredOutputPrompt(
        userInput: 'test',
        outputSchema: '{}',
      );

      expect(result, isNotEmpty);
    });

    test('结构化输出先生成记忆与本轮事件，最后生成可见回复', () {
      const schema = ChatRepository.outputSchema;

      final memoryPatchIndex = schema.indexOf('"memoryPatch"');
      final summaryIndex = schema.indexOf('"summary"');
      final eventBriefIndex = schema.indexOf('"eventBrief"');
      final currentStatesIndex = schema.indexOf('"currentStates"');
      final replyIndex = schema.indexOf('"reply"');

      expect(memoryPatchIndex, greaterThanOrEqualTo(0));
      expect(summaryIndex, greaterThan(memoryPatchIndex));
      expect(eventBriefIndex, greaterThan(summaryIndex));
      expect(currentStatesIndex, greaterThan(eventBriefIndex));
      expect(replyIndex, greaterThan(currentStatesIndex));
    });

    test('角色 Prompt 明确本轮事件先于正文且正文不得改写事件结果', () {
      final composer = StructuredInputPromptComposer();
      final prompt = composer.composeSystemPromptWithContactObject(
        basePrompt: '保持角色一致',
        contact: Contact(
          id: 'role-1',
          name: '林夏',
          avatar: '',
          createdAt: DateTime(2026),
        ),
      );

      expect(prompt, contains('eventBrief 每轮必须输出'));
      expect(prompt, contains('不是对 reply 的事后摘要'));
      expect(prompt, contains('reply 必须忠实展开 eventBrief'));
      expect(
        prompt.indexOf('"memoryPatch"'),
        lessThan(prompt.indexOf('"reply"')),
      );
    });

    test('故事 Prompt 禁止 AI 擅自推动主线', () {
      final composer = StructuredInputPromptComposer();
      final prompt = composer.composeSystemPromptWithContactObject(
        basePrompt: '',
        contact: Contact(
          id: 'story-1',
          name: '雨夜',
          avatar: '',
          category: ContactCategory.story,
          createdAt: DateTime(2026),
        ),
      );

      expect(prompt, contains('不得擅自引入主要角色'));
      expect(prompt, contains('不得擅自引入主要角色、核心冲突、重大秘密、时间跳跃或场景切换'));
    });
  });
}
