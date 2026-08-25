/// 应用设置数据模型
///
/// 存储各种限长参数，包括：
/// - 输入到 LLM 的长度限制
/// - 本地存储的长度限制
/// - 关联检索的深度和长度
class AppSettings {
  const AppSettings({
    this.maxPromptListItems = 5,
    this.maxPromptLineLength = 200,
    this.maxShortTermEvents = 10,
    // 长期记忆默认只取最新 1 条 summary（多轮 1→2 cascade 后多条 summary 会堆在长期里，
    // 太多会让 prompt 变噪；旧的会通过 2→3 cascade 进超长期，不会丢）。
    this.maxLongTermEvents = 1,
    this.maxUltraTermEvents = 2,
    this.maxRelatedEvents = 5,
    this.summaryThreshold = 10,
    this.ultraSummaryThreshold = 5,
    this.maxShortQueue = 2000,
    this.maxLongQueue = 500,
    this.maxUltraQueue = 200,
    this.searchDepth = 2,
    this.lruKeywordMatchWeight = 100,
    this.lruEventEventWeight = 50,
    this.lruEventBelongingKeywordWeight = 30,
    this.lruEventBelongingNormalWeight = 10,
    this.lruEventSettingKeywordWeight = 30,
    this.lruEventSettingNormalWeight = 10,
    this.vectorSimilarityWeight = 80,
    this.keywordLibrarySize = 200,
  });

  /// Prompt 中列表项的最大数量
  final int maxPromptListItems;

  /// Prompt 中单行的最大长度
  final int maxPromptLineLength;

  /// 输入 LLM 的短期事件数量
  final int maxShortTermEvents;

  /// 输入 LLM 的长期事件数量
  final int maxLongTermEvents;

  /// 输入 LLM 的超长期事件数量
  final int maxUltraTermEvents;

  /// 关联检索返回的最大事件数
  final int maxRelatedEvents;

  /// 事件总结阈值（1→2 触发：短期队列未总结事件数 >= 此值时让 LLM 压缩到长期）
  final int summaryThreshold;

  /// 超长期总结阈值（2→3 触发：长期队列未总结事件数 >= 此值时让 LLM 再压一遍到超长期）
  /// 设为较大值（如 999）即可禁用超长期级联
  final int ultraSummaryThreshold;

  /// 短期队列最大容量（本地存储）
  final int maxShortQueue;

  /// 长期队列最大容量（本地存储）
  final int maxLongQueue;

  /// 超长期队列最大容量（本地存储）
  final int maxUltraQueue;

  /// 关联检索深度（邻居层级，BFS 跳数）
  final int searchDepth;

  /// LRU 权重：关键词匹配权重
  final int lruKeywordMatchWeight;

  /// LRU权重：事件-事件关联权重
  final int lruEventEventWeight;

  /// LRU权重：事件-物品关联（关键词相关）权重
  final int lruEventBelongingKeywordWeight;

  /// LRU权重：事件-物品关联（普通）权重
  final int lruEventBelongingNormalWeight;

  /// LRU权重：事件-设定关联（关键词相关）权重
  final int lruEventSettingKeywordWeight;

  /// LRU权重：事件-设定关联（普通）权重
  final int lruEventSettingNormalWeight;

  /// 向量相似度权重
  final int vectorSimilarityWeight;

