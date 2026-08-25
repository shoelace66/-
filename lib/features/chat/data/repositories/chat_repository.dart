import '../../../../core/data/models/app_settings.dart';
import '../../../../core/data/models/provider_settings.dart';
import '../../../../core/utils/structured_input_prompt_composer.dart';
import '../../../../infrastructure/services/ai_service.dart';
import '../models/message.dart';

class ChatRepository {
  ChatRepository({required AiService aiService}) : _aiService = aiService;

  AiService get aiService => _aiService;

  static const String outputSchema = '''
{
  "protocolVersion": "roleplay-memory-v2",
  "memoryPatch": {
    "summary": {"description": "往期事件的综合总结，300字以内", "keywords": ["总结关键词1"]},
    "eventBrief": {"description": "在回复前确定的本轮规范事件，300字以内", "keywords": ["实体关键词1"], "theme": ["主题/氛围1"]},
    "relatedEventIds": [0, 3],
    "worldKnowledge": ["重要的新世界/背景知识，可省略"],
    "selfKnowledge": ["重要的新自我认知，可省略"],
    "userKnowledge": ["重要的新用户认知，可省略"],
    "belongings": ["(新增)物品名", "(提及)物品名"],
    "currentStates": {"用户创建的状态key": "新的状态value"}
  },
  "reply": "根据前述本轮事件和状态展开的回复"
}
''';

  final AiService _aiService;
  final Map<String, List<Message>> _cacheByContact = <String, List<Message>>{};

  List<Message> getCachedMessages(String contactId) {
    final list = _cacheByContact[contactId] ?? const <Message>[];
    return List<Message>.unmodifiable(list);
  }

  Future<Message> askAi({
    required String contactId,
    required String contactName,
    required Message userMessage,
    String? systemPrompt,
    AppSettings? settings,
    LlmProfile? profile,
  }) async {
    final list = _cacheByContact.putIfAbsent(contactId, () => <Message>[]);
    list.add(userMessage);

    final composer = StructuredInputPromptComposer(
      settings: settings ?? const AppSettings(),
    );
    final mergedPrompt = composer.composeStructuredOutputPrompt(
      userInput: userMessage.content,
      systemPrompt: systemPrompt,
      outputSchema: outputSchema,
    );

    final assistantReply = await _aiService.ask(
      mergedPrompt,
      contactId: contactId,
      contactName: contactName,
      profile: profile,
    );

    final assistantMessage = Message(
      id: 'assistant-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      content: assistantReply,
      createdAt: DateTime.now(),
    );
    list.add(assistantMessage);
    return assistantMessage;
  }

  Stream<String> askAiStream({
    required String contactId,
    required String contactName,
    required Message userMessage,
    String? systemPrompt,
    AppSettings? settings,
    LlmProfile? profile,
  }) {
    final list = _cacheByContact.putIfAbsent(contactId, () => <Message>[]);
    list.add(userMessage);
    final composer = StructuredInputPromptComposer(
      settings: settings ?? const AppSettings(),
    );
    final prompt = composer.composeStructuredOutputPrompt(
      userInput: userMessage.content,
      systemPrompt: systemPrompt,
      outputSchema: outputSchema,
    );
    return _aiService.askStream(
      prompt,
      contactId: contactId,
      contactName: contactName,
      profile: profile,
    );
  }

  Future<String> askUtility({
    required String contactId,
    required String contactName,
    required String prompt,
    LlmProfile? profile,
  }) {
    return _aiService.ask(
      prompt,
      contactId: contactId,
      contactName: contactName,
      profile: profile,
    );
  }
}
