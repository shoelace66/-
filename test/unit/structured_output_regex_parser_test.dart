import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/utils/structured_output_regex_parser.dart';

void main() {
  group('StructuredOutputRegexParser', () {
    group('extractReply', () {
      test('从纯 JSON 中提取 reply', () {
        final raw = '{"reply": "你好！", "memoryPatch": {}}';
        expect(StructuredOutputRegexParser.extractReply(raw), '你好！');
      });

      test('从 markdown code fence 中提取', () {
        final raw = '''
这是 LLM 的回复：
```json
{"reply": "测试回复", "memoryPatch": {}}
```
以上是结果。''';
        expect(StructuredOutputRegexParser.extractReply(raw), '测试回复');
      });

      test('无 reply 字段返回 null', () {
        final raw = '{"memoryPatch": {"events": []}}';
        expect(StructuredOutputRegexParser.extractReply(raw), isNull);
      });

      test('空字符串返回 null', () {
        expect(StructuredOutputRegexParser.extractReply(''), isNull);
      });

      test('非 JSON 返回 null', () {
        expect(StructuredOutputRegexParser.extractReply('纯文本'), isNull);
      });

      test('reply 为空字符串返回 null', () {
        final raw = '{"reply": "", "memoryPatch": {}}';
        expect(StructuredOutputRegexParser.extractReply(raw), isNull);
      });
    });

    group('extractMemoryPatch', () {
      test('提取 memoryPatch', () {
        final raw = '{"reply": "ok", "memoryPatch": {"worldKnowledge": ["a"]}}';
        final patch = StructuredOutputRegexParser.extractMemoryPatch(raw);
        expect(patch, isNotNull);
        expect(patch!['worldKnowledge'], ['a']);
      });

      test('无 memoryPatch 返回 null', () {
        final raw = '{"reply": "ok"}';
        expect(StructuredOutputRegexParser.extractMemoryPatch(raw), isNull);
      });
    });

    group('extractStringList', () {
      test('提取字符串列表', () {
        final patch = {'worldKnowledge': ['a', 'b', 'c']};
        expect(
          StructuredOutputRegexParser.extractStringList(patch, 'worldKnowledge'),
          ['a', 'b', 'c'],
        );
      });

      test('空字段返回空列表', () {
        expect(
          StructuredOutputRegexParser.extractStringList({}, 'missing'),
          isEmpty,
        );
      });

      test('null patch 返回空列表', () {
        expect(
          StructuredOutputRegexParser.extractStringList(null, 'key'),
          isEmpty,
        );
      });

      test('非列表类型返回空列表', () {
        final patch = {'key': 'not a list'};
        expect(
          StructuredOutputRegexParser.extractStringList(patch, 'key'),
          isEmpty,
        );
      });

      test('过滤空字符串', () {
        final patch = {'key': ['a', '', '  ', 'b']};
        expect(
          StructuredOutputRegexParser.extractStringList(patch, 'key'),
          ['a', 'b'],
        );
      });
    });

    group('extractStringMap', () {
      test('提取字符串 Map', () {
        final patch = {'currentStates': {'mood': 'happy', 'location': 'home'}};
        final result = StructuredOutputRegexParser.extractStringMap(
          patch,
          'currentStates',
        );
        expect(result, {'mood': 'happy', 'location': 'home'});
      });

      test('空字段返回空 Map', () {
        expect(
          StructuredOutputRegexParser.extractStringMap({}, 'missing'),
          isEmpty,
        );
      });
    });

    group('parsePrimaryPayload', () {
      test('解析有效 JSON', () {
        final raw = '{"reply": "hi", "memoryPatch": {}}';
        final result = StructuredOutputRegexParser.parsePrimaryPayload(raw);
        expect(result, isNotNull);
        expect(result!['reply'], 'hi');
      });

      test('从混合文本中提取 JSON', () {
        final raw = '以下是结果：{"reply": "hi"}';
        final result = StructuredOutputRegexParser.parsePrimaryPayload(raw);
        expect(result, isNotNull);
        expect(result!['reply'], 'hi');
      });
    });
  });
}
