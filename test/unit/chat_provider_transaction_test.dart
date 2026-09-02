import 'dart:async';

import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/message.dart';
import 'package:flutter_chat_demo/features/chat/data/repositories/chat_repository.dart';
import 'package:flutter_chat_demo/features/chat/application/chat_view_state.dart';
import 'package:flutter_chat_demo/features/chat/domain/providers/chat_provider.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/chat_persistence.dart';
import 'package:flutter_chat_demo/infrastructure/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryPersistence persistence;
  late _FakeAiService aiService;
  late ChatProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    persistence = _MemoryPersistence(
      ChatSnapshot(contacts: <Contact>[_contact()]),
    );
    aiService = _FakeAiService();
    provider = ChatProvider(
      persistence: persistence,
      repository: ChatRepository(aiService: aiService),
    );
    await provider.initialize();
    await provider.saveProviderSettings(
      const ProviderSettings(
        llm: LlmProfile(apiKey: 'test-key'),
      ),
    );
  });

  tearDown(() => provider.dispose());

  test('成功发送在最终事务中同时提交消息和正文前事件', () async {
    aiService.mainResponse = '''
{"protocolVersion":"roleplay-memory-v2","memoryPatch":{"eventBrief":{"description":"林夏接过车票","keywords":["林夏","车票"]}},"reply":"她把车票仔细收进了口袋。"}
''';

    await provider.sendMessage('把车票给她');

    expect(provider.messages, hasLength(2));
    expect(provider.messages.first.status, MessageStatus.sent);
    expect(provider.messages.last.content, '她把车票仔细收进了口袋。');
    expect(provider.selectedContact?.eventGraph.turnCount, 1);
    expect(
      provider
          .selectedContact?.eventGraph.shortTermQueue.single.event.description,
      '林夏接过车票',
    );
    final committed = persistence.snapshot;
    expect(committed.messagesByContact['role-1'], hasLength(2));
    expect(committed.contacts.single.eventGraph.turnCount, 1);
  });

  test('模型失败保留 failed 用户消息但不提交任何记忆变化', () async {
    aiService.failure = const AiServiceException('模拟网络失败');

    await provider.sendMessage('这次会失败');

    expect(provider.messages.single.status, MessageStatus.failed);
    expect(provider.selectedContact?.eventGraph.turnCount, 0);
    expect(persistence.snapshot.messagesByContact['role-1']?.single.status,
        MessageStatus.failed);
    expect(persistence.snapshot.contacts.single.eventGraph.turnCount, 0);
  });

  test('撤回同时恢复消息历史和事件图', () async {
    aiService.mainResponse = '''
{"memoryPatch":{"eventBrief":{"description":"发生了一件事"}},"reply":"事情发生了。"}
''';
    await provider.sendMessage('推动这一轮');
    expect(provider.canRecall, isTrue);

    expect(await provider.recallLastTurn(), isTrue);

    expect(provider.messages, isEmpty);
    expect(provider.selectedContact?.eventGraph.turnCount, 0);
    expect(persistence.snapshot.messagesByContact['role-1'], isEmpty);
    expect(persistence.snapshot.contacts.single.eventGraph.turnCount, 0);
  });

  test('记忆修改记录跨重启保留且可以无损撤销', () async {
    aiService.mainResponse = '''
{"memoryPatch":{"eventBrief":{"description":"林夏收到一张蓝色车票","keywords":["林夏","车票"]}},"reply":"她收下了。"}
''';
    await provider.sendMessage('给她车票');
    final node = provider.memoryNodes.single;

    expect(
      await provider.reviseMemory(
        node.id,
        const EventMemory(
          description: '林夏收到一张红色车票',
          keywords: <String>['林夏', '红色车票'],
        ),
      ),
      isTrue,
    );
    expect(provider.canUndoMemoryRevision, isTrue);
    expect(
      persistence.metadata.entries
          .singleWhere((entry) => entry.key.startsWith('memory_revision_v1_'))
          .value,
      isNotEmpty,
    );

    provider.dispose();
    provider = ChatProvider(
      persistence: persistence,
      repository: ChatRepository(aiService: aiService),
    );
    await provider.initialize();

    expect(provider.canUndoMemoryRevision, isTrue);
    expect(await provider.undoLastMemoryRevision(), isTrue);
    expect(
      provider.memoryNodes.single.event.description,
      '林夏收到一张蓝色车票',
    );
    expect(
      persistence.metadata.entries
          .singleWhere((entry) => entry.key.startsWith('memory_revision_v1_'))
          .value,
      isEmpty,
    );
  });

  test('完整备份恢复角色消息和事件，但不改变 API 设置', () async {
    aiService.mainResponse = '''
{"memoryPatch":{"eventBrief":{"description":"林夏记住了雨夜"}},"reply":"雨声还在窗外。"}
''';
    await provider.sendMessage('记住这个雨夜');
    final backup = await provider.exportBackupJson();
    final originalKey = provider.currentApiKey;

    await provider.addContact(name: '临时角色', avatar: '');
    expect(provider.contacts, hasLength(2));
    expect(await provider.restoreBackupJson(backup), isTrue);

    expect(provider.contacts, hasLength(1));
    expect(provider.messages, hasLength(2));
    expect(provider.memoryNodes.single.event.description, '林夏记住了雨夜');
    expect(provider.currentApiKey, originalKey);
  });

  test('停止非流式生成立即结束等待且不提交记忆', () async {
    aiService.pendingMain = Completer<String>();

    final sending = provider.sendMessage('等待中的请求');
    await Future<void>.delayed(Duration.zero);
    expect(provider.canCancelGeneration, isTrue);
    provider.cancelGeneration();
    await sending;

    expect(provider.isLoading, isFalse);
    expect(provider.isTyping, isFalse);
    expect(provider.error, isNull);
    expect(provider.messages.single.status, MessageStatus.cancelled);
    expect(provider.state.generationStatus, ChatGenerationStatus.cancelled);
    expect(provider.selectedContact?.eventGraph.turnCount, 0);
    expect(persistence.snapshot.contacts.single.eventGraph.turnCount, 0);
  });

  test('流式回复逐块更新可见消息并在完整 JSON 后原子提交记忆', () async {
    await provider.saveProviderSettings(
      const ProviderSettings(
        llm: LlmProfile(
          apiKey: 'test-key',
          parameters: LlmParameters(stream: true),
        ),
      ),
    );
    final stream = StreamController<String>();
    aiService.pendingStream = stream;

    final sending = provider.sendMessage('开始流式回复');
    await Future<void>.delayed(Duration.zero);
    stream.add(
      '{"memoryPatch":{"eventBrief":{"description":"流式事件"}},"reply":"你',
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(provider.messages.last.content, '你');
    expect(provider.messages.last.status, MessageStatus.sending);
    expect(provider.state.generationStatus, ChatGenerationStatus.streaming);

    stream.add('好"}');
    await stream.close();
    await sending;

    expect(provider.messages, hasLength(2));
    expect(provider.messages.last.content, '你好');
    expect(provider.messages.last.status, MessageStatus.sent);
    expect(provider.state.generationStatus, ChatGenerationStatus.completed);
    expect(provider.memoryNodes.single.event.description, '流式事件');
    expect(persistence.snapshot.messagesByContact['role-1'], hasLength(2));
  });

  test('取消流式回复保留部分文本并标记 cancelled', () async {
    await provider.saveProviderSettings(
      const ProviderSettings(
        llm: LlmProfile(
          apiKey: 'test-key',
          parameters: LlmParameters(stream: true),
        ),
      ),
    );
    final stream = StreamController<String>();
    aiService.pendingStream = stream;
    final sending = provider.sendMessage('取消流式回复');
    await Future<void>.delayed(Duration.zero);
    stream.add('{"memoryPatch":{},"reply":"部分');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    provider.cancelGeneration();
    await sending;
    await stream.close();

    expect(provider.messages, hasLength(2));
    expect(provider.messages.first.status, MessageStatus.cancelled);
    expect(provider.messages.last.content, '部分');
    expect(provider.messages.last.status, MessageStatus.cancelled);
    expect(provider.state.generationStatus, ChatGenerationStatus.cancelled);
    expect(provider.selectedContact?.eventGraph.turnCount, 0);
  });

  test('修改上一轮后先撤回旧记忆再重新生成', () async {
    aiService.mainResponse = '''
{"memoryPatch":{"eventBrief":{"description":"林夏收下蓝色车票"}},"reply":"她收下了蓝色车票。"}
''';
    await provider.sendMessage('给她蓝色车票');
    aiService.mainResponse = '''
{"memoryPatch":{"eventBrief":{"description":"林夏拒绝红色车票"}},"reply":"她轻轻摇头。"}
''';

    expect(
      await provider.regenerateLastTurn(editedInput: '改成给她红色车票'),
      isTrue,
    );

    expect(provider.messages, hasLength(2));
    expect(provider.messages.first.content, '改成给她红色车票');
    expect(provider.messages.last.content, '她轻轻摇头。');
    expect(provider.memoryNodes, hasLength(1));
    expect(provider.memoryNodes.single.event.description, '林夏拒绝红色车票');
    expect(provider.selectedContact?.eventGraph.turnCount, 1);
  });

  test('消息编辑与删除立即持久化到当前分支', () async {
    aiService.mainResponse = '{"memoryPatch":{},"reply":"原回复"}';
    await provider.sendMessage('原问题');
    final assistantId = provider.messages.last.id;
    final userId = provider.messages.first.id;

    expect(await provider.editMessage(assistantId, '修订后的回复'), isTrue);
    expect(provider.messages.last.content, '修订后的回复');
    expect(
      persistence.snapshot.messagesByContact['role-1']?.last.content,
      '修订后的回复',
    );

    expect(await provider.deleteMessage(userId), isTrue);
    expect(provider.messages, hasLength(1));
    expect(persistence.snapshot.messagesByContact['role-1'], hasLength(1));
  });

  test('任意消息可保存并切换候选回复', () async {
    aiService.mainResponse = '{"memoryPatch":{},"reply":"原回复"}';
    await provider.sendMessage('给出回复');
    final messageId = provider.messages.last.id;
    aiService.mainResponse = '另一个候选回复';

    expect(await provider.generateReplyCandidate(messageId), isTrue);
    expect(provider.messages.last.alternatives, ['另一个候选回复']);
    expect(
      await provider.applyReplyCandidate(messageId, '另一个候选回复'),
      isTrue,
    );
    expect(provider.messages.last.content, '另一个候选回复');
    expect(provider.messages.last.alternatives, contains('原回复'));
  });

  test('记忆锁跨重启持久化并阻止作废和删除', () async {
    aiService.mainResponse =
        '{"memoryPatch":{"eventBrief":{"description":"不可删除的记忆"}},"reply":"记住了"}';
    await provider.sendMessage('锁定它');
    final nodeId = provider.memoryNodes.single.id;

    expect(await provider.setMemoryLocked(nodeId, true), isTrue);
    expect(provider.isMemoryLocked(nodeId), isTrue);
    expect(await provider.invalidateMemory(nodeId), isFalse);
    expect(await provider.deleteMemory(nodeId), isFalse);

    provider.dispose();
    provider = ChatProvider(
      persistence: persistence,
      repository: ChatRepository(aiService: aiService),
    );
    await provider.initialize();
    expect(provider.isMemoryLocked(nodeId), isTrue);
  });

  test('主 LLM Profile 失败后自动使用备用 Profile', () async {
    await provider.saveProviderSettings(
      const ProviderSettings(
        llm: LlmProfile(apiKey: 'primary', model: 'bad-model'),
        fallbackLlmProfiles: <LlmProfile>[
          LlmProfile(apiKey: 'fallback', model: 'good-model'),
        ],
      ),
    );
    aiService.failingModels.add('bad-model');
    aiService.mainResponse = '{"memoryPatch":{},"reply":"备用成功"}';

    await provider.sendMessage('测试 fallback');

    expect(provider.error, isNull);
    expect(provider.messages.last.content, '备用成功');
    expect(aiService.requestedModels, containsAll(['bad-model', 'good-model']));
  });
}

