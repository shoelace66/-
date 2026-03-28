import '../../../../core/data/models/app_settings.dart';
import '../../../../core/utils/structured_input_prompt_composer.dart';
import '../../../../infrastructure/services/ai_service.dart';
import '../models/message.dart';

class ChatRepository {
  ChatRepository({required AiService aiService}) : _aiService = aiService;

  /// AI 服务实例
  ///
  /// 用于直接调用 LLM，如自然语言转 JSON 等功能
  AiService get aiService => _aiService;

  /// LLM输出Schema
  ///
  /// 定义LLM应返回的JSON结构，包含：
  /// - reply: AI的回复内容
  /// - memoryPatch: 记忆更新补丁，包含知识、事件、物品等
  static const String outputSchema = '''
{
  "reply": "给用户的回复",
  "memoryPatch": {
    "worldKnowledge": ["新增的世界观知识，无则[]"],
    "selfKnowledge": ["新增的自我认知，无则[]"],
    "userKnowledge": ["新增的对用户了解，无则[]"],
    "events": [{
      "time": "",
      "location": "",
      "characters": "",
      "cause": "",
      "process": "",
      "result": "",
      "attitude": ""
    }],
    "belongings": ["(新增)手电筒","(提及)地图，无则[]"],
    "status": ["状态变化，无则[]"],
    "mood": "当前情绪，无则空字符串",
    "time": "当前时间，无则空字符串"
  }
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
  }) async {
    final list = _cacheByContact.putIfAbsent(contactId, () => <Message>[]);
    list.add(userMessage);

    final composer = StructuredInputPromptComposer(
        settings: settings ?? const AppSettings());
    final mergedPrompt = composer.composeStructuredOutputPrompt(
      userInput: userMessage.content,
      systemPrompt: systemPrompt,
      outputSchema: outputSchema,
    );

    final assistantReply = await _aiService.ask(
      mergedPrompt,
      contactId: contactId,
      contactName: contactName,
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

  Future<String> askUtility({
    required String contactId,
    required String contactName,
    required String prompt,
  }) {
    return _aiService.ask(
      prompt,
      contactId: contactId,
      contactName: contactName,
    );
  }
}
