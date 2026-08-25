import '../../../../core/data/models/app_settings.dart';
import '../../data/models/contact.dart';
import 'memory_patch_reducer.dart';

class EnqueuedEvent {
  const EnqueuedEvent({required this.graph, required this.nodeId});

  final EventGraphMemory graph;
  final String nodeId;
}

/// 事件图的纯业务变换。
///
/// 所有方法均返回新图，不读写存储；节点 ID 和时间由调用者传入，便于事务提交和测试。
class MemoryGraphService {
  const MemoryGraphService();

  EnqueuedEvent enqueue({
    required EventGraphMemory graph,
    required EventTier tier,
    required EventMemory event,
    required String nodeId,
    required int createdAtMs,
    required AppSettings settings,
  }) {
    final node = EventNode(
      id: nodeId,
      tier: tier,
      event: event,
      createdAtMs: createdAtMs,
    );
    switch (tier) {
      case EventTier.shortTerm:
        return EnqueuedEvent(
          graph: graph.copyWith(
            shortTermQueue: <EventNode>[node, ...graph.shortTermQueue]
                .take(settings.maxShortQueue)
                .toList(growable: false),
          ),
          nodeId: nodeId,
        );
      case EventTier.longTerm:
        return EnqueuedEvent(
          graph: graph.copyWith(
            longTermQueue: <EventNode>[node, ...graph.longTermQueue]
                .take(settings.maxLongQueue)
                .toList(growable: false),
          ),
          nodeId: nodeId,
        );
      case EventTier.ultraLongTerm:
        return EnqueuedEvent(
          graph: graph.copyWith(
            ultraLongTermQueue: <EventNode>[node, ...graph.ultraLongTermQueue]
                .take(settings.maxUltraQueue)
                .toList(growable: false),
          ),
          nodeId: nodeId,
        );
    }
  }

  EventGraphMemory markSummarized({
    required EventGraphMemory graph,
    required EventTier tier,
    required Set<String> nodeIds,
  }) {
    if (nodeIds.isEmpty) return graph;
    List<EventNode> update(List<EventNode> queue) => queue
        .map((node) => nodeIds.contains(node.id)
            ? EventNode(
                id: node.id,
                tier: node.tier,
                event: node.event,
                createdAtMs: node.createdAtMs,
                summarized: true,
                invalidated: node.invalidated,
                needsReview: node.needsReview,
              )
            : node)
        .toList(growable: false);
    switch (tier) {
      case EventTier.shortTerm:
        return graph.copyWith(shortTermQueue: update(graph.shortTermQueue));
      case EventTier.longTerm:
        return graph.copyWith(longTermQueue: update(graph.longTermQueue));
      case EventTier.ultraLongTerm:
        return graph.copyWith(
          ultraLongTermQueue: update(graph.ultraLongTermQueue),
        );
    }
  }

  List<EventNode> queueForTier(EventGraphMemory graph, EventTier tier) {
    return switch (tier) {
      EventTier.shortTerm => graph.shortTermQueue,
      EventTier.longTerm => graph.longTermQueue,
      EventTier.ultraLongTerm => graph.ultraLongTermQueue,
    };
  }

  EventGraphMemory removeNode(EventGraphMemory graph, String nodeId) {
    List<EventNode> without(List<EventNode> queue) =>
        queue.where((node) => node.id != nodeId).toList(growable: false);
    Map<String, List<String>> cleanQueues(Map<String, List<String>> queues) => {
          for (final entry in queues.entries)
            if (entry.value.any((id) => id != nodeId))
              entry.key: entry.value
                  .where((id) => id != nodeId)
                  .toList(growable: false),
        };
    return graph.copyWith(
      shortTermQueue: without(graph.shortTermQueue),
      longTermQueue: without(graph.longTermQueue),
      ultraLongTermQueue: without(graph.ultraLongTermQueue),
      edges: <String, EventEdge>{
        for (final entry in graph.edges.entries)
          if (entry.value.fromNodeId != nodeId &&
              entry.value.toNodeId != nodeId)
            entry.key: entry.value,
      },
      belongingEventQueues: cleanQueues(graph.belongingEventQueues),
      settingEventQueues: cleanQueues(graph.settingEventQueues),
    );
  }

