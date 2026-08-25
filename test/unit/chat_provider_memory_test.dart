import 'package:flutter_chat_demo/features/chat/data/datasources/sqlite_chat_persistence.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/message.dart';
import 'package:flutter_chat_demo/features/chat/domain/providers/chat_provider.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/chat_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late SqliteChatPersistence persistence;
  late ChatProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    persistence = SqliteChatPersistence(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await persistence.initialize();
    await persistence.replaceSnapshot(ChatSnapshot(
      contacts: <Contact>[
        Contact(
          id: 'test-role',
          name: '测试角色',
          avatar: '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
          eventGraph: const EventGraphMemory(
            shortTermQueue: <EventNode>[
              EventNode(
                id: 'e1',
                tier: EventTier.shortTerm,
                event: EventMemory(
                  description: '测试事件',
                  keywords: <String>['测试', '关键词'],
                  theme: <String>['温暖'],
                ),
                createdAtMs: 1000,
              ),
              EventNode(
                id: 'e2',
                tier: EventTier.shortTerm,
                event: EventMemory(description: '关联事件'),
                createdAtMs: 2000,
              ),
            ],
            longTermQueue: <EventNode>[
              EventNode(
                id: 'e3',
                tier: EventTier.longTerm,
                event: EventMemory(description: '阶段概括'),
                createdAtMs: 3000,
              ),
            ],
            edges: <String, EventEdge>{
              'e1->e2': EventEdge(fromNodeId: 'e1', toNodeId: 'e2'),
            },
            belongingEventQueues: <String, List<String>>{
              '花伞': <String>['e1'],
            },
          ),
        ),
      ],
      messagesByContact: <String, List<Message>>{},
    ));
    provider = ChatProvider(persistence: persistence);
    await provider.initialize();
  });

  tearDown(() async {
    provider.dispose();
    await persistence.close();
  });

  group('ChatProvider.memoryStats', () {
    test('正确统计各层级数量', () {
      expect(provider.memoryStats['total'], 3);
      expect(provider.memoryStats['shortTerm'], 2);
      expect(provider.memoryStats['longTerm'], 1);
      expect(provider.memoryStats['ultraLongTerm'], 0);
      expect(provider.memoryStats['edges'], 1);
    });
  });

  group('ChatProvider.memoryRecallDebugInfo', () {
    test('节点不存在时返回空映射', () {
      expect(provider.memoryRecallDebugInfo('nonexistent'), <String, dynamic>{});
    });

    test('返回节点完整调试信息', () {
      final info = provider.memoryRecallDebugInfo('e1');
      expect(info['nodeId'], 'e1');
      expect(info['description'], '测试事件');
      expect(info['tier'], 'shortTerm');
      expect(info['keywords'], <String>['测试', '关键词']);
      expect(info['theme'], <String>['温暖']);
      expect(info['edgeCount'], 1);
      expect(info['edges'].length, 1);
      expect(info['edges'][0]['direction'], 'e1 → e2');
      expect(info['neighbors'].length, 1);
      expect(info['neighbors'][0]['id'], 'e2');
      expect(info['belongingQueues'], <String, List<String>>{
        '花伞': <String>['e1'],
      });
    });
  });

  group('ChatProvider.memorySourceMessageId', () {
    test('无来源对话时返回null', () {
      expect(provider.memorySourceMessageId('e1'), isNull);
    });
  });
}