class _FakeAiService extends AiService {
  String mainResponse = '';
  AiServiceException? failure;
  Completer<String>? pendingMain;
  StreamController<String>? pendingStream;
  final Set<String> failingModels = <String>{};
  final List<String> requestedModels = <String>[];

  @override
  Future<String> ask(
    String prompt, {
    required String contactId,
    required String contactName,
    String? systemPrompt,
    LlmProfile? profile,
    RecallRequestBudget? requestBudget,
  }) async {
    if (prompt.contains('提取本轮对话中的关键词')) {
      return '{"keywords":["车票"],"theme":[]}';
    }
    requestedModels.add(profile?.model ?? '');
    if (failingModels.contains(profile?.model)) {
      throw const AiServiceException('模拟 Profile 失败');
    }
    final error = failure;
    if (error != null) throw error;
    final pending = pendingMain;
    if (pending != null) return pending.future;
    return mainResponse;
  }

  @override
  Stream<String> askStream(
    String prompt, {
    required String contactId,
    required String contactName,
    String? systemPrompt,
    LlmProfile? profile,
  }) {
    final stream = pendingStream;
    if (stream != null) return stream.stream;
    return Stream<String>.value(mainResponse);
  }
}

class _MemoryPersistence implements ChatPersistence {
  _MemoryPersistence(this.snapshot);

