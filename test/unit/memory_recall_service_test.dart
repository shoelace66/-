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

    test('物品和设定队列只接受完整关系键，不再做双向包含', () {
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

      final belonging = service.recall(graph, <String>['银钥匙']);
      final setting = service.recall(graph, <String>['旧车站']);

      expect(belonging.single.description, 'belonging-event');
      expect(setting.single.description, 'setting-event');
      expect(service.recall(graph, <String>['钥匙']), isEmpty);
      expect(service.recall(graph, <String>['车站']), isEmpty);
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

  group('MemoryRecallService structured index and matching', () {
    test('保守归一化合并 aliases，并按图对象身份缓存索引', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('a', 10, keywords: <String>['Rain']),
          _node('b', 20, keywords: <String>['ＲＡＩＮ']),
        ],
      );

      final first = service.indexFor(graph);
      final second = service.indexFor(graph);
      final rain = first.keywordTerms.single;

      expect(second, same(first));
      expect(rain.ref.normalizedValue, 'rain');
      expect(rain.aliases, <String>['Rain', 'ＲＡＩＮ']);
      expect(rain.nodeIds, <String>{'a', 'b'});
      expect(rain.postingCount, 2);
      expect(rain.newestCreatedAtMs, 20);
      expect(
        service.indexFor(graph.copyWith()),
        isNot(same(first)),
      );
    });

    test('只匹配完整已知词项，重叠时保留最长项', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('long', 30, keywords: <String>['银钥匙']),
          _node('short', 20, keywords: <String>['钥匙']),
          _node('latin', 10, keywords: <String>['rain']),
        ],
      );

      final matches = service.matchInput(
        service.indexFor(graph),
        '还记得银钥匙和 RAIN 吗？',
      );

      expect(
        matches.map((term) => term.normalizedValue),
        <String>['银钥匙', 'rain'],
      );
      expect(
        service.query(graph, '训练 training').candidates,
        isEmpty,
      );
    });

    test('CJK 单字只在归一化后的整句等于该词时命中', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('lin', 10, keywords: <String>['林']),
        ],
      );

      expect(service.query(graph, '森林').candidates, isEmpty);
      expect(service.query(graph, '去林里').candidates, isEmpty);
      expect(service.query(graph, '  林  ').candidates.single.node.id, 'lin');
    });

    test('Latin 词项要求 ASCII 字母数字边界', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('rain', 10, keywords: <String>['rain']),
        ],
      );

      expect(service.query(graph, 'training').candidates, isEmpty);
      expect(service.query(graph, 'rain2').candidates, isEmpty);
      expect(
          service.query(graph, 'rain-storm').candidates.single.node.id, 'rain');
      expect(service.query(graph, '下rain了').candidates.single.node.id, 'rain');
    });

    test('不扫描 description、sourceDialog 或 knowledgeNodes', () {
      const graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          EventNode(
            id: 'event',
            tier: EventTier.shortTerm,
            event: EventMemory(
              description: '秘密车站',
              sourceDialog: '银钥匙藏在这里',
            ),
            createdAtMs: 10,
          ),
        ],
        knowledgeNodes: <KnowledgeNode>[
          KnowledgeNode(
            id: 'knowledge',
            type: KnowledgeType.world,
            content: '秘密车站 银钥匙',
            createdAtMs: 1,
          ),
        ],
      );

      expect(service.indexFor(graph).catalog, isEmpty);
      expect(service.query(graph, '秘密车站和银钥匙').candidates, isEmpty);
    });
  });

  group('MemoryRecallService deterministic scoring', () {
    test('keyword、relation、theme 按固定权重计分，多类证据加 25', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('mixed', 40,
              keywords: <String>['hero'], theme: <String>['warm']),
          _node('keyword', 30, keywords: <String>['hero']),
          _node('relation', 20),
          _node('theme', 10, theme: <String>['warm']),
        ],
        belongingEventQueues: const <String, List<String>>{
          'umbrella': <String>['relation'],
        },
      );

      final candidates = service.query(graph, 'hero umbrella warm').candidates;
      final scores = <String, int>{
        for (final candidate in candidates) candidate.node.id: candidate.score,
      };

      expect(candidates.map((candidate) => candidate.node.id),
          <String>['mixed', 'keyword', 'relation', 'theme']);
      expect(scores, <String, int>{
        'mixed': 180,
        'keyword': 120,
        'relation': 100,
        'theme': 35,
      });
      expect(candidates.last.themeOnly, isTrue);
      expect(candidates.first.hasStrongDirectEvidence, isTrue);
    });

    test('关键词和主题计分有上限且同分默认较新优先', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node(
            'new',
            20,
            keywords: <String>['k1', 'k2', 'k3', 'k4'],
            theme: <String>['t1', 't2', 't3'],
          ),
          _node(
            'old',
            10,
            keywords: <String>['k1', 'k2', 'k3', 'k4'],
            theme: <String>['t1', 't2', 't3'],
          ),
        ],
      );
      final index = service.indexFor(graph);
      final terms = service.resolveTerms(
        index,
        <String>['k1', 'k2', 'k3', 'k4', 't1', 't2', 't3'],
      );

      final newest = service.search(index, terms, depth: 0);
      final oldest = service.search(
        index,
        terms,
        depth: 0,
        recency: RecallRecency.oldest,
      );

      expect(newest.first.score, 455);
      expect(
          newest.map((candidate) => candidate.node.id), <String>['new', 'old']);
      expect(
          oldest.map((candidate) => candidate.node.id), <String>['old', 'new']);
    });

    test('summarized 扣 10，needsReview 扣 120 且保留状态', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('normal', 30, keywords: <String>['key']),
          _node('summary', 20, keywords: <String>['key'], summarized: true),
          _node('review', 10, keywords: <String>['key'], needsReview: true),
        ],
      );

      final candidates = service.query(graph, 'key').candidates;

      expect(
          candidates.map((candidate) => candidate.score), <int>[120, 110, 0]);
      expect(candidates.last.needsReview, isTrue);
      expect(candidates[1].summarized, isTrue);
    });

    test('直接命中始终排在图扩展前，图最多两跳且环不会重复', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('seed', 50, keywords: <String>['anchor']),
          _node('theme', 40, theme: <String>['warm']),
          _node('one-hop', 30),
          _node('two-hop', 20),
          _node('three-hop', 10),
        ],
        edges: const <String, EventEdge>{
          'seed-one': EventEdge(fromNodeId: 'seed', toNodeId: 'one-hop'),
          'one-two': EventEdge(fromNodeId: 'one-hop', toNodeId: 'two-hop'),
          'two-one-back': EventEdge(
            fromNodeId: 'two-hop',
            toNodeId: 'one-hop',
          ),
          'two-three': EventEdge(fromNodeId: 'two-hop', toNodeId: 'three-hop'),
        },
      );

      final candidates = service.query(graph, 'anchor warm').candidates;

      expect(
        candidates.map((candidate) => candidate.node.id),
        <String>['seed', 'theme', 'one-hop', 'two-hop'],
      );
      expect(candidates.map((candidate) => candidate.graphDistance),
          <int>[0, 0, 1, 2]);
      expect(candidates[2].score, 48);
      expect(candidates[3].score, 21);
    });

    test('多直接种子只取最大图贡献，并在两个种子连接时加 10', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('a', 30, keywords: <String>['anchor']),
          _node('b', 20, keywords: <String>['anchor']),
          _node('shared', 10),
        ],
        edges: const <String, EventEdge>{
          'a-shared': EventEdge(fromNodeId: 'a', toNodeId: 'shared'),
          'b-shared': EventEdge(fromNodeId: 'b', toNodeId: 'shared'),
        },
      );

      final shared = service
          .query(graph, 'anchor')
          .candidates
          .singleWhere((candidate) => candidate.node.id == 'shared');

      expect(shared.score, 58);
      expect(shared.evidence.seedNodeIds, <String>{'a', 'b'});
    });

    test('强种子一跳距离不被更近的 theme 弱种子路径混淆', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('strong', 40, keywords: <String>['hero']),
          _node('weak', 30, theme: <String>['warm']),
          _node('bridge', 20),
          _node('target', 10),
        ],
        belongingEventQueues: const <String, List<String>>{
          'umbrella': <String>['strong'],
        },
        edges: const <String, EventEdge>{
          'strong-bridge': EventEdge(
            fromNodeId: 'strong',
            toNodeId: 'bridge',
          ),
          'bridge-target': EventEdge(
            fromNodeId: 'bridge',
            toNodeId: 'target',
          ),
          'weak-target': EventEdge(fromNodeId: 'weak', toNodeId: 'target'),
        },
      );

      final candidates = service.query(graph, 'hero umbrella warm').candidates;
      final bridge =
          candidates.singleWhere((candidate) => candidate.node.id == 'bridge');
      final target =
          candidates.singleWhere((candidate) => candidate.node.id == 'target');

      expect(bridge.oneHopFromStrongSeed, isTrue);
      expect(target.graphDistance, 1, reason: '最近路径来自 theme 弱种子');
      expect(target.themeOnly, isFalse, reason: '证据也包含二跳强种子');
      expect(target.oneHopFromStrongSeed, isFalse);
    });

    test('排除热节点但仍允许它作为图种子，候选池硬限制为 12', () {
      final graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          _node('hot', 100, keywords: <String>['anchor']),
          ...List<EventNode>.generate(
            14,
            (index) => _node('cold-$index', 90 - index),
          ),
        ],
        edges: <String, EventEdge>{
          for (var index = 0; index < 14; index++)
            'edge-$index': EventEdge(
              fromNodeId: 'hot',
              toNodeId: 'cold-$index',
            ),
        },
      );

      final candidates = service
          .query(
            graph,
            'anchor',
            excludedNodeIds: const <String>{'hot'},
            maxCandidates: 99,
          )
          .candidates;

      expect(candidates, hasLength(12));
      expect(candidates.every((candidate) => !candidate.direct), isTrue);
      expect(candidates.map((candidate) => candidate.node.id),
          isNot(contains('hot')));
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
  bool summarized = false,
  bool invalidated = false,
  bool needsReview = false,
  EventTier tier = EventTier.shortTerm,
}) {
  return EventNode(
    id: id,
    tier: tier,
    event: EventMemory(
      description: id,
      keywords: keywords,
      theme: theme,
    ),
    createdAtMs: createdAtMs,
    summarized: summarized,
    invalidated: invalidated,
    needsReview: needsReview,
  );
}
