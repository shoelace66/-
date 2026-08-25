import '../../data/models/contact.dart';

class MemoryRevisionImpact {
  const MemoryRevisionImpact({
    required this.eventNodeId,
    required this.edgeCount,
    required this.belongingKeys,
    required this.settingKeys,
    required this.affectedSummaryNodeIds,
  });

  final String eventNodeId;
  final int edgeCount;
  final List<String> belongingKeys;
  final List<String> settingKeys;
  final List<String> affectedSummaryNodeIds;

  bool get hasRelatedData =>
      edgeCount > 0 ||
      belongingKeys.isNotEmpty ||
      settingKeys.isNotEmpty ||
      affectedSummaryNodeIds.isNotEmpty;
}

class MemoryRevisionRecord {
  const MemoryRevisionRecord({
    required this.id,
    required this.eventNodeId,
    required this.graphTurnCount,
    required this.previousNode,
    required this.removedEdges,
    required this.previousBelongingQueues,
    required this.previousSettingQueues,
    required this.previousReviewStates,
  });

  final String id;
  final String eventNodeId;
  final int graphTurnCount;
  final EventNode previousNode;
  final Map<String, EventEdge> removedEdges;
  final Map<String, List<String>> previousBelongingQueues;
  final Map<String, List<String>> previousSettingQueues;
  final Map<String, bool> previousReviewStates;

  factory MemoryRevisionRecord.fromJson(Map<String, dynamic> json) {
    Map<String, List<String>> readQueues(Object? raw) {
      if (raw is! Map) return const <String, List<String>>{};
      return <String, List<String>>{
        for (final entry in raw.entries)
          entry.key.toString(): entry.value is List
              ? (entry.value as List)
                  .map((value) => value.toString())
                  .toList(growable: false)
              : const <String>[],
      };
    }

    final edgeRaw = json['removedEdges'];
    final reviewRaw = json['previousReviewStates'];
    return MemoryRevisionRecord(
      id: (json['id'] ?? '').toString(),
      eventNodeId: (json['eventNodeId'] ?? '').toString(),
      graphTurnCount: (json['graphTurnCount'] as num?)?.toInt() ?? 0,
      previousNode: EventNode.fromJson(
        Map<String, dynamic>.from(json['previousNode'] as Map? ?? const {}),
      ),
      removedEdges: edgeRaw is Map
          ? <String, EventEdge>{
              for (final entry in edgeRaw.entries)
                entry.key.toString(): EventEdge.fromJson(
                  Map<String, dynamic>.from(entry.value as Map),
                ),
            }
          : const <String, EventEdge>{},
      previousBelongingQueues: readQueues(json['previousBelongingQueues']),
      previousSettingQueues: readQueues(json['previousSettingQueues']),
      previousReviewStates: reviewRaw is Map
          ? <String, bool>{
              for (final entry in reviewRaw.entries)
                entry.key.toString(): entry.value == true,
            }
          : const <String, bool>{},
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'eventNodeId': eventNodeId,
        'graphTurnCount': graphTurnCount,
        'previousNode': previousNode.toJson(),
        'removedEdges': <String, dynamic>{
          for (final entry in removedEdges.entries)
            entry.key: entry.value.toJson(),
        },
        'previousBelongingQueues': previousBelongingQueues,
        'previousSettingQueues': previousSettingQueues,
        'previousReviewStates': previousReviewStates,
      };
}

class MemoryRevisionResult {
  const MemoryRevisionResult({required this.graph, required this.record});

  final EventGraphMemory graph;
  final MemoryRevisionRecord record;
}

/// 记忆修订、作废和撤销规则。
///
/// 修订时不猜测旧关系是否仍然成立：相关边和关系队列暂时失效，受影响的阶段/
/// 长期概括被标记为待复核；撤销最近修订时可以无损恢复这些数据。
class MemoryRevisionService {
  const MemoryRevisionService();

  MemoryRevisionImpact preview(EventGraphMemory graph, String eventNodeId) {
    final nodes = _nodeMap(graph);
    if (!nodes.containsKey(eventNodeId)) {
      throw ArgumentError.value(eventNodeId, 'eventNodeId', 'Event not found');
    }
    final incident = graph.edges.values
        .where((edge) =>
            edge.fromNodeId == eventNodeId || edge.toNodeId == eventNodeId)
        .toList(growable: false);
    final affectedSummaries = <String>{};
    for (final edge in incident) {
      final otherId =
          edge.fromNodeId == eventNodeId ? edge.toNodeId : edge.fromNodeId;
      final other = nodes[otherId];
      if (other != null && other.tier != EventTier.shortTerm) {
        affectedSummaries.add(otherId);
      }
    }
    return MemoryRevisionImpact(
      eventNodeId: eventNodeId,
      edgeCount: incident.length,
      belongingKeys: _relationKeys(graph.belongingEventQueues, eventNodeId),
      settingKeys: _relationKeys(graph.settingEventQueues, eventNodeId),
      affectedSummaryNodeIds: affectedSummaries.toList(growable: false),
    );
  }

