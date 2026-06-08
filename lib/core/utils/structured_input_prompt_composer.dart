import '../../features/chat/data/models/contact.dart';
import '../data/models/app_settings.dart';

class StructuredInputPromptComposer {
  StructuredInputPromptComposer({this.settings = const AppSettings()});

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
      StringBuffer buffer, List<EventNode> nodes, int startIdx) {
    if (nodes.isEmpty) {
      buffer.writeln('- (none)');
      return startIdx;
    }
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final state = node.summarized ? 'summarized' : 'active';
      final line = _clip(node.event.toPromptLine());
      buffer.writeln(
          '- [${startIdx + i}] [$state] ${line.isEmpty ? "(empty)" : line}');
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

  void _writeMemorySection(StringBuffer buffer, Contact contact) {
    _writeStringList(buffer, '世界/背景知识', contact.worldKnowledge.items);
    _writeStringList(buffer, '自我认知', contact.selfKnowledge.items);
    _writeStringList(buffer, '用户认知', contact.userKnowledge.items);

    final short =
        contact.eventGraph.shortTermQueue.take(_maxShortTermEvents).toList();
    final long =
        contact.eventGraph.longTermQueue.take(_maxLongTermEvents).toList();
    final ultra = contact.eventGraph.ultraLongTermQueue
        .take(_maxUltraTermEvents)
        .toList();

    buffer.writeln('### 事件记忆（编号用于 relatedEventIds 关联）');
    buffer.writeln('短期事件:');
    var idx = _writeEventNodes(buffer, short, 0);
    buffer.writeln('长期总结:');
    idx = _writeEventNodes(buffer, long, idx);
    buffer.writeln('历史事件:');
    _writeEventNodes(buffer, ultra, idx);
    buffer.writeln();
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

  String _buildContactPrompt(
    Contact contact, {
    bool needSummary = false,
    List<EventMemory> pendingSummaryEvents = const [],
  }) {
    final buffer = StringBuffer();

    buffer.writeln('## 固定输入内容');
    final fixedInput = contact.fixedInput.trim();
    buffer.writeln(fixedInput.isEmpty ? '名称: ${contact.name}' : fixedInput);
    buffer.writeln();

    buffer.writeln('## 记忆内容');
    _writeMemorySection(buffer, contact);

    buffer.writeln('## 当前状态');
    _writeStateSection(buffer, contact);

    buffer.writeln('## 联想内容');
    _writeEventMemories(buffer, contact.events.items);
    buffer.writeln();

    // 需要总结时，添加往期待总结事件
    if (needSummary && pendingSummaryEvents.isNotEmpty) {
      buffer.writeln('## 往期待总结事件');
      buffer.writeln('以下事件需要你进行综合总结，提取核心脉络和关键信息：');
      for (int i = 0; i < pendingSummaryEvents.length; i++) {
        buffer.writeln('- ${pendingSummaryEvents[i].toPromptLine()}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  static String _buildRules({
    bool isStory = false,
    bool mustSummarize = false,
  }) {
    final modeRule = isStory
        ? '- 你在续写一个虚构故事，用户输入代表下一步发展。'
        : '- 你正在进行角色扮演对话，回复应符合固定输入内容中的身份和语气。';
    final mustSummaryRule = mustSummarize
        ? '- 【强制】本轮必须输出 memoryPatch.summary 字段，因为短期事件队列'
            '已达到总结阈值，需要把过往事件压缩进长期记忆。'
            'summary 的 description 用来综合概括"往期待总结事件"里所有内容。'
        : '- 可选：如果你觉得一个场景/话题已经告一段落，输出 memoryPatch.summary '
            '把它压缩进长期记忆（仅在你认为值得总结时输出，不要每轮都输出）。';
    return '''
## 运行规则
$modeRule
$mustSummaryRule
- 每轮都必须参考四个输入部分：固定输入内容、记忆内容、联想内容、当前状态。
- 固定输入内容是稳定设定，不要在 memoryPatch 中改写它。
- 当前状态只允许更新已经存在的 key；不要新增用户没有创建过的状态 key。
- 如果某个状态发生变化，在 memoryPatch.currentStates 中输出该 key 的新 value。
- 记忆内容和联想内容用于保持连续性，可在重要时写入 memoryPatch 的知识、事件或物品字段。
- 不要输出 Markdown 代码块。
''';
  }

  static String _buildJsonFormat({bool isStory = false}) {
    final typeLabel = isStory ? '故事' : '角色';

    return '''
必须输出合法 JSON，且仅包含以下结构：
{
  "reply": "$typeLabel回复内容",
  "memoryPatch": {
    "worldKnowledge": ["重要的新世界/背景知识，可省略"],
    "selfKnowledge": ["重要的新自我认知，可省略"],
    "userKnowledge": ["重要的新用户认知，可省略"],
    "summary": {"description": "往期事件的综合总结，300字以内。可选输出（仅在场景/话题结束或本轮要求时输出）", "keywords": ["总结关键词1", "总结关键词2"]},
    "eventBrief": {"description": "本次事件的缩写概述，300字以内", "keywords": ["实体关键词1"], "theme": ["主题/氛围1"]},
    "relatedEventIds": [0, 3],
    "belongings": ["(新增)物品名", "(提及)物品名"],
    "currentStates": {"用户创建的状态key": "新的状态value"}
  }
}

输出要求：
1. 必须输出 JSON，不要包含额外说明。
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
''';
  }

  String composeStructuredOutputPrompt({
    required String userInput,
    String? systemPrompt,
    required String outputSchema,
  }) {
    final input = userInput.trim();
    final prompt = (systemPrompt ?? '').trim();
    return <String>[
      '【输出格式】',
      outputSchema,
      '',
      '【输出要求】',
      '1. 必须输出 JSON，不要包含额外说明。',
      '2. JSON 必须可以直接解析，不要包含 Markdown 代码块标记。',
      '',
      if (prompt.isNotEmpty) ...[
        '【系统提示】',
        prompt,
        '',
      ],
      '【用户输入】',
      input,
    ].join('\n');
  }

  String composeSystemPromptWithContactObject({
    required String basePrompt,
    required Contact contact,
    bool mustSummarize = false,
    List<EventMemory> pendingSummaryEvents = const [],
  }) {
    final base = basePrompt.trim();
    final isStory = contact.category == ContactCategory.story;
    final parts = <String>[
      if (base.isNotEmpty) base,
      _buildRules(isStory: isStory, mustSummarize: mustSummarize),
      '## 输出格式',
      _buildJsonFormat(isStory: isStory),
      _buildContactPrompt(contact,
          needSummary: mustSummarize,
          pendingSummaryEvents: pendingSummaryEvents),
      '{"reply":"所有指令均已载入","memoryPatch":{}}',
    ];
    return parts.join('\n\n');
  }
}
