import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/chat/data/models/contact.dart';
import 'structured_output_regex_parser.dart';

/// 生图 prompt 润色结果
@immutable
class PolishedImagePrompt {
  const PolishedImagePrompt({
    required this.englishPrompt,
    required this.negativePrompt,
    this.seed,
    this.appearanceSignature = '',
  });

  /// 实际送给生图 API 的英文 prompt
  final String englishPrompt;

  /// 负面提示词（用户没要求时为空字符串，但保留字段方便 UI 展示）
  final String negativePrompt;

  /// 固定种子，用于支持 seed 的 Provider 实现角色外观一致性
  final int? seed;

  /// 角色外观特征签名，用于 Prompt 前缀固定
  final String appearanceSignature;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'englishPrompt': englishPrompt,
        'negativePrompt': negativePrompt,
        if (seed != null) 'seed': seed,
        if (appearanceSignature.isNotEmpty)
          'appearanceSignature': appearanceSignature,
      };
}

/// 把"用户的口语化中文描述 + 当前联系人设定"翻译成结构化英文生图 prompt
///
/// 设计原则：
/// - **不依赖 AI** 在 service 内直接调，而是把构造好的 system prompt 字符串暴露出来
///   让调用方走 `AiService.ask(...)`，这样能复用现有 LLM provider 配置、超时、错误处理
/// - 输出是一段 **结构化 JSON**（`englishPrompt` + `negativePrompt`），
///   用 [StructuredOutputRegexParser] 解析，兼容不同 LLM 的返回风格
/// - prompt 模板和联系人上下文抽离，方便单测
class ImagePromptPolisher {
  ImagePromptPolisher._internal();

  static final ImagePromptPolisher instance = ImagePromptPolisher._internal();

  /// 把联系人关键字段压平成一段"风格描述"，给 LLM 用来理解语境
  String buildContactContext(Contact? contact) {
    if (contact == null) return '（无联系人设定）';
    final lines = <String>[];
    lines.add('name: ${contact.name}');
    if (contact.category == ContactCategory.story) {
      lines.add('type: story（故事 / 世界观）');
    } else if (contact.category == ContactCategory.assistant) {
      lines.add('type: assistant（通用助手，无视觉人设）');
    } else {
      lines.add('type: character（角色）');
    }

    void addList(String label, List<String> items) {
      if (items.isEmpty) return;
      final joined = items.where((s) => s.trim().isNotEmpty).join('；');
      if (joined.isNotEmpty) lines.add('$label: $joined');
    }

    addList('personality', contact.personality);
    addList('appearance', contact.appearance);
    addList('personalInfo', contact.personalInfo);
    addList('backgroundStory', contact.backgroundStory);
    addList('narrativeRules', contact.narrativeRules);
    addList('otherCharacteristics', contact.otherCharacteristics);
    addList('belongings', contact.belongings);
    addList('status', contact.status);
    if (contact.mood.trim().isNotEmpty) {
      lines.add('mood: ${contact.mood}');
    }
    if (contact.time.trim().isNotEmpty) {
      lines.add('time: ${contact.time}');
    }
    if (contact.currentStates.isNotEmpty) {
      final pairs = contact.currentStates.entries
          .where((e) => e.value.trim().isNotEmpty)
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
      if (pairs.isNotEmpty) lines.add('currentStates: $pairs');
    }
    return lines.join('\n');
  }

  /// 提取角色外观特征签名，用于 Prompt 固定前缀
  ///
  /// 算法：将角色的 appearance + personality + name 合并为固定特征描述串，
  /// 每次生图都作为 Prompt 前缀，保证同一角色输出一致的视觉风格。
  String buildAppearanceSignature(Contact contact) {
    final parts = <String>[];
    if (contact.appearance.isNotEmpty) {
      parts.addAll(contact.appearance);
    }
    if (contact.personality.isNotEmpty) {
      parts.add(contact.personality.take(3).join('、'));
    }
    return parts.isNotEmpty ? parts.join('，') : '';
  }

  /// 从联系人 ID 和外观特征推导固定种子
  ///
  /// 同一角色始终使用相同 seed，保证支持 seed 参数的 Provider 输出一致。
  static int deriveSeed(Contact contact) {
    final raw = contact.id.hashCode * 31 + contact.appearance.join().hashCode;
    return raw & 0x7FFFFFFF;
  }

