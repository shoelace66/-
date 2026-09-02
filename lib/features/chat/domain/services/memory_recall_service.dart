import 'dart:collection';

import '../../data/models/contact.dart';

/// 可用于事件召回的结构化字段类型。
enum RecallTermKind { keyword, relation, theme }

/// PLAN 阶段可选的写入时间排序偏好。
///
/// 事件没有可靠的故事内时间，因此这里只控制同分节点的写入顺序。
enum RecallRecency { any, newest, oldest }

/// 索引中一个结构化词项的稳定引用。
class RecallTermRef {
  const RecallTermRef({
    required this.kind,
    required this.normalizedValue,
  });

  final RecallTermKind kind;
  final String normalizedValue;

  @override
  bool operator ==(Object other) =>
      other is RecallTermRef &&
      other.kind == kind &&
      other.normalizedValue == normalizedValue;

  @override
  int get hashCode => Object.hash(kind, normalizedValue);

  @override
  String toString() => '${kind.name}:$normalizedValue';
}

/// 提供给召回协调器构造结构化目录的词项元数据。
class RecallTermEntry {
  RecallTermEntry._({
    required this.ref,
    required Iterable<String> aliases,
    required Iterable<String> nodeIds,
    required this.newestCreatedAtMs,
  })  : aliases = List<String>.unmodifiable(aliases),
        nodeIds = Set<String>.unmodifiable(nodeIds);

  final RecallTermRef ref;

  /// 归一化后属于同一词项的原始写法，第一项可作为目录展示值。
  final List<String> aliases;
  final Set<String> nodeIds;
  final int newestCreatedAtMs;

  String get value => aliases.isEmpty ? ref.normalizedValue : aliases.first;
  int get postingCount => nodeIds.length;
}

/// 单个候选的可解释召回证据。
class RecallEvidence {
  RecallEvidence._({
    required Iterable<RecallTermRef> keywordTerms,
    required Iterable<RecallTermRef> relationTerms,
    required Iterable<RecallTermRef> themeTerms,
    required Iterable<String> seedNodeIds,
  })  : keywordTerms = List<RecallTermRef>.unmodifiable(keywordTerms),
        relationTerms = List<RecallTermRef>.unmodifiable(relationTerms),
        themeTerms = List<RecallTermRef>.unmodifiable(themeTerms),
        seedNodeIds = Set<String>.unmodifiable(seedNodeIds);

  final List<RecallTermRef> keywordTerms;
  final List<RecallTermRef> relationTerms;
  final List<RecallTermRef> themeTerms;

  /// 对图扩展候选产生贡献的直接命中节点；直接候选为空。
  final Set<String> seedNodeIds;

  bool get hasKeyword => keywordTerms.isNotEmpty;
  bool get hasRelation => relationTerms.isNotEmpty;
  bool get hasTheme => themeTerms.isNotEmpty;
}

/// 本地结构化检索产生的事件候选。
class RecallCandidate {
  const RecallCandidate({
    required this.node,
    required this.score,
    required this.direct,
    required this.themeOnly,
    required this.graphDistance,
    required this.evidence,
    this.oneHopFromStrongSeed = false,
  });

  final EventNode node;
  final int score;

  /// 节点自身是否直接包含命中的 keyword/relation/theme。
  final bool direct;

  /// 候选的查询证据是否只有 theme；此类结果不可自动确认。
  final bool themeOnly;

  /// 直接命中为 0，纯图扩展为 1 或 2。
  final int graphDistance;
  final RecallEvidence evidence;

  /// 图扩展候选是否至少距 keyword/relation 强种子一跳。
  /// 不能用 [graphDistance] 代替，因为最近路径可能来自弱 theme 种子。
  final bool oneHopFromStrongSeed;

  bool get needsReview => node.needsReview;
  bool get summarized => node.summarized;
  bool get hasStrongDirectEvidence =>
      direct && (evidence.hasKeyword || evidence.hasRelation);
}

