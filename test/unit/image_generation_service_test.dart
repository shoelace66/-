import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/infrastructure/services/image_generation_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ImageGenerationService', () {
    tearDown(() {
      ImageGenerationService.instance.debugSetHttpClient(null);
    });

    test('空描述返回 failure', () async {
      final result = await ImageGenerationService.instance.generate(prompt: '');
      expect(result.success, isFalse);
      expect(result.error, isNotNull);
    });

    test('纯空格描述同样视为空', () async {
      final result =
          await ImageGenerationService.instance.generate(prompt: '   \n  ');
      expect(result.success, isFalse);
    });

    test('未配置 baseUrl 时返回清晰错误', () async {
      ImageGenerationService.instance.updateProfile(
        const ImageProfile(
          presetId: 'openai_image',
          apiKey: '',
          baseUrl: '',
          model: 'gpt-image-1',
        ),
      );
      final result = await ImageGenerationService.instance.generate(
        prompt: '夕阳下的城市',
      );
      expect(result.success, isFalse);
      expect(result.error, contains('Base URL'));
    });

    test('Pollinations 不需要 apiKey，且测试不访问真实网络', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.host, 'image.pollinations.ai');
        expect(request.url.path, contains('/prompt/sunset'));
        expect(request.url.queryParameters['model'], 'flux');
        return http.Response.bytes(
          <int>[1, 2, 3, 4],
          200,
          headers: const <String, String>{'content-type': 'image/png'},
        );
      });
      ImageGenerationService.instance.debugSetHttpClient(client);

      final result = await ImageGenerationService.instance.generate(
        prompt: 'sunset',
        profile: const ImageProfile(
          presetId: 'pollinations',
          apiKey: '',
          baseUrl: 'https://image.pollinations.ai',
          model: 'flux',
          parameters: ImageParameters(timeoutSeconds: 5),
        ),
      );

      expect(result.success, isTrue);
      expect(result.imageBytes, <int>[1, 2, 3, 4]);
      expect(result.error, isNull);
    });
  });
}
