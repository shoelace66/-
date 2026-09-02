import '../../features/chat/data/models/contact.dart';
import '../../features/chat/domain/services/character_behavior_policy.dart';
import '../../features/chat/domain/services/story_control_policy.dart';
import '../../features/worldbook/domain/entities/world_book.dart';
import '../data/models/app_settings.dart';

/// 一次角色扮演请求中可被供应商前缀缓存的 system 消息，以及每轮变化的 user 消息。
class CacheAwarePromptParts {
  const CacheAwarePromptParts({
    required this.systemPrompt,
    required this.userPrompt,
  });

  final String systemPrompt;
  final String userPrompt;

  String get debugView => '【system message（可缓存前缀）】\n$systemPrompt\n\n'
      '【user message（本轮动态内容）】\n$userPrompt';
}

/// 联系人 Prompt 中低频变化的前缀与每轮变化的上下文。
class ContactPromptSections {
  const ContactPromptSections({
    required this.cacheablePrefix,
    required this.dynamicContext,
  });

  final String cacheablePrefix;
  final String dynamicContext;

  String get merged => <String>[cacheablePrefix, dynamicContext]
      .where((part) => part.trim().isNotEmpty)
      .join('\n\n');
}

class StructuredInputPromptComposer {
  StructuredInputPromptComposer({this.settings = const AppSettings()});

  static const String protocolVersion = 'roleplay-memory-v2';

  final AppSettings settings;

  int get _maxPromptListItems => settings.maxPromptListItems;
  int get _maxPromptLineLength => settings.maxPromptLineLength;
  int get _maxShortTermEvents => settings.maxShortTermEvents;
  int get _maxLongTermEvents => settings.maxLongTermEvents;
  int get _maxUltraTermEvents => settings.maxUltraTermEvents;

  String _clip(String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    if (v.length <= _maxPromptLineLength) return v;
    return v.substring(0, _maxPromptLineLength);
  }

  void _writeStringList(StringBuffer buffer, String title, List<String> items) {
    final normalized = items.map(_clip).where((e) => e.isNotEmpty).toList();
    if (normalized.isEmpty) return;
    buffer.writeln('### $title');
    for (final item in normalized.take(_maxPromptListItems)) {
      buffer.writeln('- $item');
    }
    buffer.writeln();
  }