/// 一次 L0 查询的完整结果，供协调器决定是否进入 PLAN/JUDGE。
class RecallQueryResult {
  RecallQueryResult({
    required this.index,
    required Iterable<RecallTermRef> matchedTerms,
    required Iterable<RecallCandidate> candidates,
  })  : matchedTerms = List<RecallTermRef>.unmodifiable(matchedTerms),
        candidates = List<RecallCandidate>.unmodifiable(candidates);

  final MemoryRecallIndex index;
  final List<RecallTermRef> matchedTerms;
  final List<RecallCandidate> candidates;
}

/// 从一个 [EventGraphMemory] 快照派生出的只读结构化索引。
class MemoryRecallIndex {
  MemoryRecallIndex._({
    required Iterable<EventNode> nodes,
    required Map<String, EventNode> nodeById,
    required Map<String, Set<String>> adjacentNodeIds,
    required Iterable<RecallTermEntry> catalog,
    required Map<RecallTermRef, RecallTermEntry> entryByRef,
    required Map<String, List<RecallTermEntry>> entriesByNormalizedValue,
    required Map<int, List<_TermPattern>> patternsByFirstCodeUnit,
  })  : nodes = List<EventNode>.unmodifiable(nodes),
        nodeById = Map<String, EventNode>.unmodifiable(nodeById),
        adjacentNodeIds = Map<String, Set<String>>.unmodifiable(
          adjacentNodeIds.map(
            (key, value) => MapEntry(key, Set<String>.unmodifiable(value)),
          ),
        ),
        catalog = List<RecallTermEntry>.unmodifiable(catalog),
        _entryByRef = Map<RecallTermRef, RecallTermEntry>.unmodifiable(
          entryByRef,
        ),
        _entriesByNormalizedValue =
            Map<String, List<RecallTermEntry>>.unmodifiable(
          entriesByNormalizedValue.map(
            (key, value) =>
                MapEntry(key, List<RecallTermEntry>.unmodifiable(value)),
          ),
        ),
        _patternsByFirstCodeUnit = Map<int, List<_TermPattern>>.unmodifiable(
          patternsByFirstCodeUnit.map(
            (key, value) =>
                MapEntry(key, List<_TermPattern>.unmodifiable(value)),
          ),
        );

  final List<EventNode> nodes;
  final Map<String, EventNode> nodeById;
  final Map<String, Set<String>> adjacentNodeIds;
  final List<RecallTermEntry> catalog;

  final Map<RecallTermRef, RecallTermEntry> _entryByRef;
  final Map<String, List<RecallTermEntry>> _entriesByNormalizedValue;
  final Map<int, List<_TermPattern>> _patternsByFirstCodeUnit;

  Iterable<RecallTermEntry> get keywordTerms =>
      catalog.where((entry) => entry.ref.kind == RecallTermKind.keyword);

  Iterable<RecallTermEntry> get relationTerms =>
      catalog.where((entry) => entry.ref.kind == RecallTermKind.relation);

  Iterable<RecallTermEntry> get themeTerms =>
      catalog.where((entry) => entry.ref.kind == RecallTermKind.theme);

  RecallTermEntry? entryFor(RecallTermRef ref) => _entryByRef[ref];
}

/// 事件图的纯本地结构化召回与关系清理。
///
/// 本服务不扫描事件描述或原始对话，不做分词、n-gram、拼音、编辑距离或
/// 同义词扩展。每轮只把 [search] 返回的有限候选交给上层协调器。
class MemoryRecallService {
  const MemoryRecallService();

  static const int maxCandidatePoolSize = 12;
  static final Expando<MemoryRecallIndex> _indexCache =
      Expando<MemoryRecallIndex>('memoryRecallIndex');

  /// 按图对象身份缓存索引。
  ///
  /// [EventGraphMemory] 应被当作不可变快照使用；图发生变化后应产生新对象，
  /// 此时自然会构建新索引。
  MemoryRecallIndex indexFor(EventGraphMemory graph) {
    final cached = _indexCache[graph];
    if (cached != null) return cached;
    final index = buildIndex(graph);
    _indexCache[graph] = index;
    return index;
  }

