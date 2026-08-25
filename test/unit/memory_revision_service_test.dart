import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/memory_revision_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = MemoryRevisionService();

  test('影响预览列出关联边、物品、设定和上层概括', () {
    final impact = service.preview(_graph(), 'source');

    expect(impact.edgeCount, 1);
    expect(impact.belongingKeys, <String>['花伞']);
    expect(impact.settingKeys, <String>['车站']);
    expect(impact.affectedSummaryNodeIds, <String>['summary']);
  });

  test('修订使旧关系失效并标记上层概括，撤销可完整恢复', () {
    final original = _graph();
    final revised = service.revise(
      graph: original,
      eventNodeId: 'source',
      revisedEvent: const EventMemory(description: '修订后的事件'),
      revisionId: 'revision-1',
    );

    expect(revised.graph.shortTermQueue.single.event.description, '修订后的事件');
    expect(revised.graph.edges, isEmpty);
    expect(revised.graph.belongingEventQueues, isEmpty);
    expect(revised.graph.settingEventQueues, isEmpty);
    expect(revised.graph.longTermQueue.single.needsReview, isTrue);

    final restored = service.undo(revised.graph, revised.record);
    expect(restored.shortTermQueue.single.event.description, '原始事件');
    expect(restored.edges.keys, <String>['summary->source']);
    expect(restored.belongingEventQueues['花伞'], <String>['source']);
    expect(restored.settingEventQueues['车站'], <String>['source']);
    expect(restored.longTermQueue.single.needsReview, isFalse);
  });

  test('作废保留节点与原文供撤销，但节点被标记为 invalidated', () {
    final result = service.revise(
      graph: _graph(),
      eventNodeId: 'source',
      revisedEvent: const EventMemory(),
      revisionId: 'revision-2',
      invalidate: true,
    );

    expect(result.graph.shortTermQueue.single.invalidated, isTrue);
    expect(result.graph.shortTermQueue.single.event.description, '原始事件');
    expect(
      service
          .undo(result.graph, result.record)
          .shortTermQueue
          .single
          .invalidated,
      isFalse,
    );
  });

  test('产生新对话轮次后拒绝覆盖式撤销旧修订', () {
    final result = service.revise(
      graph: _graph(),
      eventNodeId: 'source',
      revisedEvent: const EventMemory(description: '修订'),
      revisionId: 'revision-3',
    );

    expect(
      () => service.undo(
        result.graph.copyWith(turnCount: result.graph.turnCount + 1),
        result.record,
      ),
      throwsStateError,
    );
  });
}

EventGraphMemory _graph() => const EventGraphMemory(
      shortTermQueue: <EventNode>[
        EventNode(
          id: 'source',
          tier: EventTier.shortTerm,
          event: EventMemory(description: '原始事件'),
          createdAtMs: 1,
        ),
      ],
      longTermQueue: <EventNode>[
        EventNode(
          id: 'summary',
          tier: EventTier.longTerm,
          event: EventMemory(description: '阶段概括'),
          createdAtMs: 2,
        ),
      ],
      edges: <String, EventEdge>{
        'summary->source': EventEdge(
          fromNodeId: 'summary',
          toNodeId: 'source',
        ),
      },
      belongingEventQueues: <String, List<String>>{
        '花伞': <String>['source'],
      },
      settingEventQueues: <String, List<String>>{
        '车站': <String>['source'],
      },
      turnCount: 4,
    );
