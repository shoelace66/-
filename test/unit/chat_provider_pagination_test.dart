import 'package:flutter_chat_demo/features/chat/data/datasources/sqlite_chat_persistence.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/message.dart';
import 'package:flutter_chat_demo/features/chat/domain/providers/chat_provider.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/chat_persistence.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/chat_backup_codec.dart';
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
    final messages = List<Message>.generate(
      250,
      (index) => Message(
        id: 'm$index',
        role: index.isEven ? MessageRole.user : MessageRole.assistant,
        content: '消息-$index',
        createdAt: DateTime.fromMillisecondsSinceEpoch(index),
      ),
    );
    await persistence.replaceSnapshot(ChatSnapshot(
      contacts: <Contact>[
        Contact(
          id: 'role-1',
          name: '分页角色',
          avatar: '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        ),
      ],
      messagesByContact: <String, List<Message>>{'role-1': messages},
    ));
    provider = ChatProvider(persistence: persistence);
    await provider.initialize();
  });

  tearDown(() async {
    provider.dispose();
    await persistence.close();
  });

  test('初始化只载入最新窗口并可按游标向前加载', () async {
    expect(provider.messages, hasLength(100));
    expect(provider.messages.first.id, 'm150');
    expect(provider.messages.last.id, 'm249');
    expect(provider.totalMessageCount, 250);
    expect(provider.hasOlderMessages, isTrue);

    expect(await provider.loadOlderMessages(), isTrue);
    expect(provider.messages, hasLength(200));
    expect(provider.messages.first.id, 'm50');
    expect(provider.messages.last.id, 'm249');
    expect(provider.hasOlderMessages, isTrue);

    expect(await provider.loadOlderMessages(), isTrue);
    expect(provider.messages, hasLength(250));
    expect(provider.messages.first.id, 'm0');
    expect(provider.messages.last.id, 'm249');
    expect(provider.hasOlderMessages, isFalse);
  });

  test('分页状态下完整备份仍包含未加载历史', () async {
    expect(provider.messages, hasLength(100));

    final encoded = await provider.exportBackupJson();
    final snapshot = const ChatBackupCodec().decode(encoded);

    expect(snapshot.messagesByContact['role-1'], hasLength(250));
    expect(snapshot.messagesByContact['role-1']?.first.id, 'm0');
    expect(snapshot.messagesByContact['role-1']?.last.id, 'm249');
  });

  test('向已分页会话追加消息不会删除未加载历史', () async {
    await provider.appendImageMessage(
      contactId: 'role-1',
      prompt: '雨夜车站',
      imageUrl: 'https://example.invalid/image.png',
    );

    final restored = await persistence.readSnapshot();
    final messages = restored.messagesByContact['role-1']!;
    expect(messages, hasLength(251));
    expect(messages.first.id, 'm0');
    expect(messages[249].id, 'm249');
    expect(messages.last.content, '雨夜车站');
  });
}