  /// 显式构建一个不含 invalidated 节点的结构化索引。
  MemoryRecallIndex buildIndex(EventGraphMemory graph) {
    final nodeById = <String, EventNode>{};
    for (final node in <EventNode>[
      ...graph.shortTermQueue,
      ...graph.longTermQueue,
      ...graph.ultraLongTermQueue,
    ]) {
      if (node.invalidated || node.id.isEmpty) continue;
      nodeById.putIfAbsent(node.id, () => node);
    }

    final mutableEntries = <RecallTermRef, _MutableTermEntry>{};

    void addTerm(RecallTermKind kind, String rawValue, String nodeId) {
      final displayValue = rawValue.trim();
      final normalizedValue = _normalize(displayValue);
      if (normalizedValue.isEmpty || !nodeById.containsKey(nodeId)) return;
      final ref = RecallTermRef(
        kind: kind,
        normalizedValue: normalizedValue,
      );
      final entry = mutableEntries.putIfAbsent(
        ref,
        () => _MutableTermEntry(ref: ref),
      );
      entry.aliases.add(displayValue);
      entry.nodeIds.add(nodeId);
      final createdAtMs = nodeById[nodeId]!.createdAtMs;
      if (createdAtMs > entry.newestCreatedAtMs) {
        entry.newestCreatedAtMs = createdAtMs;
      }
    }

    for (final node in nodeById.values) {
      for (final keyword in node.event.keywords) {
        addTerm(RecallTermKind.keyword, keyword, node.id);
      }
      for (final theme in node.event.theme) {
        addTerm(RecallTermKind.theme, theme, node.id);
      }
    }

    void addRelationQueues(Map<String, List<String>> queues) {
      for (final entry in queues.entries) {
        for (final nodeId in entry.value) {
          addTerm(RecallTermKind.relation, entry.key, nodeId);
        }
      }
    }

    addRelationQueues(graph.belongingEventQueues);
    addRelationQueues(graph.settingEventQueues);

    final catalog = mutableEntries.values
        .map(
          (entry) => RecallTermEntry._(
            ref: entry.ref,
            aliases: entry.aliases,
            nodeIds: entry.nodeIds,
            newestCreatedAtMs: entry.newestCreatedAtMs,
          ),
        )
        .toList(growable: false)
      ..sort(_compareCatalogEntries);
    final entryByRef = <RecallTermRef, RecallTermEntry>{
      for (final entry in catalog) entry.ref: entry,
    };

    final entriesByNormalizedValue = <String, List<RecallTermEntry>>{};
    for (final entry in catalog) {
      entriesByNormalizedValue
          .putIfAbsent(entry.ref.normalizedValue, () => <RecallTermEntry>[])
          .add(entry);
    }

    final patternsByFirstCodeUnit = <int, List<_TermPattern>>{};
    for (final entry in entriesByNormalizedValue.entries) {
      final value = entry.key;
      if (value.isEmpty) continue;
      patternsByFirstCodeUnit
          .putIfAbsent(value.codeUnitAt(0), () => <_TermPattern>[])
          .add(_TermPattern(value: value, entries: entry.value));
    }
    for (final patterns in patternsByFirstCodeUnit.values) {
      patterns.sort((left, right) {
        final byLength = right.value.length.compareTo(left.value.length);
        return byLength != 0 ? byLength : left.value.compareTo(right.value);
      });
    }

    final adjacentNodeIds = <String, LinkedHashSet<String>>{};
    for (final edge in graph.edges.values) {
      if (!nodeById.containsKey(edge.fromNodeId) ||
          !nodeById.containsKey(edge.toNodeId) ||
          edge.fromNodeId == edge.toNodeId) {
        continue;
      }
      adjacentNodeIds
          .putIfAbsent(edge.fromNodeId, LinkedHashSet<String>.new)
          .add(edge.toNodeId);
      adjacentNodeIds
          .putIfAbsent(edge.toNodeId, LinkedHashSet<String>.new)
          .add(edge.fromNodeId);
    }

    return MemoryRecallIndex._(
      nodes: nodeById.values,
      nodeById: nodeById,
      adjacentNodeIds: adjacentNodeIds,
      catalog: catalog,
      entryByRef: entryByRef,
      entriesByNormalizedValue: entriesByNormalizedValue,
      patternsByFirstCodeUnit: patternsByFirstCodeUnit,
    );
  }

