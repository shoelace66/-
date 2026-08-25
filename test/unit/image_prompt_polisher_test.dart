import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_chat_demo/core/utils/image_prompt_polisher.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';

void main() {
  group('ImagePromptPolisher', () {
    test('buildContactContext 把联系人关键字段都纳入', () {
      final contact = Contact(
        id: 'c1',
        name: '李逍遥',
        avatar: '🗡️',
        category: ContactCategory.contact,
        personality: const ['热血', '正直'],
        appearance: const ['白衣少年', '腰间佩剑'],
        backgroundStory: const ['余杭镇少年', '客栈小伙计'],
        mood: '激昂',
        currentStates: const {'好感度': '10', '当前地点': '余杭镇'},
        createdAt: DateTime(2024),
      );
      final ctx = ImagePromptPolisher.instance.buildContactContext(contact);
      expect(ctx, contains('name: 李逍遥'));
      expect(ctx, contains('type: character'));
      expect(ctx, contains('personality: 热血；正直'));
      expect(ctx, contains('appearance: 白衣少年；腰间佩剑'));
      expect(ctx, contains('backgroundStory: 余杭镇少年；客栈小伙计'));
      expect(ctx, contains('mood: 激昂'));
      expect(ctx, contains('currentStates: 好感度=10; 当前地点=余杭镇'));
    });

    test('buildContactContext：联系人 null 返回占位字符串', () {
      final ctx = ImagePromptPolisher.instance.buildContactContext(null);
      expect(ctx, contains('无联系人设定'));
    });

    test('buildContactContext：空字段被自动过滤', () {
      final contact = Contact(
        id: 'c1',
        name: '空',
        avatar: '',
        createdAt: DateTime(2024),
      );
      final ctx = ImagePromptPolisher.instance.buildContactContext(contact);
      expect(ctx.contains('personality:'), isFalse);
      expect(ctx.contains('appearance:'), isFalse);
      expect(ctx.contains('mood:'), isFalse);
      expect(ctx, contains('name: 空'));
    });

    test('buildSystemPrompt 强调输出英文 + negative prompt', () {
      final sys = ImagePromptPolisher.instance.buildSystemPrompt();
      expect(sys.toLowerCase(), contains('english'));
      expect(sys.toLowerCase(), contains('negative'));
      expect(sys, contains('prompt'));
    });

    test('buildUserPrompt 包含联系人上下文和用户原文', () {
      final user = ImagePromptPolisher.instance.buildUserPrompt(
        userDescription: '夕阳下的城市',
        contactContext: 'name: A',
      );
      expect(user, contains('name: A'));
      expect(user, contains('夕阳下的城市'));
      expect(user, contains('联系人'));
    });

    test('polish：LLM 返回纯 JSON 时正确解析', () async {
      final result = await ImagePromptPolisher.instance.polish(
        userDescription: '夕阳',
        ask: (_, __) async =>
            '{"englishPrompt":"cinematic sunset, warm orange light, long shadows","negativePrompt":"blurry, low quality"}',
      );
      expect(result.englishPrompt,
          'cinematic sunset, warm orange light, long shadows');
      expect(result.negativePrompt, 'blurry, low quality');
    });

    test('polish：LLM 返回带 markdown 代码块的 JSON 时也能解析', () async {
      final result = await ImagePromptPolisher.instance.polish(
        userDescription: '夕阳',
        ask: (_, __) async => '''
```json
{"englishPrompt":"a cat","negativePrompt":"dog"}
```
''',
      );
      expect(result.englishPrompt, 'a cat');
      expect(result.negativePrompt, 'dog');
    });

    test('polish：LLM 只返回内联字段（不带大括号）时，正则兜底', () async {
      // 不带外层 {}，用正则从内联字段中抠出来
      final result = await ImagePromptPolisher.instance.polish(
        userDescription: '夕阳',
        ask: (_, __) async =>
            'englishPrompt: "a cyberpunk city" negativePrompt: "blurry"',
      );
      expect(result.englishPrompt, 'a cyberpunk city');
      expect(result.negativePrompt, 'blurry');
    });

    test('polish：LLM 返回单引号 JSON 也能解析', () async {
      final result = await ImagePromptPolisher.instance.polish(
        userDescription: '夕阳',
        ask: (_, __) async =>
            "{'englishPrompt':'a tree','negativePrompt':'leaf'}",
      );
      expect(result.englishPrompt, 'a tree');
      expect(result.negativePrompt, 'leaf');
    });

    test('polish：LLM 返回完全无效内容时退回原文 + 默认 negative', () async {
      final result = await ImagePromptPolisher.instance.polish(
        userDescription: '夕阳下的城市',
        ask: (_, __) async => '抱歉我无法处理',
      );
      expect(result.englishPrompt, '夕阳下的城市');
      expect(result.negativePrompt,
          'blurry, low quality, deformed, extra fingers, watermark, text');
    });

    test('polish：negativePrompt 为空时也填默认值', () async {
      final result = await ImagePromptPolisher.instance.polish(
        userDescription: 'x',
        ask: (_, __) async => '{"englishPrompt":"a bird"}',
      );
      expect(result.englishPrompt, 'a bird');
      expect(result.negativePrompt, isNotEmpty);
    });

    test('polish：传给 ask 的 system + user prompt 都正确', () async {
      String? capturedSys;
      String? capturedUser;
      await ImagePromptPolisher.instance.polish(
        userDescription: '夕阳',
        contact: Contact(
          id: 'c1',
          name: 'X',
          avatar: '',
          createdAt: DateTime(2024),
        ),
        ask: (sys, user) async {
          capturedSys = sys;
          capturedUser = user;
          return '{"englishPrompt":"a","negativePrompt":"b"}';
        },
      );
      expect(capturedSys, isNotNull);
      expect(capturedSys!.toLowerCase(), contains('english'));
      expect(capturedUser, contains('夕阳'));
      expect(capturedUser, contains('name: X'));
    });
  });
}
