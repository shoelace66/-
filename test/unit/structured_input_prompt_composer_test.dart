import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/data/models/app_settings.dart';
import 'package:flutter_chat_demo/core/utils/structured_input_prompt_composer.dart';

void main() {
  group('StructuredInputPromptComposer', () {
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
  });
}