  /// 在自然语言输入中匹配完整的已知结构化词项。
  ///
  /// 重叠命中只保留最长项；CJK 单字只在整句等于该词时命中；以 ASCII
  /// 字母或数字起止的词项要求相应位置存在字母数字边界。
  List<RecallTermRef> matchInput(MemoryRecallIndex index, String input) {
    final normalizedInput = _normalize(input);
    if (normalizedInput.isEmpty) return const <RecallTermRef>[];

    final hits = <_TermHit>[];
    for (var start = 0; start < normalizedInput.length; start++) {
      final patterns =
          index._patternsByFirstCodeUnit[normalizedInput.codeUnitAt(start)];
      if (patterns == null) continue;
      for (final pattern in patterns) {
        final value = pattern.value;
        if (_isSingleCjk(value) && normalizedInput != value) continue;
        if (!normalizedInput.startsWith(value, start)) continue;
        final end = start + value.length;
        if (!_hasLatinBoundaries(normalizedInput, value, start, end)) continue;
        hits.add(_TermHit(start: start, end: end, pattern: pattern));
      }
    }
    if (hits.isEmpty) return const <RecallTermRef>[];

    hits.sort((left, right) {
      final byLength = right.length.compareTo(left.length);
      if (byLength != 0) return byLength;
      final byStart = left.start.compareTo(right.start);
      if (byStart != 0) return byStart;
      return left.pattern.value.compareTo(right.pattern.value);
    });

    final retained = <_TermHit>[];
    for (final hit in hits) {
      final overlaps = retained.any(
        (other) => hit.start < other.end && other.start < hit.end,
      );
      if (!overlaps) retained.add(hit);
    }
    retained.sort((left, right) => left.start.compareTo(right.start));

    final result = <RecallTermRef>{};
    for (final hit in retained) {
      for (final entry in hit.pattern.entries) {
        result.add(entry.ref);
      }
    }
    return List<RecallTermRef>.unmodifiable(result);
  }

  /// 把 PLAN 返回的目录值或旧调用方的关键词精确还原为索引引用。
  ///
  /// 这里只做完整词项相等，不执行子串或模糊匹配。
  List<RecallTermRef> resolveTerms(
    MemoryRecallIndex index,
    Iterable<String> values, {
    Set<RecallTermKind>? kinds,
  }) {
    final result = <RecallTermRef>{};
    for (final value in values) {
      final normalizedValue = _normalize(value);
      if (normalizedValue.isEmpty) continue;
      for (final entry in index._entriesByNormalizedValue[normalizedValue] ??
          const <RecallTermEntry>[]) {
        if (kinds == null || kinds.contains(entry.ref.kind)) {
          result.add(entry.ref);
        }
      }
    }
    return List<RecallTermRef>.unmodifiable(result);
  }

