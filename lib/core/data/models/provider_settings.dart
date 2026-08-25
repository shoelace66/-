import 'package:flutter/foundation.dart';

import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';

/// 提供商预设模板
///
/// 用户在 UI 上选择某个预设后，baseUrl / model / 一些字段会自动套上默认值。
/// 用户仍可手动修改任意字段（实际保存的是 [LLMProfile]，模板只用于快速填写）。
@immutable
class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.defaultModel,
    required this.models,
    this.notes,
  });

  final String id;
  final String label;
  final String baseUrl;
  final String defaultModel;
  final List<String> models;
  final String? notes;

  static const List<ProviderPreset> llmPresets = <ProviderPreset>[
    ProviderPreset(
      id: 'openai',
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      defaultModel: 'gpt-4o-mini',
      models: <String>[
        'gpt-4o',
        'gpt-4o-mini',
        'gpt-4-turbo',
        'gpt-3.5-turbo',
        'o1',
        'o1-mini',
      ],
      notes: '官方 OpenAI 端点，路径 /v1/chat/completions',
    ),
    ProviderPreset(
      id: 'deepseek',
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      defaultModel: 'deepseek-chat',
      models: <String>[
        'deepseek-chat',
        'deepseek-reasoner',
      ],
      notes: '国内常用，OpenAI 兼容',
    ),
    ProviderPreset(
      id: 'moonshot',
      label: 'Moonshot（Kimi）',
      baseUrl: 'https://api.moonshot.cn/v1',
      defaultModel: 'moonshot-v1-8k',
      models: <String>[
        'moonshot-v1-8k',
        'moonshot-v1-32k',
        'moonshot-v1-128k',
      ],
    ),
    ProviderPreset(
      id: 'zhipu',
      label: '智谱 GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      defaultModel: 'glm-4-flash',
      models: <String>[
        'glm-4-flash',
        'glm-4-air',
        'glm-4-airx',
        'glm-4-plus',
        'glm-4-long',
      ],
    ),
    ProviderPreset(
      id: 'qwen',
      label: '通义千问（DashScope）',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      defaultModel: 'qwen-plus',
      models: <String>[
        'qwen-plus',
        'qwen-turbo',
        'qwen-max',
        'qwen-long',
      ],
    ),
    ProviderPreset(
      id: 'doubao',
      label: '豆包（Volcengine Ark）',
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      defaultModel: 'doubao-1-5-pro-32k-250115',
      models: <String>[
        'doubao-1-5-pro-32k-250115',
        'doubao-1-5-lite-32k-250115',
        'doubao-pro-32k',
        'doubao-lite-32k',
      ],
    ),
    ProviderPreset(
      id: 'ollama',
      label: 'Ollama（本地）',
      baseUrl: 'http://localhost:11434/v1',
      defaultModel: 'llama3.1',
      models: <String>[
        'llama3.1',
        'llama3.2',
        'qwen2.5',
        'gemma2',
      ],
      notes: '本地推理服务，OpenAI 兼容',
    ),
    ProviderPreset(
      id: 'vllm',
      label: 'vLLM（自部署）',
      baseUrl: 'http://localhost:8000/v1',
      defaultModel: 'meta-llama/Meta-Llama-3-8B-Instruct',
      models: <String>[
        'meta-llama/Meta-Llama-3-8B-Instruct',
        'Qwen/Qwen2.5-7B-Instruct',
      ],
      notes: '自部署推理服务',
    ),
    ProviderPreset(
      id: 'custom',
      label: '自定义（OpenAI 兼容）',
      baseUrl: '',
      defaultModel: '',
      models: <String>[],
      notes: '任意 OpenAI 兼容服务，自行填写 baseUrl / model',
    ),
  ];

  static const List<ProviderPreset> imagePresets = <ProviderPreset>[
    ProviderPreset(
      id: 'openai_image',
      label: 'OpenAI Images（gpt-image-1 / dall-e-3）',
      baseUrl: 'https://api.openai.com/v1',
      defaultModel: 'gpt-image-1',
      models: <String>['gpt-image-1', 'dall-e-3', 'dall-e-2'],
      notes: 'POST /v1/images/generations',
    ),
    ProviderPreset(
      id: 'stability',
      label: 'Stability AI',
      baseUrl: 'https://api.stability.ai',
      defaultModel: 'stable-image-core',
      models: <String>[
        'stable-image-core',
        'stable-image-ultra',
        'sd3.5-large',
      ],
      notes: 'POST /v2beta/stable-image/generate/core',
    ),
    ProviderPreset(
      id: 'pollinations',
      label: 'Pollinations（免 key）',
      baseUrl: 'https://image.pollinations.ai',
      defaultModel: 'flux',
      models: <String>['flux', 'turbo', 'sd'],
      notes: 'GET /prompt/{描述}，无需 API Key',
    ),
    ProviderPreset(
      id: 'doubao_image',
      label: '豆包（Volcengine Ark）',
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      defaultModel: 'doubao-seedream-3-0-t2i-250415',
      models: <String>[
        'doubao-seedream-3-0-t2i-250415',
        'doubao-seedream-2-0-t2i-250415',
      ],
      notes: 'POST /images/generations',
    ),
    ProviderPreset(
      id: 'custom_image',
      label: '自定义（OpenAI Images 兼容）',
      baseUrl: '',
      defaultModel: '',
      models: <String>[],
    ),
  ];

  static const List<ProviderPreset> ttsPresets = <ProviderPreset>[
    ProviderPreset(
      id: 'edge_tts',
      label: 'Edge TTS（免费 · 微软公开）',
      baseUrl: 'https://api.tts.fynote.com',
      defaultModel: 'zh-CN-XiaoxiaoNeural',
      models: <String>[],
      notes: '需要中转服务或本地 edge_tts 代理；音色列表见联系人编辑',
    ),
    ProviderPreset(
      id: 'openai_tts',
      label: 'OpenAI TTS',
      baseUrl: 'https://api.openai.com/v1',
      defaultModel: 'tts-1',
      models: <String>['tts-1', 'tts-1-hd', 'gpt-4o-mini-tts'],
      notes: 'POST /v1/audio/speech',
    ),
    ProviderPreset(
      id: 'custom_tts',
      label: '自定义（POST 文本返回音频）',
      baseUrl: '',
      defaultModel: '',
      models: <String>[],
    ),
  ];

  static ProviderPreset findById(String? id, List<ProviderPreset> list) {
    if (id == null || id.isEmpty) return list.last;
    for (final p in list) {
      if (p.id == id) return p;
    }
    return list.last;
  }
}