  ChatSnapshot snapshot;
  final Map<String, String> metadata = <String, String>{};

  @override
  Future<void> initialize() async {}

  @override
  Future<ChatSnapshot> readSnapshot() async => snapshot;

  @override
  Future<void> replaceSnapshot(ChatSnapshot value) async {
    snapshot = _copy(value);
  }

  @override
  Future<void> saveConversation({
    required Contact contact,
    required List<Message> messages,
    Map<String, String> metadataUpdates = const <String, String>{},
  }) async {
    final contacts = <Contact>[
      ...snapshot.contacts.where((item) => item.id != contact.id),
      contact.deepCopy(),
    ];
    snapshot = ChatSnapshot(
      contacts: contacts,
      messagesByContact: <String, List<Message>>{
        ...snapshot.messagesByContact,
        contact.id: List<Message>.from(messages),
      },
    );
    metadata.addAll(metadataUpdates);
  }

  @override
  Future<void> deleteConversation(String contactId) async {
    snapshot = ChatSnapshot(
      contacts:
          snapshot.contacts.where((item) => item.id != contactId).toList(),
      messagesByContact: <String, List<Message>>{
        for (final entry in snapshot.messagesByContact.entries)
          if (entry.key != contactId) entry.key: entry.value,
      },
    );
  }

  @override
  Future<String?> readMetadata(String key) async => metadata[key];

  @override
  Future<void> writeMetadata(String key, String value) async {
    metadata[key] = value;
  }

  @override
  Future<void> close() async {}

  ChatSnapshot _copy(ChatSnapshot value) => ChatSnapshot(
        contacts: value.contacts.map((contact) => contact.deepCopy()).toList(),
        messagesByContact: <String, List<Message>>{
          for (final entry in value.messagesByContact.entries)
            entry.key: List<Message>.from(entry.value),
        },
      );
}

Contact _contact() => Contact(
      id: 'role-1',
      name: '林夏',
      avatar: '',
      fixedInput: '你是林夏。',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    );