  EventGraphMemory linkSummarySources({
    required EventGraphMemory graph,
    required String summaryNodeId,
    required Iterable<String> sourceNodeIds,
  }) {
    final validIds = _nodeMap(graph).keys.toSet();
    final edges = Map<String, EventEdge>.from(graph.edges);
    for (final sourceId in sourceNodeIds.toSet()) {
      if (sourceId == summaryNodeId || !validIds.contains(sourceId)) continue;
      final edge = EventEdge(
        fromNodeId: summaryNodeId,
        toNodeId: sourceId,
      );
      edges[edge.toUniqueKey()] = edge;
    }
    return graph.copyWith(edges: edges);
  }

  EventGraphMemory applyLru({
    required EventGraphMemory graph,
    required List<String> inputKeywords,
    required AppSettings settings,
  }) {
    var result = graph;
    result = _applyQueueLru(
      result,
      tier: EventTier.shortTerm,
      fixedCount: settings.maxShortTermEvents,
      inputKeywords: inputKeywords,
      settings: settings,
    );
    result = _applyQueueLru(
      result,
      tier: EventTier.longTerm,
      fixedCount: settings.maxLongTermEvents,
      inputKeywords: inputKeywords,
      settings: settings,
    );
    return _applyQueueLru(
      result,
      tier: EventTier.ultraLongTerm,
      fixedCount: settings.maxUltraTermEvents,
      inputKeywords: inputKeywords,
      settings: settings,
    );
  }

  EventGraphMemory updateBelongingRelations({
    required EventGraphMemory graph,
    required String? eventNodeId,
    required List<BelongingChange> changes,
    required List<String> inputKeywords,
    int queueLimit = 100,
  }) {
    if (changes.isEmpty || eventNodeId == null || eventNodeId.isEmpty) {
      return graph;
    }
    final nodes = _nodeMap(graph);
    final keywords = inputKeywords.map((item) => item.toLowerCase()).toSet();
    final queues = _copyQueues(graph.belongingEventQueues);
    for (final change in changes) {
      final queue = <String>[
        ...queues[change.name] ?? const <String>[],
        eventNodeId,
      ];
      queues[change.name] = _sortRelationQueue(
        queue,
        nodes: nodes,
        keywords: keywords,
      ).take(queueLimit).toList(growable: false);
    }
    return graph.copyWith(belongingEventQueues: queues);
  }

  EventGraphMemory updateSettingRelations({
    required EventGraphMemory graph,
    required String? eventNodeId,
    required List<Map<String, dynamic>> settings,
    required List<String> inputKeywords,
    int queueLimit = 100,
  }) {
    if (eventNodeId == null ||
        eventNodeId.isEmpty ||
        settings.isEmpty ||
        inputKeywords.isEmpty) {
      return graph;
    }
    final nodes = _nodeMap(graph);
    final keywords = inputKeywords.map((item) => item.toLowerCase()).toSet();
    final queues = _copyQueues(graph.settingEventQueues);
    for (final setting in settings) {
      final key = (setting['key'] ?? '').toString().trim();
      final value = (setting['value'] ?? '').toString().trim();
      final related = setting['relate'] is List
          ? (setting['relate'] as List).map((item) => item.toString())
          : const <String>[];
      if (key.isEmpty) continue;
      final terms = '$key $value ${related.join(' ')}'
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((term) => term.isNotEmpty)
          .toSet();
      if (keywords.intersection(terms).isEmpty) continue;
      final queue = <String>[
        ...queues[key] ?? const <String>[],
        eventNodeId,
      ];
      queues[key] = _sortRelationQueue(
        queue,
        nodes: nodes,
        keywords: keywords,
      ).take(queueLimit).toList(growable: false);
    }
    return graph.copyWith(settingEventQueues: queues);
  }