/// LLM 调用参数（运行时下发到 AiService）
@immutable
class LlmParameters {
  const LlmParameters({
    this.temperature = 0.7,
    this.topP = 1.0,
    this.maxTokens = 2048,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.timeoutSeconds = 60,
    this.stream = false,
  });

  /// 0.0 - 2.0
  final double temperature;

  /// 0.0 - 1.0
  final double topP;

  /// 单次回复最大 token，0 = 不限制
  final int maxTokens;

  /// -2.0 - 2.0
  final double frequencyPenalty;
  final double presencePenalty;

  /// 请求超时秒数
  final int timeoutSeconds;

  /// 是否通过 OpenAI 兼容 SSE 增量接收回复。
  /// 完整 JSON 到达后才会提交 memoryPatch。
  final bool stream;

  LlmParameters copyWith({
    double? temperature,
    double? topP,
    int? maxTokens,
    double? frequencyPenalty,
    double? presencePenalty,
    int? timeoutSeconds,
    bool? stream,
  }) {
    return LlmParameters(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: maxTokens ?? this.maxTokens,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      stream: stream ?? this.stream,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'temperature': temperature,
        'topP': topP,
        'maxTokens': maxTokens,
        'frequencyPenalty': frequencyPenalty,
        'presencePenalty': presencePenalty,
        'timeoutSeconds': timeoutSeconds,
        'stream': stream,
      };

  factory LlmParameters.fromJson(Map<String, dynamic> json) {
    return LlmParameters(
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      topP: (json['topP'] as num?)?.toDouble() ?? 1.0,
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 2048,
      frequencyPenalty: (json['frequencyPenalty'] as num?)?.toDouble() ?? 0.0,
      presencePenalty: (json['presencePenalty'] as num?)?.toDouble() ?? 0.0,
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 60,
      stream: json['stream'] == true,
    );
  }
}

/// LLM 提供商完整配置
@immutable
class LlmProfile {
  const LlmProfile({
    this.presetId = 'deepseek',
    this.apiKey = '',
    this.baseUrl = 'https://api.deepseek.com',
    this.model = 'deepseek-chat',
    this.parameters = const LlmParameters(),
    this.inputPricePerMillion = 0,
    this.outputPricePerMillion = 0,
  });

  final String presetId;
  final String apiKey;
  final String baseUrl;
  final String model;
  final LlmParameters parameters;
  final double inputPricePerMillion;
  final double outputPricePerMillion;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  LlmProfile copyWith({
    String? presetId,
    String? apiKey,
    String? baseUrl,
    String? model,
    LlmParameters? parameters,
    double? inputPricePerMillion,
    double? outputPricePerMillion,
  }) {
    return LlmProfile(
      presetId: presetId ?? this.presetId,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      parameters: parameters ?? this.parameters,
      inputPricePerMillion: inputPricePerMillion ?? this.inputPricePerMillion,
      outputPricePerMillion:
          outputPricePerMillion ?? this.outputPricePerMillion,
    );
  }