  MemoryRevisionResult revise({
    required EventGraphMemory graph,
    required String eventNodeId,
    required EventMemory revisedEvent,
    required String revisionId,
    bool invalidate = false,
  }) {
    if (!invalidate && revisedEvent.isEmpty) {
      throw ArgumentError.value(revisedEvent, 'revisedEvent', 'Event is empty');
    }
    final nodes = _nodeMap(graph);
    final previous = nodes[eventNodeId];
    if (previous == null) {
      throw ArgumentError.value(eventNodeId, 'eventNodeId', 'Event not found');
    }
    final impact = preview(graph, eventNodeId);
    final affectedIds = impact.affectedSummaryNodeIds.toSet();
    final previousReviewStates = <String, bool>{
      for (final id in affectedIds) id: nodes[id]?.needsReview ?? false,
    };
    final removedEdges = <String, EventEdge>{
      for (final entry in graph.edges.entries)
        if (entry.value.fromNodeId == eventNodeId ||
            entry.value.toNodeId == eventNodeId)
          entry.key: entry.value,
    };
    final retainedEdges = Map<String, EventEdge>.from(graph.edges)
      ..removeWhere((key, edge) => removedEdges.containsKey(key));

    List<EventNode> updateQueue(List<EventNode> queue) => queue.map((node) {
          if (node.id == eventNodeId) {
            return _copyNode(
              node,
              event: invalidate ? node.event : revisedEvent,
              invalidated: invalidate,
              needsReview: false,
            );
          }
          if (affectedIds.contains(node.id)) {
            return _copyNode(node, needsReview: true);
          }
          return node;
        }).toList(growable: false);

    final record = MemoryRevisionRecord(
      id: revisionId,
      eventNodeId: eventNodeId,
      graphTurnCount: graph.turnCount,
      previousNode: previous,
      removedEdges: removedEdges,
      previousBelongingQueues: _copyQueues(graph.belongingEventQueues),
      previousSettingQueues: _copyQueues(graph.settingEventQueues),
      previousReviewStates: previousReviewStates,
    );
    return MemoryRevisionResult(
      graph: graph.copyWith(
        shortTermQueue: updateQueue(graph.shortTermQueue),
        longTermQueue: updateQueue(graph.longTermQueue),
        ultraLongTermQueue: updateQueue(graph.ultraLongTermQueue),
        edges: retainedEdges,
        belongingEventQueues:
            _removeFromQueues(graph.belongingEventQueues, eventNodeId),
        settingEventQueues:
            _removeFromQueues(graph.settingEventQueues, eventNodeId),
      ),
      record: record,
    );
  }

  EventGraphMemory undo(EventGraphMemory graph, MemoryRevisionRecord record) {
    if (graph.turnCount != record.graphTurnCount) {
      throw StateError('Cannot undo memory revision after a new turn');
    }
    final edges = Map<String, EventEdge>.from(graph.edges)
      ..addAll(record.removedEdges);
    List<EventNode> restore(List<EventNode> queue) => queue.map((node) {
          if (node.id == record.eventNodeId) return record.previousNode;
          if (record.previousReviewStates.containsKey(node.id)) {
            return _copyNode(
              node,
              needsReview: record.previousReviewStates[node.id]!,
            );
          }
          return node;
        }).toList(growable: false);
    return graph.copyWith(
      shortTermQueue: restore(graph.shortTermQueue),
      longTermQueue: restore(graph.longTermQueue),
      ultraLongTermQueue: restore(graph.ultraLongTermQueue),
      edges: edges,
      belongingEventQueues: _copyQueues(record.previousBelongingQueues),
      settingEventQueues: _copyQueues(record.previousSettingQueues),
    );
  }

  EventNode _copyNode(
    EventNode node, {
    EventMemory? event,
    bool? invalidated,
    bool? needsReview,
  }) {
    return EventNode(
      id: node.id,
      tier: node.tier,
      event: event ?? node.event,
      createdAtMs: node.createdAtMs,
      summarized: node.summarized,
      invalidated: invalidated ?? node.invalidated,
      needsReview: needsReview ?? node.needsReview,
    );
  }

  Map<String, EventNode> _nodeMap(EventGraphMemory graph) =>
      <String, EventNode>{
        for (final node in graph.shortTermQueue) node.id: node,
        for (final node in graph.longTermQueue) node.id: node,
        for (final node in graph.ultraLongTermQueue) node.id: node,
      };

  List<String> _relationKeys(
    Map<String, List<String>> queues,
    String eventNodeId,
  ) =>
      queues.entries
          .where((entry) => entry.value.contains(eventNodeId))
          .map((entry) => entry.key)
          .toList(growable: false);

  Map<String, List<String>> _removeFromQueues(
    Map<String, List<String>> queues,
    String eventNodeId,
  ) {
    final result = <String, List<String>>{};
    for (final entry in queues.entries) {
      final retained =
          entry.value.where((id) => id != eventNodeId).toList(growable: false);
      if (retained.isNotEmpty) result[entry.key] = retained;
    }
    return result;
  }

  Map<String, List<String>> _copyQueues(Map<String, List<String>> source) =>
      <String, List<String>>{
        for (final entry in source.entries)
          entry.key: List<String>.from(entry.value),
      };
}