  /// 使用冻结的结构化词项执行确定性评分和最多两跳图扩展。
  List<RecallCandidate> search(
    MemoryRecallIndex index,
    Iterable<RecallTermRef> terms, {
    Set<String> excludedNodeIds = const <String>{},
    int maxCandidates = maxCandidatePoolSize,
    int depth = 2,
    RecallRecency recency = RecallRecency.any,
  }) {
    if (maxCandidates <= 0 || index.nodes.isEmpty) {
      return const <RecallCandidate>[];
    }
    final effectiveLimit = maxCandidates > maxCandidatePoolSize
        ? maxCandidatePoolSize
        : maxCandidates;
    final effectiveDepth = depth.clamp(0, 2);
    final directEvidence = <String, _EvidenceAccumulator>{};

    void sortCandidates(List<RecallCandidate> candidates) {
      candidates.sort((left, right) {
        if (left.direct != right.direct) return left.direct ? -1 : 1;
        final byScore = right.score.compareTo(left.score);
        if (byScore != 0) return byScore;
        final byDistance = left.graphDistance.compareTo(right.graphDistance);
        if (byDistance != 0) return byDistance;
        final byCreatedAt = recency == RecallRecency.oldest
            ? left.node.createdAtMs.compareTo(right.node.createdAtMs)
            : right.node.createdAtMs.compareTo(left.node.createdAtMs);
        if (byCreatedAt != 0) return byCreatedAt;
        return left.node.id.compareTo(right.node.id);
      });
    }

    for (final ref in LinkedHashSet<RecallTermRef>.from(terms)) {
      final entry = index.entryFor(ref);
      if (entry == null) continue;
      for (final nodeId in entry.nodeIds) {
        directEvidence.putIfAbsent(nodeId, _EvidenceAccumulator.new).add(ref);
      }
    }
    if (directEvidence.isEmpty) return const <RecallCandidate>[];

    final directScores = <String, int>{};
    for (final entry in directEvidence.entries) {
      final node = index.nodeById[entry.key];
      if (node == null) continue;
      directScores[entry.key] = entry.value.baseScore + _statusAdjustment(node);
    }

    final directCandidates = <RecallCandidate>[];
    for (final entry in directEvidence.entries) {
      if (excludedNodeIds.contains(entry.key)) continue;
      final node = index.nodeById[entry.key];
      final score = directScores[entry.key];
      if (node == null || score == null) continue;
      directCandidates.add(
        RecallCandidate(
          node: node,
          score: score,
          direct: true,
          themeOnly: entry.value.themeOnly,
          graphDistance: 0,
          evidence: entry.value.toEvidence(),
        ),
      );
    }
    // 直接命中永远排在图扩展之前；数量已填满候选池时无需遍历图。
    if (directCandidates.length >= effectiveLimit) {
      sortCandidates(directCandidates);
      return List<RecallCandidate>.unmodifiable(
        directCandidates.take(effectiveLimit),
      );
    }

    final graphEvidence = <String, _GraphAccumulator>{};
    if (effectiveDepth > 0) {
      for (final seedEntry in directScores.entries) {
        if (seedEntry.value <= 0) continue;
        final seedId = seedEntry.key;
        final queue = Queue<_TraversalStep>();
        final visitedDepth = <String, int>{seedId: 0};
        for (final next in index.adjacentNodeIds[seedId] ?? const <String>{}) {
          queue.add(_TraversalStep(id: next, depth: 1));
        }

        while (queue.isNotEmpty) {
          final step = queue.removeFirst();
          final previousDepth = visitedDepth[step.id];
          if (previousDepth != null && previousDepth <= step.depth) continue;
          visitedDepth[step.id] = step.depth;
          final node = index.nodeById[step.id];
          if (node == null) continue;

          if (step.id != seedId && !directEvidence.containsKey(step.id)) {
            final contribution =
                _graphContribution(seedEntry.value, step.depth);
            final accumulator =
                graphEvidence.putIfAbsent(step.id, _GraphAccumulator.new);
            accumulator.add(
              seedId: seedId,
              distance: step.depth,
              contribution: contribution,
              evidence: directEvidence[seedId]!,
              strongSeed: directEvidence[seedId]!.hasStrongEvidence,
            );
          }

          if (step.depth < effectiveDepth) {
            for (final next
                in index.adjacentNodeIds[step.id] ?? const <String>{}) {
              queue.add(_TraversalStep(id: next, depth: step.depth + 1));
            }
          }
        }
      }
    }

    final candidates = List<RecallCandidate>.from(directCandidates);
    for (final entry in graphEvidence.entries) {
      if (excludedNodeIds.contains(entry.key)) continue;
      final node = index.nodeById[entry.key];
      if (node == null) continue;
      final score = entry.value.maxContribution +
          (entry.value.seedNodeIds.length >= 2 ? 10 : 0) +
          _statusAdjustment(node);
      candidates.add(
        RecallCandidate(
          node: node,
          score: score,
          direct: false,
          themeOnly: entry.value.evidence.themeOnly,
          graphDistance: entry.value.minDistance,
          evidence: entry.value.evidence.toEvidence(
            seedNodeIds: entry.value.seedNodeIds,
          ),
          oneHopFromStrongSeed: entry.value.minStrongSeedDistance == 1,
        ),
      );
    }

    sortCandidates(candidates);

    return List<RecallCandidate>.unmodifiable(candidates.take(effectiveLimit));
  }