  EventGraphMemory _applyQueueLru(
    EventGraphMemory graph, {
    required EventTier tier,
    required int fixedCount,
    required List<String> inputKeywords,
    required AppSettings settings,
  }) {
    final queue = queueForTier(graph, tier);
    if (queue.length <= fixedCount) return graph;
    final retained = queue.take(fixedCount).toList(growable: false);
    final sorted = _sortNodes(
      queue.skip(fixedCount).toList(),
      graph: graph,
      inputKeywords: inputKeywords,
      settings: settings,
    );
    final result = <EventNode>[...retained, ...sorted];
    return switch (tier) {
      EventTier.shortTerm => graph.copyWith(shortTermQueue: result),
      EventTier.longTerm => graph.copyWith(longTermQueue: result),
      EventTier.ultraLongTerm => graph.copyWith(ultraLongTermQueue: result),
    };
  }

  List<EventNode> _sortNodes(
    List<EventNode> events, {
    required EventGraphMemory graph,
    required List<String> inputKeywords,
    required AppSettings settings,
  }) {
    final keywords = inputKeywords.map((item) => item.toLowerCase()).toSet();
    final nodes = _nodeMap(graph);
    final adjacent = <String, Set<String>>{};
    for (final edge in graph.edges.values) {
      if (!nodes.containsKey(edge.fromNodeId) ||
          !nodes.containsKey(edge.toNodeId)) {
        continue;
      }
      adjacent
          .putIfAbsent(edge.fromNodeId, () => <String>{})
          .add(edge.toNodeId);
      adjacent
          .putIfAbsent(edge.toNodeId, () => <String>{})
          .add(edge.fromNodeId);
    }
    final scores = <String, int>{};
    for (final node in events) {
      final terms = _eventTerms(node);
      var score =
          keywords.intersection(terms).length * settings.lruKeywordMatchWeight;
      for (final neighborId in adjacent[node.id] ?? const <String>{}) {
        final neighbor = nodes[neighborId];
        if (neighbor != null &&
            keywords.intersection(_eventTerms(neighbor)).isNotEmpty) {
          score += settings.lruEventEventWeight;
          break;
        }
      }
      score += _relationScore(
        node.id,
        graph.belongingEventQueues,
        keywords,
        keywordWeight: settings.lruEventBelongingKeywordWeight,
        normalWeight: settings.lruEventBelongingNormalWeight,
      );
      score += _relationScore(
        node.id,
        graph.settingEventQueues,
        keywords,
        keywordWeight: settings.lruEventSettingKeywordWeight,
        normalWeight: settings.lruEventSettingNormalWeight,
      );
      scores[node.id] = score;
    }
    return List<EventNode>.from(events)
      ..sort((left, right) {
        final scoreOrder =
            (scores[right.id] ?? 0).compareTo(scores[left.id] ?? 0);
        return scoreOrder != 0
            ? scoreOrder
            : right.createdAtMs.compareTo(left.createdAtMs);
      });
  }

  int _relationScore(
    String nodeId,
    Map<String, List<String>> queues,
    Set<String> keywords, {
    required int keywordWeight,
    required int normalWeight,
  }) {
    for (final entry in queues.entries) {
      if (!entry.value.contains(nodeId)) continue;
      final key = entry.key.toLowerCase();
      return keywords.any((term) => key.contains(term) || term.contains(key))
          ? keywordWeight
          : normalWeight;
    }
    return 0;
  }

  List<String> _sortRelationQueue(
    List<String> queue, {
    required Map<String, EventNode> nodes,
    required Set<String> keywords,
  }) {
    final unique = queue.toSet().toList();
    unique.sort((left, right) {
      int score(String id) {
        final node = nodes[id];
        if (node == null) return 0;
        return keywords.intersection(_eventTerms(node)).length * 100 +
            node.createdAtMs ~/ 1000000;
      }

      return score(right).compareTo(score(left));
    });
    return unique;
  }

  Set<String> _eventTerms(EventNode node) => <String>{
        ...node.event.keywords.map((item) => item.toLowerCase()),
        ...node.event.theme.map((item) => item.toLowerCase()),
      };

  Map<String, EventNode> _nodeMap(EventGraphMemory graph) =>
      <String, EventNode>{
        for (final node in graph.shortTermQueue) node.id: node,
        for (final node in graph.longTermQueue) node.id: node,
        for (final node in graph.ultraLongTermQueue) node.id: node,
      };

  Map<String, List<String>> _copyQueues(Map<String, List<String>> source) =>
      <String, List<String>>{
        for (final entry in source.entries)
          entry.key: List<String>.from(entry.value),
      };
}