  /// 关键词库最大容量
  final int keywordLibrarySize;

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      maxPromptListItems: (json['maxPromptListItems'] as num?)?.toInt() ?? 5,
      maxPromptLineLength:
          (json['maxPromptLineLength'] as num?)?.toInt() ?? 200,
      maxShortTermEvents: (json['maxShortTermEvents'] as num?)?.toInt() ?? 10,
      maxLongTermEvents: (json['maxLongTermEvents'] as num?)?.toInt() ?? 1,
      maxUltraTermEvents: (json['maxUltraTermEvents'] as num?)?.toInt() ?? 2,
      maxRelatedEvents: (json['maxRelatedEvents'] as num?)?.toInt() ?? 5,
      summaryThreshold: (json['summaryThreshold'] as num?)?.toInt() ?? 10,
      ultraSummaryThreshold:
          (json['ultraSummaryThreshold'] as num?)?.toInt() ?? 5,
      maxShortQueue: (json['maxShortQueue'] as num?)?.toInt() ?? 2000,
      maxLongQueue: (json['maxLongQueue'] as num?)?.toInt() ?? 500,
      maxUltraQueue: (json['maxUltraQueue'] as num?)?.toInt() ?? 200,
      searchDepth: (json['searchDepth'] as num?)?.toInt() ?? 2,
      lruKeywordMatchWeight:
          (json['lruKeywordMatchWeight'] as num?)?.toInt() ?? 100,
      lruEventEventWeight: (json['lruEventEventWeight'] as num?)?.toInt() ?? 50,
      lruEventBelongingKeywordWeight:
          (json['lruEventBelongingKeywordWeight'] as num?)?.toInt() ?? 30,
      lruEventBelongingNormalWeight:
          (json['lruEventBelongingNormalWeight'] as num?)?.toInt() ?? 10,
      lruEventSettingKeywordWeight:
          (json['lruEventSettingKeywordWeight'] as num?)?.toInt() ?? 30,
      lruEventSettingNormalWeight:
          (json['lruEventSettingNormalWeight'] as num?)?.toInt() ?? 10,
      vectorSimilarityWeight:
          (json['vectorSimilarityWeight'] as num?)?.toInt() ?? 80,
      keywordLibrarySize: (json['keywordLibrarySize'] as num?)?.toInt() ?? 200,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'maxPromptListItems': maxPromptListItems,
      'maxPromptLineLength': maxPromptLineLength,
      'maxShortTermEvents': maxShortTermEvents,
      'maxLongTermEvents': maxLongTermEvents,
      'maxUltraTermEvents': maxUltraTermEvents,
      'maxRelatedEvents': maxRelatedEvents,
      'summaryThreshold': summaryThreshold,
      'ultraSummaryThreshold': ultraSummaryThreshold,
      'maxShortQueue': maxShortQueue,
      'maxLongQueue': maxLongQueue,
      'maxUltraQueue': maxUltraQueue,
      'searchDepth': searchDepth,
      'lruKeywordMatchWeight': lruKeywordMatchWeight,
      'lruEventEventWeight': lruEventEventWeight,
      'lruEventBelongingKeywordWeight': lruEventBelongingKeywordWeight,
      'lruEventBelongingNormalWeight': lruEventBelongingNormalWeight,
      'lruEventSettingKeywordWeight': lruEventSettingKeywordWeight,
      'lruEventSettingNormalWeight': lruEventSettingNormalWeight,
      'vectorSimilarityWeight': vectorSimilarityWeight,
      'keywordLibrarySize': keywordLibrarySize,
    };
  }

  AppSettings copyWith({
    int? maxPromptListItems,
    int? maxPromptLineLength,
    int? maxShortTermEvents,
    int? maxLongTermEvents,
    int? maxUltraTermEvents,
    int? maxRelatedEvents,
    int? summaryThreshold,
    int? ultraSummaryThreshold,
    int? maxShortQueue,
    int? maxLongQueue,
    int? maxUltraQueue,
    int? searchDepth,
    int? lruKeywordMatchWeight,
    int? lruEventEventWeight,
    int? lruEventBelongingKeywordWeight,
    int? lruEventBelongingNormalWeight,
    int? lruEventSettingKeywordWeight,
    int? lruEventSettingNormalWeight,
    int? vectorSimilarityWeight,
    int? keywordLibrarySize,
  }) {
    return AppSettings(
      maxPromptListItems: maxPromptListItems ?? this.maxPromptListItems,
      maxPromptLineLength: maxPromptLineLength ?? this.maxPromptLineLength,
      maxShortTermEvents: maxShortTermEvents ?? this.maxShortTermEvents,
      maxLongTermEvents: maxLongTermEvents ?? this.maxLongTermEvents,
      maxUltraTermEvents: maxUltraTermEvents ?? this.maxUltraTermEvents,
      maxRelatedEvents: maxRelatedEvents ?? this.maxRelatedEvents,
      summaryThreshold: summaryThreshold ?? this.summaryThreshold,
      ultraSummaryThreshold:
          ultraSummaryThreshold ?? this.ultraSummaryThreshold,
      maxShortQueue: maxShortQueue ?? this.maxShortQueue,
      maxLongQueue: maxLongQueue ?? this.maxLongQueue,
      maxUltraQueue: maxUltraQueue ?? this.maxUltraQueue,
      searchDepth: searchDepth ?? this.searchDepth,
      lruKeywordMatchWeight:
          lruKeywordMatchWeight ?? this.lruKeywordMatchWeight,
      lruEventEventWeight: lruEventEventWeight ?? this.lruEventEventWeight,
      lruEventBelongingKeywordWeight:
          lruEventBelongingKeywordWeight ?? this.lruEventBelongingKeywordWeight,
      lruEventBelongingNormalWeight:
          lruEventBelongingNormalWeight ?? this.lruEventBelongingNormalWeight,
      lruEventSettingKeywordWeight:
          lruEventSettingKeywordWeight ?? this.lruEventSettingKeywordWeight,
      lruEventSettingNormalWeight:
          lruEventSettingNormalWeight ?? this.lruEventSettingNormalWeight,
      vectorSimilarityWeight:
          vectorSimilarityWeight ?? this.vectorSimilarityWeight,
      keywordLibrarySize: keywordLibrarySize ?? this.keywordLibrarySize,
    );
  }
}
