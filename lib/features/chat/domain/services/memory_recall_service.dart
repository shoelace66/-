import 'dart:collection';

import '../../data/models/contact.dart';

/// 事件图召回与关系清理。
///
/// 事件图完整保存在本地；每轮只把 [recall] 返回的有限结果放进 Prompt。
class MemoryRecallService {
  const MemoryRecallService();

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

    final inputKeywordSet =
        inputKeywords.map((keyword) => keyword.toLowerCase()).toSet();
    final effectiveDepth = depth < 1 ? 1 : depth;
    final allNodes = _allNodes(graph);
    if (allNodes.isEmpty) return const <EventNode>[];

    final scored = <_ScoredNode>[];
    for (final node in allNodes) {
      final eventTerms = <String>{
        ...node.event.keywords.map((keyword) => keyword.toLowerCase()),
        ...node.event.theme.map((theme) => theme.toLowerCase()),
      };
      final hitCount = inputKeywordSet.intersection(eventTerms).length;
      if (hitCount > 0) {
        scored.add(_ScoredNode(node: node, score: hitCount));
      }
    }
    scored.sort((left, right) {
      if (left.score != right.score) {
        return right.score.compareTo(left.score);
      }
      return right.node.createdAtMs.compareTo(left.node.createdAtMs);
    });

    final idToNode = <String, EventNode>{
      for (final node in allNodes) node.id: node,
    };
    final adjacent = <String, LinkedHashSet<String>>{};
    for (final edge in graph.edges.values) {
      if (!idToNode.containsKey(edge.fromNodeId) ||
          !idToNode.containsKey(edge.toNodeId)) {
        continue;
      }
      adjacent
          .putIfAbsent(edge.fromNodeId, LinkedHashSet<String>.new)
          .add(edge.toNodeId);
      adjacent
          .putIfAbsent(edge.toNodeId, LinkedHashSet<String>.new)
          .add(edge.fromNodeId);
    }

    final result = <EventNode>[];
    final seen = <String>{};
    for (final hit in scored) {
      if (result.length >= maxResults) break;
      if (seen.add(hit.node.id)) result.add(hit.node);

      final queue = Queue<_TraversalStep>.from(
        (adjacent[hit.node.id] ?? const <String>{})
            .map((id) => _TraversalStep(id: id, depth: 1)),
      );
      while (queue.isNotEmpty && result.length < maxResults) {
        final step = queue.removeFirst();
        if (!seen.add(step.id)) continue;
        final node = idToNode[step.id];
        if (node == null) continue;
        result.add(node);
        if (step.depth < effectiveDepth) {
          for (final next in adjacent[step.id] ?? const <String>{}) {
            queue.add(_TraversalStep(id: next, depth: step.depth + 1));
          }
        }
      }
    }

    _appendQueueMatches(
      result: result,
      seen: seen,
      queues: graph.belongingEventQueues,
      inputKeywords: inputKeywordSet,
      idToNode: idToNode,
      maxResults: maxResults,
    );
    _appendQueueMatches(
      result: result,
      seen: seen,
      queues: graph.settingEventQueues,
      inputKeywords: inputKeywordSet,
      idToNode: idToNode,
      maxResults: maxResults,
    );

    return result.take(maxResults).toList(growable: false);
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

  void _appendQueueMatches({
    required List<EventNode> result,
    required Set<String> seen,
    required Map<String, List<String>> queues,
    required Set<String> inputKeywords,
    required Map<String, EventNode> idToNode,
    required int maxResults,
  }) {
    for (final entry in queues.entries) {
      if (result.length >= maxResults) return;
      final key = entry.key.toLowerCase();
      final matches =
          inputKeywords.any((term) => key.contains(term) || term.contains(key));
      if (!matches) continue;

      for (final eventId in entry.value.reversed) {
        if (result.length >= maxResults) return;
        final node = idToNode[eventId];
        if (node != null && seen.add(node.id)) {
          result.add(node);
        }
      }
    }
  }

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
}

class _ScoredNode {
  const _ScoredNode({required this.node, required this.score});

  final EventNode node;
  final int score;
}

class _TraversalStep {
  const _TraversalStep({required this.id, required this.depth});

  final String id;
  final int depth;
}