  /// 便捷的 L0 完整查询入口。
  RecallQueryResult query(
    EventGraphMemory graph,
    String input, {
    Set<String> excludedNodeIds = const <String>{},
    int maxCandidates = maxCandidatePoolSize,
    int depth = 2,
    RecallRecency recency = RecallRecency.any,
  }) {
    final index = indexFor(graph);
    final matchedTerms = matchInput(index, input);
    final candidates = search(
      index,
      matchedTerms,
      excludedNodeIds: excludedNodeIds,
      maxCandidates: maxCandidates,
      depth: depth,
      recency: recency,
    );
    return RecallQueryResult(
      index: index,
      matchedTerms: matchedTerms,
      candidates: candidates,
    );
  }

  /// 兼容旧调用方：输入已经是结构化词项，不把它们当自由文本扫描。
  List<EventMemory> recall(
    EventGraphMemory graph,
    List<String> inputKeywords, {
    int maxResults = 5,
    int depth = 2,
  }) {
    return recallNodes(
      graph,
      inputKeywords,
      maxResults: maxResults,
      depth: depth,
    ).map((node) => node.event).toList(growable: false);
  }

  List<EventNode> recallNodes(
    EventGraphMemory graph,
    List<String> inputKeywords, {
    int maxResults = 5,
    int depth = 2,
  }) {
    if (inputKeywords.isEmpty || maxResults <= 0) {
      return const <EventNode>[];
    }

    final index = indexFor(graph);
    final terms = resolveTerms(index, inputKeywords);
    return search(
      index,
      terms,
      maxCandidates: maxResults,
      depth: depth,
    ).map((candidate) => candidate.node).toList(growable: false);
  }

  /// 把模型返回的 Prompt 编号转换为请求发出前冻结的稳定节点 ID。
  ///
  /// [promptNodeIds] 的顺序必须与 Prompt 中展示的编号完全一致。这样即使
  /// 当前事件已经插入队列或 LRU 已重排，也不会把关系连到错误节点。
  EventGraphMemory applyRelatedEdges({
    required EventGraphMemory graph,
    required String currentEventNodeId,
    required List<String> promptNodeIds,
    required dynamic relatedEventIds,
    int maxEdges = 2,
  }) {
    if (relatedEventIds is! List || relatedEventIds.isEmpty || maxEdges <= 0) {
      return graph;
    }

    final validIds = _allNodes(graph).map((node) => node.id).toSet();
    final edges = Map<String, EventEdge>.from(graph.edges);
    var added = 0;
    for (final raw in relatedEventIds) {
      if (added >= maxEdges) break;
      final index = raw is int ? raw : int.tryParse(raw.toString());
      if (index == null || index < 0 || index >= promptNodeIds.length) continue;
      final targetNodeId = promptNodeIds[index];
      if (targetNodeId == currentEventNodeId ||
          !validIds.contains(targetNodeId)) {
        continue;
      }
      final edge = EventEdge(
        fromNodeId: currentEventNodeId,
        toNodeId: targetNodeId,
      );
      if (edges.containsKey(edge.toUniqueKey())) continue;
      edges[edge.toUniqueKey()] = edge;
      added++;
    }
    return graph.copyWith(edges: edges);
  }

  /// 删除事件队列截断后留下的悬空边和悬空关联 ID。
  ///
  /// 这使事件关系可以跨轮保留，同时其规模仍受实际事件节点容量约束。
  EventGraphMemory pruneDanglingRelations(EventGraphMemory graph) {
    final validIds = _allNodes(graph).map((node) => node.id).toSet();
    final edges = <String, EventEdge>{};
    for (final edge in graph.edges.values) {
      if (!validIds.contains(edge.fromNodeId) ||
          !validIds.contains(edge.toNodeId)) {
        continue;
      }
      edges[edge.toUniqueKey()] = edge;
    }

    return graph.copyWith(
      belongingEventQueues:
          _pruneRelationQueues(graph.belongingEventQueues, validIds),
      settingEventQueues:
          _pruneRelationQueues(graph.settingEventQueues, validIds),
      edges: edges,
    );
  }