  /// 写入事件节点，带编号（用于 LLM 关联）
  int _writeEventNodes(
    StringBuffer buffer,
    List<EventNode> nodes,
    int startIdx, {
    bool markFirstAsContinuityAnchor = false,
  }) {
    if (nodes.isEmpty) {
      buffer.writeln('- (none)');
      return startIdx;
    }
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final state = node.summarized ? 'summarized' : 'active';
      final line = _clip(node.event.toPromptLine());
      final anchor =
          markFirstAsContinuityAnchor && i == 0 ? ' [上一轮终点/连续性锚点]' : '';
      buffer.writeln(
          '- [${startIdx + i}] [$state]$anchor ${line.isEmpty ? "(empty)" : line}');
    }
    return startIdx + nodes.length;
  }

  void _writeEventMemories(StringBuffer buffer, List<EventMemory> events) {
    if (events.isEmpty) {
      buffer.writeln('- (none)');
      return;
    }
    for (final event in events.take(_maxPromptListItems)) {
      final line = _clip(event.toPromptLine());
      if (line.isEmpty) continue;
      buffer.writeln('- $line');
    }
  }

  void _writeDurableKnowledgeSection(StringBuffer buffer, Contact contact) {
    _writeStringList(buffer, '世界/背景知识', contact.worldKnowledge.items);
    _writeWorldBookSection(buffer, contact.worldBook);
    _writeStringList(buffer, '自我认知', contact.selfKnowledge.items);
    _writeStringList(buffer, '用户认知', contact.userKnowledge.items);
  }

  int _writeDurableEventSection(
    StringBuffer buffer,
    Contact contact,
    int startIdx,
  ) {
    final long =
        contact.eventGraph.longTermQueue.take(_maxLongTermEvents).toList();
    final ultra = contact.eventGraph.ultraLongTermQueue
        .take(_maxUltraTermEvents)
        .toList();

    buffer.writeln('### 低频事件记忆（编号用于 relatedEventIds 关联）');
    buffer.writeln('历史事件:');
    var idx = _writeEventNodes(buffer, ultra, startIdx);
    buffer.writeln('长期总结:');
    idx = _writeEventNodes(buffer, long, idx);
    buffer.writeln();
    return idx;
  }

  int _writeShortTermEventSection(
    StringBuffer buffer,
    Contact contact,
    int startIdx,
  ) {
    final short =
        contact.eventGraph.shortTermQueue.take(_maxShortTermEvents).toList();
    buffer.writeln('### 短期事件（按新到旧）');
    final idx = _writeEventNodes(
      buffer,
      short,
      startIdx,
      markFirstAsContinuityAnchor: true,
    );
    buffer.writeln();
    return idx;
  }

  void _writeStateSection(StringBuffer buffer, Contact contact) {
    final states = <String, String>{...contact.currentStates};

    for (final item in contact.status) {
      final key = item.trim();
      if (key.isNotEmpty) states.putIfAbsent(key, () => '');
    }
    if (contact.mood.trim().isNotEmpty) {
      states.putIfAbsent('mood', () => contact.mood.trim());
    }
    if (contact.time.trim().isNotEmpty) {
      states.putIfAbsent('time', () => contact.time.trim());
    }

    if (states.isEmpty) {
      buffer.writeln('- (none)');
      return;
    }

    for (final entry in states.entries.take(_maxPromptListItems)) {
      final key = _clip(entry.key);
      final value = _clip(entry.value);
      if (key.isEmpty) continue;
      buffer.writeln('$key: ${value.isEmpty ? "(empty)" : value}');
    }
  }

  void _writeWorldBookSection(StringBuffer buffer, WorldBook book) {
    if (book.isEmpty) return;
    final prompt = book.toPromptSection();
    if (prompt.isEmpty) return;
    buffer.writeln('### 世界书');
    buffer.writeln(prompt);
    buffer.writeln();
  }

  String _buildCacheableContactPrompt(Contact contact) {
    final buffer = StringBuffer();

    buffer.writeln('## 固定输入内容');
    final fixedInput = contact.fixedInput.trim();
    buffer.writeln(fixedInput.isEmpty ? '名称: ${contact.name}' : fixedInput);
    buffer.writeln();

    buffer.writeln('## 稳定与低频记忆');
    _writeDurableKnowledgeSection(buffer, contact);
    _writeDurableEventSection(buffer, contact, 0);

    return buffer.toString();
  }

  String _buildDynamicContactPrompt(
    Contact contact, {
    bool needSummary = false,
    List<EventMemory> pendingSummaryEvents = const [],
  }) {
    final buffer = StringBuffer();
    final durableEventCount =
        contact.eventGraph.ultraLongTermQueue.take(_maxUltraTermEvents).length +
            contact.eventGraph.longTermQueue.take(_maxLongTermEvents).length;

    buffer.writeln('## 本轮动态上下文');
    _writeShortTermEventSection(buffer, contact, durableEventCount);

    buffer.writeln('## 当前状态');
    _writeStateSection(buffer, contact);

    buffer.writeln('## 联想内容');
    _writeEventMemories(buffer, contact.events.items);
    buffer.writeln();

    buffer.writeln('## 本轮记忆任务');
    if (needSummary && pendingSummaryEvents.isNotEmpty) {
      buffer.writeln('【强制】本轮必须输出 memoryPatch.summary。');
      buffer.writeln('以下事件需要你进行综合总结，提取核心脉络和关键信息：');
      for (int i = 0; i < pendingSummaryEvents.length; i++) {
        buffer.writeln('- ${pendingSummaryEvents[i].toPromptLine()}');
      }
    } else {
      buffer.writeln('本轮无需强制总结；仅当场景或话题确实告一段落时，才可选输出 memoryPatch.summary。');
    }
    buffer.writeln();

    return buffer.toString();
  }

  static String _buildRules({
    bool isStory = false,
  }) {
    final modeRule = isStory
        ? '- 你在续写一个虚构故事，用户输入代表下一步发展。'
        : '- 你正在进行角色扮演对话，回复应符合固定输入内容中的身份和语气。';
    return '''
## 运行规则
$modeRule
- 每轮都必须参考固定输入、稳定与低频记忆、本轮动态上下文、联想内容和当前状态。
- 固定输入内容是稳定设定，不要在 memoryPatch 中改写它。
- 当前状态只允许更新已经存在的 key；不要新增用户没有创建过的状态 key。
- 如果某个状态发生变化，在 memoryPatch.currentStates 中输出该 key 的新 value。
- 记忆内容和联想内容用于保持连续性，可在重要时写入 memoryPatch 的知识、事件或物品字段。
- 把标记为“上一轮终点/连续性锚点”的事件视为已经发生的事实，从它的结束状态继续。
- 默认上一段 reply 与本轮 reply 会被直接拼接；开头应自然承接动作、感官、对话或因果，不要重新介绍场景或复述上一段。
- 已经开始或完成的动作不得退回意图、准备或尚未发生的阶段；未完成动作要从准确进度继续推进。
- 保持时间、地点、人物姿态、持有物、伤势和认知一致。只有用户明确要求回溯、重置、改写或指出前文错误时，才允许修正既成事实。
- 不要输出 Markdown 代码块。
''';
  }

  static String _buildJsonFormat({bool isStory = false}) {
    final typeLabel = isStory ? '故事' : '角色';
    final modeRules = isStory
        ? const StoryControlPolicy().promptRules()
        : const CharacterBehaviorPolicy().promptRules();
    final numberedModeRules = <String>[
      for (int i = 0; i < modeRules.length; i++) '${10 + i}. ${modeRules[i]}',
    ].join('\n');

    return '''
必须输出合法 JSON，且仅包含以下结构：
{
  "protocolVersion": "$protocolVersion",
  "memoryPatch": {
    "summary": {"description": "往期事件的综合总结，300字以内。可选输出（仅在场景/话题结束或本轮要求时输出）", "keywords": ["总结关键词1", "总结关键词2"]},
    "eventBrief": {"description": "在正文前确定的本轮规范事件，300字以内", "keywords": ["实体关键词1"], "theme": ["主题/氛围1"]},
    "relatedEventIds": [0, 3],
    "worldKnowledge": ["重要的新世界/背景知识，可省略"],
    "selfKnowledge": ["重要的新自我认知，可省略"],
    "userKnowledge": ["重要的新用户认知，可省略"],
    "belongings": ["(新增)物品名", "(提及)物品名"],
    "currentStates": {"用户创建的状态key": "新的状态value"}
  },
  "reply": "$typeLabel回复内容"
}

输出要求：
1. 必须输出 JSON，不要包含额外说明，并严格保持模板字段顺序：先 protocolVersion，再完整生成 memoryPatch，最后生成 reply。
2. 字段无变化时可以省略整个字段。
3. currentStates 只能包含输入中"当前状态"已有的 key。
4. keywords 是实体关键词：包含人物、地点、物品等具体实体，支持不同粒度共存（如"伞"和"花伞"）。应包含文段中出现的以及通过上下文/记忆可推断的内容。
5. theme 是主题/氛围关键词：包含情感、氛围、主题等抽象概念（如"遗憾"、"温暖"、"悬疑"、"紧张"、"浪漫"）。
6. relatedEventIds（严格控制）：仅当本次事件与某个往期事件存在**非常强的因果链**（A 直接导致/促成 B）或**高度相似的主题重复**时，才输出对应编号。
   - **宁缺毋滥**：没有把握时直接省略整个字段，不要为追求"看起来全"而硬连。
   - **上限 2 个**：本轮事件**最多**关联 2 个往期事件，超过就属于无意义堆砌。
   - **不要连环关联**：不能因为 A 与 B 有关、B 与 C 有关，就把 A→B→C 都列上；只列与"本次事件"直接相关的那一段。
   - 编号见"事件记忆"中的 [编号]，用于建立事件关联图（边越多并不代表越好，稀疏但精准的图更有用）。
7. summary 仅在场景/话题完结或本轮强制要求时输出，不要每轮都输出。
8. eventBrief 每轮必须输出。description 要写清“从哪个既有终点承接、本轮推进了什么、最终停在什么状态”，并区分动作是准备中、进行中还是已完成；它不是对 reply 的事后摘要。reply 必须忠实展开 eventBrief，不得另行改变事件结果或把进度倒退。请按普通人阅读速度估算，确保正文可读时长至少 5 秒（推荐不低于约180字），避免只给一句话式收尾。
9. summary 只概括“往期待总结事件”，不得把尚未生成的本轮 reply 混入 summary；必须保留事件的因果顺序、已确认结果和最后状态，不能把已完成事项压缩成计划或意图。
$numberedModeRules
''';
  }

  CacheAwarePromptParts composeStructuredOutputPromptParts({
    required String userInput,
    String? systemPrompt,
    String? dynamicContext,
    required String outputSchema,
  }) {
    final input = userInput.trim();
    final stablePrompt = (systemPrompt ?? '').trim();
    final turnContext = (dynamicContext ?? '').trim();
    final system = <String>[
      '【输出格式】',
      outputSchema.trim(),
      '',
      '【输出要求】',
      '1. 必须输出 JSON，不要包含额外说明。',
      '2. JSON 必须可以直接解析，不要包含 Markdown 代码块标记。',
      if (stablePrompt.isNotEmpty) ...[
        '',
        '【系统提示】',
        stablePrompt,
      ],
    ].join('\n');
    final user = <String>[
      if (turnContext.isNotEmpty) ...[
        '【本轮上下文】',
        turnContext,
        '',
      ],
      '【用户输入】',
      input,
    ].join('\n');
    return CacheAwarePromptParts(systemPrompt: system, userPrompt: user);
  }

  String composeStructuredOutputPrompt({
    required String userInput,
    String? systemPrompt,
    required String outputSchema,
  }) {
    final parts = composeStructuredOutputPromptParts(
      userInput: userInput,
      systemPrompt: systemPrompt,
      outputSchema: outputSchema,
    );
    return <String>[parts.systemPrompt, parts.userPrompt].join('\n\n');
  }

  ContactPromptSections composeSystemPromptSectionsWithContactObject({
    required String basePrompt,
    required Contact contact,
    bool mustSummarize = false,
    List<EventMemory> pendingSummaryEvents = const [],
  }) {
    final base = basePrompt.trim();
    final isStory = contact.category == ContactCategory.story;
    final stableParts = <String>[
      if (base.isNotEmpty) base,
      _buildRules(isStory: isStory),
      '## 输出格式',
      _buildJsonFormat(isStory: isStory),
      '{"protocolVersion":"$protocolVersion","memoryPatch":{},"reply":"所有指令均已载入"}',
      _buildCacheableContactPrompt(contact),
    ];
    return ContactPromptSections(
      cacheablePrefix: stableParts.join('\n\n'),
      dynamicContext: _buildDynamicContactPrompt(
        contact,
        needSummary: mustSummarize,
        pendingSummaryEvents: pendingSummaryEvents,
      ),
    );
  }

  String composeSystemPromptWithContactObject({
    required String basePrompt,
    required Contact contact,
    bool mustSummarize = false,
    List<EventMemory> pendingSummaryEvents = const [],
  }) {
    return composeSystemPromptSectionsWithContactObject(
      basePrompt: basePrompt,
      contact: contact,
      mustSummarize: mustSummarize,
      pendingSummaryEvents: pendingSummaryEvents,
    ).merged;
  }
}
