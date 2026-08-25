import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/constants/api_constants.dart';

void main() {
  group('ApiConstants', () {
    setUp(() {
      ApiConstants.runtimeApiKey = '';
      ApiConstants.runtimeBaseUrl = 'https://api.deepseek.com';
      ApiConstants.runtimeModel = 'deepseek-chat';
    });

    test('hasApiKey 在无 key 时返回 false', () {
      expect(ApiConstants.hasApiKey, isFalse);
    });

    test('hasApiKey 在有 key 时返回 true', () {
      ApiConstants.runtimeApiKey = 'sk-test';
      expect(ApiConstants.hasApiKey, isTrue);
    });

    test('hasApiKey 忽略空白 key', () {
      ApiConstants.runtimeApiKey = '   ';
      expect(ApiConstants.hasApiKey, isFalse);
    });

    test('chatCompletionsUrl 拼接正确', () {
      ApiConstants.runtimeBaseUrl = 'https://api.example.com';
      expect(
        ApiConstants.chatCompletionsUrl,
        'https://api.example.com/chat/completions',
      );
    });

    test('chatCompletionsCompatUrl 去掉末尾 /v1 后拼接', () {
      ApiConstants.runtimeBaseUrl = 'https://api.example.com/v1';
      expect(
        ApiConstants.chatCompletionsCompatUrl,
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('chatCompletionsCompatUrl 无 /v1 时正常拼接', () {
      ApiConstants.runtimeBaseUrl = 'https://api.example.com';
      expect(
        ApiConstants.chatCompletionsCompatUrl,
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('runtimeModel 默认值', () {
      expect(ApiConstants.runtimeModel, 'deepseek-chat');
    });

    test('runtimeTimeoutSeconds 默认值', () {
      expect(ApiConstants.runtimeTimeoutSeconds, 60);
    });
  });
}
