enum ContactCategory { story, contact, assistant }

class LruReadyBucket {
  const LruReadyBucket._({
    required this.items,
    required this.indexByValue,
  });

  factory LruReadyBucket([List<String> source = const <String>[]]) {
    final normalized = <String>[];
    final index = <String, int>{};
    for (final raw in source) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      if (index.containsKey(value)) continue;
      normalized.add(value);
      index[value] = normalized.length - 1;
    }
    return LruReadyBucket._(
      items: List<String>.unmodifiable(normalized),
      indexByValue: Map<String, int>.unmodifiable(index),
    );
  }

  const LruReadyBucket.empty()
      : items = const <String>[],
        indexByValue = const <String, int>{};

  final List<String> items;
  final Map<String, int> indexByValue;
}

class WorldKnowledgeBucket extends LruReadyBucket {
  factory WorldKnowledgeBucket([List<String> source = const <String>[]]) {
    final base = LruReadyBucket(source);
    return WorldKnowledgeBucket._(
      items: base.items,
      indexByValue: base.indexByValue,
    );
  }

  const WorldKnowledgeBucket._({
    required super.items,
    required super.indexByValue,
  }) : super._();

  const WorldKnowledgeBucket.empty() : super.empty();
}

class SelfKnowledgeBucket extends LruReadyBucket {
  factory SelfKnowledgeBucket([List<String> source = const <String>[]]) {
    final base = LruReadyBucket(source);
    return SelfKnowledgeBucket._(
      items: base.items,
      indexByValue: base.indexByValue,
    );
  }

  const SelfKnowledgeBucket._({
    required super.items,
    required super.indexByValue,
  }) : super._();

  const SelfKnowledgeBucket.empty() : super.empty();
}

class UserKnowledgeBucket extends LruReadyBucket {
  factory UserKnowledgeBucket([List<String> source = const <String>[]]) {
    final base = LruReadyBucket(source);
    return UserKnowledgeBucket._(
      items: base.items,
      indexByValue: base.indexByValue,
    );
  }

  const UserKnowledgeBucket._({
    required super.items,
    required super.indexByValue,
  }) : super._();

  const UserKnowledgeBucket.empty() : super.empty();
}

class EventMemory {
  const EventMemory({
    this.time = '',
    this.location = '',
    this.characters = '',
    this.cause = '',
    this.process = '',
    this.result = '',
    this.attitude = '',
    this.sourceDialog = '',
  });

  final String time;
  final String location;
  final String characters;
  final String cause;
  final String process;
  final String result;
  final String attitude;

  /// 原始对话内容（用户输入 + LLM 输出），用于事件总结时提供上下文
  final String sourceDialog;

  bool get isEmpty =>
      time.trim().isEmpty &&
      location.trim().isEmpty &&
      characters.trim().isEmpty &&
      cause.trim().isEmpty &&
      process.trim().isEmpty &&
      result.trim().isEmpty &&
      attitude.trim().isEmpty;

  factory EventMemory.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();
    return EventMemory(
      time: read('time'),
      location: read('location'),
      characters: read('characters'),
      cause: read('cause'),
      process: read('process'),
      result: read('result'),
      attitude: read('attitude'),
      sourceDialog: read('sourceDialog'),
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'time': time,
      'location': location,
      'characters': characters,
      'cause': cause,
      'process': process,
      'result': result,
      'attitude': attitude,
    };
    if (sourceDialog.isNotEmpty) {
      json['sourceDialog'] = sourceDialog;
    }
    return json;
  }

  String toPromptLine() {
    final seg = <String>[];
    if (time.trim().isNotEmpty) seg.add('时间=$time');
    if (location.trim().isNotEmpty) seg.add('地点=$location');
    if (characters.trim().isNotEmpty) seg.add('人物=$characters');
    if (cause.trim().isNotEmpty) seg.add('起因=$cause');
    if (process.trim().isNotEmpty) seg.add('经过=$process');
    if (result.trim().isNotEmpty) seg.add('结果=$result');
    if (attitude.trim().isNotEmpty) seg.add('态度=$attitude');
    return seg.join('；');
  }

  /// 生成用于事件总结的详细描述，包含原始对话内容
  String toSummaryPromptLine() {
    final base = toPromptLine();
    if (sourceDialog.trim().isNotEmpty) {
      return '$base\n【原始对话】\n$sourceDialog';
    }
    return base;
  }

  String toSearchableText() {
    return '$time $location $characters $cause $process $result $attitude $sourceDialog';
  }
}

