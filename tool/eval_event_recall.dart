import 'dart:convert';
import 'dart:io';

import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/event_recall_coordinator.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/memory_recall_service.dart';
import 'package:flutter_chat_demo/infrastructure/services/ai_service.dart';

/// Reproducible, offline release-gate evaluation for event recall.
///
/// The evaluator deliberately calls the production coordinator and recall
/// service. The only model is [_DeterministicFakeModel], which reads the
/// coordinator's frozen JSON prompt and returns a valid response. No HTTP or
/// other network-capable API is imported by this tool.
Future<void> main() async {
  // Flutter's test runner invokes a Dart entrypoint with no arguments. An
  // environment override keeps the evaluator useful for alternate fixtures
  // while the checked-in release fixture remains the default.
  final fixturePath = Platform.environment['EVENT_RECALL_FIXTURE'] ??
      'test/fixtures/event_recall_eval_v1.json';
  final fixture = _Fixture.load(File(fixturePath));
  final samples = fixture.samples;
  if (samples.length < fixture.minimumSampleCount) {
    throw StateError(
      'fixture has ${samples.length} samples; '
      'minimum is ${fixture.minimumSampleCount}',
    );
  }

  const profile = LlmProfile(
    model: 'deterministic-offline-fake',
    parameters: LlmParameters(
      temperature: 0,
      maxTokens: 256,
      timeoutSeconds: 1,
      stream: false,
    ),
  );
  const recallService = MemoryRecallService();
  final coordinator = EventRecallCoordinator(recallService: recallService);
  final rows = <_EvalResult>[];
  for (final sample in samples) {
    final graphSpec = _GraphFactory.build(sample);
    final fake = _DeterministicFakeModel(sample);
    final outcome = await coordinator.recall(
      graph: graphSpec.graph,
      currentInput: sample.current,
      recentMessages: sample.recent,
      hotNodeIds: graphSpec.hotNodeIds,
      mainProfile: profile,
      memoryRecallProfile: profile,
      invokeModel: fake.call,
      maxResults: 5,
      depth: 2,
    );
    final actualIds =
        outcome.nodes.map((node) => node.id).toList(growable: false);
    rows.add(
      _EvalResult(
        sample: sample,
        actualIds: actualIds,
        postCount: outcome.postCount,
        phase: outcome.phase,
        modelCalls: fake.calls,
      ),
    );
  }

  final overallRecall = _recallAt5(rows);
  final explicitRows = rows.where((row) => row.sample.explicitStructured);
  final explicitRecall = _recallAt5(explicitRows);
  final averagePosts =
      rows.fold<int>(0, (sum, row) => sum + row.postCount) / rows.length;
  final secondCallRate =
      rows.where((row) => row.postCount >= 2).length / rows.length;
  final baseline = fixture.baselineOverallRecallAt5;

  _require(
    explicitRecall >= fixture.minimumExplicitStructuredRecallAt5,
    'explicit structured Recall@5 ${_pct(explicitRecall)} is below '
    '${_pct(fixture.minimumExplicitStructuredRecallAt5)}',
  );
  _require(
    overallRecall >= fixture.minimumOverallRecallAt5,
    'overall Recall@5 ${_pct(overallRecall)} is below '
    '${_pct(fixture.minimumOverallRecallAt5)}',
  );
  _require(
    overallRecall >= baseline,
    'overall Recall@5 ${_pct(overallRecall)} is below frozen baseline '
    '${_pct(baseline)}',
  );
  _require(
    averagePosts <= fixture.maximumAverageExtraPosts + 1e-9,
    'average extra POST ${averagePosts.toStringAsFixed(3)} exceeds '
    '${fixture.maximumAverageExtraPosts.toStringAsFixed(3)}',
  );
  _require(
    secondCallRate <= fixture.maximumSecondCallRate + 1e-9,
    'second-call rate ${_pct(secondCallRate)} exceeds '
    '${_pct(fixture.maximumSecondCallRate)}',
  );
  for (final gate in <int>[0, 1, 2]) {
    _require(
      rows.any((row) => row.sample.expectedPosts == gate),
      'fixture does not cover the $gate-POST gate',
    );
    _require(
      rows
          .where((row) => row.sample.expectedPosts == gate)
          .every((row) => row.postCount == gate),
      'a sample expected to use the $gate-POST gate used another count',
    );
  }

  stdout.writeln('event-recall offline release evaluation');
  stdout.writeln('fixture: $fixturePath (v${fixture.version})');
  stdout.writeln('model: deterministic fake; network: disabled');
  stdout.writeln('samples: ${rows.length}');
  stdout.writeln(
    'explicit structured Recall@5: ${_pct(explicitRecall)} '
    '(${explicitRows.length} samples)',
  );
  stdout.writeln('overall Recall@5: ${_pct(overallRecall)}');
  stdout.writeln(
    'frozen old baseline: ${_pct(baseline)}; '
    'delta: ${_signedPp(overallRecall - baseline)} pp',
  );
  stdout.writeln('average extra POST: ${averagePosts.toStringAsFixed(3)}');
  stdout.writeln('second-call rate: ${_pct(secondCallRate)}');
  stdout.writeln(
    'gate samples/posts: '
    '${_gateSummary(rows, 0)}; ${_gateSummary(rows, 1)}; '
    '${_gateSummary(rows, 2)}',
  );
  final byCategory = <String, List<_EvalResult>>{};
  for (final row in rows) {
    byCategory.putIfAbsent(row.sample.category, () => <_EvalResult>[]).add(row);
  }
  for (final entry in byCategory.entries) {
    stdout.writeln(
      'category ${entry.key}: ${_pct(_recallAt5(entry.value))}, '
      'posts=${_averagePosts(entry.value).toStringAsFixed(2)}, '
      'n=${entry.value.length}',
    );
  }
  stdout.writeln('PASS: all release thresholds satisfied');
}

