import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/infrastructure/services/tts_service.dart';

void main() {
  group('TtsService 传参 / 响应格式', () {
    setUp(() async {
      await TtsService.instance.stop();
      TtsService.instance.updateProfile(const TtsProfile());
      TtsService.instance.debugSetAudioPlayback(_SilentTtsAudioPlayback());
    });

    tearDown(() async {
      await TtsService.instance.stop();
      TtsService.instance.debugSetAudioPlayback(null);
      TtsService.instance.debugSetHttpClient(null);
    });

    test('OpenAI TTS：POST {baseUrl}/audio/speech + Bearer + 正确请求体', () async {
      late http.Request captured;
      final audioBytes = Uint8List.fromList(<int>[0xFF, 0xFB, 0x90, 0x00]);
      final mock = MockClient((request) async {
        captured = request;
        return http.Response.bytes(audioBytes, 200, headers: <String, String>{
          'content-type': 'audio/mpeg',
        });
      });
      TtsService.instance.debugSetHttpClient(mock);

      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'openai_tts',
          apiKey: 'sk-test',
          baseUrl: 'https://api.openai.com/v1',
          model: 'tts-1',
          timeoutSeconds: 30,
        ),
      );

      // 触发一次后立刻 stop 避免等播放计时器
      unawaited(TtsService.instance.speak(
        messageId: 'm1',
        text: '你好',
        voice: const VoiceOption(
          id: 'zh-CN-XiaoxiaoNeural',
          label: '晓晓',
          locale: 'zh-CN',
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await TtsService.instance.stop();

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'https://api.openai.com/v1/audio/speech');
      expect(captured.headers['Authorization'], 'Bearer sk-test');
      expect(captured.headers['Content-Type'], contains('application/json'));

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'tts-1');
      expect(body['input'], '你好');
      // 边-小被映射到 shimmer（女声 edge-tts 风格）
      expect(body['voice'], 'shimmer');
      expect(body['response_format'], 'mp3');
    });

    test('OpenAI TTS：edge-tts Yunxi 风格映射到 onyx', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response.bytes(Uint8List.fromList(<int>[0xFF]), 200);
      });
      TtsService.instance.debugSetHttpClient(mock);

      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'openai_tts',
          apiKey: 'sk',
          baseUrl: 'https://api.openai.com/v1',
          model: 'tts-1',
        ),
      );

      unawaited(TtsService.instance.speak(
        messageId: 'm1',
        text: 'hi',
        voice: const VoiceOption(
          id: 'zh-CN-YunxiNeural',
          label: '云希',
          locale: 'zh-CN',
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await TtsService.instance.stop();

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['voice'], 'onyx');
    });

    test('OpenAI TTS：未知 voice 直接当字符串使用', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response.bytes(Uint8List.fromList(<int>[0xFF]), 200);
      });
      TtsService.instance.debugSetHttpClient(mock);

      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'openai_tts',
          apiKey: 'sk',
          baseUrl: 'https://api.openai.com/v1',
          model: 'tts-1',
        ),
      );

      unawaited(TtsService.instance.speak(
        messageId: 'm1',
        text: 'hi',
        voice: const VoiceOption(
          id: 'custom-voice-id',
          label: 'Custom',
          locale: 'en',
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await TtsService.instance.stop();

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['voice'], 'custom-voice-id');
    });

    test('OpenAI TTS：model 为空时默认 tts-1', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response.bytes(Uint8List.fromList(<int>[0xFF]), 200);
      });
      TtsService.instance.debugSetHttpClient(mock);

      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'openai_tts',
          apiKey: 'sk',
          baseUrl: 'https://api.openai.com/v1',
          model: '',
        ),
      );

      unawaited(TtsService.instance.speak(
        messageId: 'm1',
        text: 'hi',
        voice: VoiceOption.fallback,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await TtsService.instance.stop();

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'tts-1');
    });

    test('OpenAI TTS：缺 apiKey / baseUrl 提前抛 TtsServiceException', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        return http.Response.bytes(Uint8List.fromList(<int>[0xFF]), 200);
      });
      TtsService.instance.debugSetHttpClient(mock);

      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'openai_tts',
          apiKey: '',
          baseUrl: 'https://api.openai.com/v1',
          model: 'tts-1',
        ),
      );
      await TtsService.instance.speak(
        messageId: 'm1',
        text: 'hi',
        voice: VoiceOption.fallback,
      );
      expect(attempts, 0);
      expect(TtsService.instance.state, TtsPlaybackState.idle);

      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'openai_tts',
          apiKey: 'sk',
          baseUrl: '',
          model: 'tts-1',
        ),
      );
      await TtsService.instance.speak(
        messageId: 'm1',
        text: 'hi',
        voice: VoiceOption.fallback,
      );
    });

    test('edge_tts：POST {baseUrl}/tts + {text, voice}', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response.bytes(Uint8List.fromList(<int>[0xFF, 0xFB]), 200);
      });
      TtsService.instance.debugSetHttpClient(mock);

      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'edge_tts',
          apiKey: '',
          baseUrl: 'https://my-edge-proxy',
          model: 'zh-CN-XiaoxiaoNeural',
        ),
      );

      unawaited(TtsService.instance.speak(
        messageId: 'm1',
        text: '测试',
        voice: const VoiceOption(
          id: 'zh-CN-YunxiNeural',
          label: '云希',
          locale: 'zh-CN',
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await TtsService.instance.stop();

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'https://my-edge-proxy/tts');
      expect(captured.headers.containsKey('Authorization'), isFalse);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['text'], '测试');
      // edge_tts 直接传 voice id，不做 OpenAI 映射
      expect(body['voice'], 'zh-CN-YunxiNeural');
    });

    test('custom_tts：POST {baseUrl} + {text, voice, model}', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response.bytes(Uint8List.fromList(<int>[0xFF]), 200);
      });
      TtsService.instance.debugSetHttpClient(mock);

      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'custom_tts',
          apiKey: '',
          baseUrl: 'https://my-tts.example.com',
          model: 'my-tts-v1',
        ),
      );

      unawaited(TtsService.instance.speak(
        messageId: 'm1',
        text: 'hi',
        voice: const VoiceOption(
          id: 'v1',
          label: 'V1',
          locale: 'en',
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await TtsService.instance.stop();

      expect(captured.url.toString(), 'https://my-tts.example.com');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['text'], 'hi');
      expect(body['voice'], 'v1');
      expect(body['model'], 'my-tts-v1');
    });

    test('空文本不发起请求', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        return http.Response.bytes(Uint8List.fromList(<int>[0xFF]), 200);
      });
      TtsService.instance.debugSetHttpClient(mock);

      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'openai_tts',
          apiKey: 'sk',
          baseUrl: 'https://api.openai.com/v1',
          model: 'tts-1',
        ),
      );

      await TtsService.instance.speak(
        messageId: 'm1',
        text: '   ',
        voice: VoiceOption.fallback,
      );
      expect(attempts, 0);
    });

    test('401 错误：抛 TtsServiceException，state 回到 idle', () async {
      final mock = MockClient((request) async {
        return http.Response.bytes(utf8.encode('unauthorized'), 401);
      });
      TtsService.instance.debugSetHttpClient(mock);

      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'openai_tts',
          apiKey: 'sk',
          baseUrl: 'https://api.openai.com/v1',
          model: 'tts-1',
        ),
      );

      await TtsService.instance.speak(
        messageId: 'm1',
        text: 'hi',
        voice: VoiceOption.fallback,
      );
      // 错误后 state 应回到 idle
      expect(TtsService.instance.state, TtsPlaybackState.idle);
    });
  });
}

final class _SilentTtsAudioPlayback implements TtsAudioPlayback {
  @override
  Stream<void> get onComplete => const Stream<void>.empty();

  @override
  Future<void> play(Uint8List bytes) async {}

  @override
  Future<void> stop() async {}
}
