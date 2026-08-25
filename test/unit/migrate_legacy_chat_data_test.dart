import 'dart:convert';
import 'dart:io';

import 'package:flutter_chat_demo/features/chat/application/migrate_legacy_chat_data.dart';
import 'package:flutter_chat_demo/features/chat/data/datasources/legacy_chat_snapshot_source.dart';
import 'package:flutter_chat_demo/features/chat/data/datasources/sqlite_chat_persistence.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/message.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/chat_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late SqliteChatPersistence target;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    target = SqliteChatPersistence(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await target.initialize();
  });
  tearDown(() => target.close());

  test('无损迁移旧联系人和消息，并写入幂等标记', () async {
    final legacy = _snapshot('legacy');
    final useCase = MigrateLegacyChatData(
      target: target,
      source: _FakeLegacySource(legacy),
    );

    expect(await useCase.execute(), LegacyMigrationOutcome.migrated);
    expect(await useCase.execute(), LegacyMigrationOutcome.alreadyCompleted);
    final restored = await target.readSnapshot();
    expect(restored.contacts.single.id, 'legacy');
    expect(restored.contacts.single.eventGraph.turnCount, 3);
    expect(restored.messagesByContact['legacy']?.single.content, '旧消息');
  });

  test('目标数据库已有数据时绝不被旧数据覆盖', () async {
    await target.replaceSnapshot(_snapshot('current'));
    final useCase = MigrateLegacyChatData(
      target: target,
      source: _FakeLegacySource(_snapshot('legacy')),
    );

    expect(
      await useCase.execute(),
      LegacyMigrationOutcome.targetAlreadyPopulated,
    );
    expect((await target.readSnapshot()).contacts.single.id, 'current');
  });

  test('旧数据含重复消息 ID 时迁移失败且数据库保持为空', () async {
    final message = _message('same');
    final invalid = ChatSnapshot(
      contacts: <Contact>[_contact('legacy')],
      messagesByContact: <String, List<Message>>{
        'legacy': <Message>[message, message],
      },
    );
    final useCase = MigrateLegacyChatData(
      target: target,
      source: _FakeLegacySource(invalid),
    );

    await expectLater(useCase.execute(), throwsFormatException);
    expect((await target.readSnapshot()).isEmpty, isTrue);
  });

  test('固定脱敏旧数据样本可无损迁移', () async {
    final raw = jsonDecode(
      await File('test/legacy_chat_snapshot_v1.json').readAsString(),
    ) as Map<String, dynamic>;
    final contacts = (raw['contacts'] as List)
        .map((value) => Contact.fromJson(
              Map<String, dynamic>.from(value as Map),
            ))
        .toList();
    final messages = <String, List<Message>>{
      for (final entry
          in (raw['messagesByContact'] as Map<String, dynamic>).entries)
        entry.key: (entry.value as List)
            .map((value) => Message.fromJson(
                  Map<String, dynamic>.from(value as Map),
                ))
            .toList(),
    };

    final outcome = await MigrateLegacyChatData(
      target: target,
      source: _FakeLegacySource(
        ChatSnapshot(
          contacts: contacts,
          messagesByContact: messages,
        ),
      ),
    ).execute();
    final restored = await target.readSnapshot();

    expect(outcome, LegacyMigrationOutcome.migrated);
    expect(restored.contacts.single.id, 'fixture-role');
    expect(restored.contacts.single.eventGraph.shortTermQueue.single.id,
        'fixture-event');
    expect(restored.messagesByContact['fixture-role'], hasLength(2));
  });
}

class _FakeLegacySource implements LegacyChatSnapshotSource {
  const _FakeLegacySource(this.snapshot);

  final ChatSnapshot snapshot;

  @override
  Future<ChatSnapshot> readSnapshot() async => snapshot;
}

ChatSnapshot _snapshot(String contactId) => ChatSnapshot(
      contacts: <Contact>[_contact(contactId)],
      messagesByContact: <String, List<Message>>{
        contactId: <Message>[_message('message-$contactId')],
      },
    );

Contact _contact(String id) => Contact(
      id: id,
      name: '角色-$id',
      avatar: '',
      eventGraph: EventGraphMemory(
        shortTermQueue: <EventNode>[
          EventNode(
            id: 'event-$id',
            tier: EventTier.shortTerm,
            event: EventMemory(description: '旧事件-$id'),
            createdAtMs: 1,
          ),
        ],
        turnCount: 3,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    );

Message _message(String id) => Message(
      id: id,
      role: MessageRole.user,
      content: '旧消息',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    );