  List<EventNode> _allNodes(EventGraphMemory graph) => <EventNode>[
        ...graph.shortTermQueue,
        ...graph.longTermQueue,
        ...graph.ultraLongTermQueue,
      ].where((node) => !node.invalidated).toList(growable: false);

  Map<String, List<String>> _pruneRelationQueues(
    Map<String, List<String>> queues,
    Set<String> validIds,
  ) {
    final result = <String, List<String>>{};
    for (final entry in queues.entries) {
      final seen = <String>{};
      final retained = entry.value
          .where((id) => validIds.contains(id) && seen.add(id))
          .toList(growable: false);
      if (retained.isNotEmpty) result[entry.key] = retained;
    }
    return result;
  }

  static int _compareCatalogEntries(
    RecallTermEntry left,
    RecallTermEntry right,
  ) {
    final byKind = left.ref.kind.index.compareTo(right.ref.kind.index);
    if (byKind != 0) return byKind;
    return left.ref.normalizedValue.compareTo(right.ref.normalizedValue);
  }

  static int _statusAdjustment(EventNode node) =>
      (node.summarized ? -10 : 0) + (node.needsReview ? -120 : 0);

  static int _graphContribution(int seedScore, int depth) {
    if (seedScore <= 0) return 0;
    if (depth <= 1) {
      final contribution = (seedScore * 0.40).floor();
      return contribution > 70 ? 70 : contribution;
    }
    final contribution = (seedScore * 0.18).floor();
    return contribution > 30 ? 30 : contribution;
  }

  static bool _hasLatinBoundaries(
    String input,
    String term,
    int start,
    int end,
  ) {
    if (_isAsciiAlphaNumeric(term.codeUnitAt(0)) &&
        start > 0 &&
        _isAsciiAlphaNumeric(input.codeUnitAt(start - 1))) {
      return false;
    }
    if (_isAsciiAlphaNumeric(term.codeUnitAt(term.length - 1)) &&
        end < input.length &&
        _isAsciiAlphaNumeric(input.codeUnitAt(end))) {
      return false;
    }
    return true;
  }

  static bool _isAsciiAlphaNumeric(int codeUnit) =>
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7a);

  static bool _isSingleCjk(String value) {
    final runes = value.runes.toList(growable: false);
    if (runes.length != 1) return false;
    final rune = runes.single;
    return (rune >= 0x3400 && rune <= 0x4dbf) ||
        (rune >= 0x4e00 && rune <= 0x9fff) ||
        (rune >= 0xf900 && rune <= 0xfaff) ||
        (rune >= 0x20000 && rune <= 0x2fa1f);
  }

  /// 保守归一化：不改变词义，只统一 ASCII 大小写、全角 ASCII、空白和
  /// 常见中西文标点的等价写法。
  static String _normalize(String value) {
    final buffer = StringBuffer();
    var pendingSpace = false;
    for (var rune in value.runes) {
      if (rune == 0x3000) rune = 0x20;
      if (rune >= 0xff01 && rune <= 0xff5e) rune -= 0xfee0;
      rune = _normalizedPunctuation(rune);

      if (_isWhitespace(rune)) {
        pendingSpace = buffer.isNotEmpty;
        continue;
      }
      if (pendingSpace) {
        buffer.writeCharCode(0x20);
        pendingSpace = false;
      }
      if (rune >= 0x41 && rune <= 0x5a) rune += 0x20;
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  static int _normalizedPunctuation(int rune) {
    switch (rune) {
      case 0x3001: // 、
        return 0x2c;
      case 0x3002: // 。
        return 0x2e;
      case 0x2018: // ‘
      case 0x2019: // ’
        return 0x27;
      case 0x201c: // “
      case 0x201d: // ”
        return 0x22;
      case 0x2013: // –
      case 0x2014: // —
        return 0x2d;
      case 0x2026: // …
      case 0x00b7: // ·
        return 0x2e;
      case 0x3008: // 〈
      case 0x300a: // 《
        return 0x3c;
      case 0x3009: // 〉
      case 0x300b: // 》
        return 0x3e;
      case 0x3010: // 【
        return 0x5b;
      case 0x3011: // 】
        return 0x5d;
      default:
        return rune;
    }
  }

  static bool _isWhitespace(int rune) =>
      rune == 0x20 ||
      (rune >= 0x09 && rune <= 0x0d) ||
      rune == 0x00a0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200a) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202f ||
      rune == 0x205f;
}

