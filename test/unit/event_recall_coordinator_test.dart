import 'dart:async';
import 'dart:convert';

import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/event_recall_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EventRecallCoordinator', () {
    test('明确结构化词项在 L0 完成且不调用模型', () async {
      var calls = 0;
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: <EventNode>[
            _node('key', 10, keywords: const <String>['银钥匙']),
          ],
        ),
        currentInput: '她把银钥匙交给了我',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          requestBudget.tryConsumePost();
          return '{}';
        },
      );

      expect(calls, 0);
      expect(result.phase, RecallPhase.local);
      expect(result.postCount, 0);
      expect(result.nodes.map((node) => node.id), <String>['key']);
      expect(result.activeTerms, <String>['银钥匙']);
    });

    test('无当前命中且无结构化连续性时保持 0 次调用', () async {
      var calls = 0;
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: <EventNode>[
            _node('old', 10, keywords: const <String>['林夏']),
          ],
        ),
        currentInput: '今天天气不错',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          requestBudget.tryConsumePost();
          return '{}';
        },
      );

      expect(calls, 0);
      expect(result.nodes, isEmpty);
      expect(result.phase, RecallPhase.local);
    });

    test('混合强证据与 theme-only 候选不能在 L0 自动确认', () async {
      var calls = 0;
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: <EventNode>[
            _node('keyword', 20, keywords: const <String>['林夏']),
            _node('theme', 10, theme: const <String>['遗憾']),
          ],
        ),
        currentInput: '林夏的遗憾',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          requestBudget.tryConsumePost();
          return '{"v":1,"action":"skip","k":[],"t":[],"r":[],'
              '"recency":"any","confidence":"high"}';
        },
      );

      expect(calls, 1);
      expect(result.postCount, 1);
      expect(result.nodes, isEmpty);
      expect(result.phase, RecallPhase.plan);
      expect(result.activeTerms, containsAll(<String>['林夏', '遗憾']));
    });

    test('没有冷记忆时仍保留 L0 词项供 LRU 和关系更新', () async {
      var calls = 0;
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          shortTermQueue: <EventNode>[
            _node('hot', 10, keywords: const <String>['银钥匙']),
          ],
        ),
        currentInput: '银钥匙',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{'hot'},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          return '{}';
        },
      );

      expect(calls, 0);
      expect(result.nodes, isEmpty);
      expect(result.activeTerms, <String>['银钥匙']);
    });

    test('近期结构化锚点触发 PLAN，并在候选明确时只调用一次', () async {
      var calls = 0;
      LlmProfile? seenProfile;
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: <EventNode>[
            _node('linxia', 10, keywords: const <String>['林夏']),
          ],
        ),
        currentInput: '她后来怎么样了？',
        recentMessages: const <RecallDialogueMessage>[
          RecallDialogueMessage(role: 'assistant', content: '林夏转身离开了车站。'),
        ],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: _profile('cheap'),
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          seenProfile = profile;
          expect(requestBudget.tryConsumePost(), isTrue);
          final alias = _catalogAlias(prompt, 'k', '林夏');
          return jsonEncode(<String, dynamic>{
            'v': 1,
            'action': 'search',
            'k': <String>[alias],
            't': <String>[],
            'r': <String>[],
            'recency': 'any',
            'confidence': 'high',
          });
        },
      );

      expect(calls, 1);
      expect(result.postCount, 1);
      expect(result.phase, RecallPhase.plan);
      expect(result.nodes.single.id, 'linxia');
      expect(seenProfile?.model, 'cheap');
      expect(seenProfile?.parameters.temperature, 0);
      expect(seenProfile?.parameters.maxTokens, 128);
      expect(seenProfile?.parameters.timeoutSeconds, 12);
      expect(seenProfile?.parameters.stream, isFalse);
    });

    test('近期热记忆锚点经图边关联冷记忆时触发 PLAN', () async {
      var calls = 0;
      const graph = EventGraphMemory(
        shortTermQueue: <EventNode>[
          EventNode(
            id: 'hot',
            tier: EventTier.shortTerm,
            event: EventMemory(description: '热事件', keywords: <String>['林夏']),
            createdAtMs: 20,
          ),
          EventNode(
            id: 'cold',
            tier: EventTier.shortTerm,
            event: EventMemory(description: '相邻冷事件'),
            createdAtMs: 10,
          ),
        ],
        edges: <String, EventEdge>{
          'hot-cold': EventEdge(fromNodeId: 'hot', toNodeId: 'cold'),
        },
      );
      final result = await EventRecallCoordinator().recall(
        graph: graph,
        currentInput: '她后来怎么样了？',
        recentMessages: const <RecallDialogueMessage>[
          RecallDialogueMessage(role: 'assistant', content: '林夏转身离开。'),
        ],
        hotNodeIds: const <String>{'hot'},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          requestBudget.tryConsumePost();
          final alias = _catalogAlias(prompt, 'k', '林夏');
          return jsonEncode(<String, dynamic>{
            'v': 1,
            'action': 'search',
            'k': <String>[alias],
            't': <String>[],
            'r': <String>[],
            'recency': 'any',
            'confidence': 'high',
          });
        },
      );

      expect(calls, 1);
      expect(result.nodes.map((node) => node.id), <String>['cold']);
      expect(result.phase, RecallPhase.plan);
    });

    test('候选边界模糊时 PLAN 后进入 JUDGE，总共两次调用', () async {
      var calls = 0;
      final graph = EventGraphMemory(
        longTermQueue: List<EventNode>.generate(
          6,
          (index) => _node(
            'event-$index',
            index,
            keywords: const <String>['钥匙'],
          ),
        ),
      );
      final result = await EventRecallCoordinator().recall(
        graph: graph,
        currentInput: '钥匙的事情',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          expect(requestBudget.tryConsumePost(), isTrue);
          if (prompt.startsWith('event-recall-plan-v1')) {
            final alias = _catalogAlias(prompt, 'k', '钥匙');
            return jsonEncode(<String, dynamic>{
              'v': 1,
              'action': 'search',
              'k': <String>[alias],
              't': <String>[],
              'r': <String>[],
              'recency': 'any',
              'confidence': 'medium',
            });
          }
          expect(prompt.startsWith('event-recall-judge-v1'), isTrue);
          expect(profile.parameters.maxTokens, 96);
          expect(prompt.runes.length, lessThanOrEqualTo(4800));
          final payload =
              jsonDecode(prompt.substring(prompt.indexOf('DATA=') + 5))
                  as Map<String, dynamic>;
          final cards = (payload['candidates'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(cards, hasLength(6));
          expect(
            cards.first.keys.toSet(),
            <String>{
              'id',
              'description',
              'keywords',
              'themes',
              'relations',
              'tier',
              'writeOrder',
              'status',
              'graphDistance',
            },
          );
          return '{"v":1,"selected":["E1"],"confidence":"high"}';
        },
      );

      expect(calls, 2);
      expect(result.postCount, 2);
      expect(result.phase, RecallPhase.judge);
      expect(result.nodes, hasLength(1));
      expect(result.nodes.single.id, 'event-4');
    });

    test('PLAN 已消耗两次 POST 时不再调用 JUDGE', () async {
      var calls = 0;
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: List<EventNode>.generate(
            6,
            (index) => _node(
              'event-$index',
              index,
              keywords: const <String>['钥匙'],
            ),
          ),
        ),
        currentInput: '钥匙',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          expect(requestBudget.tryConsumePost(), isTrue);
          expect(requestBudget.tryConsumePost(), isTrue);
          final alias = _catalogAlias(prompt, 'k', '钥匙');
          return jsonEncode(<String, dynamic>{
            'v': 1,
            'action': 'search',
            'k': <String>[alias],
            't': <String>[],
            'r': <String>[],
            'recency': 'any',
            'confidence': 'medium',
          });
        },
      );

      expect(calls, 1);
      expect(result.postCount, 2);
      expect(result.phase, RecallPhase.judgeFallback);
      expect(result.nodes, hasLength(5));
    });

    test('PLAN 无效时不重试并退化到原始 L0', () async {
      var calls = 0;
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: List<EventNode>.generate(
            6,
            (index) => _node(
              'event-$index',
              index,
              keywords: const <String>['车站'],
            ),
          ),
        ),
        currentInput: '车站',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          requestBudget.tryConsumePost();
          return '```json\n'
              '{"v":1,"action":"search","k":[],"t":[],"r":[],'
              '"recency":"any","confidence":"high"}\n```';
        },
      );

      expect(calls, 1);
      expect(result.postCount, 1);
      expect(result.phase, RecallPhase.planFallback);
      expect(result.nodes, hasLength(5));
    });

    test('目录外 ID 被丢弃且不会触发 JUDGE', () async {
      var calls = 0;
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: <EventNode>[
            _node('old', 10, keywords: const <String>['林夏']),
          ],
        ),
        currentInput: '她呢',
        recentMessages: const <RecallDialogueMessage>[
          RecallDialogueMessage(role: 'assistant', content: '林夏离开了。'),
        ],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          requestBudget.tryConsumePost();
          return '{"v":1,"action":"search","k":["K999"],'
              '"t":[],"r":[],"recency":"any","confidence":"low"}';
        },
      );

      expect(calls, 1);
      expect(result.nodes, isEmpty);
      expect(result.phase, RecallPhase.plan);
    });

    test('预先取消不会启动 PLAN 请求', () async {
      final cancelled = Completer<void>()..complete();
      var calls = 0;

      await expectLater(
        EventRecallCoordinator().recall(
          graph: EventGraphMemory(
            longTermQueue: List<EventNode>.generate(
              6,
              (index) => _node(
                'event-$index',
                index,
                keywords: const <String>['车站'],
              ),
            ),
          ),
          currentInput: '车站',
          recentMessages: const <RecallDialogueMessage>[],
          hotNodeIds: const <String>{},
          mainProfile: _profile('main'),
          memoryRecallProfile: null,
          cancellation: cancelled.future,
          invokeModel: ({
            required prompt,
            required profile,
            required requestBudget,
          }) async {
            calls++;
            requestBudget.tryConsumePost();
            return '{}';
          },
        ),
        throwsA(isA<EventRecallCancelled>()),
      );
      expect(calls, 0);
    });

    test('取消后阻止在途 PLAN 继续兼容端点 POST', () async {
      final cancelled = Completer<void>();
      var posts = 0;
      final recall = EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: List<EventNode>.generate(
            6,
            (index) => _node(
              'event-$index',
              index,
              keywords: const <String>['车站'],
            ),
          ),
        ),
        currentInput: '车站',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        cancellation: cancelled.future,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          if (requestBudget.tryConsumePost()) posts++;
          cancelled.complete();
          await Future<void>.delayed(Duration.zero);
          if (requestBudget.tryConsumePost()) posts++;
          return '{}';
        },
      );

      await expectLater(recall, throwsA(isA<EventRecallCancelled>()));
      await Future<void>.delayed(Duration.zero);
      expect(posts, 1);
    });

    test('PLAN 输入严格限制为 3200 字符、当前 600 字和最近 4 条', () async {
      final graph = EventGraphMemory(
        longTermQueue: List<EventNode>.generate(
          180,
          (index) => _node(
            'event-$index',
            index,
            keywords: <String>['实体${index.toString().padLeft(3, '0')}'],
            theme: const <String>['悬疑'],
          ),
        ),
      );
      final result = await EventRecallCoordinator().recall(
        graph: graph,
        currentInput: '悬疑${List<String>.filled(900, '长').join()}',
        recentMessages: List<RecallDialogueMessage>.generate(
          7,
          (index) => RecallDialogueMessage(
            role: index.isEven ? 'user' : 'assistant',
            content: '消息$index${List<String>.filled(300, '文').join()}',
          ),
        ),
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          requestBudget.tryConsumePost();
          expect(prompt.runes.length, lessThanOrEqualTo(3200));
          final payload =
              jsonDecode(prompt.substring(prompt.indexOf('DATA=') + 5))
                  as Map<String, dynamic>;
          expect((payload['current'] as String).runes.length, 600);
          final history = (payload['history'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(history.length, lessThanOrEqualTo(4));
          expect(
            history.every(
              (message) => (message['content'] as String).runes.length <= 160,
            ),
            isTrue,
          );
          return '{"v":1,"action":"skip","k":[],"t":[],"r":[],'
              '"recency":"any","confidence":"high"}';
        },
      );

      expect(result.postCount, 1);
      expect(result.phase, RecallPhase.plan);
    });

    test('JSON 转义膨胀后 PLAN 总输入仍不超过 3200 字符', () async {
      final controlHeavyInput =
          '悬疑${List<String>.filled(700, '\u0001x').join()}';
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: List<EventNode>.generate(
            6,
            (index) => _node(
              'event-$index',
              index,
              theme: const <String>['悬疑'],
            ),
          ),
        ),
        currentInput: controlHeavyInput,
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          requestBudget.tryConsumePost();
          expect(prompt.runes.length, lessThanOrEqualTo(3200));
          return '{"v":1,"action":"skip","k":[],"t":[],"r":[],'
              '"recency":"any","confidence":"high"}';
        },
      );

      expect(result.postCount, 1);
    });

    test('PLAN 超长选择数组视为无效并退化到原始 L0', () async {
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: List<EventNode>.generate(
            6,
            (index) => _node(
              'event-$index',
              index,
              keywords: const <String>['车站'],
            ),
          ),
        ),
        currentInput: '车站',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          requestBudget.tryConsumePost();
          final alias = _catalogAlias(prompt, 'k', '车站');
          return jsonEncode(<String, dynamic>{
            'v': 1,
            'action': 'search',
            'k': List<String>.filled(9, alias),
            't': <String>[],
            'r': <String>[],
            'recency': 'any',
            'confidence': 'high',
          });
        },
      );

      expect(result.postCount, 1);
      expect(result.phase, RecallPhase.planFallback);
      expect(result.nodes, hasLength(5));
    });

    test('JUDGE 超过 5 个选择视为无效并退化到 PLAN 本地前五', () async {
      var calls = 0;
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: List<EventNode>.generate(
            6,
            (index) => _node(
              'event-$index',
              index,
              keywords: const <String>['钥匙'],
            ),
          ),
        ),
        currentInput: '钥匙',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          requestBudget.tryConsumePost();
          if (prompt.startsWith('event-recall-plan-v1')) {
            final alias = _catalogAlias(prompt, 'k', '钥匙');
            return jsonEncode(<String, dynamic>{
              'v': 1,
              'action': 'search',
              'k': <String>[alias],
              't': <String>[],
              'r': <String>[],
              'recency': 'any',
              'confidence': 'medium',
            });
          }
          return '{"v":1,"selected":["E0","E1","E2","E3","E4","E5"],'
              '"confidence":"high"}';
        },
      );

      expect(calls, 2);
      expect(result.postCount, 2);
      expect(result.phase, RecallPhase.judgeFallback);
      expect(result.nodes, hasLength(5));
    });
  });
}

LlmProfile _profile(String model) => LlmProfile(
      apiKey: 'key',
      model: model,
      parameters: const LlmParameters(maxTokens: 2048, timeoutSeconds: 60),
    );

EventNode _node(
  String id,
  int createdAtMs, {
  List<String> keywords = const <String>[],
  List<String> theme = const <String>[],
}) {
  return EventNode(
    id: id,
    tier: EventTier.longTerm,
    event: EventMemory(
      description: '描述 $id',
      keywords: keywords,
      theme: theme,
    ),
    createdAtMs: createdAtMs,
  );
}

String _catalogAlias(String prompt, String bucket, String value) {
  final payload = jsonDecode(prompt.substring(prompt.indexOf('DATA=') + 5))
      as Map<String, dynamic>;
  final catalog = payload['catalog'] as Map<String, dynamic>;
  final entries = catalog[bucket] as List<dynamic>;
  final entry = entries.cast<Map<String, dynamic>>().singleWhere(
        (item) => item['value'] == value,
      );
  return entry['id'] as String;
}