  /// 从预设 ID 派生默认字段（用于"切换预设"时快速套用）
  LlmProfile withPresetDefaults({String? overrideModel}) {
    final preset = ProviderPreset.findById(presetId, ProviderPreset.llmPresets);
    return copyWith(
      baseUrl: preset.baseUrl,
      model: overrideModel ??
          (preset.defaultModel.isNotEmpty ? preset.defaultModel : model),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'presetId': presetId,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'model': model,
        'parameters': parameters.toJson(),
        'inputPricePerMillion': inputPricePerMillion,
        'outputPricePerMillion': outputPricePerMillion,
      };

  factory LlmProfile.fromJson(Map<String, dynamic> json) {
    final rawParams = json['parameters'];
    return LlmProfile(
      presetId: (json['presetId'] ?? 'deepseek').toString(),
      apiKey: (json['apiKey'] ?? '').toString(),
      baseUrl: (json['baseUrl'] ?? 'https://api.deepseek.com').toString(),
      model: (json['model'] ?? 'deepseek-chat').toString(),
      parameters: rawParams is Map
          ? LlmParameters.fromJson(
              rawParams.map((k, v) => MapEntry(k.toString(), v)),
            )
          : const LlmParameters(),
      inputPricePerMillion:
          (json['inputPricePerMillion'] as num?)?.toDouble() ?? 0,
      outputPricePerMillion:
          (json['outputPricePerMillion'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// 生图调用参数
@immutable
class ImageParameters {
  const ImageParameters({
    this.size = '1024x1024',
    this.n = 1,
    this.style = '',
    this.quality = 'standard',
    this.responseFormat = 'url',
    this.timeoutSeconds = 120,
  });

  /// OpenAI Images 支持：256x256 / 512x512 / 1024x1024 等
  final String size;

  /// 生成数量
  final int n;

  /// 风格（vivid / natural 等，部分服务支持）
  final String style;

  /// standard / hd（OpenAI dall-e-3）
  final String quality;

  /// url / b64_json
  final String responseFormat;

  final int timeoutSeconds;

  ImageParameters copyWith({
    String? size,
    int? n,
    String? style,
    String? quality,
    String? responseFormat,
    int? timeoutSeconds,
  }) {
    return ImageParameters(
      size: size ?? this.size,
      n: n ?? this.n,
      style: style ?? this.style,
      quality: quality ?? this.quality,
      responseFormat: responseFormat ?? this.responseFormat,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'size': size,
        'n': n,
        'style': style,
        'quality': quality,
        'responseFormat': responseFormat,
        'timeoutSeconds': timeoutSeconds,
      };

  factory ImageParameters.fromJson(Map<String, dynamic> json) {
    return ImageParameters(
      size: (json['size'] ?? '1024x1024').toString(),
      n: (json['n'] as num?)?.toInt() ?? 1,
      style: (json['style'] ?? '').toString(),
      quality: (json['quality'] ?? 'standard').toString(),
      responseFormat: (json['responseFormat'] ?? 'url').toString(),
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 120,
    );
  }
}

/// 生图提供商完整配置
@immutable
class ImageProfile {
  const ImageProfile({
    this.presetId = 'openai_image',
    this.apiKey = '',
    this.baseUrl = 'https://api.openai.com/v1',
    this.model = 'gpt-image-1',
    this.parameters = const ImageParameters(),
  });

  final String presetId;
  final String apiKey;
  final String baseUrl;
  final String model;
  final ImageParameters parameters;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  ImageProfile copyWith({
    String? presetId,
    String? apiKey,
    String? baseUrl,
    String? model,
    ImageParameters? parameters,
  }) {
    return ImageProfile(
      presetId: presetId ?? this.presetId,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      parameters: parameters ?? this.parameters,
    );
  }

  ImageProfile withPresetDefaults({String? overrideModel}) {
    final preset =
        ProviderPreset.findById(presetId, ProviderPreset.imagePresets);
    return copyWith(
      baseUrl: preset.baseUrl,
      model: overrideModel ??
          (preset.defaultModel.isNotEmpty ? preset.defaultModel : model),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'presetId': presetId,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'model': model,
        'parameters': parameters.toJson(),
      };

  factory ImageProfile.fromJson(Map<String, dynamic> json) {
    final rawParams = json['parameters'];
    return ImageProfile(
      presetId: (json['presetId'] ?? 'openai_image').toString(),
      apiKey: (json['apiKey'] ?? '').toString(),
      baseUrl: (json['baseUrl'] ?? 'https://api.openai.com/v1').toString(),
      model: (json['model'] ?? 'gpt-image-1').toString(),
      parameters: rawParams is Map
          ? ImageParameters.fromJson(
              rawParams.map((k, v) => MapEntry(k.toString(), v)),
            )
          : const ImageParameters(),
    );
  }
}

/// TTS 厂商配置
@immutable
class TtsProfile {
  const TtsProfile({
    this.presetId = 'edge_tts',
    this.apiKey = '',
    this.baseUrl = 'https://api.tts.fynote.com',
    this.model = 'zh-CN-XiaoxiaoNeural',
    this.timeoutSeconds = 60,
  });

  final String presetId;
  final String apiKey;
  final String baseUrl;

  /// 当 presetId == 'edge_tts' 时，model 字段是 edge-tts 音色 ID；
  /// 当 presetId == 'openai_tts' 时，model 字段是 tts-1 / tts-1-hd / gpt-4o-mini-tts
  final String model;

  final int timeoutSeconds;

  TtsProfile copyWith({
    String? presetId,
    String? apiKey,
    String? baseUrl,
    String? model,
    int? timeoutSeconds,
  }) {
    return TtsProfile(
      presetId: presetId ?? this.presetId,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  TtsProfile withPresetDefaults({String? overrideModel}) {
    final preset = ProviderPreset.findById(presetId, ProviderPreset.ttsPresets);
    return copyWith(
      baseUrl: preset.baseUrl,
      model: overrideModel ??
          (preset.defaultModel.isNotEmpty ? preset.defaultModel : model),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'presetId': presetId,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'model': model,
        'timeoutSeconds': timeoutSeconds,
      };

  factory TtsProfile.fromJson(Map<String, dynamic> json) {
    return TtsProfile(
      presetId: (json['presetId'] ?? 'edge_tts').toString(),
      apiKey: (json['apiKey'] ?? '').toString(),
      baseUrl: (json['baseUrl'] ?? 'https://api.tts.fynote.com').toString(),
      model: (json['model'] ?? 'zh-CN-XiaoxiaoNeural').toString(),
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 60,
    );
  }
}

/// 三个 provider 配置的合集，持久化到 SharedPreferences 一份
@immutable
class ProviderSettings {
  const ProviderSettings({
    this.llm = const LlmProfile(),
    this.fallbackLlmProfiles = const <LlmProfile>[],
    this.image = const ImageProfile(),
    this.tts = const TtsProfile(),
  });

  final LlmProfile llm;
  final List<LlmProfile> fallbackLlmProfiles;
  final ImageProfile image;
  final TtsProfile tts;

  ProviderSettings copyWith({
    LlmProfile? llm,
    List<LlmProfile>? fallbackLlmProfiles,
    ImageProfile? image,
    TtsProfile? tts,
  }) {
    return ProviderSettings(
      llm: llm ?? this.llm,
      fallbackLlmProfiles: fallbackLlmProfiles ?? this.fallbackLlmProfiles,
      image: image ?? this.image,
      tts: tts ?? this.tts,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'llm': llm.toJson(),
        'fallbackLlmProfiles': fallbackLlmProfiles
            .map((profile) => profile.toJson())
            .toList(growable: false),
        'image': image.toJson(),
        'tts': tts.toJson(),
      };

  factory ProviderSettings.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(dynamic v) {
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), val));
      }
      return <String, dynamic>{};
    }

    return ProviderSettings(
      llm: LlmProfile.fromJson(asMap(json['llm'])),
      fallbackLlmProfiles: (json['fallbackLlmProfiles'] as List?)
              ?.whereType<Map>()
              .map((value) => LlmProfile.fromJson(asMap(value)))
              .toList(growable: false) ??
          const <LlmProfile>[],
      image: ImageProfile.fromJson(asMap(json['image'])),
      tts: TtsProfile.fromJson(asMap(json['tts'])),
    );
  }
}

/// 解析 TTS 服务返回的音频 bytes
///
/// 不同服务商的实现不同，但最终我们都需要拿到一个 `Uint8List` 给播放器。
/// 这里保留为 typedef，方便未来扩展。
typedef TtsAudioBytes = List<int>;

/// 工具函数：从 TtsProfile + 单条消息的音色 解析出最终使用的音色 ID
///
/// - 当前联系人编辑器里也可以单独选择音色（[VoiceOption]），这里允许它
///   覆盖 [TtsProfile.model] 字段。
/// - 如果 [overrideVoice] 为空或不在 [VoiceOption.presets] 里，就用
///   profile.model。
String resolveTtsVoice({
  required TtsProfile profile,
  String? overrideVoice,
}) {
  final v = VoiceOption.findById(overrideVoice);
  if (v != null) return v.id;
  return profile.model;
}
