import '../../../worldbook/domain/entities/world_book.dart';

enum ContactCategory { story, contact, assistant }

class VoiceOption {
  const VoiceOption(
      {required this.id, required this.label, required this.locale});

  final String id;
  final String label;
  final String locale;

  static const List<VoiceOption> presets = <VoiceOption>[
    VoiceOption(id: 'zh-CN-XiaoxiaoNeural', label: '晓晓（女·温柔）', locale: 'zh-CN'),
    VoiceOption(id: 'zh-CN-YunxiNeural', label: '云希（男·阳光）', locale: 'zh-CN'),
    VoiceOption(id: 'zh-CN-YunyangNeural', label: '云扬（男·专业）', locale: 'zh-CN'),
    VoiceOption(id: 'zh-CN-XiaoyiNeural', label: '晓伊（女·活泼）', locale: 'zh-CN'),
    VoiceOption(id: 'zh-CN-YunjianNeural', label: '云健（男·激昂）', locale: 'zh-CN'),
    VoiceOption(
        id: 'zh-CN-liaoning-XiaobeiNeural', label: '晓北（女·东北）', locale: 'zh-CN'),
    VoiceOption(
        id: 'zh-CN-shaanxi-XiaoniNeural', label: '晓妮（女·陕西）', locale: 'zh-CN'),
    VoiceOption(id: 'en-US-JennyNeural', label: 'Jenny（英文·女）', locale: 'en-US'),
    VoiceOption(id: 'en-US-GuyNeural', label: 'Guy（英文·男）', locale: 'en-US'),
    VoiceOption(
        id: 'ja-JP-NanamiNeural', label: 'Nanami（日语·女）', locale: 'ja-JP'),
  ];

