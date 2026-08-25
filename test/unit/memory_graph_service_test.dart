import 'package:flutter_chat_demo/core/data/models/app_settings.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/memory_graph_service.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/memory_patch_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = MemoryGraphService();

  test('事件入队使用调用方稳定 ID，并严格执行分层容量', () {
    var graph = const EventGraphMemory();
    const settings = AppSettings(maxShortQueue: 2);
    for (var index = 0; index < 3; index++) {
      graph = service
          .enqueue(
            graph: graph,
            tier: EventTier.shortTerm,
            event: EventMemory(description: 'event-$index'),
            nodeId: 'node-$index',
            createdAtMs: index,
            settings: settings,
          )
          .graph;
    }

    expect(
      graph.shortTermQueue.map((node) => node.id),
      <String>['node-2', 'node-1'],
    );
  });

  test('只标记指定层和指定节点为已概括', () {
    final graph = EventGraphMemory(
      shortTermQueue: <EventNode>[_node('a', 2), _node('b', 1)],
      longTermQueue: <EventNode>[
        _node('long', 3, tier: EventTier.longTerm),
      ],
    );

    final result = service.markSummarized(
      graph: graph,
      tier: EventTier.shortTerm,
      nodeIds: const <String>{'b', 'long'},
    );

    expect(result.shortTermQueue.first.summarized, isFalse);
    expect(result.shortTermQueue.last.summarized, isTrue);
    expect(result.longTermQueue.single.summarized, isFalse);
  });

  test('LRU 保留固定 Prompt 区，并按关键词权重排序其余节点', () {
    final graph = EventGraphMemory(
      shortTermQueue: <EventNode>[
        _node('fixed', 40),
        _node('plain', 30),
        _node('matched', 10, keywords: const <String>['雨']),
      ],
    );
    const settings = AppSettings(maxShortTermEvents: 1);

    final result = service.applyLru(
      graph: graph,
      inputKeywords: const <String>['雨'],
      settings: settings,
    );

    expect(
      result.shortTermQueue.map((node) => node.id),
      <String>['fixed', 'matched', 'plain'],
    );
  });

  test('物品和设定关系使用稳定事件 ID，且队列不重复', () {
    var graph = EventGraphMemory(
      shortTermQueue: <EventNode>[
        _node('current', 20, keywords: const <String>['雨', '车站']),
      ],
    );
    graph = service.updateBelongingRelations(
      graph: graph,
      eventNodeId: 'current',
      changes: const <BelongingChange>[
        BelongingChange(type: BelongingChangeType.mentioned, name: '花伞'),
        BelongingChange(type: BelongingChangeType.mentioned, name: '花伞'),
      ],
      inputKeywords: const <String>['雨'],
    );
    graph = service.updateSettingRelations(
      graph: graph,
      eventNodeId: 'current',
      settings: const <Map<String, dynamic>>[
        <String, dynamic>{
          'key': '旧车站',
          'value': '常年下雨',
          'relate': <String>['车站'],
        },
      ],
      inputKeywords: const <String>['车站'],
    );

    expect(graph.belongingEventQueues['花伞'], <String>['current']);
    expect(graph.settingEventQueues['旧车站'], <String>['current']);
  });

  test('概括节点显式连接所有来源事件，重复调用仍保持边唯一', () {
    var graph = EventGraphMemory(
      shortTermQueue: <EventNode>[_node('a', 2), _node('b', 1)],
      longTermQueue: <EventNode>[
        _node('summary', 3, tier: EventTier.longTerm),
      ],
    );

    graph = service.linkSummarySources(
      graph: graph,
      summaryNodeId: 'summary',
      sourceNodeIds: const <String>['a', 'b', 'a', 'missing'],
    );

    expect(graph.edges.keys, <String>['summary->a', 'summary->b']);
  });
}

EventNode _node(
  String id,
  int createdAtMs, {
  EventTier tier = EventTier.shortTerm,
  List<String> keywords = const <String>[],
}) {
  return EventNode(
    id: id,
    tier: tier,
    event: EventMemory(description: id, keywords: keywords),
    createdAtMs: createdAtMs,
  );
}