class _MutableTermEntry {
  _MutableTermEntry({required this.ref});

  final RecallTermRef ref;
  final LinkedHashSet<String> aliases = LinkedHashSet<String>();
  final LinkedHashSet<String> nodeIds = LinkedHashSet<String>();
  int newestCreatedAtMs = 0;
}

class _TermPattern {
  const _TermPattern({required this.value, required this.entries});

  final String value;
  final List<RecallTermEntry> entries;
}

class _TermHit {
  const _TermHit({
    required this.start,
    required this.end,
    required this.pattern,
  });

  final int start;
  final int end;
  final _TermPattern pattern;

  int get length => end - start;
}

class _EvidenceAccumulator {
  final LinkedHashSet<RecallTermRef> keywordTerms =
      LinkedHashSet<RecallTermRef>();
  final LinkedHashSet<RecallTermRef> relationTerms =
      LinkedHashSet<RecallTermRef>();
  final LinkedHashSet<RecallTermRef> themeTerms =
      LinkedHashSet<RecallTermRef>();

  void add(RecallTermRef ref) {
    switch (ref.kind) {
      case RecallTermKind.keyword:
        keywordTerms.add(ref);
        return;
      case RecallTermKind.relation:
        relationTerms.add(ref);
        return;
      case RecallTermKind.theme:
        themeTerms.add(ref);
        return;
    }
  }

  void addAll(_EvidenceAccumulator other) {
    keywordTerms.addAll(other.keywordTerms);
    relationTerms.addAll(other.relationTerms);
    themeTerms.addAll(other.themeTerms);
  }

  int get baseScore {
    final keywordCount = keywordTerms.length > 3 ? 3 : keywordTerms.length;
    final relationCount = relationTerms.length > 2 ? 2 : relationTerms.length;
    final themeCount = themeTerms.length > 2 ? 2 : themeTerms.length;
    final evidenceTypeCount = <bool>[
      keywordCount > 0,
      relationCount > 0,
      themeCount > 0,
    ].where((present) => present).length;
    return keywordCount * 120 +
        relationCount * 100 +
        themeCount * 35 +
        (evidenceTypeCount >= 2 ? 25 : 0);
  }

  bool get themeOnly =>
      themeTerms.isNotEmpty && keywordTerms.isEmpty && relationTerms.isEmpty;

  bool get hasStrongEvidence =>
      keywordTerms.isNotEmpty || relationTerms.isNotEmpty;

  RecallEvidence toEvidence({Iterable<String> seedNodeIds = const <String>[]}) {
    return RecallEvidence._(
      keywordTerms: keywordTerms,
      relationTerms: relationTerms,
      themeTerms: themeTerms,
      seedNodeIds: seedNodeIds,
    );
  }
}

class _GraphAccumulator {
  int maxContribution = 0;
  int minDistance = 2;
  int? minStrongSeedDistance;
  final LinkedHashSet<String> seedNodeIds = LinkedHashSet<String>();
  final _EvidenceAccumulator evidence = _EvidenceAccumulator();

  void add({
    required String seedId,
    required int distance,
    required int contribution,
    required _EvidenceAccumulator evidence,
    required bool strongSeed,
  }) {
    seedNodeIds.add(seedId);
    if (distance < minDistance) minDistance = distance;
    if (strongSeed &&
        (minStrongSeedDistance == null || distance < minStrongSeedDistance!)) {
      minStrongSeedDistance = distance;
    }
    if (contribution > maxContribution) maxContribution = contribution;
    this.evidence.addAll(evidence);
  }
}

class _TraversalStep {
  const _TraversalStep({required this.id, required this.depth});

  final String id;
  final int depth;
}
