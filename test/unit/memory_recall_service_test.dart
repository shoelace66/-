import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/memory_recall_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = MemoryRecallService();

  group('MemoryRecallService.recall', () {
    test('按关键词命中数排序，相同时优先较新的事件', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('new', 30, keywords: <String>['雨']),
          _node('many', 10, keywords: <String>['雨', '车站']),
          _node('old', 5, keywords: <String>['雨']),
        ],
      );

      final result = service.recall(graph, <String>['雨', '车站']);

      expect(
        result.map((event) => event.description),
        <String>['many', 'new', 'old'],
      );
    });

    test('BFS 深度严格控制关联事件范围', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('a', 30, keywords: <String>['钥匙']),
          _node('b', 20),
          _node('c', 10),
        ],
        edges: <String, EventEdge>{
          'a->b': const EventEdge(fromNodeId: 'a', toNodeId: 'b'),
          'b->c': const EventEdge(fromNodeId: 'b', toNodeId: 'c'),
        },
      );

      final depthOne =
          service.recall(graph, <String>['钥匙'], depth: 1, maxResults: 10);
      final depthTwo =
          service.recall(graph, <String>['钥匙'], depth: 2, maxResults: 10);

      expect(
        depthOne.map((event) => event.description),
        <String>['a', 'b'],
      );
      expect(
        depthTwo.map((event) => event.description),
        <String>['a', 'b', 'c'],
      );
    });

    test('物品和设定队列可以补充没有直接关键词的事件', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('belonging-event', 20),
          _node('setting-event', 10),
        ],
        belongingEventQueues: const <String, List<String>>{
          '银钥匙': <String>['belonging-event'],
        },
        settingEventQueues: const <String, List<String>>{
          '旧车站': <String>['setting-event'],
        },
      );

      final belonging = service.recall(graph, <String>['钥匙']);
      final setting = service.recall(graph, <String>['车站']);

      expect(belonging.single.description, 'belonging-event');
      expect(setting.single.description, 'setting-event');
    });

    test('maxResults 可以大于旧实现固定的 5 条上限', () {
      final nodes = List<EventNode>.generate(
        7,
        (index) => _node(
          'event-$index',
          100 - index,
          keywords: <String>['共同词'],
        ),
      );

      final result = service.recall(
        EventGraphMemory(shortTermQueue: nodes),
        <String>['共同词'],
        maxResults: 6,
      );

      expect(result, hasLength(6));
    });

    test('作废事件不会参与关键词或关系召回', () {
      const graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          EventNode(
            id: 'invalid',
            tier: EventTier.shortTerm,
            event: EventMemory(
              description: '错误记忆',
              keywords: <String>['钥匙'],
            ),
            createdAtMs: 1,
            invalidated: true,
          ),
        ],
      );

      expect(service.recall(graph, <String>['钥匙']), isEmpty);
    });
  });

  group('MemoryRecallService.pruneDanglingRelations', () {
    test('保留有效跨轮关系并删除悬空关系和重复队列项', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('a', 20),
          _node('b', 10),
        ],
        belongingEventQueues: const <String, List<String>>{
          '钥匙': <String>['missing', 'a', 'a'],
          '空队列': <String>['missing'],
        },
        settingEventQueues: const <String, List<String>>{
          '车站': <String>['b', 'missing'],
        },
        edges: <String, EventEdge>{
          'a->b': const EventEdge(fromNodeId: 'a', toNodeId: 'b'),
          'a->missing': const EventEdge(fromNodeId: 'a', toNodeId: 'missing'),
        },
      );

      final result = service.pruneDanglingRelations(graph);

      expect(result.edges.keys, <String>['a->b']);
      expect(result.belongingEventQueues, <String, List<String>>{
        '钥匙': <String>['a'],
      });
      expect(result.settingEventQueues, <String, List<String>>{
        '车站': <String>['b'],
      });
    });
  });

  group('MemoryRecallService.applyRelatedEdges', () {
    test('使用请求前冻结的 Prompt 编号映射，不受新事件插队影响', () {
      final graphAfterReply = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('current', 40),
          _node('old-a', 30),
          _node('old-b', 20),
        ],
      );

      final result = service.applyRelatedEdges(
        graph: graphAfterReply,
        currentEventNodeId: 'current',
        promptNodeIds: const <String>['old-a', 'old-b'],
        relatedEventIds: const <dynamic>[0],
      );

      expect(result.edges.keys, <String>['current->old-a']);
    });

    test('忽略越界、当前节点和已淘汰节点，并限制每轮边数量', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('current', 40),
          _node('a', 30),
          _node('b', 20),
          _node('c', 10),
        ],
      );

      final result = service.applyRelatedEdges(
        graph: graph,
        currentEventNodeId: 'current',
        promptNodeIds: const <String>[
          'current',
          'missing',
          'a',
          'b',
          'c',
        ],
        relatedEventIds: const <dynamic>[-1, 0, 1, 2, '3', 4, 99],
        maxEdges: 2,
      );

      expect(
        result.edges.keys,
        <String>['current->a', 'current->b'],
      );
    });

    test('重复关系不会覆盖或重复计数', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('current', 30),
          _node('a', 20),
          _node('b', 10),
        ],
        edges: const <String, EventEdge>{
          'current->a': EventEdge(fromNodeId: 'current', toNodeId: 'a'),
        },
      );

      final result = service.applyRelatedEdges(
        graph: graph,
        currentEventNodeId: 'current',
        promptNodeIds: const <String>['a', 'b'],
        relatedEventIds: const <dynamic>[0, 1],
        maxEdges: 1,
      );

      expect(result.edges.keys, <String>['current->a', 'current->b']);
    });
  });
}

EventNode _node(
  String id,
  int createdAtMs, {
  List<String> keywords = const <String>[],
  List<String> theme = const <String>[],
}) {
  return EventNode(
    id: id,
    tier: EventTier.shortTerm,
    event: EventMemory(
      description: id,
      keywords: keywords,
      theme: theme,
    ),
    createdAtMs: createdAtMs,
  );
}