void _require(bool condition, String message) {
  if (!condition) {
    throw StateError('event-recall release gate failed: $message');
  }
}

String _pct(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _signedPp(double value) {
  final sign = value >= 0 ? '+' : '';
  return '$sign${(value * 100).toStringAsFixed(1)}';
}

double _recallAt5(Iterable<_EvalResult> rows) {
  final values = rows.toList(growable: false);
  if (values.isEmpty) return 1;
  var hits = 0;
  for (final row in values) {
    final expected = row.sample.expectedNodeIds.toSet();
    final actual = row.actualIds.take(5).toSet();
    if (expected.isEmpty ? actual.isEmpty : expected.every(actual.contains)) {
      hits++;
    }
  }
  return hits / values.length;
}

double _averagePosts(Iterable<_EvalResult> rows) {
  final values = rows.toList(growable: false);
  if (values.isEmpty) return 0;
  return values.fold<int>(0, (sum, row) => sum + row.postCount) / values.length;
}

String _gateSummary(List<_EvalResult> rows, int gate) {
  final values = rows.where((row) => row.sample.expectedPosts == gate).toList();
  return '$gate=${values.length}/${_averagePosts(values).toStringAsFixed(2)}POST';
}

class _Fixture {
  _Fixture({
    required this.version,
    required this.minimumSampleCount,
    required this.minimumExplicitStructuredRecallAt5,
    required this.minimumOverallRecallAt5,
    required this.maximumAverageExtraPosts,
    required this.maximumSecondCallRate,
    required this.baselineOverallRecallAt5,
    required this.samples,
  });

  final int version;
  final int minimumSampleCount;
  final double minimumExplicitStructuredRecallAt5;
  final double minimumOverallRecallAt5;
  final double maximumAverageExtraPosts;
  final double maximumSecondCallRate;
  final double baselineOverallRecallAt5;
  final List<_Sample> samples;

  factory _Fixture.load(File file) {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final thresholds = json['releaseThresholds'] as Map<String, dynamic>;
    final baseline = json['baseline'] as Map<String, dynamic>;
    final groups =
        (json['groups'] as List<dynamic>).cast<Map<String, dynamic>>();
    final samples = <_Sample>[];
    for (final group in groups) {
      final scenario = group['scenario'].toString();
      final category = group['category'].toString();
      final expectedPosts = (group['expectedPosts'] as num).toInt();
      final explicitStructured = group['explicitStructured'] == true;
      for (final raw in (group['samples'] as List<dynamic>)) {
        final value = raw as Map<String, dynamic>;
        final recent =
            ((value['recent'] as List<dynamic>?) ?? const <dynamic>[])
                .map((message) {
          final item = message as Map<String, dynamic>;
          return RecallDialogueMessage(
            role: item['role'].toString(),
            content: item['content'].toString(),
          );
        }).toList(growable: false);
        samples.add(
          _Sample(
            id: value['id'].toString(),
            scenario: scenario,
            category: category,
            expectedPosts: expectedPosts,
            explicitStructured: explicitStructured,
            term: value['term'].toString(),
            current: value['current'].toString(),
            recent: recent,
            expectedNodeIds:
                (value['expectedNodeIds'] as List<dynamic>).cast<String>(),
          ),
        );
      }
    }
    return _Fixture(
      version: (json['v'] as num).toInt(),
      minimumSampleCount: (thresholds['minimumSampleCount'] as num).toInt(),
      minimumExplicitStructuredRecallAt5:
          (thresholds['minimumExplicitStructuredRecallAt5'] as num).toDouble(),
      minimumOverallRecallAt5:
          (thresholds['minimumOverallRecallAt5'] as num).toDouble(),
      maximumAverageExtraPosts:
          (thresholds['maximumAverageExtraPosts'] as num).toDouble(),
      maximumSecondCallRate:
          (thresholds['maximumSecondCallRate'] as num).toDouble(),
      baselineOverallRecallAt5:
          (baseline['overallRecallAt5'] as num).toDouble(),
      samples: List<_Sample>.unmodifiable(samples),
    );
  }
}

class _Sample {
  _Sample({
    required this.id,
    required this.scenario,
    required this.category,
    required this.expectedPosts,
    required this.explicitStructured,
    required this.term,
    required this.current,
    required this.recent,
    required this.expectedNodeIds,
  });

  final String id;
  final String scenario;
  final String category;
  final int expectedPosts;
  final bool explicitStructured;
  final String term;
  final String current;
  final List<RecallDialogueMessage> recent;
  final List<String> expectedNodeIds;
}

class _EvalResult {
  _EvalResult({
    required this.sample,
    required this.actualIds,
    required this.postCount,
    required this.phase,
    required this.modelCalls,
  });

  final _Sample sample;
  final List<String> actualIds;
  final int postCount;
  final RecallPhase phase;
  final int modelCalls;
}

class _GraphSpec {
  const _GraphSpec(this.graph, this.hotNodeIds);

  final EventGraphMemory graph;
  final Set<String> hotNodeIds;
}

class _GraphFactory {
  static _GraphSpec build(_Sample sample) {
    final targetId = sample.expectedNodeIds.isEmpty
        ? '${sample.id}-target'
        : sample.expectedNodeIds.first;
    final isHotGraph = sample.scenario == 'continuity_hot_graph';
    final isTheme = sample.category == 'theme';
    final isAmbiguous = sample.category == 'ambiguity';
    final relation = sample.scenario.contains('relation');
    final target = EventNode(
      id: targetId,
      tier: EventTier.longTerm,
      event: EventMemory(
        description: targetId,
        keywords: relation || isTheme || isHotGraph
            ? const <String>[]
            : <String>[sample.term],
        theme: isTheme ? <String>[sample.term] : const <String>[],
      ),
      createdAtMs: 1000,
    );

    if (isHotGraph) {
      final hotId = '${sample.id}-hot';
      final hot = EventNode(
        id: hotId,
        tier: EventTier.shortTerm,
        event: EventMemory(description: hotId, keywords: <String>[sample.term]),
        createdAtMs: 1100,
      );
      final edge = EventEdge(fromNodeId: hotId, toNodeId: targetId);
      return _GraphSpec(
        EventGraphMemory(
          shortTermQueue: <EventNode>[hot],
          longTermQueue: <EventNode>[target],
          edges: <String, EventEdge>{edge.toUniqueKey(): edge},
        ),
        <String>{hotId},
      );
    }

    final nodes = <EventNode>[target];
    if (isTheme || isAmbiguous) {
      final count = isAmbiguous ? 5 : 5;
      for (var index = 0; index < count; index++) {
        final id = '${sample.id}-distractor-$index';
        nodes.add(
          EventNode(
            id: id,
            tier: EventTier.longTerm,
            event: EventMemory(
              description: id,
              keywords: isAmbiguous ? <String>[sample.term] : const <String>[],
              theme: isTheme ? <String>[sample.term] : const <String>[],
            ),
            createdAtMs: 900 - index,
          ),
        );
      }
    }
    final graph = EventGraphMemory(
      longTermQueue: nodes,
      belongingEventQueues: sample.scenario.contains('belonging')
          ? <String, List<String>>{
              sample.term: <String>[targetId]
            }
          : const <String, List<String>>{},
      settingEventQueues: sample.scenario.contains('setting') ||
              sample.scenario == 'continuity_relation'
          ? <String, List<String>>{
              sample.term: <String>[targetId]
            }
          : const <String, List<String>>{},
    );
    return _GraphSpec(graph, const <String>{});
  }
}

class _DeterministicFakeModel {
  _DeterministicFakeModel(this.sample);

  final _Sample sample;
  int calls = 0;

  Future<String> call({
    required String prompt,
    required LlmProfile profile,
    required RecallRequestBudget requestBudget,
  }) async {
    calls++;
    if (!requestBudget.tryConsumePost()) {
      throw StateError('fake model received an exhausted request budget');
    }
    final payload = jsonDecode(prompt.substring(prompt.indexOf('DATA=') + 5))
        as Map<String, dynamic>;
    if (prompt.startsWith('event-recall-plan-v1')) {
      final aliases = <String>[];
      for (final bucket in <String>['k', 't', 'r']) {
        final items =
            (payload['catalog'][bucket] as List<dynamic>?) ?? const <dynamic>[];
        aliases.addAll(
          items.map((item) => (item as Map<String, dynamic>)['id'].toString()),
        );
      }
      return jsonEncode(<String, dynamic>{
        'v': 1,
        'action': aliases.isEmpty ? 'skip' : 'search',
        'k': _aliases(payload, 'k'),
        't': _aliases(payload, 't'),
        'r': _aliases(payload, 'r'),
        'recency': 'any',
        'confidence': 'high',
      });
    }
    if (!prompt.startsWith('event-recall-judge-v1')) {
      throw const FormatException('unexpected coordinator prompt');
    }
    final cards =
        (payload['candidates'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var index = 0; index < cards.length; index++) {
      if (cards[index]['description'].toString() ==
          sample.expectedNodeIds.first) {
        return '{"v":1,"selected":["E$index"],"confidence":"high"}';
      }
    }
    return '{"v":1,"selected":[],"confidence":"low"}';
  }

  List<String> _aliases(Map<String, dynamic> payload, String bucket) {
    final items =
        (payload['catalog'][bucket] as List<dynamic>?) ?? const <dynamic>[];
    return items
        .map((item) => (item as Map<String, dynamic>)['id'].toString())
        .take(bucket == 'k' ? 8 : 4)
        .toList(growable: false);
  }
}
