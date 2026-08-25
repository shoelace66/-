import 'package:flutter_chat_demo/features/chat/data/datasources/sqlite_chat_persistence.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/message.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/chat_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late SqliteChatPersistence persistence;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    persistence = SqliteChatPersistence(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await persistence.initialize();
  });

  tearDown(() => persistence.close());

  test('完整往返联系人、消息、三级事件、边和关系队列', () async {
    final contact = _contact('role-1');
    final messages = <Message>[
      _message('m1', MessageRole.user, '你好', 1),
      _message('m2', MessageRole.assistant, '晚上好', 2),
    ];

    await persistence.replaceSnapshot(ChatSnapshot(
      contacts: <Contact>[contact],
      messagesByContact: <String, List<Message>>{'role-1': messages},
    ));
    final restored = await persistence.readSnapshot();

    expect(restored.contacts, hasLength(1));
    final restoredContact = restored.contacts.single;
    expect(restoredContact.name, '角色-role-1');
    expect(restoredContact.eventGraph.shortTermQueue.single.id, 'short-1');
    expect(restoredContact.eventGraph.longTermQueue.single.summarized, isTrue);
    expect(restoredContact.eventGraph.ultraLongTermQueue.single.id, 'ultra-1');
    expect(restoredContact.eventGraph.edges.keys, <String>['short-1->long-1']);
    expect(
      restoredContact.eventGraph.belongingEventQueues,
      <String, List<String>>{
        '花伞': <String>['short-1']
      },
    );
    expect(
      restoredContact.eventGraph.settingEventQueues,
      <String, List<String>>{
        '车站': <String>['long-1']
      },
    );
    expect(restoredContact.eventGraph.turnCount, 9);
    expect(
      restored.messagesByContact['role-1']?.map((message) => message.id),
      <String>['m1', 'm2'],
    );
  });

  test('会话保存失败时联系人、事件图和消息整体回滚', () async {
    final original = _contact('role-1');
    await persistence.replaceSnapshot(ChatSnapshot(
      contacts: <Contact>[original],
      messagesByContact: <String, List<Message>>{
        'role-1': <Message>[_message('original', MessageRole.user, '原消息', 1)],
      },
    ));
    final changed = Contact(
      id: original.id,
      name: '不应提交的新名称',
      avatar: '',
      createdAt: original.createdAt,
    );
    final duplicate = _message('duplicate', MessageRole.user, '重复', 2);

    await expectLater(
      persistence.saveConversation(
        contact: changed,
        messages: <Message>[duplicate, duplicate],
      ),
      throwsA(isA<ChatStorageException>()),
    );
    final restored = await persistence.readSnapshot();

    expect(restored.contacts.single.name, original.name);
    expect(restored.contacts.single.eventGraph.turnCount, 9);
    expect(restored.messagesByContact['role-1']?.single.id, 'original');
  });

  test('删除联系人时级联删除消息和事件数据', () async {
    await persistence.replaceSnapshot(ChatSnapshot(
      contacts: <Contact>[_contact('role-1')],
      messagesByContact: <String, List<Message>>{
        'role-1': <Message>[_message('m1', MessageRole.user, '消息', 1)],
      },
    ));

    await persistence.deleteConversation('role-1');
    final restored = await persistence.readSnapshot();

    expect(restored.isEmpty, isTrue);
  });

  test('消息使用稳定 sequence 游标向前分页且不重不漏', () async {
    final messages = List<Message>.generate(
      250,
      (index) => _message(
        'm$index',
        index.isEven ? MessageRole.user : MessageRole.assistant,
        '消息-$index',
        index,
      ),
    );
    await persistence.replaceSnapshot(ChatSnapshot(
      contacts: <Contact>[_contact('role-1')],
      messagesByContact: <String, List<Message>>{'role-1': messages},
    ));

    final newest = await persistence.readMessagesPage(
      contactId: 'role-1',
      limit: 100,
    );
    final middle = await persistence.readMessagesPage(
      contactId: 'role-1',
      beforeSequence: newest.startSequence,
      limit: 100,
    );
    final oldest = await persistence.readMessagesPage(
      contactId: 'role-1',
      beforeSequence: middle.startSequence,
      limit: 100,
    );

    expect(newest.startSequence, 150);
    expect(newest.totalCount, 250);
    expect(newest.hasOlder, isTrue);
    expect(newest.messages.first.id, 'm150');
    expect(newest.messages.last.id, 'm249');
    expect(middle.startSequence, 50);
    expect(middle.messages.first.id, 'm50');
    expect(middle.messages.last.id, 'm149');
    expect(oldest.startSequence, 0);
    expect(oldest.hasOlder, isFalse);
    expect(oldest.messages.first.id, 'm0');
    expect(oldest.messages.last.id, 'm49');

    final ids = <String>[
      ...oldest.messages.map((message) => message.id),
      ...middle.messages.map((message) => message.id),
      ...newest.messages.map((message) => message.id),
    ];
    expect(ids, <String>[for (var index = 0; index < 250; index++) 'm$index']);
  });

  test('保存已加载尾部时保留未加载的早期消息', () async {
    final original = <Message>[
      for (var index = 0; index < 10; index++)
        _message('m$index', MessageRole.user, '原消息-$index', index),
    ];
    final contact = _contact('role-1');
    await persistence.replaceSnapshot(ChatSnapshot(
      contacts: <Contact>[contact],
      messagesByContact: <String, List<Message>>{'role-1': original},
    ));
    final tail = await persistence.readMessagesPage(
      contactId: 'role-1',
      limit: 4,
    );

    await persistence.saveConversationTail(
      contact: contact,
      startSequence: tail.startSequence,
      messages: <Message>[
        _message('m6', MessageRole.user, '已修改-6', 6),
        ...tail.messages.skip(1),
        _message('m10', MessageRole.assistant, '新增-10', 10),
      ],
    );
    final restored = await persistence.readSnapshot();
    final messages = restored.messagesByContact['role-1']!;

    expect(messages, hasLength(11));
    expect(messages.take(6).map((message) => message.id),
        <String>['m0', 'm1', 'm2', 'm3', 'm4', 'm5']);
    expect(messages[6].content, '已修改-6');
    expect(messages.last.id, 'm10');
  });

  test(
    '万级历史只读取请求的最新窗口',
    () async {
      final messages = List<Message>.generate(
        10000,
        (index) => _message(
          'm$index',
          index.isEven ? MessageRole.user : MessageRole.assistant,
          '消息-$index',
          index,
        ),
      );
      await persistence.replaceSnapshot(ChatSnapshot(
        contacts: <Contact>[_contact('role-1')],
        messagesByContact: <String, List<Message>>{'role-1': messages},
      ));

      final page = await persistence.readMessagesPage(
        contactId: 'role-1',
        limit: 100,
      );

      expect(page.messages, hasLength(100));
      expect(page.totalCount, 10000);
      expect(page.startSequence, 9900);
      expect(page.messages.first.id, 'm9900');
      expect(page.messages.last.id, 'm9999');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('检查点创建分支并原子切换消息与联系人状态', () async {
    final original = _contact('role-1');
    final firstMessages = <Message>[
      _message('m1', MessageRole.user, '第一轮', 1),
      _message('m2', MessageRole.assistant, '第一轮回复', 2),
    ];
    await persistence.replaceSnapshot(ChatSnapshot(
      contacts: <Contact>[original],
      messagesByContact: <String, List<Message>>{'role-1': firstMessages},
    ));

    final mainBranch = (await persistence.listBranches('role-1')).single;
    final checkpoint = await persistence.createCheckpoint(
      contact: original,
      sourceMessageId: 'm2',
      label: '第一轮结束',
      isKey: true,
    );
    final changed = Contact(
      id: original.id,
      name: '主分支新状态',
      avatar: '',
      eventGraph: const EventGraphMemory(turnCount: 2),
      createdAt: original.createdAt,
    );
    await persistence.saveConversation(
      contact: changed,
      messages: <Message>[
        ...firstMessages,
        _message('m3', MessageRole.user, '第二轮', 3),
      ],
    );
    final fork = await persistence.createBranchFromCheckpoint(
      checkpointId: checkpoint.id,
      name: '从第一轮改写',
    );

    final forkSnapshot = await persistence.switchBranch(
      contactId: 'role-1',
      branchId: fork.id,
    );
    expect(forkSnapshot.messages.map((message) => message.id),
        <String>['m1', 'm2']);
    expect(forkSnapshot.contact.name, original.name);
    expect((await persistence.readSnapshot()).messagesByContact['role-1'],
        hasLength(2));

    final mainSnapshot = await persistence.switchBranch(
      contactId: 'role-1',
      branchId: mainBranch.id,
    );
    expect(mainSnapshot.messages.map((message) => message.id),
        <String>['m1', 'm2', 'm3']);
    expect(mainSnapshot.contact.name, '主分支新状态');
    expect((await persistence.listCheckpoints('role-1')).single.isKey, isTrue);
  });

  test('主分支和活动分支受删除保护，非活动分支可重命名删除', () async {
    final contact = _contact('role-1');
    await persistence.replaceSnapshot(ChatSnapshot(
      contacts: <Contact>[contact],
      messagesByContact: <String, List<Message>>{
        'role-1': <Message>[_message('m1', MessageRole.user, '一轮', 1)],
      },
    ));
    final main = (await persistence.listBranches('role-1')).single;
    final checkpoint = await persistence.createCheckpoint(
      contact: contact,
      sourceMessageId: 'm1',
    );
    final fork = await persistence.createBranchFromCheckpoint(
      checkpointId: checkpoint.id,
      name: '临时分支',
    );

    await expectLater(persistence.deleteBranch(main.id),
        throwsA(isA<ChatStorageException>()));
    await persistence.renameBranch(fork.id, '已重命名');
    expect((await persistence.listBranches('role-1')).last.name, '已重命名');
    await persistence.deleteBranch(fork.id);
    expect(await persistence.listBranches('role-1'), hasLength(1));
  });

  test('时间线归档完整往返分支和检查点快照', () async {
    final contact = _contact('role-1');
    await persistence.replaceSnapshot(ChatSnapshot(
      contacts: <Contact>[contact],
      messagesByContact: <String, List<Message>>{
        'role-1': <Message>[_message('m1', MessageRole.user, '一轮', 1)],
      },
    ));
    final checkpoint = await persistence.createCheckpoint(
      contact: contact,
      sourceMessageId: 'm1',
      label: '关键节点',
      isKey: true,
    );
    await persistence.createBranchFromCheckpoint(
      checkpointId: checkpoint.id,
      name: '归档分支',
    );
    final archive = await persistence.readTimelineArchive();

    await persistence.replaceSnapshot(ChatSnapshot(
      contacts: <Contact>[contact],
      messagesByContact: const <String, List<Message>>{'role-1': <Message>[]},
    ));
    await persistence.replaceTimelineArchive(archive);
    final restored = await persistence.readTimelineArchive();

    expect(restored.branches, hasLength(2));
    expect(restored.checkpoints.single.checkpoint.label, '关键节点');
    expect(restored.checkpoints.single.messages.single.id, 'm1');
  });

  test('完整历史搜索返回命中消息并可读取上下文窗口', () async {
    final messages = List<Message>.generate(
      12,
      (index) => _message(
        'm$index',
        index.isEven ? MessageRole.user : MessageRole.assistant,
        index == 7 ? '雨夜车站的蓝色车票' : '普通消息 $index',
        index,
      ),
    );
    await persistence.replaceSnapshot(
      ChatSnapshot(
        contacts: <Contact>[_contact('role-1')],
        messagesByContact: <String, List<Message>>{'role-1': messages},
      ),
    );

    final hits = await persistence.searchMessages(
      contactId: 'role-1',
      query: '蓝色车票',
    );
    expect(hits.single.message.id, 'm7');
    expect(hits.single.sequence, 7);

    final context = await persistence.readMessageContext(
      contactId: 'role-1',
      sequence: hits.single.sequence,
      radius: 2,
    );
    expect(
        context.map((message) => message.id), ['m5', 'm6', 'm7', 'm8', 'm9']);
  });
}

Contact _contact(String id) {
  return Contact(
    id: id,
    name: '角色-$id',
    avatar: '',
    worldKnowledge: WorldKnowledgeBucket(const <String>['雨城']),
    eventGraph: EventGraphMemory(
      shortTermQueue: <EventNode>[
        _node('short-1', EventTier.shortTerm, 30),
      ],
      longTermQueue: <EventNode>[
        _node('long-1', EventTier.longTerm, 20, summarized: true),
      ],
      ultraLongTermQueue: <EventNode>[
        _node('ultra-1', EventTier.ultraLongTerm, 10),
      ],
      belongingEventQueues: const <String, List<String>>{
        '花伞': <String>['short-1'],
      },
      settingEventQueues: const <String, List<String>>{
        '车站': <String>['long-1'],
      },
      edges: const <String, EventEdge>{
        'short-1->long-1': EventEdge(
          fromNodeId: 'short-1',
          toNodeId: 'long-1',
        ),
      },
      turnCount: 9,
    ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
  );
}

EventNode _node(
  String id,
  EventTier tier,
  int createdAtMs, {
  bool summarized = false,
}) {
  return EventNode(
    id: id,
    tier: tier,
    event: EventMemory(description: '事件-$id', keywords: <String>[id]),
    createdAtMs: createdAtMs,
    summarized: summarized,
  );
}

Message _message(
  String id,
  MessageRole role,
  String content,
  int createdAtMs,
) {
  return Message(
    id: id,
    role: role,
    content: content,
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
  );
}
