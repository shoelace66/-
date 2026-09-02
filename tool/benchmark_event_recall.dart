import 'dart:math' as math;

import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/memory_recall_service.dart';

const _nodeCount = 2700;
const _iterations = 30;
const _p95BudgetMs = 50.0;

void main() {
  const recall = MemoryRecallService();
  final graph = _buildGraph();
  final hubGraph = _buildHubGraph();

  // Warm up the JIT before taking measurements.
  for (var i = 0; i < 3; i++) {
    final index = recall.buildIndex(graph);
    recall.search(index, recall.matchInput(index, '角色42在地点7提到事件1042'));
  }

  final buildSamples = <double>[];
  final querySamples = <double>[];
  final commonTermSamples = <double>[];
  for (var i = 0; i < _iterations; i++) {
    final buildWatch = Stopwatch()..start();
    final index = recall.buildIndex(graph);
    buildWatch.stop();
    buildSamples.add(buildWatch.elapsedMicroseconds / 1000);

    final queryWatch = Stopwatch()..start();
    final terms = recall.matchInput(index, '角色42在地点7提到事件1042');
    recall.search(index, terms);
    queryWatch.stop();
    querySamples.add(queryWatch.elapsedMicroseconds / 1000);

    final commonTermWatch = Stopwatch()..start();
    final commonTerm = recall.matchInput(index, '主题1');
    recall.search(index, commonTerm);
    commonTermWatch.stop();
    commonTermSamples.add(commonTermWatch.elapsedMicroseconds / 1000);
  }

  final hubIndex = recall.buildIndex(hubGraph);
  final hubSamples = <double>[];
  for (var i = 0; i < _iterations; i++) {
    final watch = Stopwatch()..start();
    final terms = recall.matchInput(hubIndex, '中心锚点');
    recall.search(hubIndex, terms);
    watch.stop();
    hubSamples.add(watch.elapsedMicroseconds / 1000);
  }

  final buildP95 = _percentile(buildSamples, 0.95);
  final queryP95 = _percentile(querySamples, 0.95);
  final commonTermP95 = _percentile(commonTermSamples, 0.95);
  final hubP95 = _percentile(hubSamples, 0.95);
  print('event recall benchmark ($_nodeCount nodes, $_iterations iterations)');
  print(
      'index build: p50=${_percentile(buildSamples, 0.50).toStringAsFixed(2)} ms, '
      'p95=${buildP95.toStringAsFixed(2)} ms');
  print(
      'query:       p50=${_percentile(querySamples, 0.50).toStringAsFixed(2)} ms, '
      'p95=${queryP95.toStringAsFixed(2)} ms');
  print(
      'common term: p50=${_percentile(commonTermSamples, 0.50).toStringAsFixed(2)} ms, '
      'p95=${commonTermP95.toStringAsFixed(2)} ms');
  print(
      'star graph:  p50=${_percentile(hubSamples, 0.50).toStringAsFixed(2)} ms, '
      'p95=${hubP95.toStringAsFixed(2)} ms');

  if (buildP95 >= _p95BudgetMs ||
      queryP95 >= _p95BudgetMs ||
      commonTermP95 >= _p95BudgetMs ||
      hubP95 >= _p95BudgetMs) {
    throw StateError(
        'P95 must remain below ${_p95BudgetMs.toStringAsFixed(0)} ms');
  }
}

EventGraphMemory _buildHubGraph() {
  final nodes = List<EventNode>.generate(
    _nodeCount,
    (index) => EventNode(
      id: 'hub-event-$index',
      tier: EventTier.longTerm,
      event: EventMemory(
        description: '星形图事件 $index',
        keywords: index == 0 ? const <String>['中心锚点'] : const <String>[],
      ),
      createdAtMs: index,
    ),
    growable: false,
  );
  final edges = <String, EventEdge>{};
  for (var index = 1; index < _nodeCount; index++) {
    final edge = EventEdge(
      fromNodeId: 'hub-event-0',
      toNodeId: 'hub-event-$index',
    );
    edges[edge.toUniqueKey()] = edge;
  }
  return EventGraphMemory(longTermQueue: nodes, edges: edges);
}

EventGraphMemory _buildGraph() {
  final nodes = List<EventNode>.generate(
    _nodeCount,
    (index) => EventNode(
      id: 'event-$index',
      tier: EventTier.longTerm,
      event: EventMemory(
        description: '基准事件 $index',
        keywords: <String>[
          '角色${index % 90}',
          '地点${index % 45}',
          '事件$index',
        ],
        theme: <String>['主题${index % 12}'],
      ),
      createdAtMs: index,
    ),
    growable: false,
  );
  final edges = <String, EventEdge>{};
  for (var index = 0; index < _nodeCount - 1; index++) {
    final edge = EventEdge(
      fromNodeId: 'event-$index',
      toNodeId: 'event-${index + 1}',
    );
    edges[edge.toUniqueKey()] = edge;
    if (index + 17 < _nodeCount) {
      final chord = EventEdge(
        fromNodeId: 'event-$index',
        toNodeId: 'event-${index + 17}',
      );
      edges[chord.toUniqueKey()] = chord;
    }
  }
  return EventGraphMemory(longTermQueue: nodes, edges: edges);
}

double _percentile(List<double> values, double percentile) {
  final sorted = List<double>.from(values)..sort();
  final index = math.max(0, (sorted.length * percentile).ceil() - 1);
  return sorted[index];
}
