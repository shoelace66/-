import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/features/chat/data/datasources/sqlite_chat_persistence.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/repositories/chat_repository.dart';
import 'package:flutter_chat_demo/features/chat/domain/providers/chat_provider.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/chat_persistence.dart';
import 'package:flutter_chat_demo/infrastructure/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late SqliteChatPersistence persistence;
  late _TimelineAiService aiService;
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
          id: 'role-1',
          name: '林夏',
          avatar: '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        ),
      ],
    ));
    aiService = _TimelineAiService();
    provider = ChatProvider(
      persistence: persistence,
      repository: ChatRepository(aiService: aiService),
    );
    await provider.initialize();
    await provider.saveProviderSettings(
      const ProviderSettings(llm: LlmProfile(apiKey: 'test-key')),
    );
  });

  tearDown(() async {
    provider.dispose();
    await persistence.close();
  });

  test('成功轮次自动创建检查点并可从检查点切换分支', () async {
    aiService.replyText = '主分支第一轮';
    await provider.sendMessage('第一轮');

    expect(provider.conversationBranches.single.isMain, isTrue);
    expect(provider.conversationCheckpoints, hasLength(1));
    final firstCheckpoint = provider.conversationCheckpoints.single;

    aiService.replyText = '主分支第二轮';
    await provider.sendMessage('第二轮');
    expect(provider.messages, hasLength(4));

    expect(
      await provider.createBranchFromCheckpoint(
        firstCheckpoint.id,
        name: '改写第二轮',
      ),
      isTrue,
    );
    expect(provider.messages, hasLength(2));
    expect(provider.activeConversationBranch?.name, '改写第二轮');

    aiService.replyText = '分支里的另一种发展';
    await provider.sendMessage('另一种选择');
    expect(provider.messages.last.content, '分支里的另一种发展');

    final main = provider.conversationBranches.singleWhere(
      (branch) => branch.isMain,
    );
    expect(await provider.switchConversationBranch(main.id), isTrue);
    expect(provider.messages, hasLength(4));
    expect(provider.messages.last.content, '主分支第二轮');
  });

  test('失败轮次不会创建检查点', () async {
    aiService.failure = const AiServiceException('模拟失败');

    await provider.sendMessage('失败的一轮');

    expect(provider.conversationCheckpoints, isEmpty);
    expect(provider.messages.single.status.name, 'failed');
  });

  test('完整备份恢复分支、检查点和活动分支', () async {
    aiService.replyText = '第一轮';
    await provider.sendMessage('第一轮');
    final checkpoint = provider.conversationCheckpoints.single;
    expect(
      await provider.createBranchFromCheckpoint(
        checkpoint.id,
        name: '备份中的分支',
      ),
      isTrue,
    );
    final activeId = provider.activeConversationBranch!.id;
    final backup = await provider.exportBackupJson();

    await provider.renameConversationBranch(activeId, '临时改名');
    expect(await provider.restoreBackupJson(backup), isTrue);

    expect(provider.conversationBranches, hasLength(2));
    expect(provider.activeConversationBranch?.id, activeId);
    expect(provider.activeConversationBranch?.name, '备份中的分支');
    expect(provider.conversationCheckpoints, hasLength(1));
  });
}

class _TimelineAiService extends AiService {
  String replyText = '默认回复';
  AiServiceException? failure;

  @override
  Future<String> ask(
    String prompt, {
    String? contactId,
    String? contactName,
    String? systemPrompt,
    LlmProfile? profile,
    RecallRequestBudget? requestBudget,
  }) async {
    if (prompt.contains('提取本轮对话中的关键词')) {
      return '{"keywords":["测试"],"theme":[]}';
    }
    final currentFailure = failure;
    if (currentFailure != null) throw currentFailure;
    return '{"memoryPatch":{"eventBrief":{"description":"$replyText"}},'
        '"reply":"$replyText"}';
  }
}
