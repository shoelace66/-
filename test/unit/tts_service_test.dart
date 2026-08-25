import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/infrastructure/services/tts_service.dart';

void main() {
  group('TtsService', () {
    setUp(() async {
      await TtsService.instance.stop();
      TtsService.instance.debugSetAudioPlayback(null);
    });

    tearDown(() async {
      await TtsService.instance.stop();
      TtsService.instance.debugSetAudioPlayback(null);
      TtsService.instance.debugSetHttpClient(null);
    });

    test('初始状态是 idle', () {
      expect(TtsService.instance.state, TtsPlaybackState.idle);
      expect(TtsService.instance.currentMessageId, isNull);
    });

    test('未配置 baseUrl 的 openai_tts 回到 idle 状态', () async {
      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'openai_tts',
          apiKey: 'sk-test',
          baseUrl: '',
          model: 'tts-1',
        ),
      );
      await TtsService.instance.speak(
        messageId: 'm1',
        text: 'hello',
        voice: VoiceOption.fallback,
      );
      expect(TtsService.instance.state, TtsPlaybackState.idle);
    });

    test('空 API Key 的 openai_tts 回到 idle 状态', () async {
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
        text: 'hello',
        voice: VoiceOption.fallback,
      );
      expect(TtsService.instance.state, TtsPlaybackState.idle);
    });

    test('isPlayingMessage 只匹配当前消息', () {
      expect(TtsService.instance.isPlayingMessage('m1'), isFalse);
    });

    test('真实音频字节交给播放器，完成事件恢复 idle', () async {
      final playback = _FakeTtsAudioPlayback();
      TtsService.instance.debugSetAudioPlayback(playback);
      TtsService.instance.debugSetHttpClient(
        MockClient((_) async =>
            http.Response.bytes(Uint8List.fromList(<int>[1, 2, 3]), 200)),
      );
      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'openai_tts',
          apiKey: 'sk-test',
          baseUrl: 'https://api.openai.com/v1',
        ),
      );

      await TtsService.instance.speak(
        messageId: 'm1',
        text: '你好',
        voice: VoiceOption.fallback,
      );

      expect(playback.playedBytes, <int>[1, 2, 3]);
      expect(TtsService.instance.state, TtsPlaybackState.playing);
      expect(TtsService.instance.isPlayingMessage('m1'), isTrue);

      playback.complete();
      await Future<void>.delayed(Duration.zero);

      expect(TtsService.instance.state, TtsPlaybackState.idle);
      expect(TtsService.instance.currentMessageId, isNull);
    });

    test('停止播放会调用底层播放器并恢复 idle', () async {
      final playback = _FakeTtsAudioPlayback();
      TtsService.instance.debugSetAudioPlayback(playback);
      TtsService.instance.debugSetHttpClient(
        MockClient((_) async =>
            http.Response.bytes(Uint8List.fromList(<int>[4, 5, 6]), 200)),
      );
      TtsService.instance.updateProfile(
        const TtsProfile(
          presetId: 'openai_tts',
          apiKey: 'sk-test',
          baseUrl: 'https://api.openai.com/v1',
        ),
      );
      await TtsService.instance.speak(
        messageId: 'm2',
        text: '停止测试',
        voice: VoiceOption.fallback,
      );

      await TtsService.instance.stop();

      expect(playback.stopCount, 1);
      expect(TtsService.instance.state, TtsPlaybackState.idle);
    });
  });
}

final class _FakeTtsAudioPlayback implements TtsAudioPlayback {
  final StreamController<void> _completion = StreamController<void>.broadcast();
  Uint8List? playedBytes;
  int stopCount = 0;

  @override
  Stream<void> get onComplete => _completion.stream;

  @override
  Future<void> play(Uint8List bytes) async {
    playedBytes = Uint8List.fromList(bytes);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  void complete() => _completion.add(null);
}