  /// 生成发给 LLM 的 system prompt
  ///
  /// 强调"输出结构化 JSON"，并用 LLM 角色来稳定英文表达
  String buildSystemPrompt() {
    return '''
你是一个专业的 AI 图像生成 prompt 工程师。
任务：把用户给的中文描述（可能很口语化、不完整），结合"当前联系人/角色的设定"，
扩写、改写成一段 **结构化、具体、有画面感、英文** 的图像生成 prompt，供 Stable
Diffusion / DALL-E / Midjourney 等模型使用。

要求：
1. **必须用英文** 输出 prompt。中文描述里的实体、场景、风格要翻译/转写成英文术语
   （如 "赛博朋克" → "cyberpunk cityscape, neon lights, rain"）。
2. 充分利用"联系人设定"里的 personality / appearance / backgroundStory / mood 等，
   把角色的视觉特征自然融入 prompt（不需要把所有字段都列出来，按场景相关度挑选）。
3. prompt 长度控制在 30~80 词之间，逗号分隔的标签 + 短句风格（不要长段落）。
4. 涉及人物时，注明人物的动作、视角（portrait / full body / close-up 等）。
5. 同时输出一段 **negative prompt**（不要出现的元素）：
   "blurry, low quality, deformed, extra fingers, watermark, text"。
6. **严格按以下 JSON 格式输出**（不要输出任何解释、Markdown 代码块、注释）：

{
  "englishPrompt": "...",
  "negativePrompt": "..."
}
''';
  }

  /// 组装最终送给 LLM 的 user prompt
String buildUserPrompt({
    required String userDescription,
    required String contactContext,
    String appearanceSignature = '',
  }) {
    final sigBlock = appearanceSignature.isNotEmpty
        ? '\n# 角色固定外观特征（每次生图都必须包含，确保一致性）\n$appearanceSignature\n'
        : '';
    return '''
# 联系人 / 角色设定
$contactContext$sigBlock
# 用户原始描述（中文）
$userDescription

# 任务
请结合"联系人设定"+"用户原始描述"，输出符合要求的 JSON。
''';
  }

  /// 调用 LLM 润色 prompt
  ///
  /// [ask] 是注入的 LLM 调用函数（默认走 [AiService.ask]），
  /// 方便在测试里换成 mock。
  Future<PolishedImagePrompt> polish({
    required String userDescription,
    Contact? contact,
    required Future<String> Function(String systemPrompt, String userPrompt)
        ask,
  }) async {
    final systemPrompt = buildSystemPrompt();
    final contactContext = buildContactContext(contact);
    final appearanceSignature =
        contact != null ? buildAppearanceSignature(contact) : '';
    final userPrompt = buildUserPrompt(
      userDescription: userDescription,
      contactContext: contactContext,
      appearanceSignature: appearanceSignature,
    );
    final response = await ask(systemPrompt, userPrompt);

    // 先尝试直接 parse 整段响应
    var english = '';
    var negative = '';
    try {
      final asJson = _tryDecodeJson(response);
      if (asJson != null) {
        english = (asJson['englishPrompt'] ?? '').toString();
        negative = (asJson['negativePrompt'] ?? '').toString();
      }
    } catch (_) {}

    // 不行就用正则抓 "englishPrompt": "..." 和 "negativePrompt": "..."
    if (english.isEmpty) {
      english = _extractField(response, 'englishPrompt');
    }
    if (negative.isEmpty) {
      negative = _extractField(response, 'negativePrompt');
    }

    english = english.trim();
    negative = negative.trim();

    if (english.isEmpty) {
      // LLM 完全没有返回结构化结果时退化用原描述
      english = userDescription.trim();
    }
    if (negative.isEmpty) {
      negative =
          'blurry, low quality, deformed, extra fingers, watermark, text';
    }

    return PolishedImagePrompt(
      englishPrompt: english,
      negativePrompt: negative,
      seed: contact != null ? deriveSeed(contact) : null,
      appearanceSignature: appearanceSignature,
    );
  }

  Map<String, dynamic>? _tryDecodeJson(String response) {
    final trimmed = response.trim();
    if (trimmed.isEmpty) return null;
    try {
      return StructuredOutputRegexParser.parsePrimaryPayload(trimmed);
    } catch (_) {
      return null;
    }
  }

  String _extractField(String response, String field) {
    // 容忍 key 带双/单引号、value 带双/单引号
    final key = '''['"]?$field['"]?''';
    final patterns = <RegExp>[
      RegExp('$key\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"', dotAll: true),
      RegExp("$key\\s*:\\s*'((?:\\\\.|[^'\\\\])*)'", dotAll: true),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(response);
      if (m != null) {
        return m.group(1) ?? '';
      }
    }
    return '';
  }
}
