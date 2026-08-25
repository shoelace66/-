import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/data/models/app_settings.dart';
import '../../../../core/data/models/opencode_connection_config.dart';
import '../../../../core/data/models/provider_settings.dart';
import '../../../../core/data/datasources/shared_preferences_settings_store.dart';
import '../../../../core/domain/repositories/settings_store.dart';
import '../../../../core/utils/chinese_tokenizer_service.dart';
import '../../../../core/utils/image_prompt_polisher.dart';
import '../../../../core/utils/structured_input_prompt_composer.dart';
import '../../../../core/utils/structured_output_regex_parser.dart';
import '../../../../infrastructure/services/ai_service.dart';
import '../../../../infrastructure/services/image_generation_service.dart';
import '../../../../infrastructure/services/opencode_service.dart';
import '../../../../infrastructure/services/tts_service.dart';
import '../../data/datasources/chat_local_storage.dart';
import '../../data/datasources/legacy_chat_snapshot_source.dart';
import '../../data/datasources/sqlite_chat_persistence.dart';
import '../../data/models/contact.dart';
import '../../data/models/message.dart';
import '../../data/repositories/chat_repository.dart';
import '../../application/migrate_legacy_chat_data.dart';
import '../../application/chat_view_state.dart';
import '../../application/conversation_timeline_use_case.dart';
import '../../application/conversation_usage_estimator.dart';
import '../repositories/chat_persistence.dart';
import '../repositories/conversation_timeline.dart';
import '../services/heartbeat_manager.dart';
import '../services/input_formatter.dart';
import '../services/contact_import_parser.dart';
import '../services/memory_cascade_policy.dart';
import '../services/chat_backup_codec.dart';
import '../services/memory_graph_service.dart';
import '../services/memory_patch_reducer.dart';
import '../services/memory_recall_service.dart';
import '../services/memory_revision_service.dart';
import '../../../worldbook/domain/entities/world_book.dart';

/// 聊天状态管理器
///
/// 负责管理整个聊天应用的核心状态，包括：
/// - 联系人列表的增删改查
/// - 消息的发送与接收
/// - 与AI服务的交互
/// - 长期记忆的维护（事件图、知识库、物品等）
/// - 调试模式的切换
///
/// 使用 [ChangeNotifier] 模式，UI层通过监听此Provider来响应状态变化
class ChatProvider extends ChangeNotifier {
  static const int _messagePageSize = 100;

  /// 构造函数
  ///
  /// 支持依赖注入，便于单元测试
  /// - [repository] 聊天数据仓库
  /// - [formatter] 输入格式化服务
  /// - [heartbeat] 心跳管理器，用于检测连接状态
  /// - [agentStore] Agent数据持久化存储
  ChatProvider({
    ChatRepository? repository,
    InputFormatterService? formatter,
    HeartbeatManager? heartbeat,
    ChatAgentStore? agentStore,
    ChatPersistence? persistence,
    SettingsStore? settingsStore,
  })  : _formatter = formatter ?? InputFormatterService(),
        _heartbeat = heartbeat ?? HeartbeatManager(),
        _repository = repository ?? ChatRepository(aiService: AiService()),
        _agentStore = agentStore ?? ChatAgentStore(),
        _persistence = persistence ?? SqliteChatPersistence(),
        _settingsStore =
            settingsStore ?? const SharedPreferencesSettingsStore() {
    _timelineUseCase = ConversationTimelineUseCase(_persistence);
  }

  // ==================== 常量配置 ====================

  /// 应用设置
  AppSettings _appSettings = const AppSettings();

  /// API 提供商（LLM / 生图 / TTS）
  ProviderSettings _providerSettings = const ProviderSettings();

  /// 获取应用设置
  AppSettings get appSettings => _appSettings;

  /// 获取 provider 设置
  ProviderSettings get providerSettings => _providerSettings;

  /// 加载应用设置
  Future<void> _loadAppSettings() async {
    final appJson = await _settingsStore.readJson(AppStrings.appSettingsKey);
    if (appJson != null) {
      _appSettings = AppSettings.fromJson(appJson);
    }

    // 加载 provider 配置（LLM / 生图 / TTS）
    final providerJson =
        await _settingsStore.readJson(AppStrings.providerSettingsKey);
    if (providerJson != null) {
      _providerSettings = ProviderSettings.fromJson(providerJson);
    }
    _applyProviderSettingsToRuntime(_providerSettings);

    // 加载 opencode 连接配置
    final opencodeJson =
        await _settingsStore.readJson(AppStrings.opencodeConnectionKey);
    if (opencodeJson != null) {
      _opencodeService.updateConfig(
        OpencodeConnectionConfig.fromJson(opencodeJson),
      );
    }
  }

  /// 把 ProviderSettings 同步到运行时单例（ApiConstants / 单例服务）
  void _applyProviderSettingsToRuntime(ProviderSettings settings) {
    final llm = settings.llm;
    ApiConstants.runtimeApiKey = llm.apiKey;
    ApiConstants.runtimeBaseUrl = llm.baseUrl;
    ApiConstants.runtimeModel = llm.model;
    ApiConstants.runtimeTimeoutSeconds = llm.parameters.timeoutSeconds;
    ImageGenerationService.instance.updateProfile(settings.image);
    TtsService.instance.updateProfile(settings.tts);
  }

  /// 保存 provider 配置（LLM / 生图 / TTS 完整合集）
  Future<void> saveProviderSettings(ProviderSettings settings) async {
    _providerSettings = settings;
    _applyProviderSettingsToRuntime(settings);
    await _settingsStore.writeJson(
      AppStrings.providerSettingsKey,
      settings.toJson(),
    );
    // 同步兼容旧 agent settings（让旧 API 读取能继续工作）
    final agent = await _agentStore.readAgentSettings();
    agent['apiKey'] = settings.llm.apiKey;
    agent['apiBaseUrl'] = settings.llm.baseUrl;
    agent['apiModel'] = settings.llm.model;
    await _agentStore.saveAgentSettings(agent);
    notifyListeners();
  }

  List<LlmProfile> get llmProfiles => List<LlmProfile>.unmodifiable(
        <LlmProfile>[
          _providerSettings.llm,
          ..._providerSettings.fallbackLlmProfiles,
        ],
      );

  Future<void> activateLlmProfile(LlmProfile profile) async {
    final current = _providerSettings.llm;
    final remaining = _providerSettings.fallbackLlmProfiles
        .where((candidate) => !identical(candidate, profile))
        .toList(growable: true);
    if (!identical(current, profile)) remaining.insert(0, current);
    await saveProviderSettings(
      _providerSettings.copyWith(
        llm: profile,
        fallbackLlmProfiles: remaining,
      ),
    );
  }

  Future<Map<LlmProfile, String?>> checkLlmProfiles() async {
    final results = <LlmProfile, String?>{};
    for (final profile in llmProfiles) {
      try {
        await _repository.aiService.ask(
          '只回复 OK',
          contactId: 'provider-health-check',
          contactName: 'System',
          profile: profile,
        );
        results[profile] = null;
      } catch (error) {
        results[profile] = error.toString();
      }
    }
    return results;
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    _appSettings = settings;
    await _settingsStore.writeJson(
      AppStrings.appSettingsKey,
      settings.toJson(),
    );
    notifyListeners();
  }

  /// 是否已经有 provider 配置持久化
  Future<bool> _hasProviderSettings() async {
    return _settingsStore.contains(AppStrings.providerSettingsKey);
  }

  /// 保存 opencode 连接配置
  Future<void> saveOpencodeConfig(OpencodeConnectionConfig config) async {
    _opencodeService.updateConfig(config);
    await _settingsStore.writeJson(
      AppStrings.opencodeConnectionKey,
      config.toJson(),
    );
    notifyListeners();
  }

  /// 获取 opencode 连接配置
  OpencodeConnectionConfig get opencodeConfig => _opencodeService.config;

  Future<String?> testOpencodeConnection(
      OpencodeConnectionConfig config) async {
    final result = await OpencodeService(config: config).testConnection();
    return result.success ? null : result.error ?? '未知连接错误';
  }

  /// 事件总结阈值
  int get _summaryThreshold => _appSettings.summaryThreshold;
  int get _ultraSummaryThreshold => _appSettings.ultraSummaryThreshold;

  /// 短期事件输入LLM数量
  int get _maxShortTermEvents => _appSettings.maxShortTermEvents;

  /// 长期事件输入LLM数量
  int get _maxLongTermEvents => _appSettings.maxLongTermEvents;

  /// 超长期事件输入LLM数量
  int get _maxUltraTermEvents => _appSettings.maxUltraTermEvents;

  /// 关联事件数量
  int get _maxRelatedEvents => _appSettings.maxRelatedEvents;

  /// Prompt列表项最大数量
  int get _maxPromptListItems => _appSettings.maxPromptListItems;

  /// 关键词提取正则表达式
  ///
  /// 中文分词服务实例
  /// 用于从用户输入中提取本地关键词，替代原有的正则表达式分词
  final ChineseTokenizerService _tokenizer = ChineseTokenizerService();

  // ==================== 依赖服务 ====================

  /// 聊天数据仓库
  ///
  /// 负责与AI服务通信，发送请求并接收响应
  final ChatRepository _repository;

  /// 输入格式化服务
  ///
  /// 对用户输入进行预处理，如去除多余空白
  final InputFormatterService _formatter;

  /// 心跳管理器
  ///
  /// 定期检查与AI服务的连接状态
  final HeartbeatManager _heartbeat;

  /// Agent数据持久化存储
  ///
  /// 使用SharedPreferences存储联系人、消息历史、API设置等
  final ChatAgentStore _agentStore;

  final ChatPersistence _persistence;
  late final ConversationTimelineUseCase _timelineUseCase;

  final SettingsStore _settingsStore;

  final ContactImportParser _contactImportParser = const ContactImportParser();

  final ChatBackupCodec _chatBackupCodec = const ChatBackupCodec();
  final ConversationUsageEstimator _usageEstimator =
      const ConversationUsageEstimator();

  /// 三级记忆级联判定（纯业务规则）。
  final MemoryCascadePolicy _memoryCascadePolicy = const MemoryCascadePolicy();

  final MemoryGraphService _memoryGraphService = const MemoryGraphService();

  /// LLM 记忆补丁解析与联系人字段归并（纯业务规则）。
  final MemoryPatchReducer _memoryPatchReducer = const MemoryPatchReducer();

  /// 本地事件图召回与关系清理。
  final MemoryRecallService _memoryRecallService = const MemoryRecallService();

  final MemoryRevisionService _memoryRevisionService =
      const MemoryRevisionService();

  /// opencode CLI 交互服务
  ///
  /// 用于助手类型联系人，通过网络连接到运行 opencode 的 PC
  final OpencodeService _opencodeService = OpencodeService();

  // ==================== 状态数据 ====================

  /// 联系人列表
  final List<Contact> _contacts = <Contact>[];

  /// 按联系人ID索引的消息列表
  ///
  /// Key为联系人ID，Value为该联系人的消息历史
  final Map<String, List<Message>> _messagesByContact =
      <String, List<Message>>{};
  final Map<String, int> _loadedStartSequenceByContact = <String, int>{};
  final Map<String, int> _messageCountByContact = <String, int>{};
  final Map<String, bool> _hasOlderMessagesByContact = <String, bool>{};
  final Map<String, List<ConversationBranch>> _branchesByContact =
      <String, List<ConversationBranch>>{};
  final Map<String, List<ConversationCheckpoint>> _checkpointsByContact =
      <String, List<ConversationCheckpoint>>{};

  /// 临时关键词缓存
  ///
  /// 按联系人ID存储最近一次对话提取的关键词
  /// 用于关联事件搜索
  final Map<String, List<String>> _tempKeywordsByContact =
      <String, List<String>>{};

  final Map<String, MemoryRevisionRecord> _lastMemoryRevisions =
      <String, MemoryRevisionRecord>{};
  final Map<String, Set<String>> _lockedMemoryNodeIds = <String, Set<String>>{};

  /// ==================== 撤回功能相关 ====================

  /// 最近一轮对话前的 Contact 快照
  /// 用于支持单条消息撤回
  Contact? _lastContactSnapshot;

  /// 最近一轮对话前的消息列表快照
  List<Message>? _lastMessagesSnapshot;

  /// 当前选中的联系人ID
  String? _selectedContactId;

  /// 系统提示词
  ///
  /// 作为基础系统提示，会与联系人信息合并后发送给LLM
  String _systemPrompt = '你是一个AI角色扮演对话助手，专注于沉浸式对话体验。';

  // ==================== 公开状态（UI可直接访问） ====================

  /// 是否正在加载中
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// AI是否正在输入（用于显示打字指示器）
  bool _isTyping = false;
  bool get isTyping => _isTyping;

  /// Whether an older message page is currently being prepended.
  bool _isLoadingOlderMessages = false;
  bool get isLoadingOlderMessages => _isLoadingOlderMessages;

  Completer<void>? _generationCancellation;
  ChatGenerationStatus _generationStatus = ChatGenerationStatus.idle;

  /// 是否已完成初始化
  ChatInitializationState _initialization =
      const ChatInitializationState.initial();
  ChatInitializationState get initialization => _initialization;
  bool get isInitialized => _initialization.isReady;

  /// 是否处于调试模式
  ///
  /// 调试模式下会显示完整的Prompt和关键词提取信息
  bool _isDebugMode = false;
  bool get isDebugMode => _isDebugMode;

  /// 错误信息
  String? _error;
  String? get error => _error;

  /// 当前连接状态
  ConnectionStatus _connectionStatus = ConnectionStatus.connected;
  ConnectionStatus get connectionStatus => _connectionStatus;

  // ==================== Getters ====================

