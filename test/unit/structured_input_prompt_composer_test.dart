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

    test('缓存友好请求把固定 system 与动态 user 严格分离', () {
      final composer = StructuredInputPromptComposer();
      final result = composer.composeStructuredOutputPromptParts(
        userInput: '继续推门',
        systemPrompt: '固定规则与角色设定',
        dynamicContext: '上一轮停在门已经推开一道缝',
        outputSchema: '{"reply":"string"}',
      );

      expect(result.systemPrompt, contains('固定规则与角色设定'));
      expect(result.systemPrompt, isNot(contains('门已经推开一道缝')));
      expect(result.systemPrompt, isNot(contains('继续推门')));
      expect(result.userPrompt, contains('门已经推开一道缝'));
      expect(result.userPrompt, endsWith('继续推门'));
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
      expect(prompt, contains('上一轮终点/连续性锚点'));
      expect(prompt, contains('已经开始或完成的动作不得退回'));
      expect(prompt, contains('上一段 reply 与本轮 reply 会被直接拼接'));
    });

    test('低频事件位于缓存前缀，短期事件和总结任务位于动态尾部', () {
      const ultra = EventNode(
        id: 'ultra-1',
        tier: EventTier.ultraLongTerm,
        event: EventMemory(description: '很久以前两人已经相识'),
        createdAtMs: 1,
      );
      const long = EventNode(
        id: 'long-1',
        tier: EventTier.longTerm,
        event: EventMemory(description: '两人抵达旧宅'),
        createdAtMs: 2,
      );
      const short = EventNode(
        id: 'short-1',
        tier: EventTier.shortTerm,
        event: EventMemory(description: '门已经被推开一道缝'),
        createdAtMs: 3,
      );
      final composer = StructuredInputPromptComposer();
      final sections = composer.composeSystemPromptSectionsWithContactObject(
        basePrompt: '保持连续',
        contact: Contact(
          id: 'role-cache',
          name: '林夏',
          avatar: '',
          fixedInput: '固定角色设定',
          eventGraph: const EventGraphMemory(
            ultraLongTermQueue: <EventNode>[ultra],
            longTermQueue: <EventNode>[long],
            shortTermQueue: <EventNode>[short],
          ),
          createdAt: DateTime(2026),
        ),
        mustSummarize: true,
        pendingSummaryEvents: const <EventMemory>[
          EventMemory(description: '需要总结的旧事件'),
        ],
      );

      expect(sections.cacheablePrefix, contains('固定角色设定'));
      expect(sections.cacheablePrefix, contains('很久以前两人已经相识'));
      expect(sections.cacheablePrefix, contains('两人抵达旧宅'));
      expect(sections.cacheablePrefix, isNot(contains('门已经被推开一道缝')));
      expect(
        sections.cacheablePrefix,
        isNot(contains('【强制】本轮必须输出 memoryPatch.summary。')),
      );
      expect(sections.dynamicContext, contains('门已经被推开一道缝'));
      expect(sections.dynamicContext, contains('[2] [active] [上一轮终点/连续性锚点]'));
      expect(sections.dynamicContext, contains('【强制】'));
      expect(sections.dynamicContext, contains('需要总结的旧事件'));

      final merged = sections.merged;
      expect(
        merged.indexOf('所有指令均已载入'),
        lessThan(merged.indexOf('门已经被推开一道缝')),
      );
    });

    test('连续两轮只更新短期事件时 system 缓存前缀保持完全一致', () {
      Contact contactWithShort(String id, String description) => Contact(
            id: 'role-cache-stable',
            name: '林夏',
            avatar: '',
            fixedInput: '固定角色设定',
            eventGraph: EventGraphMemory(
              longTermQueue: const <EventNode>[
                EventNode(
                  id: 'long-stable',
                  tier: EventTier.longTerm,
                  event: EventMemory(description: '两人已经抵达旧宅'),
                  createdAtMs: 1,
                ),
              ],
              shortTermQueue: <EventNode>[
                EventNode(
                  id: id,
                  tier: EventTier.shortTerm,
                  event: EventMemory(description: description),
                  createdAtMs: 2,
                ),
              ],
            ),
            createdAt: DateTime(2026),
          );

      final composer = StructuredInputPromptComposer();
      final first = composer.composeSystemPromptSectionsWithContactObject(
        basePrompt: '保持连续',
        contact: contactWithShort('short-1', '手已经搭在门把上'),
      );
      final second = composer.composeSystemPromptSectionsWithContactObject(
        basePrompt: '保持连续',
        contact: contactWithShort('short-2', '门已经被推开一道缝'),
      );

      expect(first.cacheablePrefix, second.cacheablePrefix);
      expect(first.dynamicContext, isNot(second.dynamicContext));
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
