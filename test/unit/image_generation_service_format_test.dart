import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/infrastructure/services/image_generation_service.dart';

void main() {
  group('ImageGenerationService 传参 / 响应格式', () {
    setUp(() {
      // 清理单例 profile，避免被前面的测试污染
      ImageGenerationService.instance.updateProfile(const ImageProfile());
    });

    test('OpenAI Images：POST {baseUrl}/images/generations + 正确请求体', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{
            'created': 1700000000,
            'data': <Map<String, dynamic>>[
              <String, dynamic>{'url': 'https://example.com/img.png'},
            ],
          })),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      ImageGenerationService.instance.debugSetHttpClient(mock);

      ImageGenerationService.instance.updateProfile(
        const ImageProfile(
          presetId: 'openai_image',
          apiKey: 'sk-test',
          baseUrl: 'https://api.openai.com/v1',
          model: 'dall-e-3',
          parameters: ImageParameters(
            size: '1024x1024',
            n: 1,
            style: 'vivid',
            quality: 'hd',
            responseFormat: 'url',
            timeoutSeconds: 60,
          ),
        ),
      );

      final result = await ImageGenerationService.instance.generate(
        prompt: '夕阳下的城市',
      );

      expect(captured.method, 'POST');
      expect(captured.url.toString(),
          'https://api.openai.com/v1/images/generations');
      expect(captured.headers['Authorization'], 'Bearer sk-test');
      expect(captured.headers['Content-Type'], contains('application/json'));

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'dall-e-3');
      expect(body['prompt'], '夕阳下的城市');
      expect(body['n'], 1);
      expect(body['size'], '1024x1024');
      expect(body['style'], 'vivid');
      expect(body['quality'], 'hd');
      expect(body['response_format'], 'url');

      expect(result.success, isTrue);
      expect(result.imageUrl, 'https://example.com/img.png');
      expect(result.imageBytes, isNull);
    });

    test('OpenAI Images：style/quality 为空时不写入字段', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{
            'data': <Map<String, dynamic>>[
              <String, dynamic>{'url': 'https://example.com/x.png'},
            ],
          })),
          200,
        );
      });
      ImageGenerationService.instance.debugSetHttpClient(mock);

      ImageGenerationService.instance.updateProfile(
        const ImageProfile(
          presetId: 'openai_image',
          apiKey: 'sk',
          baseUrl: 'https://api.openai.com/v1',
          model: 'dall-e-3',
          parameters: ImageParameters(
            style: '',
            quality: '',
            responseFormat: 'url',
          ),
        ),
      );

      await ImageGenerationService.instance.generate(prompt: 'x');

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.containsKey('style'), isFalse);
      expect(body.containsKey('quality'), isFalse);
    });

    test('OpenAI Images：b64_json 响应解析为 bytes', () async {
      final pngBytes = Uint8List.fromList(
          <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final mock = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{
            'data': <Map<String, dynamic>>[
              <String, dynamic>{'b64_json': base64Encode(pngBytes)},
            ],
          })),
          200,
        );
      });
      ImageGenerationService.instance.debugSetHttpClient(mock);

      ImageGenerationService.instance.updateProfile(
        const ImageProfile(
          presetId: 'openai_image',
          apiKey: 'sk',
          baseUrl: 'https://api.openai.com/v1',
          model: 'dall-e-3',
        ),
      );

      final result =
          await ImageGenerationService.instance.generate(prompt: 'x');
      expect(result.success, isTrue);
      expect(result.imageUrl, isNull);
      expect(result.imageBytes, isNotNull);
      expect(result.imageBytes!.length, pngBytes.length);
      expect(result.imageBytes![0], pngBytes[0]);
    });

    test('OpenAI Images：空 baseUrl 直接返回清晰错误', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        return http.Response.bytes(utf8.encode('{}'), 200);
      });
      ImageGenerationService.instance.debugSetHttpClient(mock);

      ImageGenerationService.instance.updateProfile(
        const ImageProfile(
          presetId: 'openai_image',
          apiKey: 'sk',
          baseUrl: '',
          model: 'm',
        ),
      );

      final result =
          await ImageGenerationService.instance.generate(prompt: 'x');
      expect(result.success, isFalse);
      expect(result.error, contains('Base URL'));
      expect(attempts, 0, reason: '无 baseUrl 不应发请求');
    });

    test('Pollinations：GET {baseUrl}/prompt/{描述}?width=&height=&nologo=&model=',
        () async {
      late http.Request captured;
      final pngBytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]);
      final mock = MockClient((request) async {
        captured = request;
        return http.Response.bytes(pngBytes, 200);
      });
      ImageGenerationService.instance.debugSetHttpClient(mock);

      ImageGenerationService.instance.updateProfile(
        const ImageProfile(
          presetId: 'pollinations',
          apiKey: '',
          baseUrl: 'https://image.pollinations.ai',
          model: 'flux',
          parameters: ImageParameters(
            size: '512x768',
            timeoutSeconds: 30,
          ),
        ),
      );

      final result = await ImageGenerationService.instance.generate(
        prompt: 'sunset city',
      );

      expect(captured.method, 'GET');
      expect(captured.url.path, '/prompt/sunset%20city');
      expect(captured.url.queryParameters['model'], 'flux');
      expect(captured.url.queryParameters['width'], '512');
      expect(captured.url.queryParameters['height'], '768');
      expect(captured.url.queryParameters['nologo'], 'true');
      // 无 Authorization header
      expect(captured.headers.containsKey('Authorization'), isFalse);

      expect(result.success, isTrue);
      expect(result.imageBytes, isNotNull);
      expect(result.imageBytes!.length, pngBytes.length);
    });

    test(
        'Stability：POST {baseUrl}/v2beta/stable-image/generate/{model} + Bearer + Accept: image/*',
        () async {
      late http.Request captured;
      final pngBytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]);
      final mock = MockClient((request) async {
        captured = request;
        return http.Response.bytes(pngBytes, 200);
      });
      ImageGenerationService.instance.debugSetHttpClient(mock);

      ImageGenerationService.instance.updateProfile(
        const ImageProfile(
          presetId: 'stability',
          apiKey: 'sk-stability',
          baseUrl: 'https://api.stability.ai',
          model: 'core',
          parameters: ImageParameters(size: '1024x1024', timeoutSeconds: 60),
        ),
      );

      final result =
          await ImageGenerationService.instance.generate(prompt: 'p');

      expect(captured.method, 'POST');
      expect(captured.url.toString(),
          'https://api.stability.ai/v2beta/stable-image/generate/core');
      expect(captured.headers['Authorization'], 'Bearer sk-stability');
      expect(captured.headers['Accept'], 'image/*');

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['prompt'], 'p');
      expect(body['output_format'], 'png');
      expect(body['aspect_ratio'], '1:1');

      expect(result.success, isTrue);
      expect(result.imageBytes, isNotNull);
    });

    test('Stability：size=1920x1080 自动转换为 aspect_ratio=16:9', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response.bytes(Uint8List.fromList(<int>[0x89, 0x50]), 200);
      });
      ImageGenerationService.instance.debugSetHttpClient(mock);

      ImageGenerationService.instance.updateProfile(
        const ImageProfile(
          presetId: 'stability',
          apiKey: 'sk',
          baseUrl: 'https://api.stability.ai',
          model: 'core',
          parameters: ImageParameters(size: '1920x1080'),
        ),
      );

      await ImageGenerationService.instance.generate(prompt: 'p');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['aspect_ratio'], '16:9');
    });

    test('Stability：缺 apiKey 提前返回错误', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        return http.Response.bytes(Uint8List.fromList(<int>[0x89, 0x50]), 200);
      });
      ImageGenerationService.instance.debugSetHttpClient(mock);

      ImageGenerationService.instance.updateProfile(
        const ImageProfile(
          presetId: 'stability',
          apiKey: '',
          baseUrl: 'https://api.stability.ai',
          model: 'core',
        ),
      );

      final result =
          await ImageGenerationService.instance.generate(prompt: 'p');
      expect(result.success, isFalse);
      expect(result.error, contains('API Key'));
      expect(attempts, 0);
    });

    test('401 错误映射为清晰的提示', () async {
      final mock = MockClient((request) async {
        return http.Response.bytes(utf8.encode('unauthorized'), 401);
      });
      ImageGenerationService.instance.debugSetHttpClient(mock);

      ImageGenerationService.instance.updateProfile(
        const ImageProfile(
          presetId: 'openai_image',
          apiKey: 'sk',
          baseUrl: 'https://api.openai.com/v1',
          model: 'dall-e-3',
        ),
      );

      final result =
          await ImageGenerationService.instance.generate(prompt: 'p');
      expect(result.success, isFalse);
      expect(result.error, contains('API Key'));
    });

    test('空描述 / 纯空格直接返回 failure', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        return http.Response.bytes(utf8.encode('{}'), 200);
      });
      ImageGenerationService.instance.debugSetHttpClient(mock);

      final r1 = await ImageGenerationService.instance.generate(prompt: '');
      expect(r1.success, isFalse);
      final r2 =
          await ImageGenerationService.instance.generate(prompt: '   \n  ');
      expect(r2.success, isFalse);
      expect(attempts, 0);
    });
  });
}