  /// 获取不可修改的联系人列表副本
  List<Contact> get contacts => List<Contact>.unmodifiable(_contacts);

  ChatViewState get state => ChatViewState(
        initialization: _initialization,
        contacts: _contacts,
        messages: messages,
        branches: conversationBranches,
        checkpoints: conversationCheckpoints,
        selectedContactId: _selectedContactId,
        selectedContact: selectedContact,
        isLoading: _isLoading,
        isTyping: _isTyping,
        isLoadingOlderMessages: _isLoadingOlderMessages,
        hasOlderMessages: hasOlderMessages,
        totalMessageCount: totalMessageCount,
        isDebugMode: _isDebugMode,
        canCancelGeneration: canCancelGeneration,
        canRecall: canRecall,
        canRegenerateLastTurn: canRegenerateLastTurn,
        error: _error,
        connectionStatus: _connectionStatus,
        generationStatus: _generationStatus,
      );

  bool get canCancelGeneration =>
      isLoading &&
      _generationCancellation != null &&
      !_generationCancellation!.isCompleted;

  void cancelGeneration() {
    final cancellation = _generationCancellation;
    if (cancellation == null || cancellation.isCompleted) return;
    cancellation.complete();
    _isTyping = false;
    _generationStatus = ChatGenerationStatus.cancelled;
    notifyListeners();
  }

  Future<T> _awaitGeneration<T>(Future<T> operation) {
    final cancellation = _generationCancellation;
    if (cancellation == null) return operation;
    return Future.any<T>(<Future<T>>[
      operation,
      cancellation.future.then<T>(
        (_) => throw const _GenerationCancelled(),
      ),
    ]);
  }

  Future<void> _consumeGenerationStream(
    Stream<String> stream,
    void Function(String chunk) onChunk,
  ) async {
    final iterator = StreamIterator<String>(stream);
    try {
      while (true) {
        final cancellation = _generationCancellation;
        final hasNext = cancellation == null
            ? await iterator.moveNext()
            : await Future.any<bool>([
                iterator.moveNext(),
                cancellation.future.then<bool>(
                  (_) => throw const _GenerationCancelled(),
                ),
              ]);
        if (!hasNext) return;
        onChunk(iterator.current);
      }
    } finally {
      // Cancellation must release the UI state immediately. In particular, an
      // async* fallback wrapper may wait for its current upstream stream to
      // close before its cancellation future completes. Start cleanup, but do
      // not let an uncooperative provider keep sendMessage suspended.
      unawaited(iterator.cancel());
    }
  }