class EventLruBucket {
  const EventLruBucket._({
    required this.items,
    required this.indexByKey,
  });

  factory EventLruBucket([List<EventMemory> source = const <EventMemory>[]]) {
    final normalized = <EventMemory>[];
    final index = <String, int>{};
    for (final e in source) {
      if (e.isEmpty) continue;
      final key = _eventKey(e);
      if (index.containsKey(key)) continue;
      normalized.add(e);
      index[key] = normalized.length - 1;
    }
    return EventLruBucket._(
      items: List<EventMemory>.unmodifiable(normalized),
      indexByKey: Map<String, int>.unmodifiable(index),
    );
  }

  const EventLruBucket.empty()
      : items = const <EventMemory>[],
        indexByKey = const <String, int>{};

  final List<EventMemory> items;
  final Map<String, int> indexByKey;

  static String _eventKey(EventMemory e) {
    return '${e.time}|${e.location}|${e.characters}|${e.cause}|${e.process}|${e.result}|${e.attitude}|${e.sourceDialog}';
  }
}

enum EventTier { shortTerm, longTerm, ultraLongTerm }

extension EventTierX on EventTier {
  String get storageKey {
    switch (this) {
      case EventTier.shortTerm:
        return 'short';
      case EventTier.longTerm:
        return 'long';
      case EventTier.ultraLongTerm:
        return 'ultra';
    }
  }
}

class EventNode {
  const EventNode({
    required this.id,
    required this.tier,
    required this.event,
    required this.createdAtMs,
    this.summarized = false,
  });

  final String id;
  final EventTier tier;
  final EventMemory event;
  final int createdAtMs;
  final bool summarized;

  factory EventNode.fromJson(Map<String, dynamic> json) {
    final tierText = (json['tier'] ?? '').toString();
    return EventNode(
      id: (json['id'] ?? '').toString(),
      tier: _eventTierFromStorage(tierText),
      event: EventMemory.fromJson(_asMap(json['event'])),
      createdAtMs: (json['createdAtMs'] is num)
          ? (json['createdAtMs'] as num).toInt()
          : 0,
      summarized: json['summarized'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'tier': tier.storageKey,
      'event': event.toJson(),
      'createdAtMs': createdAtMs,
      'summarized': summarized,
    };
  }
}

class EventEdge {
  const EventEdge({
    required this.fromNodeId,
    required this.toNodeId,
  });

  final String fromNodeId;
  final String toNodeId;

  String toUniqueKey() => '$fromNodeId->$toNodeId';

