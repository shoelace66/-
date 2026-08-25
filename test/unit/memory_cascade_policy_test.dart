import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/memory_cascade_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = MemoryCascadePolicy();

  group('MemoryCascadePolicy', () {
    test('未达到任一阈值时不触发级联', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('s1', EventTier.shortTerm),
          _node('s2', EventTier.shortTerm, summarized: true),
        ],
        longTermQueue: <EventNode>[
          _node('l1', EventTier.longTerm),
        ],
      );

      final decision = policy.evaluate(
        graph: graph,
        shortTermThreshold: 2,
        longTermThreshold: 2,
      );

      expect(decision.needsSummary, isFalse);
      expect(decision.sourceTier, isNull);
      expect(decision.pendingEvents, isEmpty);
    });

    test('短期和长期同时达到阈值时固定优先短期', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('s1', EventTier.shortTerm),
          _node('s2', EventTier.shortTerm),
          _node('s3', EventTier.shortTerm),
        ],
        longTermQueue: <EventNode>[
          _node('l1', EventTier.longTerm),
          _node('l2', EventTier.longTerm),
        ],
      );

      final decision = policy.evaluate(
        graph: graph,
        shortTermThreshold: 2,
        longTermThreshold: 2,
      );

      expect(decision.sourceTier, EventTier.shortTerm);
      expect(
        decision.pendingEvents.map((event) => event.description),
        <String>['s1', 's2'],
      );
    });

    test('短期未达到阈值时允许长期进入超长期级联', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('s1', EventTier.shortTerm),
        ],
        longTermQueue: <EventNode>[
          _node('l1', EventTier.longTerm),
          _node('l2', EventTier.longTerm),
        ],
      );

      final decision = policy.evaluate(
        graph: graph,
        shortTermThreshold: 2,
        longTermThreshold: 2,
      );

      expect(decision.sourceTier, EventTier.longTerm);
      expect(
        decision.pendingEvents.map((event) => event.description),
        <String>['l1', 'l2'],
      );
    });

    test('已概括节点不计入阈值或待概括事件', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('s1', EventTier.shortTerm),
          _node('s2', EventTier.shortTerm, summarized: true),
          _node('s3', EventTier.shortTerm),
        ],
      );

      final decision = policy.evaluate(
        graph: graph,
        shortTermThreshold: 2,
        longTermThreshold: 2,
      );

      expect(
        decision.pendingEvents.map((event) => event.description),
        <String>['s1', 's3'],
      );
    });
  });
}

EventNode _node(
  String id,
  EventTier tier, {
  bool summarized = false,
}) {
  return EventNode(
    id: id,
    tier: tier,
    event: EventMemory(description: id),
    createdAtMs: id.hashCode.abs(),
    summarized: summarized,
  );
}