  Future<Message> _askRoleplayWithFallback({
    required Contact contact,
    required Message userMessage,
    required String systemPrompt,
  }) async {
    AiServiceException? lastError;
    for (final profile in llmProfiles.where((profile) => profile.hasApiKey)) {
      try {
        return await _awaitGeneration(_repository.askAi(
          contactId: contact.id,
          contactName: contact.name,
          userMessage: userMessage,
          systemPrompt: systemPrompt,
          settings: _appSettings,
          profile: profile,
        ));
      } on AiServiceException catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? const AiServiceException('没有可用的 LLM Profile。');
  }

  Stream<String> _streamRoleplayWithFallback({
    required Contact contact,
    required Message userMessage,
    required String systemPrompt,
  }) async* {
    AiServiceException? lastError;
    for (final profile in llmProfiles.where((profile) => profile.hasApiKey)) {
      var emitted = false;
      try {
        await for (final chunk in _repository.askAiStream(
          contactId: contact.id,
          contactName: contact.name,
          userMessage: userMessage,
          systemPrompt: systemPrompt,
          settings: _appSettings,
          profile: profile,
        )) {
          emitted = true;
          yield chunk;
        }
        return;
      } on AiServiceException catch (error) {
        lastError = error;
        if (emitted) rethrow;
      }
    }
    throw lastError ?? const AiServiceException('没有可用的 LLM Profile。');
  }

  /// 获取当前选中的联系人ID
  String? get selectedContactId => _selectedContactId;

  /// 获取当前API密钥
  String get currentApiKey => _providerSettings.llm.apiKey;

  /// 获取当前API Base URL
  String get currentApiBaseUrl => _providerSettings.llm.baseUrl;

  /// 获取当前API Model
  String get currentApiModel => _providerSettings.llm.model;

  /// 获取当前系统提示词
  String get currentSystemPrompt => _systemPrompt;

  /// 获取当前选中的联系人对象
  ///
  /// 如果未选中任何联系人，返回null
  Contact? get selectedContact {
    final id = _selectedContactId;
    if (id == null) return null;
    for (final c in _contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 获取当前联系人的消息列表
  ///
  /// 如果未选中联系人，返回空列表
  List<Message> get messages {
    final id = _selectedContactId;
    if (id == null) return const <Message>[];
    return List<Message>.unmodifiable(_messagesByContact[id] ?? <Message>[]);
  }

  bool get hasOlderMessages {
    final id = _selectedContactId;
    return id != null && (_hasOlderMessagesByContact[id] ?? false);
  }

  int get totalMessageCount {
    final id = _selectedContactId;
    if (id == null) return 0;
    return _messageCountByContact[id] ?? (_messagesByContact[id]?.length ?? 0);
  }

  List<ConversationBranch> get conversationBranches {
    final id = _selectedContactId;
    if (id == null) return const <ConversationBranch>[];
    return List<ConversationBranch>.unmodifiable(
      _branchesByContact[id] ?? const <ConversationBranch>[],
    );
  }

  List<ConversationCheckpoint> get conversationCheckpoints {
    final id = _selectedContactId;
    if (id == null) return const <ConversationCheckpoint>[];
    return List<ConversationCheckpoint>.unmodifiable(
      _checkpointsByContact[id] ?? const <ConversationCheckpoint>[],
    );
  }

  ConversationBranch? get activeConversationBranch {
    for (final branch in conversationBranches) {
      if (branch.isActive) return branch;
    }
    return null;
  }

  ConversationUsageEstimate get conversationUsage =>
      _usageEstimator.estimate(messages, _providerSettings.llm);

  /// 是否可以撤回最近一轮对话
  bool get canRecall {
    final result = _lastContactSnapshot != null;
    debugPrint('[canRecall] result=$result, snapshot=$_lastContactSnapshot');
    return result;
  }

  bool get canRegenerateLastTurn =>
      _lastContactSnapshot?.id == _selectedContactId &&
      lastTurnUserInput != null &&
      !isLoading;

  String? get lastTurnUserInput {
    final contactId = _selectedContactId;
    final before = _lastMessagesSnapshot;
    if (contactId == null || before == null) return null;
    final current = _messagesByContact[contactId] ?? const <Message>[];
    for (final message in current.skip(before.length)) {
      if (message.role == MessageRole.user &&
          !message.content.startsWith('【调试信息】')) {
        return message.content;
      }
    }
    return null;
  }

  Future<bool> regenerateLastTurn({String? editedInput}) async {
    final original = lastTurnUserInput;
    final input = (editedInput ?? original ?? '').trim();
    if (!canRegenerateLastTurn || input.isEmpty) return false;
    if (!await recallLastTurn()) return false;
    await sendMessage(input);
    return error == null;
  }

  List<EventNode> get memoryNodes {
    final graph = selectedContact?.eventGraph;
    if (graph == null) return const <EventNode>[];
    return List<EventNode>.unmodifiable(<EventNode>[
      ...graph.shortTermQueue,
      ...graph.longTermQueue,
      ...graph.ultraLongTermQueue,
    ]);
  }

  bool get canUndoMemoryRevision {
    final contact = selectedContact;
    if (contact == null) return false;
    final record = _lastMemoryRevisions[contact.id];
    return record != null &&
        record.graphTurnCount == contact.eventGraph.turnCount;
  }

  // ==================== 初始化与配置 ====================

  /// 初始化Provider
  ///
  /// 从持久化存储加载：
  /// 1. Agent设置（API密钥、系统提示词）
  /// 2. 联系人列表
  /// 3. 各联系人的消息历史
  ///
  /// 如果联系人列表为空，自动创建一个演示联系人
  Future<void> initialize() async {
    if (_initialization.status == ChatInitializationStatus.loading ||
        _initialization.status == ChatInitializationStatus.ready) {
      return;
    }
    _initialization = const ChatInitializationState.loading();
    _error = null;
    notifyListeners();

    try {
      try {
        await _loadAppSettings();
        final settings = await _agentStore.readAgentSettings();
        _systemPrompt = (settings['systemPrompt'] ?? _systemPrompt).toString();
        if (!await _hasProviderSettings()) {
          await saveProviderSettings(
            ProviderSettings(
              llm: LlmProfile(
                apiKey: (settings['apiKey'] ?? '').toString(),
                baseUrl: (settings['apiBaseUrl'] ?? 'https://api.deepseek.com')
                    .toString(),
                model: (settings['apiModel'] ?? 'deepseek-chat').toString(),
              ),
            ),
          );
        }
      } catch (cause) {
        throw ChatInitializationFailure('设置', cause);
      }

      try {
        await _tokenizer.init();
      } catch (cause) {
        debugPrint('中文分词模块不可用，将使用降级分词：$cause');
      }

      try {
        await _initializeLocalData();
      } catch (cause) {
        throw ChatInitializationFailure('本地数据库', cause);
      }

      _heartbeat.start((status) {
        _connectionStatus = status;
        notifyListeners();
      });
      _initialization = const ChatInitializationState.ready();
      _error = null;
      notifyListeners();
    } on ChatInitializationFailure catch (failure) {
      _initialization = ChatInitializationState.failure(
        module: failure.module,
        message: failure.cause.toString(),
      );
      _error = failure.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _initializeLocalData() async {
    await _persistence.initialize();
    await MigrateLegacyChatData(
      target: _persistence,
      source: SharedPreferencesLegacyChatSnapshotSource(_agentStore),
    ).execute();
    final paginated = _persistence is PaginatedChatPersistence;
    final snapshot = paginated ? null : await _persistence.readSnapshot();
    final localContacts = paginated
        ? await (_persistence as PaginatedChatPersistence).readContacts()
        : snapshot!.contacts;
    final localMessages =
        snapshot?.messagesByContact ?? const <String, List<Message>>{};
    _contacts
      ..clear()
      ..addAll(localContacts);
    _messagesByContact.clear();
    _loadedStartSequenceByContact.clear();
    _messageCountByContact.clear();
    _hasOlderMessagesByContact.clear();
    _branchesByContact.clear();
    _checkpointsByContact.clear();
    _lastMemoryRevisions.clear();
    _lockedMemoryNodeIds.clear();
    _selectedContactId = _contacts.firstOrNull?.id;

    for (final contact in _contacts) {
      if (!paginated) {
        final loaded = List<Message>.from(
          localMessages[contact.id] ?? const <Message>[],
        );
        _messagesByContact[contact.id] = loaded;
        _loadedStartSequenceByContact[contact.id] = 0;
        _messageCountByContact[contact.id] = loaded.length;
        _hasOlderMessagesByContact[contact.id] = false;
      }
      final revisionRaw =
          await _persistence.readMetadata(_memoryRevisionKey(contact.id));
      if (revisionRaw != null && revisionRaw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(revisionRaw);
          if (decoded is Map) {
            _lastMemoryRevisions[contact.id] = MemoryRevisionRecord.fromJson(
              Map<String, dynamic>.from(decoded),
            );
          }
        } catch (cause) {
          debugPrint('忽略损坏的记忆修订记录 ${contact.id}: $cause');
        }
      }
      final locksRaw =
          await _persistence.readMetadata(_memoryLocksKey(contact.id));
      if (locksRaw != null && locksRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(locksRaw);
          if (decoded is List) {
            _lockedMemoryNodeIds[contact.id] =
                decoded.map((value) => value.toString()).toSet();
          }
        } catch (cause) {
          debugPrint('忽略损坏的记忆锁记录 ${contact.id}: $cause');
        }
      }
    }

    final selectedId = _selectedContactId;
    if (selectedId != null) {
      if (paginated) await _loadInitialMessagePage(selectedId);
      await _refreshTimeline(selectedId);
    }
  }

  Future<void> _loadInitialMessagePage(String contactId) async {
    final persistence = _persistence;
    if (persistence is! PaginatedChatPersistence) return;
    final paginated = persistence as PaginatedChatPersistence;
    final page = await paginated.readMessagesPage(
      contactId: contactId,
      limit: _messagePageSize,
    );
    _messagesByContact[contactId] = List<Message>.from(page.messages);
    _loadedStartSequenceByContact[contactId] = page.startSequence;
    _messageCountByContact[contactId] = page.totalCount;
    _hasOlderMessagesByContact[contactId] = page.hasOlder;
  }

  Future<bool> loadOlderMessages() async {
    final contactId = _selectedContactId;
    final persistence = _persistence;
    if (contactId == null ||
        persistence is! PaginatedChatPersistence ||
        isLoadingOlderMessages ||
        !(_hasOlderMessagesByContact[contactId] ?? false)) {
      return false;
    }
    final paginated = persistence as PaginatedChatPersistence;
    _isLoadingOlderMessages = true;
    notifyListeners();
    try {
      final page = await paginated.readMessagesPage(
        contactId: contactId,
        beforeSequence: _loadedStartSequenceByContact[contactId],
        limit: _messagePageSize,
      );
      final current =
          _messagesByContact.putIfAbsent(contactId, () => <Message>[]);
      current.insertAll(0, page.messages);
      _loadedStartSequenceByContact[contactId] = page.startSequence;
      _messageCountByContact[contactId] = page.totalCount;
      _hasOlderMessagesByContact[contactId] = page.hasOlder;
      _error = null;
      return page.messages.isNotEmpty;
    } catch (e) {
      _error = '加载更早消息失败：$e';
      return false;
    } finally {
      _isLoadingOlderMessages = false;
      notifyListeners();
    }
  }

  Future<void> _refreshTimeline(String contactId) async {
    final state = await _timelineUseCase.load(contactId);
    _branchesByContact[contactId] = state.branches;
    _checkpointsByContact[contactId] = state.checkpoints;
  }

  Future<void> refreshConversationTimeline() async {
    final contactId = _selectedContactId;
    if (contactId == null) return;
    try {
      await _refreshTimeline(contactId);
      _error = null;
    } catch (e) {
      _error = '加载对话时间线失败：$e';
    }
    notifyListeners();
  }

  Future<void> _createCompletedTurnCheckpoint(
    String contactId,
    String sourceMessageId,
  ) async {
    if (!_timelineUseCase.isAvailable) return;
    final contactIndex = _contacts.indexWhere((item) => item.id == contactId);
    if (contactIndex < 0) return;
    var label = '';
    final messages = _messagesByContact[contactId] ?? const <Message>[];
    for (final message in messages.reversed) {
      if (message.id != sourceMessageId) continue;
      final normalized = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      label = normalized.length > 32
          ? '${normalized.substring(0, 32)}…'
          : normalized;
      break;
    }
    try {
      await _timelineUseCase.createCheckpoint(
        contact: _contacts[contactIndex],
        sourceMessageId: sourceMessageId,
        label: label,
      );
      await _refreshTimeline(contactId);
    } catch (e) {
      debugPrint('创建对话检查点失败: $e');
      _error = '本轮消息已保存，但检查点创建失败';
    }
  }

  Future<bool> createBranchFromCheckpoint(
    String checkpointId, {
    required String name,
    bool switchToNewBranch = true,
  }) async {
    final contactId = _selectedContactId;
    if (contactId == null || !_timelineUseCase.isAvailable || isLoading) {
      return false;
    }
    try {
      final branch = await _timelineUseCase.createBranch(
        checkpointId: checkpointId,
        name: name,
      );
      if (branch == null) return false;
      if (switchToNewBranch) {
        return switchConversationBranch(branch.id);
      }
      await _refreshTimeline(contactId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = '创建分支失败：$e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> switchConversationBranch(String branchId) async {
    final contactId = _selectedContactId;
    if (contactId == null || !_timelineUseCase.isAvailable || isLoading) {
      return false;
    }
    _isLoadingOlderMessages = true;
    notifyListeners();
    try {
      final snapshot = await _timelineUseCase.switchBranch(
        contactId: contactId,
        branchId: branchId,
      );
      if (snapshot == null) return false;
      final index = _contacts.indexWhere((item) => item.id == contactId);
      if (index >= 0) _contacts[index] = snapshot.contact;
      final all = snapshot.messages;
      final start =
          all.length > _messagePageSize ? all.length - _messagePageSize : 0;
      _messagesByContact[contactId] = List<Message>.from(all.skip(start));
      _loadedStartSequenceByContact[contactId] = start;
      _messageCountByContact[contactId] = all.length;
      _hasOlderMessagesByContact[contactId] = start > 0;
      _clearSnapshot();
      await _refreshTimeline(contactId);
      _error = null;
      return true;
    } catch (e) {
      _error = '切换分支失败：$e';
      return false;
    } finally {
      _isLoadingOlderMessages = false;
      notifyListeners();
    }
  }

  Future<bool> renameConversationBranch(String branchId, String name) async {
    final contactId = _selectedContactId;
    if (contactId == null || !_timelineUseCase.isAvailable) {
      return false;
    }
    try {
      await _timelineUseCase.renameBranch(branchId, name);
      await _refreshTimeline(contactId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = '重命名分支失败：$e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteConversationBranch(String branchId) async {
    final contactId = _selectedContactId;
    if (contactId == null || !_timelineUseCase.isAvailable) {
      return false;
    }
    try {
      await _timelineUseCase.deleteBranch(branchId);
      await _refreshTimeline(contactId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = '删除分支失败：$e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> setCheckpointKey(String checkpointId, bool isKey) async {
    final contactId = _selectedContactId;
    if (contactId == null || !_timelineUseCase.isAvailable) {
      return false;
    }
    try {
      await _timelineUseCase.setCheckpointKey(checkpointId, isKey);
      await _refreshTimeline(contactId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = '更新关键节点失败：$e';
      notifyListeners();
      return false;
    }
  }

  Future<void> _persistAll() {
    final paginated = _persistence;
    final contact = selectedContact;
    if (paginated is PaginatedChatPersistence && contact != null) {
      final paginatedStore = paginated as PaginatedChatPersistence;
      final messages = _messagesByContact[contact.id] ?? const <Message>[];
      _loadedStartSequenceByContact.putIfAbsent(contact.id, () => 0);
      _messageCountByContact[contact.id] = messages.length;
      _hasOlderMessagesByContact[contact.id] = false;
      return paginatedStore.saveConversationTail(
        contact: contact,
        startSequence: 0,
        messages: List<Message>.from(messages),
      );
    }
    return _persistence.replaceSnapshot(
      ChatSnapshot(
        contacts: List<Contact>.from(_contacts),
        messagesByContact: <String, List<Message>>{
          for (final entry in _messagesByContact.entries)
            entry.key: List<Message>.from(entry.value),
        },
      ),
    );
  }

  Future<void> _persistConversation(
    String contactId, {
    Map<String, String> metadataUpdates = const <String, String>{},
  }) {
    Contact? contact;
    for (final item in _contacts) {
      if (item.id == contactId) {
        contact = item;
        break;
      }
    }
    if (contact == null) return Future<void>.value();
    final messages = List<Message>.from(
      _messagesByContact[contactId] ?? const <Message>[],
    );
    final paginated = _persistence;
    if (paginated is PaginatedChatPersistence) {
      final paginatedStore = paginated as PaginatedChatPersistence;
      final startSequence = _loadedStartSequenceByContact[contactId] ?? 0;
      _messageCountByContact[contactId] = startSequence + messages.length;
      return paginatedStore.saveConversationTail(
        contact: contact,
        startSequence: startSequence,
        messages: messages,
        metadataUpdates: metadataUpdates,
      );
    }
    return _persistence.saveConversation(
      contact: contact,
      messages: messages,
      metadataUpdates: metadataUpdates,
    );
  }

  String _memoryRevisionKey(String contactId) =>
      'memory_revision_v1_$contactId';

  String _memoryLocksKey(String contactId) => 'memory_locks_v1_$contactId';

  Future<String> exportBackupJson() async {
    final snapshot = await _persistence.readSnapshot();
    final timeline = await _timelineUseCase.exportArchive();
    return _chatBackupCodec.encode(snapshot, timeline: timeline);
  }

  Future<bool> restoreBackupJson(String source) async {
    try {
      final bundle = _chatBackupCodec.decodeBundle(source);
      final restored = bundle.snapshot;
      final revisionContactIds = <String>{
        ..._contacts.map((contact) => contact.id),
        ...restored.contacts.map((contact) => contact.id),
      };
      await _persistence.replaceSnapshot(restored);
      await _timelineUseCase.restoreArchive(bundle.timeline);
      for (final contactId in revisionContactIds) {
        await _persistence.writeMetadata(_memoryRevisionKey(contactId), '');
      }
      _contacts
        ..clear()
        ..addAll(restored.contacts);
      _selectedContactId = _contacts.isEmpty ? null : _contacts.first.id;
      _messagesByContact.clear();
      _loadedStartSequenceByContact.clear();
      _messageCountByContact.clear();
      _hasOlderMessagesByContact.clear();
      _branchesByContact.clear();
      _checkpointsByContact.clear();
      final paginated = _persistence is PaginatedChatPersistence;
      for (final contact in restored.contacts) {
        final all = restored.messagesByContact[contact.id] ?? const <Message>[];
        _messageCountByContact[contact.id] = all.length;
        if (!paginated || contact.id == _selectedContactId) {
          final start = paginated && all.length > _messagePageSize
              ? all.length - _messagePageSize
              : 0;
          _messagesByContact[contact.id] = List<Message>.from(all.skip(start));
          _loadedStartSequenceByContact[contact.id] = start;
          _hasOlderMessagesByContact[contact.id] = start > 0;
        }
      }
      _lastMemoryRevisions.clear();
      _tempKeywordsByContact.clear();
      _clearSnapshot();
      _error = null;
      if (_selectedContactId != null) {
        await _refreshTimeline(_selectedContactId!);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = '恢复备份失败：$e';
      notifyListeners();
      return false;
    }
  }

  /// 保存API配置
  ///
  /// 同时更新内存状态和持久化存储（兼容旧的 apiKey/apiBaseUrl/apiModel 入口）
  Future<void> saveApiConfig({
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    final next = _providerSettings.copyWith(
      llm: _providerSettings.llm.copyWith(
        apiKey: apiKey.trim(),
        baseUrl: baseUrl.trim().isEmpty
            ? 'https://api.deepseek.com'
            : baseUrl.trim(),
        model: model.trim().isEmpty ? 'deepseek-chat' : model.trim(),
      ),
    );
    await saveProviderSettings(next);
  }

  /// 保存系统提示词
  Future<void> saveSystemPrompt(String prompt) async {
    _systemPrompt = prompt.trim();
    final settings = await _agentStore.readAgentSettings();
    settings['systemPrompt'] = _systemPrompt;
    await _agentStore.saveAgentSettings(settings);
    notifyListeners();
  }

  /// 切换调试模式
  ///
  /// 调试模式下会在聊天界面显示：
  /// - 关键词提取结果（本地提取和LLM提取）
  /// - 完整的系统Prompt
  void toggleDebugMode() {
    _isDebugMode = !isDebugMode;
    notifyListeners();
  }

  /// 刷新连接状态
  ///
  /// 手动触发重新连接检查
  void refreshConnection() {
    _heartbeat.markReconnecting();
  }

  // ==================== 联系人管理 ====================

  /// 选择联系人
  ///
  /// 切换当前活跃的聊天对象
  Future<void> selectContact(String contactId) async {
    if (_selectedContactId == contactId) return;
    if (!_contacts.any((c) => c.id == contactId)) return;
    _selectedContactId = contactId;
    _clearSnapshot();
    notifyListeners();
    if (!_messagesByContact.containsKey(contactId) &&
        _persistence is PaginatedChatPersistence) {
      _isLoadingOlderMessages = true;
      notifyListeners();
      try {
        await _loadInitialMessagePage(contactId);
        _error = null;
      } catch (e) {
        _error = '加载会话失败：$e';
        _messagesByContact[contactId] = <Message>[];
      } finally {
        _isLoadingOlderMessages = false;
        notifyListeners();
      }
    }
    try {
      await _refreshTimeline(contactId);
    } catch (e) {
      _error = '加载对话时间线失败：$e';
    }
    notifyListeners();
  }

  MemoryRevisionImpact? previewMemoryRevision(String eventNodeId) {
    final contact = selectedContact;
    if (contact == null) return null;
    try {
      return _memoryRevisionService.preview(contact.eventGraph, eventNodeId);
    } on ArgumentError {
      return null;
    }
  }

  bool isMemoryLocked(String eventNodeId) {
    final contactId = _selectedContactId;
    return contactId != null &&
        (_lockedMemoryNodeIds[contactId]?.contains(eventNodeId) ?? false);
  }

  Future<bool> setMemoryLocked(String eventNodeId, bool locked) async {
    final contact = selectedContact;
    if (contact == null || !memoryNodes.any((node) => node.id == eventNodeId)) {
      return false;
    }
    final locks =
        _lockedMemoryNodeIds.putIfAbsent(contact.id, () => <String>{});
    locked ? locks.add(eventNodeId) : locks.remove(eventNodeId);
    await _persistence.writeMetadata(
      _memoryLocksKey(contact.id),
      jsonEncode(locks.toList(growable: false)),
    );
    notifyListeners();
    return true;
  }

  Future<bool> deleteMemory(String eventNodeId) async {
    final contact = selectedContact;
    if (contact == null || isMemoryLocked(eventNodeId)) return false;
    final node =
        memoryNodes.where((item) => item.id == eventNodeId).firstOrNull;
    if (node == null) return false;
    final graph =
        _memoryGraphService.removeNode(contact.eventGraph, eventNodeId);
    final updated = contact.copyWith(
      eventGraph: graph,
      events: EventLruBucket(
        contact.events.items
            .where((event) => event.description != node.event.description)
            .toList(growable: false),
      ),
    );
    final index = _contacts.indexWhere((item) => item.id == contact.id);
    if (index < 0) return false;
    _contacts[index] = updated;
    await _persistConversation(contact.id);
    notifyListeners();
    return true;
  }

  Future<bool> reviseMemory(
    String eventNodeId,
    EventMemory revisedEvent,
  ) {
    return _applyMemoryRevision(
      eventNodeId: eventNodeId,
      revisedEvent: revisedEvent,
      invalidate: false,
    );
  }

  Future<bool> invalidateMemory(String eventNodeId) {
    if (isMemoryLocked(eventNodeId)) return Future<bool>.value(false);
    return _applyMemoryRevision(
      eventNodeId: eventNodeId,
      revisedEvent: const EventMemory(),
      invalidate: true,
    );
  }

  Future<bool> _applyMemoryRevision({
    required String eventNodeId,
    required EventMemory revisedEvent,
    required bool invalidate,
  }) async {
    final contact = selectedContact;
    if (contact == null) return false;
    try {
      final result = _memoryRevisionService.revise(
        graph: contact.eventGraph,
        eventNodeId: eventNodeId,
        revisedEvent: revisedEvent,
        revisionId: 'revision-${DateTime.now().microsecondsSinceEpoch}',
        invalidate: invalidate,
      );
      final previousDescription = result.record.previousNode.event.description;
      final retained = contact.events.items
          .where((event) => event.description != previousDescription)
          .toList(growable: false);
      final updated = contact.copyWith(
        eventGraph: result.graph,
        events: EventLruBucket(
          _dedupeEvents(<EventMemory>[
            ...retained,
            ..._flattenGraphEvents(result.graph),
          ]),
        ),
      );
      final index = _contacts.indexWhere((item) => item.id == contact.id);
      if (index < 0) return false;
      _contacts[index] = updated;
      _lastMemoryRevisions[contact.id] = result.record;
      await _persistConversation(
        contact.id,
        metadataUpdates: <String, String>{
          _memoryRevisionKey(contact.id): jsonEncode(result.record.toJson()),
        },
      );
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = '记忆修改失败：$e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> undoLastMemoryRevision() async {
    final contact = selectedContact;
    if (contact == null) return false;
    final record = _lastMemoryRevisions[contact.id];
    if (record == null) return false;
    try {
      final graph = _memoryRevisionService.undo(contact.eventGraph, record);
      final retained = contact.events.items
          .where((event) =>
              event.description != record.previousNode.event.description)
          .toList(growable: false);
      final updated = contact.copyWith(
        eventGraph: graph,
        events: EventLruBucket(
          _dedupeEvents(<EventMemory>[
            ...retained,
            ..._flattenGraphEvents(graph),
          ]),
        ),
      );
      final index = _contacts.indexWhere((item) => item.id == contact.id);
      if (index < 0) return false;
      _contacts[index] = updated;
      _lastMemoryRevisions.remove(contact.id);
      await _persistConversation(
        contact.id,
        metadataUpdates: <String, String>{
          _memoryRevisionKey(contact.id): '',
        },
      );
      _error = null;
      notifyListeners();
      return true;
    } on StateError {
      _error = '已有新对话，无法撤销这次记忆修改';
      notifyListeners();
      return false;
    } catch (e) {
      _error = '撤销记忆修改失败：$e';
      notifyListeners();
      return false;
    }
  }

  Map<String, int> get memoryStats {
    final contact = selectedContact;
    if (contact == null) return <String, int>{};
    final graph = contact.eventGraph;
    final allNodes = <EventNode>[
      ...graph.shortTermQueue,
      ...graph.longTermQueue,
      ...graph.ultraLongTermQueue,
    ];
    final contactId = contact.id;
    final locks = _lockedMemoryNodeIds[contactId] ?? const <String>{};
    return <String, int>{
      'shortTerm': graph.shortTermQueue.length,
      'longTerm': graph.longTermQueue.length,
      'ultraLongTerm': graph.ultraLongTermQueue.length,
      'edges': graph.edges.length,
      'locked': locks.length,
      'invalidated': allNodes.where((n) => n.invalidated).length,
      'needsReview': allNodes.where((n) => n.needsReview).length,
      'total': allNodes.length,
    };
  }

  String? memorySourceMessageId(String eventNodeId) {
    final contact = selectedContact;
    if (contact == null) return null;
    final node = memoryNodes.where((n) => n.id == eventNodeId).firstOrNull;
    if (node == null) return null;
    final source = node.event.sourceDialog;
    if (source.isEmpty) return null;
    const userLine = '用户：';
    const aiLine = 'AI：';
    final userIdx = source.indexOf(userLine);
    final aiIdx = source.indexOf(aiLine, userIdx + 1);
    if (userIdx < 0 || aiIdx < 0) return null;
    final userContent = source.substring(userIdx + userLine.length, aiIdx).trim();
    final messages = _messagesByContact[contact.id] ?? const <Message>[];
    for (final msg in messages.reversed) {
      if (msg.content.contains(userContent)) return msg.id;
    }
    return null;
  }

  /// 记忆召回调试信息
  Map<String, dynamic> memoryRecallDebugInfo(String eventNodeId) {
    final contact = selectedContact;
    if (contact == null) return <String, dynamic>{};
    final graph = contact.eventGraph;
    final node = memoryNodes.where((n) => n.id == eventNodeId).firstOrNull;
    if (node == null) return <String, dynamic>{};

    final incidentEdges = graph.edges.values
        .where((e) => e.fromNodeId == eventNodeId || e.toNodeId == eventNodeId)
        .toList(growable: false);

    final neighborIds = <String>{};
    final edgeDetails = <Map<String, String>>[];
    for (final edge in incidentEdges) {
      final otherId = edge.fromNodeId == eventNodeId ? edge.toNodeId : edge.fromNodeId;
      neighborIds.add(otherId);
      edgeDetails.add(<String, String>{
        'direction': '${edge.fromNodeId} → ${edge.toNodeId}',
        'otherId': otherId,
      });
    }

    final neighbors = <Map<String, String>>[];
    for (final nid in neighborIds) {
      final n = memoryNodes.where((n) => n.id == nid).firstOrNull;
      if (n != null) {
        neighbors.add(<String, String>{
          'id': n.id,
          'description': n.event.description.length > 80
              ? '${n.event.description.substring(0, 80)}...'
              : n.event.description,
          'tier': n.tier.name,
        });
      }
    }

    return <String, dynamic>{
      'nodeId': eventNodeId,
      'description': node.event.description,
      'tier': node.tier.name,
      'keywords': node.event.keywords,
      'theme': node.event.theme,
      'createdAt': DateTime.fromMillisecondsSinceEpoch(node.createdAtMs)
          .toIso8601String(),
      'summarized': node.summarized,
      'invalidated': node.invalidated,
      'needsReview': node.needsReview,
      'edgeCount': incidentEdges.length,
      'edges': edgeDetails,
      'neighbors': neighbors,
      'belongingQueues': <String, List<String>>{
        for (final entry in graph.belongingEventQueues.entries)
          if (entry.value.contains(eventNodeId)) entry.key: entry.value,
      },
      'settingQueues': <String, List<String>>{
        for (final entry in graph.settingEventQueues.entries)
          if (entry.value.contains(eventNodeId)) entry.key: entry.value,
      },
    };
  }

  /// 更新当前联系人的世界书
  void updateWorldBook(WorldBook book) {
    final contact = selectedContact;
    if (contact == null) return;
    final updated = contact.copyWith(worldBook: book);
    final index = _contacts.indexWhere((c) => c.id == contact.id);
    if (index >= 0) {
      _contacts[index] = updated;
      notifyListeners();
    }
  }

  /// 添加新联系人
  ///
  /// 创建联系人并自动选中新联系人
  /// 返回是否添加成功（失败原因：名称为空）
  Future<bool> addContact({
    required String name,
    String? contactId,
    required String avatar,
    String fixedInput = '',
    Map<String, String> currentStates = const <String, String>{},
    List<String> personality = const <String>[],
    List<String> appearance = const <String>[],
    List<String> personalInfo = const <String>[],
    List<Map<String, dynamic>> settings = const <Map<String, dynamic>>[],
    List<String> backgroundStory = const <String>[],
    List<String> narrativeRules = const <String>[],
    List<String> otherCharacteristics = const <String>[],
    ContactCategory category = ContactCategory.contact,
    String voice = '',
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return false;

    // 自动生成唯一ID
    final normalizedId = contactId?.trim().isNotEmpty == true
        ? contactId!.trim()
        : _generateUniqueId(category);

    // 如果提供的ID已存在，自动生成新的
    if (_contacts.any((e) => e.id == normalizedId)) {
      return false;
    }

    final contact = Contact(
      id: normalizedId,
      name: normalizedName,
      avatar: avatar.trim(),
      fixedInput: fixedInput.trim(),
      currentStates: _normalizeStateMap(currentStates),
      personality: personality,
      appearance: appearance,
      personalInfo: personalInfo,
      settings: settings,
      backgroundStory: backgroundStory,
      narrativeRules: narrativeRules,
      otherCharacteristics: otherCharacteristics,
      keywordLibrary:
          _extractLocalKeywords('$normalizedName ${fixedInput.trim()}')
              .toList(),
      category: category,
      voice: voice,
      createdAt: DateTime.now(),
    );
    _contacts.add(contact);
    _messagesByContact.putIfAbsent(contact.id, () => <Message>[]);
    _loadedStartSequenceByContact[contact.id] = 0;
    _messageCountByContact[contact.id] = 0;
    _hasOlderMessagesByContact[contact.id] = false;
    _selectedContactId = contact.id;
    await _persistAll();
    notifyListeners();
    return true;
  }

  /// 从 JSON 创建联系人
  ///
  /// JSON 格式示例（角色）：
  /// ```json
  /// {
  ///   "id": "character-001",
  ///   "name": "角色名称",
  ///   "avatar": "⭐",
  ///   "personality": ["直接", "理性", "冷静"],
  ///   "appearance": ["黑色外套", "短发"],
  ///   "personalInfo": ["职业：侦探", "年龄：28岁"],
  ///   "backgroundStory": ["背景故事"],
  ///   "narrativeRules": ["说话简洁", "不使用表情符号"],
  ///   "otherCharacteristics": ["喜欢咖啡", "讨厌雨天"],
  ///   "worldKnowledge": ["世界观知识"],
  ///   "selfKnowledge": ["自我认知"],
  ///   "userKnowledge": ["对用户的了解"],
  ///   "belongings": ["物品"],
  ///   "status": ["健康"],
  ///   "mood": "专注",
  ///   "time": "晚上8点"
  /// }
  /// ```
  ///
  /// JSON 格式示例（故事模式）：
  /// ```json
  /// {
  ///   "id": "story-001",
  ///   "name": "魔法大陆",
  ///   "avatar": "🏰",
  ///   "personality": ["奇幻", "冒险", "史诗"],
  ///   "backgroundStory": [
  ///     "一个充满魔法的世界，魔法石是能量的来源",
  ///     "千年前的大战导致了魔法的衰落",
  ///     "如今魔法师们正在寻找失落的魔法石"
  ///   ],
  ///   "settings": [
  ///     {"key": "魔法系统", "value": "这片大陆的魔法基于魔法石的能量，不同颜色的魔法石代表不同属性的魔法", "relate": ["魔法石", "能量", "法术", "属性"]},
  ///     {"key": "魔法师", "value": "能够激发魔法石能量的人，分为初级、中级、高级三个等级", "relate": ["魔法", "魔法石", "施法者", "等级"]},
  ///     {"key": "魔法石", "value": "稀有的能量结晶，分布在危险的古遗迹中", "relate": ["魔法", "能量", "遗迹"]}
  ///   ],
  ///   "narrativeRules": [
  ///     "用细腻的描写代替概括性叙述",
  ///     "多使用感官细节，描写视觉、听觉、嗅觉",
  ///     "保持第三人称叙事视角",
  ///     "每次续写控制在300-500字"
  ///   ],
  ///   "otherCharacteristics": [
  ///     "故事基调：神秘而充满希望",
  ///     "主要冲突：魔法师与掠夺者的对抗",
  ///     "主题：勇气、友谊、自我发现"
  ///   ],
  ///   "worldKnowledge": [
  ///     "大陆分为东西南北四个王国",
  ///     "每个王国都有独特的魔法传统",
  ///     "魔法学院是培养魔法师的圣地"
  ///   ],
  ///   "selfKnowledge": [
  ///     "主角是一个天赋异禀的年轻魔法师",
  ///     "主角对自己的能力还不够自信",
  ///     "主角渴望证明自己的价值"
  ///   ],
  ///   "userKnowledge": [
  ///     "用户是故事的引导者，决定故事走向",
  ///     "用户的输入代表故事的发展方向"
  ///   ],
  ///   "belongings": ["魔法石碎片", "古老卷轴", "魔法师法杖"],
  ///   "status": ["故事进行中", "主角刚刚踏上旅程"],
  ///   "mood": "神秘而充满期待",
  ///   "time": "清晨，太阳刚刚升起"
  /// }
  /// ```
  ///
  /// 返回是否创建成功（失败原因：名称为空或JSON解析失败）
  /// 注意：如果 JSON 中没有提供 id，会自动生成唯一 id
  Future<bool> addContactFromJson(
    String jsonString, {
    ContactCategory category = ContactCategory.contact,
  }) async {
    final data = _contactImportParser.parse(jsonString);
    if (data == null) return false;
    return _persistImportedContact(
      data,
      category: category,
      useRequestedId: true,
    );
  }

  /// 从 JSON 创建联系人，支持后备字段合并
  ///
  /// 当 JSON 中缺少某些字段时，使用后备字段填充
  /// 适用于 JSON 模式和自然语言模式，允许用户先在表单填写部分信息
  /// 注意：id 会自动生成，不需要提供
  Future<bool> addContactFromJsonWithFallback(
    String jsonString, {
    ContactCategory category = ContactCategory.contact,
    String? fallbackName,
    String? fallbackAvatar,
    String? fallbackFixedInput,
    Map<String, String>? fallbackCurrentStates,
    String fallbackVoice = '',
  }) async {
    final data = _contactImportParser.parse(
      jsonString,
      fallback: ContactImportFallback(
        name: fallbackName ?? '',
        avatar: fallbackAvatar ?? '',
        fixedInput: fallbackFixedInput ?? '',
        currentStates: fallbackCurrentStates ?? const <String, String>{},
        voice: fallbackVoice,
      ),
    );
    if (data == null) return false;
    return _persistImportedContact(
      data,
      category: category,
      useRequestedId: false,
    );
  }

  Future<bool> _persistImportedContact(
    ContactImportData data, {
    required ContactCategory category,
    required bool useRequestedId,
  }) async {
    var id = useRequestedId ? data.requestedId : '';
    if (id.isEmpty || _contacts.any((contact) => contact.id == id)) {
      id = _generateUniqueId(category);
    }
    while (_contacts.any((contact) => contact.id == id)) {
      id = _generateUniqueId(category);
    }
    final contact = data.toContact(
      id: id,
      category: category,
      keywordLibrary:
          _extractLocalKeywords('${data.name} ${data.fixedInput}').toList(),
      createdAt: DateTime.now(),
    );
    _contacts.add(contact);
    _messagesByContact.putIfAbsent(contact.id, () => <Message>[]);
    _loadedStartSequenceByContact[contact.id] = 0;
    _messageCountByContact[contact.id] = 0;
    _hasOlderMessagesByContact[contact.id] = false;
    _selectedContactId = contact.id;
    await _persistAll();
    notifyListeners();
    return true;
  }

  /// 删除联系人
  ///
  /// 删除指定 ID 的联系人及其所有消息记录
  /// 同时删除关联的向量记忆数据，与事件队列同步清理
  /// 如果删除的是当前选中的联系人，会自动切换到其他联系人或清空选择
  /// 返回是否删除成功（失败原因：联系人不存在）
  Future<bool> deleteContact(String contactId) async {
    final index = _contacts.indexWhere((c) => c.id == contactId);
    if (index == -1) return false;

    // 从列表中移除
    _contacts.removeAt(index);

    // 删除关联的消息记录
    _messagesByContact.remove(contactId);
    _loadedStartSequenceByContact.remove(contactId);
    _messageCountByContact.remove(contactId);
    _hasOlderMessagesByContact.remove(contactId);
    _branchesByContact.remove(contactId);
    _checkpointsByContact.remove(contactId);

    // 如果删除的是当前选中的联系人，更新选中状态
    if (_selectedContactId == contactId) {
      if (_contacts.isNotEmpty) {
        _selectedContactId = _contacts.first.id;
      } else {
        _selectedContactId = null;
      }
    }

    // SQLite 外键级联删除该联系人的消息与事件图。
    await _persistence.deleteConversation(contactId);
    final selectedId = _selectedContactId;
    if (selectedId != null &&
        !_messagesByContact.containsKey(selectedId) &&
        _persistence is PaginatedChatPersistence) {
      await _loadInitialMessagePage(selectedId);
    }
    if (selectedId != null) await _refreshTimeline(selectedId);

    notifyListeners();
    return true;
  }

  /// 将自然语言描述转换为角色或故事 JSON
  ///
  /// 使用 LLM 将用户的自然语言描述转换为标准的 JSON 格式
  /// 如果转换失败，返回 null
  ///
  /// [naturalLanguage] 自然语言描述，例如：
  /// 角色："创建一个名叫小明的侦探，性格理性冷静，穿着黑色外套"
  /// 故事："创建一个魔法世界的故事，包含魔法师、魔法石等元素"
  /// [isStory] 是否为故事类型（true=故事，false=角色）
  Future<String?> convertNaturalLanguageToJson(
    String naturalLanguage, {
    bool isStory = false,
  }) async {
    if (naturalLanguage.trim().isEmpty) return null;

    if (DateTime.now().microsecondsSinceEpoch >= 0) {
      final typeLabel = isStory ? '故事' : '角色';
      final systemPrompt = '''
你是一个$typeLabel创建 JSON 格式化助手。
请把用户的自然语言描述转换为创建对象用的 JSON，只输出 JSON，不要输出解释。

必须包含字段：
- name: $typeLabel名称，不能为空
- avatar: 一个 emoji 或简短符号，可以为空字符串
- fixedInput: 每轮对话固定输入给 LLM 的提示词
- currentStates: 对象，key 是用户要求记录的状态名，value 初始为空字符串或描述中明确给出的初始值

不要输出 personality、appearance、backgroundStory、settings、status、mood、time 等旧预设字段。

示例：
{
  "name": "$typeLabel名称",
  "avatar": "★",
  "fixedInput": "你是...",
  "currentStates": {
    "好感度": "",
    "当前位置": ""
  }
}
''';

      try {
        final response = await _repository.aiService.ask(
          '$systemPrompt\n\n用户描述：\n$naturalLanguage',
          contactId: 'system-nlp-to-json',
          contactName: 'System',
          profile: _providerSettings.llm,
        );
        final jsonStr = _extractJsonFromResponse(response);
        if (jsonStr == null || jsonStr.isEmpty) return null;

        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        final name = (json['name'] ?? '').toString().trim();
        if (name.isEmpty) return null;
        return jsonStr;
      } catch (e) {
        debugPrint('convertNaturalLanguageToJson failed: $e');
        return null;
      }
    }

    final systemPrompt = isStory
        ? '''你是一个json格式化助手。请将用户的自然语言理解扩充后描述转换为标准的 JSON 格式。

必须包含的字段：
- id: 使用小写字母、数字和连字符，如 "story-001"
- name: 故事名称

可选字段（根据描述提取，没有则留空或空数组）：
- avatar: 一个 emoji 或简短符号作为头像
- personality: 故事风格标签数组，如 ["奇幻", "冒险"]
- backgroundStory: 背景概述数组
- settings: 故事设定数组，每个设定包含 key（设定名称）、value（设定描述）和 relate（关联关键词数组），如 [{"key":"魔法","value":"基于魔法石的能量","relate":["魔法石","能量"]},{"key":"魔法师","value":"能够激发魔法石的人","relate":["魔法","魔法石"]}]

输出要求：
1. 只输出纯 JSON，不要包含任何解释文字
2. 如果描述中缺少某些信息，使用空字符串或空数组
3. name 不能为空
4. settings 中的 relate 字段用于关联搜索，应包含与设定相关的关键词
5. 各个字段应该尽可能在不改变原意的前提下充实信息

示例输出：
{"id":"magic-world-001","name":"魔法大陆","avatar":"🏰","personality":["奇幻","冒险"],"backgroundStory":["一个充满魔法的世界","魔法石是能量的来源"],"settings":[{"key":"魔法","value":"这片大陆的魔法基于魔法石","relate":["魔法石","能量","法术"]},{"key":"魔法师","value":"能够激发魔法石能量的人","relate":["魔法","魔法石","施法者"]}]}
'''
        : '''你是一个角色创建助手。请将用户的自然语言描述转换为标准的 JSON 格式。

必须包含的字段：
- id: 使用小写字母、数字和连字符，如 "character-001"
- name: 角色名称

可选字段（根据描述提取，没有则留空或空数组）：
- avatar: 一个 emoji 或简短符号作为头像
- personality: 性格特点数组，如 ["理性", "冷静"]
- appearance: 外貌特征数组，如 ["黑色外套", "短发"]
- backgroundStory: 背景故事数组
- worldKnowledge: 世界观知识数组
- selfKnowledge: 自我认知数组
- userKnowledge: 对用户的了解数组
- belongings: 物品持有数组
- status: 身体状态数组
- mood: 当前情绪
- time: 当前时间


''';

    try {
      // 使用 AI 服务进行转换
      final response = await _repository.aiService.ask(
        '$systemPrompt\n\n用户描述：\n$naturalLanguage',
        contactId: 'system-nlp-to-json',
        contactName: 'System',
        profile: _providerSettings.llm,
      );

      // 尝试从响应中提取 JSON
      final jsonStr = _extractJsonFromResponse(response);
      if (jsonStr == null || jsonStr.isEmpty) {
        debugPrint('Failed to extract JSON from LLM response');
        return null;
      }

      // 验证 JSON 是否有效
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final id = (json['id'] ?? '').toString().trim();
      final name = (json['name'] ?? '').toString().trim();

      if (id.isEmpty || name.isEmpty) {
        debugPrint('LLM generated JSON missing required fields (id/name)');
        return null;
      }

      return jsonStr;
    } catch (e) {
      debugPrint('convertNaturalLanguageToJson failed: $e');
      return null;
    }
  }

  /// 从 LLM 响应中提取 JSON 字符串
  String? _extractJsonFromResponse(String response) {
    // 尝试直接解析整个响应
    final trimmed = response.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed;
    }

    // 尝试从代码块中提取
    final codeBlockReg =
        RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false);
    final codeMatch = codeBlockReg.firstMatch(response);
    if (codeMatch != null) {
      final content = codeMatch.group(1)?.trim() ?? '';
      if (content.startsWith('{') && content.endsWith('}')) {
        return content;
      }
    }

    // 尝试找到第一个 { 和最后一个 }
    final startIndex = response.indexOf('{');
    final endIndex = response.lastIndexOf('}');
    if (startIndex != -1 && endIndex != -1 && startIndex < endIndex) {
      return response.substring(startIndex, endIndex + 1);
    }

    return null;
  }

  // ==================== 消息发送核心流程 ====================

  /// 发送消息
  ///
  /// 完整的消息处理流程：
  /// 1. 验证输入并创建用户消息
  /// 2. 提取关键词（本地 + LLM）
  /// 3. 构建系统Prompt（基础提示 + 联系人信息）
  /// 4. 发送请求到AI服务
  /// 5. 解析响应并提取回复内容
  /// 6. 更新联系人记忆（memoryPatch）
  /// 7. 触发事件总结（如达到阈值）
  Future<void> sendMessage(String rawInput) async {
    // 检查API Key是否已设置
    if (!llmProfiles.any((profile) => profile.hasApiKey)) {
      _error = '请先设置 API Key';
      notifyListeners();
      return;
    }

    final selected = selectedContact;
    if (selected == null) {
      _error = AppStrings.noContact;
      notifyListeners();
      return;
    }

    // 格式化输入
    final input = _formatter.normalize(rawInput);
    if (input.isEmpty || isLoading) return;

    final generationCancellation = Completer<void>();
    _generationCancellation = generationCancellation;

    // ===== 保存快照（在修改任何状态前）=====
    _saveSnapshot(selected);

    // 创建用户消息
    final userMessage = Message(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.user,
      content: input,
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );
    final currentList =
        _messagesByContact.putIfAbsent(selected.id, () => <Message>[]);
    currentList.add(userMessage);
    await _persistConversation(selected.id);

    // 设置加载状态
    _isLoading = true;
    _isTyping = true;
    _generationStatus = ChatGenerationStatus.preparing;
    _error = null;
    notifyListeners();

    String? streamingMessageId;
    try {
      final currentContact = selectedContact;
      if (currentContact == null) {
        _error = AppStrings.noContact;
        notifyListeners();
        return;
      }

      // 助手类型：走 opencode CLI 流程
      if (currentContact.category == ContactCategory.assistant) {
        await _sendAssistantMessage(
          currentContact,
          userMessage,
          input: input,
        );
        return;
      }

      // 步骤1: 提取关键词（提供往期关键词库）
      final keywords = await _extractTurnKeywords(
        contactId: selected.id,
        contactName: selected.name,
        userInput: userMessage.content,
        existingKeywordLibrary: currentContact.keywordLibrary,
        existingThemeLibrary: currentContact.themeLibrary,
      );

      // 步骤2: 构建Prompt联系人（包含筛选后的事件和知识）
      final promptContext = _buildPromptContact(
        currentContact,
        inputKeywords: keywords.mergedKeywords,
      );
      final promptContact = promptContext.contact;

      // 两级级联独立判断，固定优先 1→2（短→长），避免同轮压缩两层。
      final cascadeDecision = _memoryCascadePolicy.evaluate(
        graph: currentContact.eventGraph,
        shortTermThreshold: _summaryThreshold,
        longTermThreshold: _ultraSummaryThreshold,
      );
      final needSummary = cascadeDecision.needsSummary;
      final summarySourceTier = cascadeDecision.sourceTier;
      final pendingSummaryEvents = cascadeDecision.pendingEvents;

      // 步骤3: 合并系统Prompt
      final systemPrompt = _mergeSystemPromptWithContact(
        basePrompt: _systemPrompt,
        contact: promptContact,
        needSummary: needSummary,
        pendingSummaryEvents: pendingSummaryEvents,
      );

      // 调试模式：显示关键词和完整Prompt
      if (isDebugMode) {
        final composer = StructuredInputPromptComposer(settings: _appSettings);
        final structured = composer.composeStructuredOutputPrompt(
          userInput: userMessage.content,
          systemPrompt: systemPrompt,
          outputSchema: ChatRepository.outputSchema,
        );
        currentList.add(
          Message(
            id: 'debug-${DateTime.now().microsecondsSinceEpoch}',
            role: MessageRole.user,
            content: '【调试信息】关键词提取\n'
                '本地(JSON): ${jsonEncode({
                  "keywords": keywords.localKeywords
                })}\n'
                'LLM(JSON): ${jsonEncode({"keywords": keywords.llmKeywords})}\n'
                '合并(JSON): ${jsonEncode({
                  "keywords": keywords.mergedKeywords
                })}\n\n'
                '【调试信息】完整 Prompt\n$structured',
            createdAt: DateTime.now(),
          ),
        );
        await _persistConversation(selected.id);
      }

      // 步骤5: 发送AI请求
      final Message reply;
      if (_providerSettings.llm.parameters.stream) {
        streamingMessageId =
            'assistant-${DateTime.now().microsecondsSinceEpoch}';
        final raw = StringBuffer();
        final throttle = Stopwatch()..start();
        await _consumeGenerationStream(
          _streamRoleplayWithFallback(
            contact: selected,
            userMessage: userMessage,
            systemPrompt: systemPrompt,
          ),
          (chunk) {
            raw.write(chunk);
            final partial =
                StructuredOutputRegexParser.extractPartialReply(raw.toString());
            if (partial == null || partial.isEmpty) return;
            final index = currentList.indexWhere(
              (message) => message.id == streamingMessageId,
            );
            final draft = Message(
              id: streamingMessageId!,
              role: MessageRole.assistant,
              content: partial,
              createdAt: DateTime.now(),
              status: MessageStatus.sending,
            );
            if (index < 0) {
              currentList.add(draft);
            } else {
              currentList[index] = draft;
            }
            _generationStatus = ChatGenerationStatus.streaming;
            _isTyping = false;
            if (throttle.elapsedMilliseconds >= 32) {
              throttle.reset();
              notifyListeners();
            }
          },
        );
        final rawReply = raw.toString();
        if (rawReply.trim().isEmpty) {
          throw const AiServiceException('模型返回了空的流式响应。');
        }
        reply = Message(
          id: streamingMessageId,
          role: MessageRole.assistant,
          content: rawReply,
          createdAt: DateTime.now(),
        );
      } else {
        reply = await _askRoleplayWithFallback(
          contact: selected,
          userMessage: userMessage,
          systemPrompt: systemPrompt,
        );
      }

      // 更新用户消息状态为已发送
      _updateMessageStatus(selected.id, userMessage.id, MessageStatus.sent);

      // 步骤6: 提取回复内容（从JSON中提取reply字段）
      final String? replyContent =
          StructuredOutputRegexParser.extractReply(reply.content) ??
              // LLM 没返回标准 JSON（直接吐纯文本）时，AiService 已把整段当 reply
              // 返回了，但这里 extractReply 还是解析不出 reply 字段，所以再退一步：
              // 把 AiService 给的 content 整段当作可见内容展示，至少用户能看到 LLM 说啥
              (reply.content.trim().isEmpty ? null : reply.content.trim());

      // 检查是否成功提取到回复内容
      if (replyContent == null) {
        _generationStatus = ChatGenerationStatus.failure;
        // 如果提取失败，可能是AI返回了错误消息
        _error = 'AI 回复格式错误，请稍后重试';
        if (isDebugMode) {
          currentList.add(
            Message(
              id: 'debug-raw-${DateTime.now().microsecondsSinceEpoch}',
              role: MessageRole.user,
              content: '【调试信息】LLM 原生输出（格式异常，无法解析）\n${reply.content}',
              createdAt: DateTime.now(),
            ),
          );
          await _persistConversation(selected.id);
        }
        _updateMessageStatus(selected.id, userMessage.id, MessageStatus.failed);
        await _persistConversation(selected.id);
        return;
      }

      final completedReply = Message(
        id: reply.id,
        role: reply.role,
        content: replyContent,
        createdAt: reply.createdAt,
      );
      final streamedIndex =
          currentList.indexWhere((message) => message.id == reply.id);
      if (streamedIndex < 0) {
        currentList.add(completedReply);
      } else {
        currentList[streamedIndex] = completedReply;
      }

      // 调试模式：显示 LLM 原生输出
      if (isDebugMode) {
        currentList.add(
          Message(
            id: 'debug-raw-${DateTime.now().microsecondsSinceEpoch}',
            role: MessageRole.user,
            content: '【调试信息】LLM 原生输出\n${reply.content}',
            createdAt: DateTime.now(),
          ),
        );
      }

      // 步骤7: 更新联系人记忆
      await _updateContactFromMemoryPatch(
        selected,
        reply.content,
        userInput: input,
        inputKeywords: keywords.mergedKeywords,
        promptEventNodeIds: promptContext.eventNodeIds,
        summarySourceTier: summarySourceTier,
      );
      await _createCompletedTurnCheckpoint(selected.id, reply.id);
      _generationStatus = ChatGenerationStatus.completed;
    } on _GenerationCancelled {
      _error = null;
      _generationStatus = ChatGenerationStatus.cancelled;
      _updateMessageStatus(
          selected.id, userMessage.id, MessageStatus.cancelled);
      if (streamingMessageId != null) {
        _updateMessageStatus(
          selected.id,
          streamingMessageId,
          MessageStatus.cancelled,
        );
      }
      await _rollbackMemoryOnFailure(selected.id);
    } on AiServiceException catch (e) {
      _generationStatus = ChatGenerationStatus.failure;
      _error = e.userMessage;
      _updateMessageStatus(selected.id, userMessage.id, MessageStatus.failed);
      _heartbeat.markReconnecting();
      // 调试模式：把 LLM 原生响应附在最后一条用户消息后面，
      // 即使抛了"格式异常"也能看到 LLM 到底吐了什么。
      if (isDebugMode && e.rawResponse != null) {
        final currentList = _messagesByContact[selected.id] ?? <Message>[];
        currentList.add(
          Message(
            id: 'debug-raw-${DateTime.now().microsecondsSinceEpoch}',
            role: MessageRole.user,
            content: '【调试信息】LLM 原生输出（请求失败：${e.userMessage}）\n${e.rawResponse}',
            createdAt: DateTime.now(),
          ),
        );
      }
      // 发送失败时回退记忆状态，但保留消息列表显示
      await _rollbackMemoryOnFailure(selected.id);
    } catch (e, st) {
      _generationStatus = ChatGenerationStatus.failure;
      debugPrint('sendMessage failed: $e');
      debugPrint('$st');
      final raw = e.toString().trim();
      _error = raw.isEmpty ? AppStrings.networkError : '请求失败：$raw';
      _updateMessageStatus(selected.id, userMessage.id, MessageStatus.failed);
      _heartbeat.markReconnecting();
      // 发送失败时回退记忆状态，但保留消息列表显示
      await _rollbackMemoryOnFailure(selected.id);
    } finally {
      if (identical(_generationCancellation, generationCancellation)) {
        _generationCancellation = null;
        _isLoading = false;
        _isTyping = false;
      }
      notifyListeners();
    }
  }

  /// 助手类型消息发送流程
  ///
  /// 流程：
  /// 1. 将用户输入原封不动转发给 opencode
  /// 2. opencode 同步返回 AI 响应文本
  /// 3. 跟"角色"流程一样，用 [StructuredOutputRegexParser.extractReply] 把
  ///    opencode 输出里的 `reply` 字段"转义"出来
  /// 4. 没解析到 reply 字段时退回到原始输出
  /// 5. 余下的渲染、保存、通知 UI 等流程与"角色"流程保持一致
  /// 6. 若服务自动分配/更新了 sessionId，把它持久化下来
  ///
  /// 注意：opencode 自带上下文管理，因此这里不跑角色扮演的记忆图
  /// （eventGraph、memoryPatch、关键词等只对"角色"/"故事"类型有意义）
  Future<void> _sendAssistantMessage(
    Contact contact,
    Message userMessage, {
    required String input,
  }) async {
    final currentList = _messagesByContact[contact.id] ?? <Message>[];

    // 1. 转发给 opencode
    final result = await _awaitGeneration(_opencodeService.execute(input));

    // 2. 处理结果：成功就拿到 raw 文本，失败就显示错误
    final String rawOutput;
    if (result.success) {
      rawOutput = result.output;
    } else {
      rawOutput = '指令执行失败：${result.error ?? "未知错误"}';
    }

    // 3. 跟"角色"流程一致：尝试从响应里解析 `reply` 字段
    //    opencode 一般返回纯文本/Markdown，这里解析不到时直接用原始输出
    final escaped = StructuredOutputRegexParser.extractReply(rawOutput);
    final finalReply =
        (escaped != null && escaped.isNotEmpty) ? escaped : rawOutput;

    currentList.add(Message(
      id: 'assistant-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      content: finalReply,
      createdAt: DateTime.now(),
    ));

    _updateMessageStatus(contact.id, userMessage.id, MessageStatus.sent);
    await _persistConversation(contact.id);
    await _createCompletedTurnCheckpoint(contact.id, currentList.last.id);
    _generationStatus = ChatGenerationStatus.completed;

    // 4. 若 service 自动选了 sessionId，持久化下来
    final currentSession = _opencodeService.config.sessionId;
    if (currentSession.isNotEmpty &&
        currentSession != opencodeConfig.sessionId) {
      await saveOpencodeConfig(
          opencodeConfig.copyWith(sessionId: currentSession));
    }

    _isLoading = false;
    _isTyping = false;
    notifyListeners();
  }

  /// 重新发送消息
  ///
  /// 当消息发送失败时，用户可以点击重试
  Future<void> resendMessage(String contactId, String messageId) async {
    final messages = _messagesByContact[contactId];
    if (messages == null) return;

    final messageIndex = messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    final message = messages[messageIndex];
    if (message.role != MessageRole.user ||
        message.status != MessageStatus.failed) {
      return;
    }

    // 移除失败的消息，避免重复
    messages.removeAt(messageIndex);
    await _persistConversation(contactId);
    notifyListeners();

    // 重新发送
    await sendMessage(message.content);
  }

  Future<bool> editMessage(String messageId, String content) async {
    final contactId = _selectedContactId;
    final normalized = content.trim();
    if (contactId == null || normalized.isEmpty || isLoading) return false;
    final messages = _messagesByContact[contactId];
    final index =
        messages?.indexWhere((message) => message.id == messageId) ?? -1;
    if (messages == null || index < 0) return false;
    messages[index] = messages[index].copyWith(content: normalized);
    await _persistConversation(contactId);
    notifyListeners();
    return true;
  }

  Future<bool> deleteMessage(String messageId) async {
    final contactId = _selectedContactId;
    if (contactId == null || isLoading) return false;
    final messages = _messagesByContact[contactId];
    final index =
        messages?.indexWhere((message) => message.id == messageId) ?? -1;
    if (messages == null || index < 0) return false;
    messages.removeAt(index);
    await _persistConversation(contactId);
    notifyListeners();
    return true;
  }

  Future<bool> generateReplyCandidate(String messageId) async {
    final contact = selectedContact;
    final messages = contact == null ? null : _messagesByContact[contact.id];
    final index =
        messages?.indexWhere((message) => message.id == messageId) ?? -1;
    if (contact == null || messages == null || index < 0 || isLoading) {
      return false;
    }
    final contextStart = index > 7 ? index - 7 : 0;
    final context = messages
        .sublist(contextStart, index + 1)
        .map((message) =>
            '${message.role == MessageRole.user ? "用户" : "AI"}：${message.content}')
        .join('\n');
    try {
      final raw = await _repository.askUtility(
        contactId: contact.id,
        contactName: contact.name,
        profile: _providerSettings.llm,
        prompt: '根据以下上下文，为最后一条消息生成一个不同措辞、逻辑连贯的 AI 候选回复。'
            '只输出候选回复正文，不要解释。\n\n$context',
      );
      final candidate =
          StructuredOutputRegexParser.extractReply(raw) ?? raw.trim();
      if (candidate.isEmpty || candidate == messages[index].content) {
        return false;
      }
      messages[index] = messages[index].copyWith(
        alternatives: <String>{
          ...messages[index].alternatives,
          candidate,
        }.toList(growable: false),
      );
      await _persistConversation(contact.id);
      notifyListeners();
      return true;
    } catch (error) {
      _error = '生成候选回复失败：$error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> applyReplyCandidate(String messageId, String candidate) async {
    final contactId = _selectedContactId;
    final messages = contactId == null ? null : _messagesByContact[contactId];
    final index =
        messages?.indexWhere((message) => message.id == messageId) ?? -1;
    if (contactId == null || messages == null || index < 0 || isLoading) {
      return false;
    }
    final current = messages[index];
    if (!current.alternatives.contains(candidate)) return false;
    messages[index] = current.copyWith(
      content: candidate,
      alternatives: <String>{
        ...current.alternatives.where((value) => value != candidate),
        current.content,
      }.toList(growable: false),
    );
    await _persistConversation(contactId);
    notifyListeners();
    return true;
  }

  Future<List<MessageSearchHit>> searchCurrentConversation(
    String query, {
    int limit = 50,
  }) async {
    final contactId = _selectedContactId;
    final normalized = query.trim();
    if (contactId == null || normalized.isEmpty) {
      return const <MessageSearchHit>[];
    }
    final persistence = _persistence;
    if (persistence is SearchableChatPersistence) {
      final searchable = persistence as SearchableChatPersistence;
      return searchable.searchMessages(
        contactId: contactId,
        query: normalized,
        limit: limit,
      );
    }
    final lower = normalized.toLowerCase();
    final loaded = _messagesByContact[contactId] ?? const <Message>[];
    return <MessageSearchHit>[
      for (var index = loaded.length - 1; index >= 0; index--)
        if (loaded[index].content.toLowerCase().contains(lower))
          MessageSearchHit(message: loaded[index], sequence: index),
    ].take(limit).toList(growable: false);
  }

  Future<List<Message>> readSearchContext(
    MessageSearchHit hit, {
    int radius = 2,
  }) async {
    final contactId = _selectedContactId;
    final persistence = _persistence;
    if (contactId != null && persistence is SearchableChatPersistence) {
      final searchable = persistence as SearchableChatPersistence;
      return searchable.readMessageContext(
        contactId: contactId,
        sequence: hit.sequence,
        radius: radius,
      );
    }
    return <Message>[hit.message];
  }

  /// 在指定联系人消息列表末尾追加一张图片消息
  ///
  /// 把"用户中文描述 + 联系人设定"翻译成结构化英文生图 prompt
  ///
  /// 内部会：
  /// 1. 调一次 LLM（用当前 LLM provider）让模型扩写 prompt
  /// 2. 解析 LLM 返回的 `{englishPrompt, negativePrompt}` JSON
  /// 3. 解析失败时退化用用户原文（确保生图流程不会卡死）
  ///
  /// [contactId] 决定取哪个联系人的设定（影响 prompt 风格）；
  /// 传 null 时不带任何联系人上下文（生图风格完全由用户原文决定）。
  ///
  /// [ask] 是注入的"调 LLM"函数，方便在测试里换成 mock；
  /// 传 null 时使用 ChatProvider 内的 [AiService.ask] 默认实现。
  Future<PolishedImagePrompt> polishImagePrompt({
    required String userDescription,
    String? contactId,
    Future<String> Function(String systemPrompt, String userPrompt)? ask,
  }) async {
    Contact? contact;
    if (contactId != null) {
      for (final c in _contacts) {
        if (c.id == contactId) {
          contact = c;
          break;
        }
      }
    }

    Future<String> defaultAsk(String sys, String user) async {
      return _repository.aiService.ask(
        '$sys\n\n$user',
        contactId: 'image-prompt-polisher',
        contactName: 'System',
        profile: _providerSettings.llm,
      );
    }

    return ImagePromptPolisher.instance.polish(
      userDescription: userDescription,
      contact: contact,
      ask: ask ?? defaultAsk,
    );
  }

  /// 用于"长按消息 → 生成图片"流程：调用生图服务后，把结果作为
  /// 一条独立的 [Message]（带 imageUrl/imagePrompt）插入到消息流中，
  /// 这样渲染层就能和原消息气泡自然地串在一起。
  ///
  /// - [prompt] 是"用户原始输入 + 润色后的最终 prompt"（UI 主展示用）
  /// - [originalPrompt] 是用户最开始输入的中文原文（展开后可看到润色前后对比）
  /// - [imageUrl] 可以为 null（占位实现下没有真实 URL），UI 会以
  ///   "占位图 + 描述"的形式展示这张消息
  Future<void> appendImageMessage({
    required String contactId,
    required String prompt,
    String? imageUrl,
    String? originalPrompt,
  }) async {
    final messages = _messagesByContact.putIfAbsent(
      contactId,
      () => <Message>[],
    );
    final message = Message(
      id: 'image-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      content: prompt,
      createdAt: DateTime.now(),
      imageUrl: imageUrl,
      imagePrompt: prompt,
      originalPrompt: originalPrompt,
    );
    messages.add(message);
    await _persistConversation(contactId);
    notifyListeners();
  }

  /// 更新消息状态
  void _updateMessageStatus(
      String contactId, String messageId, MessageStatus status) {
    final messages = _messagesByContact[contactId];
    if (messages == null) return;

    final messageIndex = messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    messages[messageIndex] = messages[messageIndex].copyWith(status: status);
  }

  // ==================== 撤回功能 ====================

  /// 保存当前状态快照
  ///
  /// 在发送消息前调用，保存 Contact 和消息列表的副本
  void _saveSnapshot(Contact contact) {
    try {
      // 深拷贝 Contact（包括 eventGraph）
      _lastContactSnapshot = contact.deepCopy();

      // 复制消息列表
      final currentMessages = _messagesByContact[contact.id] ?? [];
      _lastMessagesSnapshot = List<Message>.from(currentMessages);

      debugPrint(
          '[_saveSnapshot] 快照已保存: contact=${contact.id}, messages=${_lastMessagesSnapshot!.length}');
    } catch (e, st) {
      debugPrint('[_saveSnapshot] 保存快照失败: $e');
      debugPrint('$st');
      _lastContactSnapshot = null;
      _lastMessagesSnapshot = null;
    }
  }

  /// 撤回最近一轮对话
  ///
  /// 使用快照恢复 Contact 状态和消息列表
  /// 同时删除向量数据库中本轮对话添加的记忆条目
  /// 返回是否撤回成功
  Future<bool> recallLastTurn() async {
    if (_lastContactSnapshot == null || _selectedContactId == null) {
      return false;
    }

    final contactId = _selectedContactId!;

    // 验证快照是否属于当前联系人
    if (_lastContactSnapshot!.id != contactId) {
      _clearSnapshot();
      return false;
    }

    // 1. 恢复 Contact 状态
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx >= 0) {
      _contacts[idx] = _lastContactSnapshot!;
    }

    // 2. 恢复消息列表
    if (_lastMessagesSnapshot != null) {
      _messagesByContact[contactId] = _lastMessagesSnapshot!;
    }

    // 3. 持久化
    await _persistConversation(contactId);

    // 4. 清空快照（只能撤回一次）
    _clearSnapshot();

    notifyListeners();
    return true;
  }

  /// 清空快照
  void _clearSnapshot() {
    _lastContactSnapshot = null;
    _lastMessagesSnapshot = null;
  }

  /// 发送失败时回退记忆状态
  ///
  /// 与撤回不同，此方法：
  /// - 恢复 Contact 状态（eventGraph、knowledge 等）
  /// - 删除向量数据库中新增的消息向量
  /// - 不回退消息列表（保留失败状态供用户查看）
  /// - 不清空快照（允许重发时使用）
  Future<void> _rollbackMemoryOnFailure(String contactId) async {
    if (_lastContactSnapshot == null || _lastContactSnapshot!.id != contactId) {
      return;
    }

    // 1. 恢复 Contact 状态
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx >= 0) {
      _contacts[idx] = _lastContactSnapshot!;
    }

    // 2. 持久化恢复后的 Contact 状态
    await _persistConversation(contactId);

    // 注意：不清空快照，以便用户可以重发
  }

  // ==================== 记忆更新与事件管理 ====================

  /// 从AI响应中提取记忆补丁并更新联系人
  ///
  /// 处理流程：
  /// 1. 解析memoryPatch JSON
  /// 2. 提取各类知识、事件、物品、状态
  /// 3. 将新事件加入短期队列
  /// 4. 对本地存储的事件（第11个及以后）应用LRU排序
  /// 5. 更新物品关联和边关系
  /// 6. 触发事件总结（如达到阈值）
  /// 7. 持久化更新后的联系人
  Future<void> _updateContactFromMemoryPatch(
    Contact contact,
    String response, {
    required String userInput,
    required List<String> inputKeywords,
    required List<String> promptEventNodeIds,
    // 本轮触发的级联方向：null=无强制（仅 LLM 自主输出时），
    // shortTerm = 1→2 级联（summary 入长期），
    // longTerm = 2→3 级联（summary 入超长期）
    EventTier? summarySourceTier,
  }) async {
    final patch = StructuredOutputRegexParser.extractMemoryPatch(response);
    if (patch == null) {
      await _persistConversation(contact.id);
      return;
    }

    final reducedPatch = _memoryPatchReducer.reduce(
      contact: contact,
      patch: patch,
      userInput: userInput,
      rawAiResponse: response,
    );
    final patchBelongings = reducedPatch.belongingChanges;

    // 更新事件图。关联跨轮保留，队列截断后统一清理悬空关系。
    var graph = contact.eventGraph.copyWith(
      turnCount: contact.eventGraph.turnCount + 1,
    );

    // 处理新事件
    // incomingEvents 现在只负责记忆事件：summary 和 eventBrief。
    // 顶层 reply 是给用户看的回复；故事模式下 reply 同时就是详细续写。
    // summary: 往期事件总结，进入长期队列（关键：必须真存进 long-term，
    //          下次 LLM prompt 通过 long-term.filter(!summarized) 才能再看到）
    // eventBrief: 本次事件缩写，进入短期队列
    String? currentEventNodeId;
    if (reducedPatch.events.isNotEmpty) {
      final summaryEvent = reducedPatch.summary;
      final briefEvent = reducedPatch.turnEvent;

      // 如果有 summary：按级联方向路由
      // - 1→2：summary 入 long-term（un-summarized）；源层（短期）的旧事件**只标 summarized，
      //          不迁层（它们仍留在短期里，prompt 通过 !summarized 过滤不再展示）
      // - 2→3：summary 入 ultra-long-term（un-summarized）；源层（长期）的旧摘要**只标 summarized，
      //          不迁层
      // 关键：每轮级联只往目标层加 1 个 summary 元素，目标层不会被旧事件淹没。
      if (summaryEvent != null && !summaryEvent.isEmpty) {
        // LLM 自主输出但本轮未强制级联时：按 1→2 默认处理（summary 入 long-term）
        final sourceTier = summarySourceTier ?? EventTier.shortTerm;
        final targetTier = sourceTier == EventTier.shortTerm
            ? EventTier.longTerm
            : EventTier.ultraLongTerm;

        // 1) summary 自身入目标层（仅 1 个）
        final timestamp = DateTime.now();
        final enqueuedSummary = _memoryGraphService.enqueue(
          graph: graph,
          tier: targetTier,
          event: summaryEvent,
          nodeId: 'event-${timestamp.microsecondsSinceEpoch}',
          createdAtMs: timestamp.millisecondsSinceEpoch,
          settings: _appSettings,
        );
        graph = enqueuedSummary.graph;
        // 2) 源层里未总结的旧事件：原地标 summarized，不迁层
        //    - prompt 用 where(!summarized) 过滤，自然不再展示这些旧事件
        //    - 源层 LRU 在超容量（maxShortQueue/maxLongQueue）时会自然清理
        //    - 不再把 N 个旧事件批量复制到目标层
        final sourceUnsummarized = _memoryGraphService
            .queueForTier(graph, sourceTier)
            .where((e) => !e.summarized && !e.invalidated)
            .toList();
        graph = _memoryGraphService.linkSummarySources(
          graph: graph,
          summaryNodeId: enqueuedSummary.nodeId,
          sourceNodeIds: sourceUnsummarized.map((event) => event.id),
        );
        graph = _memoryGraphService.markSummarized(
          graph: graph,
          tier: sourceTier,
          nodeIds: sourceUnsummarized.map((e) => e.id).toSet(),
        );
      }

      // 将 eventBrief 加入短期队列
      if (briefEvent != null && !briefEvent.isEmpty) {
        final timestamp = DateTime.now();
        final enqueued = _memoryGraphService.enqueue(
          graph: graph,
          tier: EventTier.shortTerm,
          event: briefEvent,
          nodeId: 'event-${timestamp.microsecondsSinceEpoch}',
          createdAtMs: timestamp.millisecondsSinceEpoch,
          settings: _appSettings,
        );
        graph = enqueued.graph;
        currentEventNodeId = enqueued.nodeId;
      }
    }

    // 对所有事件队列应用LRU排序（仅本地存储部分）
    // 各层级固定输入LLM的事件不参与LRU排序
    graph = _memoryGraphService.applyLru(
      graph: graph,
      inputKeywords: inputKeywords,
      settings: _appSettings,
    );

    // 更新物品关联和边关系（应用LRU排序）
    graph = _memoryGraphService.updateBelongingRelations(
      graph: graph,
      eventNodeId: currentEventNodeId,
      changes: patchBelongings,
      inputKeywords: inputKeywords,
    );

    // 更新设定关联和边关系
    graph = _memoryGraphService.updateSettingRelations(
      graph: graph,
      eventNodeId: currentEventNodeId,
      settings: contact.settings,
      inputKeywords: inputKeywords,
    );

    // 根据 LLM 输出的 relatedEventIds 建立边关系
    if (currentEventNodeId != null) {
      graph = _memoryRecallService.applyRelatedEdges(
        graph: graph,
        currentEventNodeId: currentEventNodeId,
        promptNodeIds: promptEventNodeIds,
        relatedEventIds: patch['relatedEventIds'],
      );
    }
    graph = _memoryRecallService.pruneDanglingRelations(graph);

    // 更新联系人数据
    final idx = _contacts.indexWhere((e) => e.id == contact.id);
    if (idx < 0) return;
    _contacts[idx] = Contact(
      id: contact.id,
      name: contact.name,
      avatar: contact.avatar,
      category: contact.category,
      fixedInput: contact.fixedInput,
      currentStates: reducedPatch.currentStates,
      personality: contact.personality,
      appearance: contact.appearance,
      personalInfo: contact.personalInfo,
      settings: contact.settings,
      backgroundStory: contact.backgroundStory,
      narrativeRules: contact.narrativeRules,
      otherCharacteristics: contact.otherCharacteristics,
      worldKnowledge: WorldKnowledgeBucket(reducedPatch.worldKnowledge),
      selfKnowledge: SelfKnowledgeBucket(reducedPatch.selfKnowledge),
      userKnowledge: UserKnowledgeBucket(reducedPatch.userKnowledge),
      keywordLibrary: _updateKeywordLibrary(
        existing: contact.keywordLibrary,
        newKeywords: _tempKeywordsByContact[contact.id] ?? const [],
        maxSize: _appSettings.keywordLibrarySize,
      ),
      themeLibrary: _updateKeywordLibrary(
        existing: contact.themeLibrary,
        newKeywords: _extractThemeFromEvents(reducedPatch.events),
        maxSize: _appSettings.keywordLibrarySize,
      ),
      events: EventLruBucket(
        _dedupeEvents(<EventMemory>[
          ...contact.events.items,
          ...reducedPatch.events,
          ..._flattenGraphEvents(graph),
        ]),
      ),
      eventGraph: graph,
      belongings: reducedPatch.belongings,
      status: reducedPatch.status,
      mood: reducedPatch.mood,
      time: reducedPatch.time,
      voice: contact.voice,
      createdAt: contact.createdAt,
    );
    await _persistConversation(contact.id);
  }

  /// 更新关键词库（LRU 策略）
  ///
  /// 新关键词追加到末尾，已有关键词移到末尾（表示最近使用）
  /// 超出容量时从头部删除最久未使用的关键词
  List<String> _updateKeywordLibrary({
    required List<String> existing,
    required List<String> newKeywords,
    required int maxSize,
  }) {
    if (newKeywords.isEmpty) return existing;
    // 合并：已有词移到末尾，新词追加
    final seen = <String>{};
    final result = <String>[];
    // 先加已有词中不在 newKeywords 中的（保留顺序）
    for (final kw in existing) {
      final lower = kw.toLowerCase();
      if (!newKeywords.any((n) => n.toLowerCase() == lower)) {
        if (seen.add(lower)) result.add(kw);
      }
    }
    // 再加本轮关键词（新的 + 被复用的都移到末尾）
    for (final kw in newKeywords) {
      final lower = kw.toLowerCase();
      if (seen.add(lower)) result.add(kw);
    }
    // 截断到最大容量
    if (result.length > maxSize) {
      return result.sublist(result.length - maxSize);
    }
    return result;
  }

  /// 从事件列表中提取所有 theme 关键词
  List<String> _extractThemeFromEvents(List<EventMemory> events) {
    final themes = <String>[];
    for (final event in events) {
      themes.addAll(event.theme);
    }
    return themes;
  }

  // ==================== Prompt构建辅助方法 ====================

  /// 构建用于Prompt的联系人对象
  ///
  /// 从完整联系人中提取用于LLM输入的子集：
  /// - 短期：前10条固定输入LLM（第11条及以后LRU排序存储）
  /// - 长期：前5条固定输入LLM（第6条及以后LRU排序存储）
  /// - 超长期：前2条固定输入LLM（第3条及以后LRU排序存储）
  /// - 关联事件：5条
  /// - 知识：各类型前5条（新增的知识优先）
  /// - 物品：前5个
  _PromptContactContext _buildPromptContact(
    Contact contact, {
    required List<String> inputKeywords,
  }) {
    // 获取各层级事件队列（已按LRU排序存储在本地）
    final shortQueue = contact.eventGraph.shortTermQueue;
    final longQueue = contact.eventGraph.longTermQueue;
    final ultraQueue = contact.eventGraph.ultraLongTermQueue;

    // 前N条固定输入LLM（保持时间顺序，最新的在前）
    final promptShort = shortQueue
        .where((node) => !node.summarized && !node.invalidated)
        .take(_maxShortTermEvents)
        .toList(growable: false);
    final promptLong = longQueue
        .where((node) => !node.summarized && !node.invalidated)
        .take(_maxLongTermEvents)
        .toList(growable: false);
    final promptUltra = ultraQueue
        .where((node) => !node.invalidated)
        .take(_maxUltraTermEvents)
        .toList(growable: false);
    final numberedNodes = <EventNode>[
      ...promptShort,
      ...promptLong,
      ...promptUltra,
    ];
    final numberedNodeIds = numberedNodes.map((node) => node.id).toSet();

    final relatedNodes = _memoryRecallService.recallNodes(
      contact.eventGraph,
      inputKeywords,
      maxResults: _maxRelatedEvents,
      depth: _appSettings.searchDepth,
    );
    final related = relatedNodes
        .where((node) => !numberedNodeIds.contains(node.id))
        .map((node) => node.event)
        .toList(growable: false);

    // 知识处理：取后N条（新增的）+ 前N条（旧的），去重后取前N条
    // 这样确保新增的知识优先输入到LLM
    final worldKnowledge = _mergeKnowledgePriority(
      contact.worldKnowledge.items,
      maxCount: _maxPromptListItems,
    );
    final selfKnowledge = _mergeKnowledgePriority(
      contact.selfKnowledge.items,
      maxCount: _maxPromptListItems,
    );
    final userKnowledge = _mergeKnowledgePriority(
      contact.userKnowledge.items,
      maxCount: _maxPromptListItems,
    );

    final promptContact = Contact(
      id: contact.id,
      name: contact.name,
      avatar: contact.avatar,
      category: contact.category,
      fixedInput: contact.fixedInput,
      currentStates: contact.currentStates,
      personality: contact.personality,
      appearance: contact.appearance,
      personalInfo: contact.personalInfo,
      settings: contact.settings,
      backgroundStory: contact.backgroundStory,
      narrativeRules: contact.narrativeRules,
      otherCharacteristics: contact.otherCharacteristics,
      worldKnowledge: WorldKnowledgeBucket(worldKnowledge),
      selfKnowledge: SelfKnowledgeBucket(selfKnowledge),
      userKnowledge: UserKnowledgeBucket(userKnowledge),
      events: EventLruBucket(_dedupeEvents(related)),
      eventGraph: EventGraphMemory(
        shortTermQueue: promptShort,
        longTermQueue: promptLong,
        ultraLongTermQueue: promptUltra,
      ),
      belongings: _firstN(contact.belongings, _maxPromptListItems),
      status: contact.status,
      mood: contact.mood,
      time: contact.time,
      createdAt: contact.createdAt,
    );
    return _PromptContactContext(
      contact: promptContact,
      eventNodeIds:
          numberedNodes.map((node) => node.id).toList(growable: false),
    );
  }

  /// 合并知识列表，优先保留新增的知识（列表末尾）
  ///
  /// 策略：取列表末尾的maxCount个（新增的）+ 列表开头的maxCount个（旧的）
  /// 合并后去重，保留顺序，最终取前maxCount个
  List<String> _mergeKnowledgePriority(List<String> items,
      {required int maxCount}) {
    if (items.length <= maxCount) return List<String>.from(items);

    // 取新增的（末尾）和旧的（开头）
    final recent = items.sublist(items.length - maxCount);
    final old = items.sublist(0, maxCount);

    // 合并并去重，保持新增优先
    final result = <String>[];
    final seen = <String>{};

    // 先加新增的（优先级高）
    for (final item in recent.reversed) {
      if (seen.add(item)) result.add(item);
    }

    // 再加旧的
    for (final item in old) {
      if (seen.add(item)) result.add(item);
    }

    // 返回前maxCount个（顺序是：最新的在前）
    return result.sublist(
        0, maxCount < result.length ? maxCount : result.length);
  }

  /// 提取本轮对话关键词
  ///
  /// 结合本地提取和LLM提取：
  /// - 本地：使用jieba分词器提取关键词
  /// - LLM：请求专门的LLM进行关键词抽取（提供往期关键词库和主题库）
  /// 合并结果并缓存，用于后续关联事件搜索
  /// 同时更新关键词库（LRU 策略）
  Future<_KeywordExtraction> _extractTurnKeywords({
    required String contactId,
    required String contactName,
    required String userInput,
    required List<String> existingKeywordLibrary,
    required List<String> existingThemeLibrary,
  }) async {
    // 本地关键词提取
    final local = _extractLocalKeywords(userInput).toList();

    // LLM关键词提取（提供往期关键词库和主题库）
    List<String> llm = const <String>[];
    List<String> llmTheme = const <String>[];
    try {
      final raw = await _awaitGeneration(_repository.askUtility(
        contactId: contactId,
        contactName: contactName,
        prompt: _buildKeywordPrompt(
            userInput, existingKeywordLibrary, existingThemeLibrary),
      ));
      final parsed = _parseKeywordsAndThemeFromRaw(raw);
      llm = parsed.keywords;
      llmTheme = parsed.theme;
    } on _GenerationCancelled {
      rethrow;
    } catch (_) {
      // 解析失败，重试一次
      try {
        final raw = await _awaitGeneration(_repository.askUtility(
          contactId: contactId,
          contactName: contactName,
          prompt: _buildKeywordPrompt(
              userInput, existingKeywordLibrary, existingThemeLibrary),
        ));
        final parsed = _parseKeywordsAndThemeFromRaw(raw);
        llm = parsed.keywords;
        llmTheme = parsed.theme;
      } on _GenerationCancelled {
        rethrow;
      } catch (_) {
        llm = const <String>[];
        llmTheme = const <String>[];
      }
    }

    // 如果LLM提取失败，使用本地提取结果
    if (llm.isEmpty) llm = List<String>.from(local);

    // 合并并去重
    final merged = _mergeUnique(local, llm);
    _tempKeywordsByContact[contactId] = merged;
    return _KeywordExtraction(
      localKeywords: local,
      llmKeywords: llm,
      mergedKeywords: merged,
      theme: llmTheme,
    );
  }

  /// 构建关键词提取Prompt
  ///
  /// 提供往期关键词库和主题库，LLM 优先复用已有关键词，必要时才新增
  String _buildKeywordPrompt(String userInput, List<String> existingKeywords,
      List<String> existingTheme) {
    final lib = existingKeywords.isEmpty ? '（空）' : existingKeywords.join('、');
    final themeLib = existingTheme.isEmpty ? '（空）' : existingTheme.join('、');
    return '你是关键词抽取器。\n'
        '往期关键词库（实体）：$lib\n'
        '往期主题库（氛围/情感）：$themeLib\n'
        '用户输入：${userInput.trim()}\n\n'
        '任务：\n'
        '1. 从用户输入中提取关键词\n'
        '2. keywords 是实体关键词：人物、地点、物品等具体实体\n'
        '3. theme 是主题/氛围关键词：情感、氛围、主题等抽象概念（如"遗憾"、"温暖"、"悬疑"）\n'
        '4. 优先从往期库中选择相关词（复用已有词保持一致性）\n'
        '5. 只有当往期库中没有合适词时，才新增\n'
        '6. 包含通过上下文/记忆可推断的内容\n\n'
        '只输出 JSON：{"keywords":["实体1"],"theme":["主题1"]}。keywords 最多 8 个，theme 最多 4 个。';
  }

  /// 构建关键词搜索输入
  ///
  /// 将用户输入和关键词合并，用于事件搜索
  /// 从LLM响应中解析关键词和主题列表
  _KeywordAndTheme _parseKeywordsAndThemeFromRaw(String raw) {
    final payload = StructuredOutputRegexParser.parsePrimaryPayload(raw);

    // 解析 keywords
    final keywordsRaw = payload?['keywords'];
    final keywords = <String>[];
    if (keywordsRaw is List) {
      for (final item in keywordsRaw) {
        final value = item?.toString().trim() ?? '';
        if (value.isEmpty || keywords.contains(value)) continue;
        keywords.add(value);
      }
    }

    // 解析 theme
    final themeRaw = payload?['theme'];
    final theme = <String>[];
    if (themeRaw is List) {
      for (final item in themeRaw) {
        final value = item?.toString().trim() ?? '';
        if (value.isEmpty || theme.contains(value)) continue;
        theme.add(value);
      }
    }

    return _KeywordAndTheme(keywords: keywords, theme: theme);
  }

  /// 从输入中提取本地关键词
  ///
  /// 使用jieba中文分词器提取关键词，替代原有的正则表达式匹配
  /// 支持中文分词、停用词过滤、词频统计
  Set<String> _extractLocalKeywords(String input) {
    try {
      // 使用jieba分词器提取关键词
      final keywords = _tokenizer.extractKeywords(input, topK: 8);
      return keywords.toSet();
    } catch (e) {
      // 如果分词器未初始化或出错，回退到简单的空格分割
      final words = input
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((s) => s.length >= 2)
          .take(8)
          .toSet();
      return words;
    }
  }

  /// 扁平化事件图，获取所有事件
  List<EventMemory> _flattenGraphEvents(EventGraphMemory graph) =>
      <EventMemory>[
        ...graph.shortTermQueue
            .where((e) => !e.invalidated)
            .map((e) => e.event),
        ...graph.longTermQueue.where((e) => !e.invalidated).map((e) => e.event),
        ...graph.ultraLongTermQueue
            .where((e) => !e.invalidated)
            .map((e) => e.event),
      ];

  // ==================== 数据提取辅助方法 ====================

  Map<String, String> _normalizeStateMap(Map<String, String> value) {
    final out = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;
      out[key] = entry.value.trim();
    }
    return out;
  }

  /// 合并两个列表并去重
  List<String> _mergeUnique(List<String> a, List<String> b) {
    final out = <String>[];
    final seen = <String>{};
    for (final item in a.followedBy(b)) {
      final v = item.trim();
      if (v.isEmpty || !seen.add(v)) continue;
      out.add(v);
    }
    return out;
  }

  /// 去除重复事件
  List<EventMemory> _dedupeEvents(List<EventMemory> input) {
    final out = <EventMemory>[];
    final seen = <String>{};
    for (final e in input) {
      final key = e.toPromptLine().trim();
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(e);
    }
    return out;
  }

  /// 获取列表的前N个元素
  List<String> _firstN(List<String> items, int n) =>
      items.length <= n ? List<String>.from(items) : items.sublist(0, n);

  /// 合并系统提示词和联系人信息
  String _mergeSystemPromptWithContact({
    required String basePrompt,
    Contact? contact,
    bool needSummary = false,
    List<EventMemory> pendingSummaryEvents = const [],
  }) {
    final base = basePrompt.trim();
    if (contact == null) return base;
    final composer = StructuredInputPromptComposer(settings: _appSettings);
    return composer.composeSystemPromptWithContactObject(
      basePrompt: base,
      contact: contact,
      mustSummarize: needSummary,
      pendingSummaryEvents: pendingSummaryEvents,
    );
  }

  /// 生成唯一联系人ID
  ///
  /// 格式：{prefix}-{timestamp}-{random}
  /// prefix: contact 或 story 根据类别决定
  String _generateUniqueId(ContactCategory category) {
    final prefix = switch (category) {
      ContactCategory.story => 'story',
      ContactCategory.contact => 'contact',
      ContactCategory.assistant => 'assistant',
    };
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random =
        (DateTime.now().microsecond % 10000).toString().padLeft(4, '0');
    return '$prefix-$timestamp-$random';
  }

  @override
  void dispose() {
    _heartbeat.stop();
    _persistence.close();
    super.dispose();
  }
}

// ==================== 内部数据类 ====================

class _GenerationCancelled implements Exception {
  const _GenerationCancelled();
}

class _PromptContactContext {
  const _PromptContactContext({
    required this.contact,
    required this.eventNodeIds,
  });

  final Contact contact;
  final List<String> eventNodeIds;
}

/// 关键词提取结果
class _KeywordExtraction {
  const _KeywordExtraction({
    required this.localKeywords,
    required this.llmKeywords,
    required this.mergedKeywords,
    required this.theme,
  });

  /// 本地正则提取的关键词
  final List<String> localKeywords;

  /// LLM提取的关键词
  final List<String> llmKeywords;

  /// 合并后的关键词（去重）
  final List<String> mergedKeywords;

  /// LLM提取的主题/氛围关键词
  final List<String> theme;
}

/// 关键词和主题解析结果
class _KeywordAndTheme {
  const _KeywordAndTheme({
    required this.keywords,
    required this.theme,
  });

  final List<String> keywords;
  final List<String> theme;
}
