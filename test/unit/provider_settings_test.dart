import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';

void main() {
  group('LlmParameters', () {
    test('默认值', () {
      const p = LlmParameters();
      expect(p.temperature, 0.7);
      expect(p.topP, 1.0);
      expect(p.maxTokens, 2048);
      expect(p.frequencyPenalty, 0.0);
      expect(p.presencePenalty, 0.0);
      expect(p.timeoutSeconds, 60);
      expect(p.stream, isFalse);
    });

    test('copyWith 只覆盖指定字段', () {
      const p = LlmParameters();
      final n = p.copyWith(temperature: 0.2, stream: true);
      expect(n.temperature, 0.2);
      expect(n.stream, isTrue);
      expect(n.topP, 1.0);
    });

    test('JSON 往返', () {
      const p = LlmParameters(
        temperature: 0.5,
        topP: 0.9,
        maxTokens: 1024,
        frequencyPenalty: 0.3,
        presencePenalty: -0.2,
        timeoutSeconds: 90,
        stream: true,
      );
      final restored = LlmParameters.fromJson(p.toJson());
      expect(restored.temperature, 0.5);
      expect(restored.topP, 0.9);
      expect(restored.maxTokens, 1024);
      expect(restored.frequencyPenalty, 0.3);
      expect(restored.presencePenalty, -0.2);
      expect(restored.timeoutSeconds, 90);
      expect(restored.stream, isTrue);
    });

    test('fromJson 在缺字段时使用默认值', () {
      final restored = LlmParameters.fromJson(const <String, dynamic>{});
      expect(restored.temperature, 0.7);
      expect(restored.stream, isFalse);
    });
  });

  group('LlmProfile', () {
    test('默认值是 deepseek', () {
      const p = LlmProfile();
      expect(p.presetId, 'deepseek');
      expect(p.baseUrl, 'https://api.deepseek.com');
      expect(p.model, 'deepseek-chat');
    });

    test('withPresetDefaults 套用预设 baseUrl 和 model', () {
      const p = LlmProfile(presetId: 'openai');
      final n = p.withPresetDefaults();
      expect(n.baseUrl, 'https://api.openai.com/v1');
      expect(n.model, 'gpt-4o-mini');
    });

    test('JSON 往返', () {
      const p = LlmProfile(
        presetId: 'openai',
        apiKey: 'sk-test',
        baseUrl: 'https://x',
        model: 'gpt-4o',
      );
      final restored = LlmProfile.fromJson(p.toJson());
      expect(restored.presetId, 'openai');
      expect(restored.apiKey, 'sk-test');
      expect(restored.model, 'gpt-4o');
    });
  });

  group('ImageProfile', () {
    test('默认值是 openai_image', () {
      const p = ImageProfile();
      expect(p.presetId, 'openai_image');
      expect(p.baseUrl, 'https://api.openai.com/v1');
      expect(p.model, 'gpt-image-1');
    });

    test('pollinations 预设默认 model 为 flux', () {
      const p = ImageProfile(presetId: 'pollinations');
      final n = p.withPresetDefaults();
      expect(n.baseUrl, 'https://image.pollinations.ai');
      expect(n.model, 'flux');
    });
  });

  group('ImageParameters', () {
    test('JSON 往返', () {
      const p = ImageParameters(
        size: '512x512',
        n: 2,
        style: 'vivid',
        quality: 'hd',
        responseFormat: 'b64_json',
        timeoutSeconds: 60,
      );
      final restored = ImageParameters.fromJson(p.toJson());
      expect(restored.size, '512x512');
      expect(restored.n, 2);
      expect(restored.style, 'vivid');
      expect(restored.quality, 'hd');
      expect(restored.responseFormat, 'b64_json');
      expect(restored.timeoutSeconds, 60);
    });
  });

  group('TtsProfile', () {
    test('默认值是 edge_tts', () {
      const p = TtsProfile();
      expect(p.presetId, 'edge_tts');
      expect(p.model, 'zh-CN-XiaoxiaoNeural');
    });

    test('openai_tts 预设默认 model 为 tts-1', () {
      const p = TtsProfile(presetId: 'openai_tts');
      final n = p.withPresetDefaults();
      expect(n.baseUrl, 'https://api.openai.com/v1');
      expect(n.model, 'tts-1');
    });

    test('JSON 往返', () {
      const p = TtsProfile(
        presetId: 'openai_tts',
        apiKey: 'sk-test',
        baseUrl: 'https://x',
        model: 'tts-1-hd',
        timeoutSeconds: 90,
      );
      final restored = TtsProfile.fromJson(p.toJson());
      expect(restored.presetId, 'openai_tts');
      expect(restored.apiKey, 'sk-test');
      expect(restored.model, 'tts-1-hd');
      expect(restored.timeoutSeconds, 90);
    });
  });

  group('ProviderSettings', () {
    test('默认值是 deepseek / openai / edge_tts', () {
      const s = ProviderSettings();
      expect(s.llm.presetId, 'deepseek');
      expect(s.image.presetId, 'openai_image');
      expect(s.tts.presetId, 'edge_tts');
    });

    test('JSON 往返', () {
      const s = ProviderSettings(
        llm: LlmProfile(
          presetId: 'openai',
          apiKey: 'sk',
          baseUrl: 'https://x',
          model: 'gpt-4o',
          parameters: LlmParameters(temperature: 0.2),
          inputPricePerMillion: 1.5,
          outputPricePerMillion: 6,
        ),
        fallbackLlmProfiles: <LlmProfile>[
          LlmProfile(apiKey: 'fallback', model: 'fallback-model'),
        ],
        memoryRecallLlm: LlmProfile(
          presetId: 'openai',
          apiKey: 'recall-key',
          baseUrl: 'https://recall.example/v1',
          model: 'cheap-model',
          parameters: LlmParameters(
            temperature: 0,
            maxTokens: 128,
            timeoutSeconds: 12,
          ),
        ),
        image: ImageProfile(
          presetId: 'pollinations',
          baseUrl: 'https://x',
          model: 'flux',
        ),
        tts: TtsProfile(
          presetId: 'openai_tts',
          apiKey: 'sk',
          baseUrl: 'https://x',
          model: 'tts-1',
        ),
      );
      final restored = ProviderSettings.fromJson(s.toJson());
      expect(restored.llm.presetId, 'openai');
      expect(restored.llm.parameters.temperature, 0.2);
      expect(restored.llm.inputPricePerMillion, 1.5);
      expect(restored.llm.outputPricePerMillion, 6);
      expect(restored.fallbackLlmProfiles.single.model, 'fallback-model');
      expect(restored.memoryRecallLlm?.apiKey, 'recall-key');
      expect(restored.memoryRecallLlm?.model, 'cheap-model');
      expect(restored.memoryRecallLlm?.parameters.maxTokens, 128);
      expect(restored.image.presetId, 'pollinations');
      expect(restored.tts.presetId, 'openai_tts');
    });

    test('fromJson 在缺字段时使用子项默认', () {
      final restored = ProviderSettings.fromJson(const <String, dynamic>{});
      expect(restored.llm.presetId, 'deepseek');
      expect(restored.memoryRecallLlm, isNull);
      expect(restored.image.presetId, 'openai_image');
      expect(restored.tts.presetId, 'edge_tts');
    });

    test('copyWith 可保留、替换和清除事件召回模型', () {
      const original = ProviderSettings(
        memoryRecallLlm: LlmProfile(apiKey: 'old', model: 'cheap-old'),
      );

      expect(original.copyWith().memoryRecallLlm?.model, 'cheap-old');
      expect(
        original
            .copyWith(
              memoryRecallLlm:
                  const LlmProfile(apiKey: 'new', model: 'cheap-new'),
            )
            .memoryRecallLlm
            ?.model,
        'cheap-new',
      );
      expect(
        original.copyWith(clearMemoryRecallLlm: true).memoryRecallLlm,
        isNull,
      );
    });
  });

  group('ProviderPreset', () {
    test('llmPresets 包含主流 OpenAI 兼容厂商', () {
      final ids = ProviderPreset.llmPresets.map((p) => p.id).toList();
      expect(ids, contains('openai'));
      expect(ids, contains('deepseek'));
      expect(ids, contains('moonshot'));
      expect(ids, contains('zhipu'));
      expect(ids, contains('qwen'));
      expect(ids, contains('doubao'));
      expect(ids, contains('ollama'));
      expect(ids, contains('vllm'));
      expect(ids, contains('custom'));
    });

    test('imagePresets 包含 stability / pollinations / doubao', () {
      final ids = ProviderPreset.imagePresets.map((p) => p.id).toList();
      expect(ids, contains('openai_image'));
      expect(ids, contains('stability'));
      expect(ids, contains('pollinations'));
      expect(ids, contains('doubao_image'));
    });

    test('ttsPresets 包含 edge_tts / openai_tts / custom', () {
      final ids = ProviderPreset.ttsPresets.map((p) => p.id).toList();
      expect(ids, contains('edge_tts'));
      expect(ids, contains('openai_tts'));
      expect(ids, contains('custom_tts'));
    });

    test('findById 找不到时回退到列表最后一项（custom）', () {
      final p =
          ProviderPreset.findById('nonexistent', ProviderPreset.llmPresets);
      expect(p.id, 'custom');
    });
  });

  group('resolveTtsVoice', () {
    test('有 override 且在 VoiceOption.presets 里时使用 override', () {
      final id = resolveTtsVoice(
        profile: const TtsProfile(model: 'tts-1'),
        overrideVoice: 'zh-CN-YunxiNeural',
      );
      expect(id, 'zh-CN-YunxiNeural');
    });

    test('override 不在 preset 里或为空时回退到 profile.model', () {
      final id = resolveTtsVoice(
        profile: const TtsProfile(model: 'tts-1'),
        overrideVoice: 'invalid-voice',
      );
      expect(id, 'tts-1');

      final id2 = resolveTtsVoice(
        profile: const TtsProfile(model: 'tts-1-hd'),
        overrideVoice: null,
      );
      expect(id2, 'tts-1-hd');
    });
  });
}