  static VoiceOption? findById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final v in presets) {
      if (v.id == id) return v;
    }
    return null;
  }

  static VoiceOption get fallback => presets.first;
}

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
    this.description = '',
    this.keywords = const <String>[],
    this.theme = const <String>[],
    this.sourceDialog = '',
  });

  /// 事件概述（300字以内的自由文本）
  final String description;

  /// LLM 输出的实体关键词列表，用于搜索和匹配
  /// 包含人物、地点、物品等具体实体
  final List<String> keywords;

  /// LLM 输出的主题/氛围关键词列表
  /// 包含情感、氛围、主题等抽象概念，如"遗憾"、"温暖"、"悬疑"
  final List<String> theme;

  /// 原始对话内容（用户输入 + LLM 输出），用于事件总结时提供上下文
  final String sourceDialog;

  bool get isEmpty => description.trim().isEmpty;

  factory EventMemory.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();

    // 兼容旧格式：检测旧字段并合并为 description
    final hasOldFields = json.containsKey('time') ||
        json.containsKey('location') ||
        json.containsKey('characters') ||
        json.containsKey('cause') ||
        json.containsKey('process') ||
        json.containsKey('result') ||
        json.containsKey('attitude');

    String description;
    if (hasOldFields && !json.containsKey('description')) {
      // 旧格式：拼接为 description
      final seg = <String>[];
      final time = read('time');
      final location = read('location');
      final characters = read('characters');
      final cause = read('cause');
      final process = read('process');
      final result = read('result');
      final attitude = read('attitude');
      if (time.isNotEmpty) seg.add('时间=$time');
      if (location.isNotEmpty) seg.add('地点=$location');
      if (characters.isNotEmpty) seg.add('人物=$characters');
      if (cause.isNotEmpty) seg.add('起因=$cause');
      if (process.isNotEmpty) seg.add('经过=$process');
      if (result.isNotEmpty) seg.add('结果=$result');
      if (attitude.isNotEmpty) seg.add('态度=$attitude');
      description = seg.join('；');
    } else {
      description = read('description');
    }

    // 解析 keywords
    final keywordsRaw = json['keywords'];
    final keywords = <String>[];
    if (keywordsRaw is List) {
      for (final item in keywordsRaw) {
        final v = item?.toString().trim() ?? '';
        if (v.isNotEmpty) keywords.add(v);
      }
    }

    // 解析 theme
    final themeRaw = json['theme'];
    final theme = <String>[];
    if (themeRaw is List) {
      for (final item in themeRaw) {
        final v = item?.toString().trim() ?? '';
        if (v.isNotEmpty) theme.add(v);
      }
    }

    return EventMemory(
      description: description,
      keywords: keywords,
      theme: theme,
      sourceDialog: read('sourceDialog'),
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'description': description,
    };
    if (keywords.isNotEmpty) {
      json['keywords'] = keywords;
    }
    if (theme.isNotEmpty) {
      json['theme'] = theme;
    }
    if (sourceDialog.isNotEmpty) {
      json['sourceDialog'] = sourceDialog;
    }
    return json;
  }

  String toPromptLine() {
    return description;
  }

  /// 生成用于事件总结的详细描述，包含原始对话内容
  String toSummaryPromptLine() {
    if (sourceDialog.trim().isNotEmpty) {
      return '$description\n【原始对话】\n$sourceDialog';
    }
    return description;
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
    return '${e.description}|${e.sourceDialog}';
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
    this.invalidated = false,
    this.needsReview = false,
  });

  final String id;
  final EventTier tier;
  final EventMemory event;
  final int createdAtMs;
  final bool summarized;
  final bool invalidated;
  final bool needsReview;

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
      invalidated: json['invalidated'] == true,
      needsReview: json['needsReview'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'tier': tier.storageKey,
      'event': event.toJson(),
      'createdAtMs': createdAtMs,
      'summarized': summarized,
      if (invalidated) 'invalidated': true,
      if (needsReview) 'needsReview': true,
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
                  description: n.event.description,
                  keywords: List<String>.from(n.event.keywords),
                  theme: List<String>.from(n.event.theme),
                  sourceDialog: n.event.sourceDialog,
                ),
                createdAtMs: n.createdAtMs,
                summarized: n.summarized,
                invalidated: n.invalidated,
                needsReview: n.needsReview,
              ))
          .toList(),
      longTermQueue: longTermQueue
          .map((n) => EventNode(
                id: n.id,
                tier: n.tier,
                event: EventMemory(
                  description: n.event.description,
                  keywords: List<String>.from(n.event.keywords),
                  theme: List<String>.from(n.event.theme),
                  sourceDialog: n.event.sourceDialog,
                ),
                createdAtMs: n.createdAtMs,
                summarized: n.summarized,
                invalidated: n.invalidated,
                needsReview: n.needsReview,
              ))
          .toList(),
      ultraLongTermQueue: ultraLongTermQueue
          .map((n) => EventNode(
                id: n.id,
                tier: n.tier,
                event: EventMemory(
                  description: n.event.description,
                  keywords: List<String>.from(n.event.keywords),
                  theme: List<String>.from(n.event.theme),
                  sourceDialog: n.event.sourceDialog,
                ),
                createdAtMs: n.createdAtMs,
                summarized: n.summarized,
                invalidated: n.invalidated,
                needsReview: n.needsReview,
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
}

class Contact {
  Contact({
    required this.id,
    required this.name,
    required this.avatar,
    this.category = ContactCategory.contact,
    this.fixedInput = '',
    this.currentStates = const <String, String>{},
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
    this.keywordLibrary = const <String>[],
    this.themeLibrary = const <String>[],
    this.events = const EventLruBucket.empty(),
    this.eventGraph = const EventGraphMemory(),
    this.belongings = const <String>[],
    this.status = const <String>[],
    this.mood = '',
    this.time = '',
    this.voice = '',
    this.worldBook = const WorldBook(),
    required this.createdAt,
  });

  final String id;
  final String name;
  final String avatar;
  final ContactCategory category;
  final String fixedInput;
  final Map<String, String> currentStates;
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
  final List<String> keywordLibrary;
  final List<String> themeLibrary;
  final EventLruBucket events;
  final EventGraphMemory eventGraph;
  final List<String> belongings;
  final List<String> status;
  final String mood;
  final String time;
  final String voice;
  final WorldBook worldBook;
  final DateTime createdAt;

  Contact copyWith({
    EventLruBucket? events,
    EventGraphMemory? eventGraph,
    WorldBook? worldBook,
  }) {
    return Contact(
      id: id,
      name: name,
      avatar: avatar,
      category: category,
      fixedInput: fixedInput,
      currentStates: currentStates,
      personality: personality,
      appearance: appearance,
      personalInfo: personalInfo,
      settings: settings,
      backgroundStory: backgroundStory,
      narrativeRules: narrativeRules,
      otherCharacteristics: otherCharacteristics,
      worldKnowledge: worldKnowledge,
      selfKnowledge: selfKnowledge,
      userKnowledge: userKnowledge,
      keywordLibrary: keywordLibrary,
      themeLibrary: themeLibrary,
      events: events ?? this.events,
      eventGraph: eventGraph ?? this.eventGraph,
      belongings: belongings,
      status: status,
      mood: mood,
      time: time,
      voice: voice,
      worldBook: worldBook ?? this.worldBook,
      createdAt: createdAt,
    );
  }

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
      fixedInput: (json['fixedInput'] ?? '').toString(),
      currentStates: _readStringMap(json['currentStates']),
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
      keywordLibrary: _readStringList(json['keywordLibrary']),
      themeLibrary: _readStringList(json['themeLibrary']),
      events: EventLruBucket(_readEventMemoryList(json['events'])),
      eventGraph: EventGraphMemory.fromJson(_asMap(json['eventGraph'])),
      belongings: _readStringList(json['belongings']),
      status: _readStringList(json['status']),
      mood: (json['mood'] ?? '').toString(),
      time: (json['time'] ?? '').toString(),
      voice: (json['voice'] ?? '').toString(),
      worldBook: WorldBook.fromJson(
        json['worldBook'] is Map
            ? Map<String, dynamic>.from(json['worldBook'] as Map)
            : null,
      ),
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
    if (fixedInput.isNotEmpty) json['fixedInput'] = fixedInput;
    if (currentStates.isNotEmpty) json['currentStates'] = currentStates;
    if (personality.isNotEmpty) json['personality'] = personality;
    if (appearance.isNotEmpty) json['appearance'] = appearance;
    if (personalInfo.isNotEmpty) json['personalInfo'] = personalInfo;
    if (settings.isNotEmpty) json['settings'] = settings;
    if (backgroundStory.isNotEmpty) json['backgroundStory'] = backgroundStory;
    if (narrativeRules.isNotEmpty) json['narrativeRules'] = narrativeRules;
    if (otherCharacteristics.isNotEmpty) {
      json['otherCharacteristics'] = otherCharacteristics;
    }
    if (worldKnowledge.items.isNotEmpty) {
      json['worldKnowledge'] = worldKnowledge.items;
    }
    if (selfKnowledge.items.isNotEmpty) {
      json['selfKnowledge'] = selfKnowledge.items;
    }
    if (userKnowledge.items.isNotEmpty) {
      json['userKnowledge'] = userKnowledge.items;
    }
    if (keywordLibrary.isNotEmpty) json['keywordLibrary'] = keywordLibrary;
    if (themeLibrary.isNotEmpty) json['themeLibrary'] = themeLibrary;
    if (events.items.isNotEmpty) {
      json['events'] = events.items.map((e) => e.toJson()).toList();
    }
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
    if (voice.isNotEmpty) json['voice'] = voice;
    if (!worldBook.isEmpty) json['worldBook'] = worldBook.toJson();

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
      fixedInput: fixedInput,
      currentStates: Map<String, String>.from(currentStates),
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
      keywordLibrary: List<String>.from(keywordLibrary),
      themeLibrary: List<String>.from(themeLibrary),
      events: EventLruBucket(events.items
          .map((e) => EventMemory(
                description: e.description,
                keywords: List<String>.from(e.keywords),
                theme: List<String>.from(e.theme),
                sourceDialog: e.sourceDialog,
              ))
          .toList()),
      eventGraph: eventGraph.deepCopy(),
      belongings: List<String>.from(belongings),
      status: List<String>.from(status),
      mood: mood,
      time: time,
      voice: voice,
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

Map<String, String> _readStringMap(dynamic value) {
  if (value is! Map) return const <String, String>{};
  final out = <String, String>{};
  for (final entry in value.entries) {
    final key = entry.key.toString().trim();
    if (key.isEmpty) continue;
    out[key] = entry.value?.toString().trim() ?? '';
  }
  return out;
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