  factory EventEdge.fromJson(Map<String, dynamic> json) {
    return EventEdge(
      fromNodeId: (json['fromNodeId'] ?? '').toString(),
      toNodeId: (json['toNodeId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fromNodeId': fromNodeId,
      'toNodeId': toNodeId,
    };
  }
}

enum KnowledgeType { world, self, user }

class KnowledgeNode {
  const KnowledgeNode({
    required this.id,
    required this.type,
    required this.content,
    required this.createdAtMs,
  });

  final String id;
  final KnowledgeType type;
  final String content;
  final int createdAtMs;

  factory KnowledgeNode.fromJson(Map<String, dynamic> json) {
    final typeText = (json['type'] ?? '').toString();
    return KnowledgeNode(
      id: (json['id'] ?? '').toString(),
      type: _knowledgeTypeFromStorage(typeText),
      content: (json['content'] ?? '').toString(),
      createdAtMs: (json['createdAtMs'] is num)
          ? (json['createdAtMs'] as num).toInt()
          : 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'content': content,
      'createdAtMs': createdAtMs,
    };
  }
}

class EventGraphMemory {
  const EventGraphMemory({
    this.shortTermQueue = const <EventNode>[],
    this.longTermQueue = const <EventNode>[],
    this.ultraLongTermQueue = const <EventNode>[],
    this.knowledgeNodes = const <KnowledgeNode>[],
    this.belongingEventQueues = const <String, List<String>>{},
    this.settingEventQueues = const <String, List<String>>{},
    this.edges = const <String, EventEdge>{},
    this.turnCount = 0,
  });

  final List<EventNode> shortTermQueue;
  final List<EventNode> longTermQueue;
  final List<EventNode> ultraLongTermQueue;
  final List<KnowledgeNode> knowledgeNodes;
  final Map<String, List<String>> belongingEventQueues;
  final Map<String, List<String>> settingEventQueues;
  final Map<String, EventEdge> edges;
  final int turnCount;

  factory EventGraphMemory.fromJson(Map<String, dynamic> json) {
    return EventGraphMemory(
      shortTermQueue: _readEventNodeList(json['shortTermQueue']),
      longTermQueue: _readEventNodeList(json['longTermQueue']),
      ultraLongTermQueue: _readEventNodeList(json['ultraLongTermQueue']),
      knowledgeNodes: _readKnowledgeNodeList(json['knowledgeNodes']),
      belongingEventQueues:
          _readBelongingEventQueues(json['belongingEventQueues']),
      settingEventQueues: _readBelongingEventQueues(json['settingEventQueues']),
      edges: _readEventEdgeMap(json['edges']),
      turnCount:
          (json['turnCount'] is num) ? (json['turnCount'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'shortTermQueue': shortTermQueue.map((e) => e.toJson()).toList(),
      'longTermQueue': longTermQueue.map((e) => e.toJson()).toList(),
      'ultraLongTermQueue': ultraLongTermQueue.map((e) => e.toJson()).toList(),
      'knowledgeNodes': knowledgeNodes.map((e) => e.toJson()).toList(),
      'belongingEventQueues': belongingEventQueues,
      'settingEventQueues': settingEventQueues,
      'turnCount': turnCount,
    };

    // 只存储非空字段
    if (edges.isNotEmpty) {
      json['edges'] = edges.values.map((e) => e.toJson()).toList();
    }

    return json;
  }

  EventGraphMemory copyWith({
    List<EventNode>? shortTermQueue,
    List<EventNode>? longTermQueue,
    List<EventNode>? ultraLongTermQueue,
    List<KnowledgeNode>? knowledgeNodes,
    Map<String, List<String>>? belongingEventQueues,
    Map<String, List<String>>? settingEventQueues,
    Map<String, EventEdge>? edges,
    int? turnCount,
  }) {
    return EventGraphMemory(
      shortTermQueue: shortTermQueue ?? this.shortTermQueue,
      longTermQueue: longTermQueue ?? this.longTermQueue,
      ultraLongTermQueue: ultraLongTermQueue ?? this.ultraLongTermQueue,
      knowledgeNodes: knowledgeNodes ?? this.knowledgeNodes,
      belongingEventQueues: belongingEventQueues ?? this.belongingEventQueues,
      settingEventQueues: settingEventQueues ?? this.settingEventQueues,
      edges: edges ?? this.edges,
      turnCount: turnCount ?? this.turnCount,
    );
  }

  List<EventMemory> get memoryEventsForPrompt {
    final short = shortTermQueue.where((e) => !e.summarized).take(10).toList();
    final long = longTermQueue.where((e) => !e.summarized).take(5).toList();
    final ultra = ultraLongTermQueue.take(2).toList();
    return <EventMemory>[
      ...short.map((e) => e.event),
      ...long.map((e) => e.event),
      ...ultra.map((e) => e.event),
    ];
  }

  /// 创建 EventGraphMemory 的深拷贝
  EventGraphMemory deepCopy() {
    return EventGraphMemory(
      shortTermQueue: shortTermQueue
          .map((n) => EventNode(
                id: n.id,
                tier: n.tier,
                event: EventMemory(
                  time: n.event.time,
                  location: n.event.location,
                  characters: n.event.characters,
                  cause: n.event.cause,
                  process: n.event.process,
                  result: n.event.result,
                  attitude: n.event.attitude,
                  sourceDialog: n.event.sourceDialog,
                ),
                createdAtMs: n.createdAtMs,
                summarized: n.summarized,
              ))
          .toList(),
      longTermQueue: longTermQueue
          .map((n) => EventNode(
                id: n.id,
                tier: n.tier,
                event: EventMemory(
                  time: n.event.time,
                  location: n.event.location,
                  characters: n.event.characters,
                  cause: n.event.cause,
                  process: n.event.process,
                  result: n.event.result,
                  attitude: n.event.attitude,
                  sourceDialog: n.event.sourceDialog,
                ),
                createdAtMs: n.createdAtMs,
                summarized: n.summarized,
              ))
          .toList(),
      ultraLongTermQueue: ultraLongTermQueue
          .map((n) => EventNode(
                id: n.id,
                tier: n.tier,
                event: EventMemory(
                  time: n.event.time,
                  location: n.event.location,
                  characters: n.event.characters,
                  cause: n.event.cause,
                  process: n.event.process,
                  result: n.event.result,
                  attitude: n.event.attitude,
                  sourceDialog: n.event.sourceDialog,
                ),
                createdAtMs: n.createdAtMs,
                summarized: n.summarized,
              ))
          .toList(),
      knowledgeNodes: knowledgeNodes
          .map((n) => KnowledgeNode(
                id: n.id,
                type: n.type,
                content: n.content,
                createdAtMs: n.createdAtMs,
              ))
          .toList(),
      belongingEventQueues: Map<String, List<String>>.from(
        belongingEventQueues.map((k, v) => MapEntry(k, List<String>.from(v))),
      ),
      settingEventQueues: Map<String, List<String>>.from(
        settingEventQueues.map((k, v) => MapEntry(k, List<String>.from(v))),
      ),
      edges: Map<String, EventEdge>.from(
        edges.map((k, v) => MapEntry(
            k,
            EventEdge(
              fromNodeId: v.fromNodeId,
              toNodeId: v.toNodeId,
            ))),
      ),
      turnCount: turnCount,
    );
  }

  List<EventMemory> relatedEventsForPrompt(String userInput,
      {int maxResults = 5, int keywordWeight = 60, int semanticWeight = 40}) {
    final keywords = _extractKeywords(userInput);
    if (keywords.isEmpty) return const <EventMemory>[];

    final allNodes = <EventNode>[
      ...shortTermQueue,
      ...longTermQueue,
      ...ultraLongTermQueue,
    ];
    if (allNodes.isEmpty) return const <EventMemory>[];

    final scored = <_ScoredNode>[];
    for (final node in allNodes) {
      // 关键词匹配分数
      final keywordScore = _keywordHitCount(
        keywords,
        _extractKeywords(node.event.toSearchableText()),
      );

      // 语义相似度分数（简化版）
      final semanticScore = _calculateSemanticSimilarity(
          userInput, node.event.toSearchableText());

      // 综合分数（使用传入的权重，支持权重和不为100的情况）
      final totalScore = keywordScore * (keywordWeight / 100) +
          semanticScore * (semanticWeight / 100);

      if (totalScore > 0) {
        scored.add(_ScoredNode(node: node, score: totalScore));
      }
    }
    scored.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      return b.node.createdAtMs.compareTo(a.node.createdAtMs);
    });

    final idToNode = <String, EventNode>{for (final n in allNodes) n.id: n};
    final adjacent = <String, Set<String>>{};
    for (final edge in edges.values) {
      adjacent
          .putIfAbsent(edge.fromNodeId, () => <String>{})
          .add(edge.toNodeId);
      adjacent
          .putIfAbsent(edge.toNodeId, () => <String>{})
          .add(edge.fromNodeId);
    }

    final result = <EventMemory>[];
    final seen = <String>{};

    for (final hit in scored) {
      if (result.length >= maxResults) break;
      if (seen.add(hit.node.id)) result.add(hit.node.event);
      final neighbors = adjacent[hit.node.id] ?? const <String>{};
      for (final id in neighbors) {
        if (result.length >= maxResults) break;
        final node = idToNode[id];
        if (node == null) continue;
        if (seen.add(node.id)) result.add(node.event);
      }
    }

    if (result.length >= maxResults) return result.take(maxResults).toList();

    final scoredBelongings = <_ScoredBelonging>[];
    for (final key in belongingEventQueues.keys) {
      final score = _keywordHitCount(keywords, _extractKeywords(key)) *
              (keywordWeight / 100) +
          _calculateSemanticSimilarity(userInput, key) * (semanticWeight / 100);
      if (score > 0) {
        scoredBelongings.add(_ScoredBelonging(name: key, score: score));
      }
    }
    scoredBelongings.sort((a, b) => b.score.compareTo(a.score));
    for (final b in scoredBelongings) {
      final queue = belongingEventQueues[b.name] ?? const <String>[];
      for (final eventId in queue.reversed) {
        if (result.length >= maxResults) break;
        final node = idToNode[eventId];
        if (node == null) continue;
        if (seen.add(node.id)) result.add(node.event);
      }
    }

    // 搜索 settingEventQueues（类似 belongings 的搜索逻辑）
    final scoredSettings = <_ScoredSetting>[];
    for (final key in settingEventQueues.keys) {
      final score = _keywordHitCount(keywords, _extractKeywords(key)) *
              (keywordWeight / 100) +
          _calculateSemanticSimilarity(userInput, key) * (semanticWeight / 100);
      if (score > 0) {
        scoredSettings.add(_ScoredSetting(key: key, score: score));
      }
    }
    scoredSettings.sort((a, b) => b.score.compareTo(a.score));
    for (final s in scoredSettings) {
      final queue = settingEventQueues[s.key] ?? const <String>[];
      for (final eventId in queue.reversed) {
        if (result.length >= maxResults) break;
        final node = idToNode[eventId];
        if (node == null) continue;
        if (seen.add(node.id)) result.add(node.event);
      }
    }

    return result.take(maxResults).toList();
  }

  double _calculateSemanticSimilarity(String text1, String text2) {
    // 简化的语义相似度计算
    // 实际项目中可以使用向量存储服务
    final words1 = _extractKeywords(text1);
    final words2 = _extractKeywords(text2);

    if (words1.isEmpty || words2.isEmpty) return 0.0;

    // 计算重叠词的比例
    final intersection = words1.intersection(words2).length;
    final union = words1.union(words2).length;

    // 计算Jaccard相似度
    return intersection / union.toDouble();
  }

  static int _keywordHitCount(Set<String> lhs, Set<String> rhs) {
    var c = 0;
    for (final k in lhs) {
      if (rhs.contains(k)) c++;
    }
    return c;
  }

  static final RegExp _tokenReg = RegExp(r'[\u4e00-\u9fffA-Za-z0-9_]{2,}');

  static Set<String> _extractKeywords(String raw) {
    final out = <String>{};
    for (final m in _tokenReg.allMatches(raw.toLowerCase())) {
      final token = m.group(0)?.trim();
      if (token == null || token.isEmpty) continue;
      out.add(token);
    }
    return out;
  }
}

class _ScoredNode {
  const _ScoredNode({required this.node, required this.score});
  final EventNode node;
  final double score;
}

class _ScoredBelonging {
  const _ScoredBelonging({required this.name, required this.score});
  final String name;
  final double score;
}

class _ScoredSetting {
  const _ScoredSetting({required this.key, required this.score});
  final String key;
  final double score;
}

class Contact {
  Contact({
    required this.id,
    required this.name,
    required this.avatar,
    this.category = ContactCategory.contact,
    this.personality = const <String>[],
    this.appearance = const <String>[],
    this.personalInfo = const <String>[],
    this.settings = const <Map<String, dynamic>>[],
    this.backgroundStory = const <String>[],
    this.narrativeRules = const <String>[],
    this.otherCharacteristics = const <String>[],
    this.worldKnowledge = const WorldKnowledgeBucket.empty(),
    this.selfKnowledge = const SelfKnowledgeBucket.empty(),
    this.userKnowledge = const UserKnowledgeBucket.empty(),
    this.events = const EventLruBucket.empty(),
    this.eventGraph = const EventGraphMemory(),
    this.belongings = const <String>[],
    this.status = const <String>[],
    this.mood = '',
    this.time = '',
    required this.createdAt,
  });

  final String id;
  final String name;
  final String avatar;
  final ContactCategory category;
  final List<String> personality;
  final List<String> appearance;
  final List<String> personalInfo;
  final List<Map<String, dynamic>> settings;
  final List<String> backgroundStory;
  final List<String> narrativeRules;
  final List<String> otherCharacteristics;
  final WorldKnowledgeBucket worldKnowledge;
  final SelfKnowledgeBucket selfKnowledge;
  final UserKnowledgeBucket userKnowledge;
  final EventLruBucket events;
  final EventGraphMemory eventGraph;
  final List<String> belongings;
  final List<String> status;
  final String mood;
  final String time;
  final DateTime createdAt;

  factory Contact.fromJson(Map<String, dynamic> json) {
    final categoryText = (json['category'] ?? '').toString();
    final createdAtIso = (json['createdAt'] ?? '').toString();
    final createdAtMs =
        (json['createdAtMs'] is num) ? (json['createdAtMs'] as num).toInt() : 0;
    return Contact(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      avatar: (json['avatar'] ?? '').toString(),
      category: _contactCategoryFromStorage(categoryText),
      personality: _readStringList(json['personality']),
      appearance: _readStringList(json['appearance']),
      personalInfo: _readStringList(json['personalInfo']),
      settings: _readSettingsList(json['settings']),
      backgroundStory: _readStringList(json['backgroundStory']),
      narrativeRules: _readStringList(json['narrativeRules']),
      otherCharacteristics: _readStringList(json['otherCharacteristics']),
      worldKnowledge:
          WorldKnowledgeBucket(_readStringList(json['worldKnowledge'])),
      selfKnowledge:
          SelfKnowledgeBucket(_readStringList(json['selfKnowledge'])),
      userKnowledge:
          UserKnowledgeBucket(_readStringList(json['userKnowledge'])),
      events: EventLruBucket(_readEventMemoryList(json['events'])),
      eventGraph: EventGraphMemory.fromJson(_asMap(json['eventGraph'])),
      belongings: _readStringList(json['belongings']),
      status: _readStringList(json['status']),
      mood: (json['mood'] ?? '').toString(),
      time: (json['time'] ?? '').toString(),
      createdAt: DateTime.tryParse(createdAtIso) ??
          DateTime.fromMillisecondsSinceEpoch(createdAtMs),
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'name': name,
      'category': category.name,
      'createdAt': createdAt.toIso8601String(),
      'createdAtMs': createdAt.millisecondsSinceEpoch,
    };

    // 只存储非空字段
    if (avatar.isNotEmpty) json['avatar'] = avatar;
    if (personality.isNotEmpty) json['personality'] = personality;
    if (appearance.isNotEmpty) json['appearance'] = appearance;
    if (personalInfo.isNotEmpty) json['personalInfo'] = personalInfo;
    if (settings.isNotEmpty) json['settings'] = settings;
    if (backgroundStory.isNotEmpty) json['backgroundStory'] = backgroundStory;
    if (narrativeRules.isNotEmpty) json['narrativeRules'] = narrativeRules;
    if (otherCharacteristics.isNotEmpty)
      json['otherCharacteristics'] = otherCharacteristics;
    if (worldKnowledge.items.isNotEmpty)
      json['worldKnowledge'] = worldKnowledge.items;
    if (selfKnowledge.items.isNotEmpty)
      json['selfKnowledge'] = selfKnowledge.items;
    if (userKnowledge.items.isNotEmpty)
      json['userKnowledge'] = userKnowledge.items;
    if (events.items.isNotEmpty)
      json['events'] = events.items.map((e) => e.toJson()).toList();
    if (eventGraph.shortTermQueue.isNotEmpty ||
        eventGraph.longTermQueue.isNotEmpty ||
        eventGraph.ultraLongTermQueue.isNotEmpty ||
        eventGraph.knowledgeNodes.isNotEmpty ||
        eventGraph.belongingEventQueues.isNotEmpty ||
        eventGraph.settingEventQueues.isNotEmpty ||
        eventGraph.edges.isNotEmpty ||
        eventGraph.turnCount > 0) {
      json['eventGraph'] = eventGraph.toJson();
    }
    if (belongings.isNotEmpty) json['belongings'] = belongings;
    if (status.isNotEmpty) json['status'] = status;
    if (mood.isNotEmpty) json['mood'] = mood;
    if (time.isNotEmpty) json['time'] = time;

    return json;
  }

  /// 创建 Contact 的深拷贝
  ///
  /// 用于撤回功能，保存对话前的完整状态
  Contact deepCopy() {
    return Contact(
      id: id,
      name: name,
      avatar: avatar,
      category: category,
      personality: List<String>.from(personality),
      appearance: List<String>.from(appearance),
      personalInfo: List<String>.from(personalInfo),
      settings: settings.map((s) => Map<String, dynamic>.from(s)).toList(),
      backgroundStory: List<String>.from(backgroundStory),
      narrativeRules: List<String>.from(narrativeRules),
      otherCharacteristics: List<String>.from(otherCharacteristics),
      worldKnowledge:
          WorldKnowledgeBucket(List<String>.from(worldKnowledge.items)),
      selfKnowledge:
          SelfKnowledgeBucket(List<String>.from(selfKnowledge.items)),
      userKnowledge:
          UserKnowledgeBucket(List<String>.from(userKnowledge.items)),
      events: EventLruBucket(events.items
          .map((e) => EventMemory(
                time: e.time,
                location: e.location,
                characters: e.characters,
                cause: e.cause,
                process: e.process,
                result: e.result,
                attitude: e.attitude,
                sourceDialog: e.sourceDialog,
              ))
          .toList()),
      eventGraph: eventGraph.deepCopy(),
      belongings: List<String>.from(belongings),
      status: List<String>.from(status),
      mood: mood,
      time: time,
      createdAt: createdAt,
    );
  }
}

ContactCategory _contactCategoryFromStorage(String raw) {
  for (final c in ContactCategory.values) {
    if (c.name == raw) return c;
  }
  return ContactCategory.contact;
}

EventTier _eventTierFromStorage(String raw) {
  for (final tier in EventTier.values) {
    if (tier.storageKey == raw || tier.name == raw) return tier;
  }
  return EventTier.shortTerm;
}

KnowledgeType _knowledgeTypeFromStorage(String raw) {
  for (final type in KnowledgeType.values) {
    if (type.name == raw) return type;
  }
  return KnowledgeType.world;
}

List<String> _readStringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .map((e) => e?.toString().trim() ?? '')
      .where((e) => e.isNotEmpty)
      .toList();
}

List<EventMemory> _readEventMemoryList(dynamic value) {
  if (value is! List) return const <EventMemory>[];
  final out = <EventMemory>[];
  for (final item in value) {
    if (item is! Map) continue;
    final event = EventMemory.fromJson(_asMap(item));
    if (!event.isEmpty) out.add(event);
  }
  return out;
}

List<EventNode> _readEventNodeList(dynamic value) {
  if (value is! List) return const <EventNode>[];
  final out = <EventNode>[];
  for (final item in value) {
    if (item is! Map) continue;
    final node = EventNode.fromJson(_asMap(item));
    if (node.id.trim().isEmpty) continue;
    out.add(node);
  }
  return out;
}

List<Map<String, dynamic>> _readSettingsList(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final item in value) {
    if (item is! Map) continue;
    final map = _asMap(item);
    final key = (map['key'] ?? '').toString().trim();
    final value = (map['value'] ?? '').toString().trim();
    if (key.isEmpty || value.isEmpty) continue;
    final relate = _readStringList(map['relate']);
    out.add({
      'key': key,
      'value': value,
      'relate': relate,
    });
  }
  return out;
}

List<KnowledgeNode> _readKnowledgeNodeList(dynamic value) {
  if (value is! List) return const <KnowledgeNode>[];
  final out = <KnowledgeNode>[];
  for (final item in value) {
    if (item is! Map) continue;
    final node = KnowledgeNode.fromJson(_asMap(item));
    if (node.id.trim().isEmpty || node.content.trim().isEmpty) continue;
    out.add(node);
  }
  return out;
}

Map<String, EventEdge> _readEventEdgeMap(dynamic value) {
  if (value is! List) return const <String, EventEdge>{};
  final out = <String, EventEdge>{};
  for (final item in value) {
    if (item is! Map) continue;
    final edge = EventEdge.fromJson(_asMap(item));
    if (edge.fromNodeId.trim().isEmpty || edge.toNodeId.trim().isEmpty) {
      continue;
    }
    out[edge.toUniqueKey()] = edge;
  }
  return out;
}

Map<String, List<String>> _readBelongingEventQueues(dynamic value) {
  if (value is! Map) return const <String, List<String>>{};
  final out = <String, List<String>>{};
  for (final entry in value.entries) {
    final key = entry.key.toString().trim();
    if (key.isEmpty) continue;
    final ids = _readStringList(entry.value);
    if (ids.isEmpty) continue;
    out[key] = ids;
  }
  return out;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return const <String, dynamic>{};
}
