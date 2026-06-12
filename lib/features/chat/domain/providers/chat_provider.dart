import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/data/models/app_settings.dart';
import '../../../../core/utils/chinese_tokenizer_service.dart';
import '../../../../core/utils/structured_input_prompt_composer.dart';
import '../../../../core/utils/structured_output_regex_parser.dart';
import '../../../../infrastructure/services/ai_service.dart';
import '../../../../infrastructure/services/opencode_service.dart';
import '../../data/datasources/chat_local_storage.dart';
import '../../data/models/contact.dart';
import '../../data/models/message.dart';
import '../../data/repositories/chat_repository.dart';
import '../services/heartbeat_manager.dart';
import '../services/input_formatter.dart';

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
  })  : _formatter = formatter ?? InputFormatterService(),
        _heartbeat = heartbeat ?? HeartbeatManager(),
        _repository = repository ?? ChatRepository(aiService: AiService()),
        _agentStore = agentStore ?? ChatAgentStore() {
    // 加载应用设置
    _loadAppSettings();
    // 启动心跳检测，监听连接状态变化
    _heartbeat.start((status) {
      connectionStatus = status;
      notifyListeners();
    });
  }

  // ==================== 常量配置 ====================

  /// 应用设置
  AppSettings _appSettings = const AppSettings();

  /// 获取应用设置
  AppSettings get appSettings => _appSettings;

  /// 加载应用设置
  Future<void> _loadAppSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppStrings.appSettingsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _appSettings = AppSettings.fromJson(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      } catch (_) {}
    }

    // 加载 opencode 连接配置
    final opencodeRaw = prefs.getString(AppStrings.opencodeConnectionKey);
    if (opencodeRaw != null && opencodeRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(opencodeRaw);
        if (decoded is Map) {
          _opencodeService.updateConfig(
            OpencodeConnectionConfig.fromJson(
              decoded.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        }
      } catch (_) {}
    }
  }

  /// 保存 opencode 连接配置
  Future<void> saveOpencodeConfig(OpencodeConnectionConfig config) async {
    _opencodeService.updateConfig(config);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppStrings.opencodeConnectionKey,
      jsonEncode(config.toJson()),
    );
    notifyListeners();
  }

  /// 获取 opencode 连接配置
  OpencodeConnectionConfig get opencodeConfig => _opencodeService.config;

  /// 获取 opencode 服务实例
  OpencodeService get opencodeService => _opencodeService;

  /// 事件总结阈值
  int get _summaryThreshold => _appSettings.summaryThreshold;
  int get _ultraSummaryThreshold => _appSettings.ultraSummaryThreshold;

  /// 短期事件队列最大容量
  int get _maxShortQueue => _appSettings.maxShortQueue;

  /// 长期事件队列最大容量
  int get _maxLongQueue => _appSettings.maxLongQueue;

  /// 超长期事件队列最大容量
  int get _maxUltraQueue => _appSettings.maxUltraQueue;

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

  /// 临时关键词缓存
  ///
  /// 按联系人ID存储最近一次对话提取的关键词
  /// 用于关联事件搜索
  final Map<String, List<String>> _tempKeywordsByContact =
      <String, List<String>>{};

  /// ==================== 撤回功能相关 ====================

  /// 最近一轮对话前的 Contact 快照
  /// 用于支持单条消息撤回
  Contact? _lastContactSnapshot;

  /// 最近一轮对话前的消息列表快照
  List<Message>? _lastMessagesSnapshot;

  /// 当前选中的联系人ID
  String? _selectedContactId;

  /// API密钥
  String _apiKey = '';

  /// API Base URL
  String _apiBaseUrl = 'https://api.deepseek.com';

  /// API Model
  String _apiModel = 'deepseek-chat';

  /// 系统提示词
  ///
  /// 作为基础系统提示，会与联系人信息合并后发送给LLM
  String _systemPrompt = '你是一个AI角色扮演对话助手，专注于沉浸式对话体验。';

  // ==================== 公开状态（UI可直接访问） ====================

  /// 是否正在加载中
  bool isLoading = false;

  /// AI是否正在输入（用于显示打字指示器）
  bool isTyping = false;

  /// 是否已完成初始化
  bool isInitialized = false;

  /// 是否处于调试模式
  ///
  /// 调试模式下会显示完整的Prompt和关键词提取信息
  bool isDebugMode = false;

  /// 错误信息
  String? error;

  /// 当前连接状态
  ConnectionStatus connectionStatus = ConnectionStatus.connected;

  // ==================== Getters ====================

  /// 获取不可修改的联系人列表副本
  List<Contact> get contacts => List<Contact>.unmodifiable(_contacts);

  /// 获取当前选中的联系人ID
  String? get selectedContactId => _selectedContactId;

  /// 获取当前API密钥
  String get currentApiKey => _apiKey;

  /// 获取当前API Base URL
  String get currentApiBaseUrl => _apiBaseUrl;

  /// 获取当前API Model
  String get currentApiModel => _apiModel;

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

  /// 是否可以撤回最近一轮对话
  bool get canRecall {
    final result = _lastContactSnapshot != null;
    debugPrint('[canRecall] result=$result, snapshot=$_lastContactSnapshot');
    return result;
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
    try {
      // 初始化中文分词服务
      await _tokenizer.init();
    } catch (e) {
      debugPrint('ChatProvider.initialize: 中文分词服务初始化失败: $e');
      // 继续初始化
    }

    try {
      // 加载Agent设置
      final settings = await _agentStore.readAgentSettings();
      _apiKey = (settings['apiKey'] ?? '').toString();
      _apiBaseUrl = (settings['apiBaseUrl'] ?? 'https://api.deepseek.com').toString();
      _apiModel = (settings['apiModel'] ?? 'deepseek-chat').toString();
      _systemPrompt = (settings['systemPrompt'] ?? _systemPrompt).toString();
      ApiConstants.runtimeApiKey = _apiKey;
      ApiConstants.runtimeBaseUrl = _apiBaseUrl;
      ApiConstants.runtimeModel = _apiModel;
    } catch (e) {
      debugPrint('ChatProvider.initialize: 加载设置失败: $e');
    }

    try {
      // 加载联系人和消息
      final localContacts = await _agentStore.readContacts();
      final localMessages = await _agentStore.readMessagesByContact();
      _contacts
        ..clear()
        ..addAll(localContacts);

      // 初始化消息列表
      if (_contacts.isNotEmpty) {
        _selectedContactId = _contacts.first.id;
        for (final c in _contacts) {
          _messagesByContact[c.id] =
              List<Message>.from(localMessages[c.id] ?? const <Message>[]);
        }
      }
    } catch (e) {
      debugPrint('ChatProvider.initialize: 加载联系人/消息失败: $e');
    }

    isInitialized = true;
    notifyListeners();
  }

  /// 保存API配置
  ///
  /// 同时更新内存状态和持久化存储
  Future<void> saveApiConfig({
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    _apiKey = apiKey.trim();
    _apiBaseUrl = baseUrl.trim().isEmpty ? 'https://api.deepseek.com' : baseUrl.trim();
    _apiModel = model.trim().isEmpty ? 'deepseek-chat' : model.trim();
    ApiConstants.runtimeApiKey = _apiKey;
    ApiConstants.runtimeBaseUrl = _apiBaseUrl;
    ApiConstants.runtimeModel = _apiModel;
    final settings = await _agentStore.readAgentSettings();
    settings['apiKey'] = _apiKey;
    settings['apiBaseUrl'] = _apiBaseUrl;
    settings['apiModel'] = _apiModel;
    await _agentStore.saveAgentSettings(settings);
    notifyListeners();
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
    isDebugMode = !isDebugMode;
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
  void selectContact(String contactId) {
    if (_selectedContactId == contactId) return;
    if (!_contacts.any((c) => c.id == contactId)) return;
    _selectedContactId = contactId;
    _clearSnapshot();
    notifyListeners();
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
      createdAt: DateTime.now(),
    );
    _contacts.add(contact);
    _messagesByContact.putIfAbsent(contact.id, () => <Message>[]);
    _selectedContactId = contact.id;
    await _agentStore.saveContacts(_contacts);
    await _agentStore.saveMessagesByContact(_messagesByContact);
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
    try {
      final decoded = jsonDecode(jsonString);
      final json = _asMap(decoded);

      final name = (json['name'] ?? '').toString().trim();
      if (name.isEmpty) return false;

      // 如果没有提供ID或ID为空，则自动生成
      var id = (json['id'] ?? '').toString().trim();
      if (id.isEmpty) {
        id = _generateUniqueId(category);
      }
      // 如果提供的ID已存在，自动生成新的
      if (_contacts.any((e) => e.id == id)) {
        id = _generateUniqueId(category);
      }

      final fixedInputStr = (json['fixedInput'] ?? '').toString();
      final contact = Contact(
        id: id,
        name: name,
        avatar: (json['avatar'] ?? '').toString(),
        fixedInput: fixedInputStr,
        currentStates: _extractStringMap(json['currentStates']),
        personality: _extractStrings(json['personality']),
        appearance: _extractStrings(json['appearance']),
        settings: _extractSettings(json['settings']),
        backgroundStory: _extractStrings(json['backgroundStory']),
        narrativeRules: _extractStrings(json['narrativeRules']),
        otherCharacteristics: _extractStrings(json['otherCharacteristics']),
        worldKnowledge: WorldKnowledgeBucket(
          _extractStrings(json['worldKnowledge']),
        ),
        selfKnowledge: SelfKnowledgeBucket(
          _extractStrings(json['selfKnowledge']),
        ),
        userKnowledge: UserKnowledgeBucket(
          _extractStrings(json['userKnowledge']),
        ),
        keywordLibrary: _extractLocalKeywords('$name $fixedInputStr').toList(),
        belongings: _extractStrings(json['belongings']),
        status: _extractStrings(json['status']),
        mood: (json['mood'] ?? '').toString(),
        time: (json['time'] ?? '').toString(),
        category: category,
        createdAt: DateTime.now(),
      );

      _contacts.add(contact);
      _messagesByContact.putIfAbsent(contact.id, () => <Message>[]);
      _selectedContactId = contact.id;
      await _agentStore.saveContacts(_contacts);
      await _agentStore.saveMessagesByContact(_messagesByContact);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('addContactFromJson failed: $e');
      return false;
    }
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
  }) async {
    try {
      final decoded = jsonDecode(jsonString);
      final json = _asMap(decoded);

      debugPrint(
          '[addContactFromJsonWithFallback] json keys: ${json.keys.toList()}');
      debugPrint(
          '[addContactFromJsonWithFallback] raw settings: ${json['settings']}');
      debugPrint(
          '[addContactFromJsonWithFallback] raw narrativeRules: ${json['narrativeRules']}');
      debugPrint(
          '[addContactFromJsonWithFallback] raw otherCharacteristics: ${json['otherCharacteristics']}');

      // 优先使用 JSON 中的值，否则使用后备值
      final name = ((json['name'] ?? '').toString().trim()).isNotEmpty
          ? (json['name'] ?? '').toString().trim()
          : fallbackName?.trim() ?? '';

      if (name.isEmpty) return false;

      // 自动生成唯一ID（忽略 JSON 和后备中的 id）
      var id = _generateUniqueId(category);
      // 确保ID唯一
      while (_contacts.any((e) => e.id == id)) {
        id = _generateUniqueId(category);
      }

      // 合并字段：JSON 优先，其次是后备值
      final personality = _extractStrings(json['personality']);
      final appearance = _extractStrings(json['appearance']);
      final personalInfo = _extractStrings(json['personalInfo']);
      final settings = _extractSettings(json['settings']);
      final backgroundStory = _extractStrings(json['backgroundStory']);
      final narrativeRules = _extractStrings(json['narrativeRules']);
      final otherCharacteristics =
          _extractStrings(json['otherCharacteristics']);

      debugPrint('[addContactFromJsonWithFallback] settings: $settings');
      debugPrint(
          '[addContactFromJsonWithFallback] narrativeRules: $narrativeRules');
      debugPrint(
          '[addContactFromJsonWithFallback] otherCharacteristics: $otherCharacteristics');

      final contact = Contact(
        id: id,
        name: name,
        avatar: ((json['avatar'] ?? '').toString()).isNotEmpty
            ? (json['avatar'] ?? '').toString()
            : fallbackAvatar ?? '',
        fixedInput: ((json['fixedInput'] ?? '').toString().trim()).isNotEmpty
            ? (json['fixedInput'] ?? '').toString().trim()
            : fallbackFixedInput ?? '',
        currentStates: _extractStringMap(json['currentStates']).isNotEmpty
            ? _extractStringMap(json['currentStates'])
            : _normalizeStateMap(
                fallbackCurrentStates ?? const <String, String>{}),
        personality: personality,
        appearance: appearance,
        personalInfo: personalInfo,
        settings: settings,
        backgroundStory: backgroundStory,
        narrativeRules: narrativeRules,
        otherCharacteristics: otherCharacteristics,
        worldKnowledge: WorldKnowledgeBucket(
          _extractStrings(json['worldKnowledge']),
        ),
        selfKnowledge: SelfKnowledgeBucket(
          _extractStrings(json['selfKnowledge']),
        ),
        userKnowledge: UserKnowledgeBucket(
          _extractStrings(json['userKnowledge']),
        ),
        keywordLibrary: _extractLocalKeywords(
                '$name ${((json['fixedInput'] ?? '').toString().trim()).isNotEmpty ? (json['fixedInput'] ?? '').toString().trim() : fallbackFixedInput ?? ''}')
            .toList(),
        belongings: _extractStrings(json['belongings']),
        status: _extractStrings(json['status']),
        mood: (json['mood'] ?? '').toString(),
        time: (json['time'] ?? '').toString(),
        category: category,
        createdAt: DateTime.now(),
      );

      _contacts.add(contact);
      _messagesByContact.putIfAbsent(contact.id, () => <Message>[]);
      _selectedContactId = contact.id;
      await _agentStore.saveContacts(_contacts);
      await _agentStore.saveMessagesByContact(_messagesByContact);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('addContactFromJsonWithFallback failed: $e');
      return false;
    }
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

    // 如果删除的是当前选中的联系人，更新选中状态
    if (_selectedContactId == contactId) {
      if (_contacts.isNotEmpty) {
        _selectedContactId = _contacts.first.id;
      } else {
        _selectedContactId = null;
      }
    }

    // 持久化更新
    await _agentStore.saveContacts(_contacts);
    await _agentStore.saveMessagesByContact(_messagesByContact);

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
    if (_apiKey.isEmpty) {
      error = '请先设置 API Key';
      notifyListeners();
      return;
    }

    final selected = selectedContact;
    if (selected == null) {
      error = AppStrings.noContact;
      notifyListeners();
      return;
    }

    // 格式化输入
    final input = _formatter.normalize(rawInput);
    if (input.isEmpty || isLoading) return;

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
    await _agentStore.saveMessagesByContact(_messagesByContact);

    // 设置加载状态
    isLoading = true;
    isTyping = true;
    error = null;
    notifyListeners();

    try {
      final currentContact = selectedContact;
      if (currentContact == null) {
        error = AppStrings.noContact;
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
      final promptContact = _buildPromptContact(currentContact,
          inputKeywords: keywords.mergedKeywords);

      // 检查是否需要总结：两级级联独立判断，优先 1→2（短→长）
      // 1→2 触发：短期队列 un-summarized ≥ summaryThreshold（默认 10）
      // 2→3 触发：长期队列 un-summarized ≥ ultraSummaryThreshold（默认 5）
      //          仅在 1→2 未触发时才考虑 2→3，避免同轮既压短又压长
      // 没有 LLM 输出的 summary 字段时，零噪声（pendingSummaryEvents 为空）
      final mustSummarizeShort =
          _unsummarizedCount(currentContact.eventGraph, EventTier.shortTerm) >=
              _summaryThreshold;
      final mustSummarizeLong = !mustSummarizeShort &&
          _unsummarizedCount(currentContact.eventGraph, EventTier.longTerm) >=
              _ultraSummaryThreshold;
      final needSummary = mustSummarizeShort || mustSummarizeLong;
      // 本轮 summary 该路由到哪一层：null=无强制（由 LLM 自主输出时），
      // 1→2 用 shortTerm，2→3 用 longTerm
      final EventTier? summarySourceTier = mustSummarizeShort
          ? EventTier.shortTerm
          : (mustSummarizeLong ? EventTier.longTerm : null);
      final pendingSummaryCap =
          mustSummarizeShort ? _summaryThreshold : _ultraSummaryThreshold;
      final pendingSummaryEvents = needSummary
          ? _queueByTier(currentContact.eventGraph,
                  mustSummarizeShort ? EventTier.shortTerm : EventTier.longTerm)
              .where((e) => !e.summarized)
              .take(pendingSummaryCap)
              .map((e) => e.event)
              .toList()
          : <EventMemory>[];

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
        await _agentStore.saveMessagesByContact(_messagesByContact);
      }

      // 步骤5: 发送AI请求
      final reply = await _repository.askAi(
        contactId: selected.id,
        contactName: selected.name,
        userMessage: userMessage,
        systemPrompt: systemPrompt,
        settings: _appSettings,
      );

      // 更新用户消息状态为已发送
      _updateMessageStatus(selected.id, userMessage.id, MessageStatus.sent);

      // 步骤6: 提取回复内容（从JSON中提取reply字段）
      final replyContent =
          StructuredOutputRegexParser.extractReply(reply.content);

      // 检查是否成功提取到回复内容
      if (replyContent == null) {
        // 如果提取失败，可能是AI返回了错误消息
        error = 'AI 回复格式错误，请稍后重试';
        _updateMessageStatus(selected.id, userMessage.id, MessageStatus.failed);
        return;
      }

      currentList.add(
        Message(
          id: reply.id,
          role: reply.role,
          content: replyContent,
          createdAt: reply.createdAt,
        ),
      );

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

      await _agentStore.saveMessagesByContact(_messagesByContact);

      // 步骤7: 更新联系人记忆
      await _updateContactFromMemoryPatch(
        selected,
        reply.content,
        userInput: input,
        inputKeywords: keywords.mergedKeywords,
        summarySourceTier: summarySourceTier,
      );
    } on AiServiceException catch (e) {
      error = e.userMessage;
      _updateMessageStatus(selected.id, userMessage.id, MessageStatus.failed);
      _heartbeat.markReconnecting();
      // 发送失败时回退记忆状态，但保留消息列表显示
      await _rollbackMemoryOnFailure(selected.id);
    } catch (e, st) {
      debugPrint('sendMessage failed: $e');
      debugPrint('$st');
      final raw = e.toString().trim();
      error = raw.isEmpty ? AppStrings.networkError : '请求失败：$raw';
      _updateMessageStatus(selected.id, userMessage.id, MessageStatus.failed);
      _heartbeat.markReconnecting();
      // 发送失败时回退记忆状态，但保留消息列表显示
      await _rollbackMemoryOnFailure(selected.id);
    } finally {
      isLoading = false;
      isTyping = false;
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
    final result = await _opencodeService.execute(input);

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
    await _agentStore.saveMessagesByContact(_messagesByContact);

    // 4. 若 service 自动选了 sessionId，持久化下来
    final currentSession = _opencodeService.config.sessionId;
    if (currentSession.isNotEmpty &&
        currentSession != opencodeConfig.sessionId) {
      await saveOpencodeConfig(
          opencodeConfig.copyWith(sessionId: currentSession));
    }

    isLoading = false;
    isTyping = false;
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
    await _agentStore.saveMessagesByContact(_messagesByContact);
    notifyListeners();

    // 重新发送
    await sendMessage(message.content);
  }

  /// 更新消息状态
  void _updateMessageStatus(
      String contactId, String messageId, MessageStatus status) {
    final messages = _messagesByContact[contactId];
    if (messages == null) return;

    final messageIndex = messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    messages[messageIndex] = messages[messageIndex].copyWith(status: status);
    _agentStore.saveMessagesByContact(_messagesByContact);
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
    await _agentStore.saveContacts(_contacts);
    await _agentStore.saveMessagesByContact(_messagesByContact);

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
    await _agentStore.saveContacts(_contacts);

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
    // 本轮触发的级联方向：null=无强制（仅 LLM 自主输出时），
    // shortTerm = 1→2 级联（summary 入长期），
    // longTerm = 2→3 级联（summary 入超长期）
    EventTier? summarySourceTier,
  }) async {
    final patch = StructuredOutputRegexParser.extractMemoryPatch(response);
    if (patch == null) return;

    // 提取各类数据（使用安全提取方法，支持字段可选）
    // 传入用户输入和 AI 回复，用于保存原始对话内容到事件中
    final incomingEvents = _extractEventsFromPatch(
      patch,
      userInput: userInput,
      aiReply: response,
    );
    final world = _mergeUnique(
      contact.worldKnowledge.items,
      StructuredOutputRegexParser.extractStringList(patch, 'worldKnowledge'),
    );
    final self = _mergeUnique(
      contact.selfKnowledge.items,
      StructuredOutputRegexParser.extractStringList(patch, 'selfKnowledge'),
    );
    final user = _mergeUnique(
      contact.userKnowledge.items,
      StructuredOutputRegexParser.extractStringList(patch, 'userKnowledge'),
    );
    final status = _mergeUnique(
      contact.status,
      StructuredOutputRegexParser.extractStringList(patch, 'status'),
    );
    final currentStates = _mergeCurrentStates(
      contact.currentStates,
      StructuredOutputRegexParser.extractStringMap(patch, 'currentStates'),
    );
    final patchBelongings = _extractBelongingPatchItems(
      StructuredOutputRegexParser.extractStringList(patch, 'belongings'),
    );

    // 更新事件图
    // 每轮清空belongingEventQueues、settingEventQueues和edges，只保留当前轮的关联
    var graph = contact.eventGraph.copyWith(
      turnCount: contact.eventGraph.turnCount + 1,
      belongingEventQueues: const <String, List<String>>{},
      settingEventQueues: const <String, List<String>>{},
      edges: const <String, EventEdge>{},
    );

    // 处理新事件
    // incomingEvents 现在只负责记忆事件：summary 和 eventBrief。
    // 顶层 reply 是给用户看的回复；故事模式下 reply 同时就是详细续写。
    // summary: 往期事件总结，进入长期队列（关键：必须真存进 long-term，
    //          下次 LLM prompt 通过 long-term.filter(!summarized) 才能再看到）
    // eventBrief: 本次事件缩写，进入短期队列
    String? currentEventNodeId;
    if (incomingEvents.isNotEmpty) {
      final summaryEvent = incomingEvents.summary;
      final briefEvent = incomingEvents.brief;

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
        graph = _enqueueNode(
          graph,
          tier: targetTier,
          event: summaryEvent,
          contactId: contact.id,
        );
        // 2) 源层里未总结的旧事件：原地标 summarized，不迁层
        //    - prompt 用 where(!summarized) 过滤，自然不再展示这些旧事件
        //    - 源层 LRU 在超容量（maxShortQueue/maxLongQueue）时会自然清理
        //    - 不再把 N 个旧事件批量复制到目标层
        final sourceUnsummarized = _queueByTier(graph, sourceTier)
            .where((e) => !e.summarized)
            .toList();
        graph = _markNodesSummarized(
          graph,
          sourceTier: sourceTier,
          sourceNodeIds: sourceUnsummarized.map((e) => e.id).toSet(),
        );
      }

      // 将 eventBrief 加入短期队列
      if (briefEvent != null && !briefEvent.isEmpty) {
        graph = _enqueueNode(
          graph,
          tier: EventTier.shortTerm,
          event: briefEvent,
          contactId: contact.id,
        );
        currentEventNodeId = graph.shortTermQueue.isNotEmpty
            ? graph.shortTermQueue.first.id
            : null;
      }
    }

    // 对所有事件队列应用LRU排序（仅本地存储部分）
    // 各层级固定输入LLM的事件不参与LRU排序
    graph = _applyLruToAllQueues(graph, inputKeywords: inputKeywords);

    // 更新物品关联和边关系（应用LRU排序）
    graph = _applyBelongingQueuesAndEdges(
      graph: graph,
      eventNodeId: currentEventNodeId,
      patch: patchBelongings,
      inputKeywords: inputKeywords,
    );

    // 更新设定关联和边关系
    graph = _applySettingQueuesAndEdges(
      graph: graph,
      eventNodeId: currentEventNodeId,
      settings: contact.settings,
      inputKeywords: inputKeywords,
    );

    // 根据 LLM 输出的 relatedEventIds 建立边关系
    if (currentEventNodeId != null) {
      graph = _applyLlmRelatedEdges(
        graph: graph,
        currentEventNodeId: currentEventNodeId,
        patch: patch,
      );
    }

    // 更新联系人数据
    final idx = _contacts.indexWhere((e) => e.id == contact.id);
    if (idx < 0) return;
    _contacts[idx] = Contact(
      id: contact.id,
      name: contact.name,
      avatar: contact.avatar,
      category: contact.category,
      fixedInput: contact.fixedInput,
      currentStates: currentStates,
      personality: contact.personality,
      appearance: contact.appearance,
      personalInfo: contact.personalInfo,
      settings: contact.settings,
      backgroundStory: contact.backgroundStory,
      narrativeRules: contact.narrativeRules,
      otherCharacteristics: contact.otherCharacteristics,
      worldKnowledge: WorldKnowledgeBucket(world),
      selfKnowledge: SelfKnowledgeBucket(self),
      userKnowledge: UserKnowledgeBucket(user),
      keywordLibrary: _updateKeywordLibrary(
        existing: contact.keywordLibrary,
        newKeywords: _tempKeywordsByContact[contact.id] ?? const [],
        maxSize: _appSettings.keywordLibrarySize,
      ),
      themeLibrary: _updateKeywordLibrary(
        existing: contact.themeLibrary,
        newKeywords: _extractThemeFromEvents(incomingEvents.all),
        maxSize: _appSettings.keywordLibrarySize,
      ),
      events: EventLruBucket(
        _dedupeEvents(<EventMemory>[
          ...contact.events.items,
          ...incomingEvents.all,
          ..._flattenGraphEvents(graph),
        ]),
      ),
      eventGraph: graph,
      belongings: _applyBelongingsQueueUpdate(
        current: contact.belongings,
        patch: patchBelongings,
      ),
      status: status,
      mood: StructuredOutputRegexParser.extractString(patch, 'mood') ??
          contact.mood,
      time: StructuredOutputRegexParser.extractString(patch, 'time') ??
          contact.time,
      createdAt: contact.createdAt,
    );
    await _agentStore.saveContacts(_contacts);
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

  /// 根据 LLM 输出的 relatedEventIds 建立边关系
  ///
  /// LLM 在输出中选择与本次事件有非常强因果关系或高度相似的往期事件编号。
  /// 这些编号对应 Prompt 中事件记忆的 [编号]。
  ///
  /// 硬约束：每个当前事件最多连 2 个往期事件，避免 LLM 一味堆砌关联导致
  /// 事件图边过密、LRU 评分被关联权重污染。
  static const int _maxLlmRelatedEdgesPerEvent = 2;

  EventGraphMemory _applyLlmRelatedEdges({
    required EventGraphMemory graph,
    required String currentEventNodeId,
    required Map<String, dynamic> patch,
  }) {
    // 提取 relatedEventIds
    final relatedIdsRaw = patch['relatedEventIds'];
    if (relatedIdsRaw is! List || relatedIdsRaw.isEmpty) return graph;

    // 收集所有事件节点（按 Prompt 中的顺序）
    final allNodes = <EventNode>[
      ...graph.shortTermQueue,
      ...graph.longTermQueue,
      ...graph.ultraLongTermQueue,
    ];

    var out = graph;
    int added = 0;
    for (final idRaw in relatedIdsRaw) {
      if (added >= _maxLlmRelatedEdgesPerEvent) break; // 硬上限：宁缺毋滥
      final idx = idRaw is int ? idRaw : int.tryParse(idRaw.toString());
      if (idx == null || idx < 0 || idx >= allNodes.length) continue;
      final targetNodeId = allNodes[idx].id;
      if (targetNodeId == currentEventNodeId) continue;
      // 避免重复边：当前事件已经连过 target 就不重复连
      final existingKey = '$currentEventNodeId->$targetNodeId';
      if (out.edges.containsKey(existingKey)) continue;
      out = _appendEdge(out,
          fromNodeId: currentEventNodeId, toNodeId: targetNodeId);
      added++;
    }

    return out;
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
  Contact? _buildPromptContact(Contact? contact,
      {required List<String> inputKeywords}) {
    if (contact == null) return null;

    // 获取各层级事件队列（已按LRU排序存储在本地）
    final shortQueue = contact.eventGraph.shortTermQueue;
    final longQueue = contact.eventGraph.longTermQueue;
    final ultraQueue = contact.eventGraph.ultraLongTermQueue;

    // 前N条固定输入LLM（保持时间顺序，最新的在前）
    final llmEvents = <EventMemory>[
      ...shortQueue
          .where((e) => !e.summarized)
          .take(_maxShortTermEvents)
          .map((e) => e.event),
      ...longQueue
          .where((e) => !e.summarized)
          .take(_maxLongTermEvents)
          .map((e) => e.event),
      ...ultraQueue.take(_maxUltraTermEvents).map((e) => e.event),
    ];

    final related = contact.eventGraph
        .relatedEventsForPrompt(
          inputKeywords,
          depth: _appSettings.searchDepth,
        )
        .take(_maxRelatedEvents);

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

    return Contact(
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
      events: EventLruBucket(
          _dedupeEvents(<EventMemory>[...llmEvents, ...related])),
      eventGraph: contact.eventGraph,
      belongings: _firstN(contact.belongings, _maxPromptListItems),
      status: contact.status,
      mood: contact.mood,
      time: contact.time,
      createdAt: contact.createdAt,
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

  /// 对所有事件队列应用LRU排序（仅用于本地存储优化）
  ///
  /// 各层级固定输入LLM的数量：
  /// - 短期：前10个固定，第11个及以后LRU排序
  /// - 长期：前5个固定，第6个及以后LRU排序
  /// - 超长期：前2个固定，第3个及以后LRU排序
  ///
  /// LRU排序规则：
  /// 1. 与当前用户输入关键词匹配的事件（权重100）
  /// 2. 与关键词匹配事件有event-event关联的（权重50）
  /// 3. 与关键词相关belonging有event-belonging关联的（权重30）
  /// 4. 普通event-belonging关联的（权重10）
  /// 5. 其他事件按时间倒序（新的在前）
  EventGraphMemory _applyLruToAllQueues(
    EventGraphMemory graph, {
    required List<String> inputKeywords,
  }) {
    // 各层级固定输入LLM的数量
    const shortFixed = 10;
    const longFixed = 5;
    const ultraFixed = 2;

    var result = graph;

    // 对短期队列应用LRU
    result = _applyLruToQueue(
      result,
      tier: EventTier.shortTerm,
      fixedCount: shortFixed,
      inputKeywords: inputKeywords,
    );

    // 对长期队列应用LRU
    result = _applyLruToQueue(
      result,
      tier: EventTier.longTerm,
      fixedCount: longFixed,
      inputKeywords: inputKeywords,
    );

    // 对超长期队列应用LRU
    result = _applyLruToQueue(
      result,
      tier: EventTier.ultraLongTerm,
      fixedCount: ultraFixed,
      inputKeywords: inputKeywords,
    );

    return result;
  }

  /// 对指定层级的事件队列应用LRU排序
  ///
  /// [fixedCount] 固定输入LLM的事件数量，不参与LRU排序
  EventGraphMemory _applyLruToQueue(
    EventGraphMemory graph, {
    required EventTier tier,
    required int fixedCount,
    required List<String> inputKeywords,
  }) {
    List<EventNode> getQueue() {
      switch (tier) {
        case EventTier.shortTerm:
          return graph.shortTermQueue;
        case EventTier.longTerm:
          return graph.longTermQueue;
        case EventTier.ultraLongTerm:
          return graph.ultraLongTermQueue;
      }
    }

    final queue = getQueue();
    if (queue.length <= fixedCount) return graph; // 不足固定数量不需要LRU排序

    // 前fixedCount个保持原顺序（时间倒序，最新的在前）
    final fixedEvents = queue.take(fixedCount).toList();

    // 剩余事件应用LRU排序
    final remaining = queue.skip(fixedCount).toList();
    final sortedRemaining = _sortEventsByLruScore(
      remaining,
      graph: graph,
      inputKeywords: inputKeywords,
    );

    // 合并队列：固定部分 + LRU排序部分
    final newQueue = <EventNode>[...fixedEvents, ...sortedRemaining];

    switch (tier) {
      case EventTier.shortTerm:
        return graph.copyWith(shortTermQueue: newQueue);
      case EventTier.longTerm:
        return graph.copyWith(longTermQueue: newQueue);
      case EventTier.ultraLongTerm:
        return graph.copyWith(ultraLongTermQueue: newQueue);
    }
  }

  /// 对事件列表按LRU分数排序
  List<EventNode> _sortEventsByLruScore(
    List<EventNode> events, {
    required EventGraphMemory graph,
    required List<String> inputKeywords,
  }) {
    if (events.isEmpty) return events;

    // 使用 LLM 提取的关键词
    final keywords = inputKeywords.map((e) => e.toLowerCase()).toSet();

    // 构建节点ID到节点的映射（包含所有事件，用于查找关联）
    final allNodes = <String, EventNode>{
      for (final node in graph.shortTermQueue) node.id: node,
      for (final node in graph.longTermQueue) node.id: node,
      for (final node in graph.ultraLongTermQueue) node.id: node,
    };

    // 构建邻接表（event-event边）
    final adjacent = <String, Set<String>>{};
    for (final edge in graph.edges.values) {
      if (allNodes.containsKey(edge.fromNodeId) &&
          allNodes.containsKey(edge.toNodeId)) {
        adjacent
            .putIfAbsent(edge.fromNodeId, () => <String>{})
            .add(edge.toNodeId);
        adjacent
            .putIfAbsent(edge.toNodeId, () => <String>{})
            .add(edge.fromNodeId);
      }
    }

    // 获取LRU权重设置
    final settings = appSettings;

    // 计算每个节点的LRU分数
    final scores = <String, int>{};
    for (final node in events) {
      var score = 0;

      // 1. 检查是否与用户输入关键词匹配（使用事件的 keywords + theme 字段）
      final nodeKeywords =
          node.event.keywords.map((e) => e.toLowerCase()).toSet();
      final nodeTheme = node.event.theme.map((e) => e.toLowerCase()).toSet();
      final nodeAll = <String>{...nodeKeywords, ...nodeTheme};
      final keywordMatches = keywords.intersection(nodeAll).length;
      score += keywordMatches * settings.lruKeywordMatchWeight;

      // 2. 检查是否有event-event关联（与被关键词匹配的事件相连）
      final neighbors = adjacent[node.id] ?? const <String>{};
      for (final neighborId in neighbors) {
        final neighbor = allNodes[neighborId];
        if (neighbor == null) continue;
        final neighborKeywords =
            neighbor.event.keywords.map((e) => e.toLowerCase()).toSet();
        final neighborTheme =
            neighbor.event.theme.map((e) => e.toLowerCase()).toSet();
        final neighborAll = <String>{...neighborKeywords, ...neighborTheme};
        if (keywords.intersection(neighborAll).isNotEmpty) {
          score += settings.lruEventEventWeight;
          break;
        }
      }

      // 3. 检查是否有event-belonging关联
      for (final entry in graph.belongingEventQueues.entries) {
        final queue = entry.value;
        if (queue.contains(node.id)) {
          final keyLower = entry.key.toLowerCase();
          if (keywords
              .any((kw) => keyLower.contains(kw) || kw.contains(keyLower))) {
            score += settings.lruEventBelongingKeywordWeight;
          } else {
            score += settings.lruEventBelongingNormalWeight;
          }
          break;
        }
      }

      // 4. 检查是否有event-setting关联
      for (final entry in graph.settingEventQueues.entries) {
        final queue = entry.value;
        if (queue.contains(node.id)) {
          final keyLower = entry.key.toLowerCase();
          if (keywords
              .any((kw) => keyLower.contains(kw) || kw.contains(keyLower))) {
            score += settings.lruEventSettingKeywordWeight;
          } else {
            score += settings.lruEventSettingNormalWeight;
          }
          break;
        }
      }

      scores[node.id] = score;
    }

    // 按分数降序排序，分数相同的按时间倒序（新的在前）
    final sorted = List<EventNode>.from(events);
    sorted.sort((a, b) {
      final scoreA = scores[a.id] ?? 0;
      final scoreB = scores[b.id] ?? 0;
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA);
      }
      return b.createdAtMs.compareTo(a.createdAtMs);
    });

    return sorted;
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
      final raw = await _repository.askUtility(
        contactId: contactId,
        contactName: contactName,
        prompt: _buildKeywordPrompt(
            userInput, existingKeywordLibrary, existingThemeLibrary),
      );
      final parsed = _parseKeywordsAndThemeFromRaw(raw);
      llm = parsed.keywords;
      llmTheme = parsed.theme;
    } catch (_) {
      // 解析失败，重试一次
      try {
        final raw = await _repository.askUtility(
          contactId: contactId,
          contactName: contactName,
          prompt: _buildKeywordPrompt(
              userInput, existingKeywordLibrary, existingThemeLibrary),
        );
        final parsed = _parseKeywordsAndThemeFromRaw(raw);
        llm = parsed.keywords;
        llmTheme = parsed.theme;
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

  // ==================== 事件图操作辅助方法 ====================

  /// 应用物品队列和边关系更新（全局LRU管理）
  ///
  /// 当物品被标记为新增或提及时：
  /// 1. 将当前事件ID加入物品的关联队列
  /// 2. 对队列应用LRU排序（基于事件与当前输入的相关性）
  /// 3. 在物品节点和事件节点之间建立边
  ///
  /// LRU规则：
  /// - 与当前用户输入关键词匹配的事件排在前面
  /// - 与关键词匹配事件有关联的排在前面
  /// - 其他事件按时间倒序
  EventGraphMemory _applyBelongingQueuesAndEdges({
    required EventGraphMemory graph,
    required String? eventNodeId,
    required List<_BelongingPatchItem> patch,
    required List<String> inputKeywords,
  }) {
    if (patch.isEmpty || eventNodeId == null || eventNodeId.isEmpty) {
      return graph;
    }

    // 使用 LLM 提取的关键词
    final keywords = inputKeywords.map((e) => e.toLowerCase()).toSet();

    // 构建节点ID到节点的映射
    final allNodes = <String, EventNode>{
      for (final node in graph.shortTermQueue) node.id: node,
      for (final node in graph.longTermQueue) node.id: node,
      for (final node in graph.ultraLongTermQueue) node.id: node,
    };

    final queues = <String, List<String>>{
      for (final e in graph.belongingEventQueues.entries)
        e.key: List<String>.from(e.value),
    };
    var out = graph;

    for (final item in patch) {
      // 获取或创建队列
      var queue = queues.putIfAbsent(item.name, () => <String>[]);

      // 添加新事件ID
      queue.add(eventNodeId);

      // 对队列应用LRU排序
      queue = _sortBelongingQueueByLru(
        queue,
        allNodes: allNodes,
        keywords: keywords,
      );

      // 限制队列长度（保留最相关的100个）
      if (queue.length > 100) {
        queue = queue.sublist(0, 100);
      }

      queues[item.name] = queue;
    }

    return out.copyWith(belongingEventQueues: queues);
  }

  /// 对belonging队列应用LRU排序
  ///
  /// 排序规则：
  /// 1. 与关键词匹配的事件（权重100）
  /// 2. 其他事件按时间倒序（新的在前）
  List<String> _sortBelongingQueueByLru(
    List<String> queue, {
    required Map<String, EventNode> allNodes,
    required Set<String> keywords,
  }) {
    if (queue.isEmpty || keywords.isEmpty) return queue;

    // 计算每个事件ID的LRU分数
    final scores = <String, int>{};

    for (final eventId in queue) {
      final node = allNodes[eventId];
      if (node == null) {
        scores[eventId] = 0;
        continue;
      }

      var score = 0;

      // 检查是否与用户输入关键词匹配（使用事件的 keywords + theme 字段）
      final nodeKeywords =
          node.event.keywords.map((e) => e.toLowerCase()).toSet();
      final nodeTheme = node.event.theme.map((e) => e.toLowerCase()).toSet();
      final nodeAll = <String>{...nodeKeywords, ...nodeTheme};
      final keywordMatches = keywords.intersection(nodeAll).length;
      score += keywordMatches * 100;

      // 加上时间戳作为次要排序依据（新的在前）
      score += (node.createdAtMs ~/ 1000000);

      scores[eventId] = score;
    }

    // 按分数降序排序
    final sorted = List<String>.from(queue);
    sorted.sort((a, b) {
      final scoreA = scores[a] ?? 0;
      final scoreB = scores[b] ?? 0;
      return scoreB.compareTo(scoreA);
    });

    return sorted;
  }

  /// 应用设定关联队列和边关系（全局LRU管理）
  ///
  /// 根据用户输入中的关键词，匹配 contact.settings 中的设定，
  /// 建立 setting-event 关联，并对队列应用LRU排序
  ///
  /// LRU规则：
  /// - 与当前用户输入关键词匹配的事件排在前面
  /// - 其他事件按时间倒序（新的在前）
  EventGraphMemory _applySettingQueuesAndEdges({
    required EventGraphMemory graph,
    required String? eventNodeId,
    required List<Map<String, dynamic>> settings,
    required List<String> inputKeywords,
  }) {
    if (eventNodeId == null ||
        eventNodeId.isEmpty ||
        settings.isEmpty ||
        inputKeywords.isEmpty) {
      return graph;
    }

    // 使用 LLM 提取的关键词
    final keywords = inputKeywords.map((e) => e.toLowerCase()).toSet();

    // 构建节点ID到节点的映射
    final allNodes = <String, EventNode>{
      for (final node in graph.shortTermQueue) node.id: node,
      for (final node in graph.longTermQueue) node.id: node,
      for (final node in graph.ultraLongTermQueue) node.id: node,
    };

    final queues = <String, List<String>>{
      for (final e in graph.settingEventQueues.entries)
        e.key: List<String>.from(e.value),
    };
    var out = graph;

    for (final setting in settings) {
      final key = (setting['key'] as String? ?? '').trim();
      final value = (setting['value'] as String? ?? '').trim();
      final relate = (setting['relate'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          <String>[];

      if (key.isEmpty) continue;

      // 构建可搜索文本：key + value + relate
      final searchableText = '$key $value ${relate.join(' ')}';
      final settingKeywords =
          searchableText.toLowerCase().split(RegExp(r'\s+')).toSet();

      // 检查是否有关键词匹配
      if (keywords.intersection(settingKeywords).isNotEmpty) {
        // 获取或创建队列
        var queue = queues.putIfAbsent(key, () => <String>[]);

        // 添加新事件ID
        queue.add(eventNodeId);

        // 对队列应用LRU排序
        queue = _sortBelongingQueueByLru(
          queue,
          allNodes: allNodes,
          keywords: keywords,
        );

        // 限制队列长度（保留最相关的100个）
        if (queue.length > 100) {
          queue = queue.sublist(0, 100);
        }

        queues[key] = queue;
      }
    }

    return out.copyWith(settingEventQueues: queues);
  }

  /// 将事件节点加入指定层级队列
  ///
  /// 创建新节点并：
  /// 1. 添加到队列头部（最新的在前）
  /// 2. 限制队列长度（超长事件会被删除）
  /// 3. 与前一个节点建立边关系（时间顺序）
  /// 4. 同步删除被截断事件的向量数据
  EventGraphMemory _enqueueNode(
    EventGraphMemory graph, {
    required EventTier tier,
    required EventMemory event,
    String? contactId,
  }) {
    if (event.isEmpty) return graph;
    // 创建新节点
    final node = EventNode(
      id: '${tier.storageKey}-${DateTime.now().microsecondsSinceEpoch}-${event.toPromptLine().hashCode.abs()}',
      tier: tier,
      event: event,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      summarized: false,
    );
    switch (tier) {
      case EventTier.shortTerm:
        final newQueue = <EventNode>[node, ...graph.shortTermQueue];
        // 找出被截断的事件并删除对应的向量数据
        _deleteTruncatedEventsFromVectorMemory(
          newQueue,
          _maxShortQueue,
          contactId,
        );
        var out = graph.copyWith(
          shortTermQueue: newQueue.take(_maxShortQueue).toList(),
        );
        return out;
      case EventTier.longTerm:
        final newQueue = <EventNode>[node, ...graph.longTermQueue];
        // 找出被截断的事件并删除对应的向量数据
        _deleteTruncatedEventsFromVectorMemory(
          newQueue,
          _maxLongQueue,
          contactId,
        );
        var out = graph.copyWith(
          longTermQueue: newQueue.take(_maxLongQueue).toList(),
        );
        return out;
      case EventTier.ultraLongTerm:
        final newQueue = <EventNode>[node, ...graph.ultraLongTermQueue];
        // 找出被截断的事件并删除对应的向量数据
        _deleteTruncatedEventsFromVectorMemory(
          newQueue,
          _maxUltraQueue,
          contactId,
        );
        var out = graph.copyWith(
          ultraLongTermQueue: newQueue.take(_maxUltraQueue).toList(),
        );
        return out;
    }
  }

  /// 删除被截断事件的向量数据
  ///
  /// [newQueue] 新的事件队列（截断前）
  /// [maxSize] 队列最大长度
  /// [contactId] 当前联系人ID
  void _deleteTruncatedEventsFromVectorMemory(
    List<EventNode> newQueue,
    int maxSize,
    String? contactId,
  ) {
    if (contactId == null || newQueue.length <= maxSize) return;

    // 获取被截断的事件（超出 maxSize 的部分）
    final truncatedEvents = newQueue.skip(maxSize).toList();
  }

  /// 添加边关系到事件图
  ///
  /// 使用唯一键去重，避免重复边
  EventGraphMemory _appendEdge(
    EventGraphMemory graph, {
    required String fromNodeId,
    required String toNodeId,
  }) {
    if (fromNodeId.trim().isEmpty || toNodeId.trim().isEmpty) return graph;
    final edge = EventEdge(fromNodeId: fromNodeId, toNodeId: toNodeId);
    final edgeMap = <String, EventEdge>{
      ...graph.edges,
      edge.toUniqueKey(): edge,
    };
    return graph.copyWith(edges: edgeMap);
  }

  /// 标记节点为已总结
  ///
  /// 在事件总结后，将被合并的原始节点标记为summarized=true
  EventGraphMemory _markNodesSummarized(
    EventGraphMemory graph, {
    required EventTier sourceTier,
    required Set<String> sourceNodeIds,
  }) {
    if (sourceNodeIds.isEmpty) return graph;
    List<EventNode> mark(List<EventNode> queue) => queue
        .map(
          (n) => sourceNodeIds.contains(n.id)
              ? EventNode(
                  id: n.id,
                  tier: n.tier,
                  event: n.event,
                  createdAtMs: n.createdAtMs,
                  summarized: true,
                )
              : n,
        )
        .toList();
    switch (sourceTier) {
      case EventTier.shortTerm:
        return graph.copyWith(shortTermQueue: mark(graph.shortTermQueue));
      case EventTier.longTerm:
        return graph.copyWith(longTermQueue: mark(graph.longTermQueue));
      case EventTier.ultraLongTerm:
        return graph;
    }
  }

  /// 获取指定层级的未总结事件数量
  int _unsummarizedCount(EventGraphMemory graph, EventTier tier) =>
      _queueByTier(graph, tier).where((n) => !n.summarized).length;

  /// 获取指定层级的事件队列
  List<EventNode> _queueByTier(EventGraphMemory graph, EventTier tier) {
    switch (tier) {
      case EventTier.shortTerm:
        return graph.shortTermQueue;
      case EventTier.longTerm:
        return graph.longTermQueue;
      case EventTier.ultraLongTerm:
        return graph.ultraLongTermQueue;
    }
  }

  /// 扁平化事件图，获取所有事件
  List<EventMemory> _flattenGraphEvents(EventGraphMemory graph) =>
      <EventMemory>[
        ...graph.shortTermQueue.map((e) => e.event),
        ...graph.longTermQueue.map((e) => e.event),
        ...graph.ultraLongTermQueue.map((e) => e.event),
      ];

  // ==================== 数据提取辅助方法 ====================

  /// 从 memoryPatch 中提取事件列表
  ///
  /// [userInput] 用户输入内容
  /// [aiReply] AI 回复内容（原始 JSON 响应）
  /// 提取的事件会包含 sourceDialog 字段，记录原始对话内容
  ///
  /// 返回记忆事件：summary 和 eventBrief。
  /// 顶层 reply 是给用户的回复；故事模式下 reply 同时就是详细续写，
  /// 不再从 memoryPatch 读取单独的详细事件字段。
  _ExtractedPatchEvents _extractEventsFromPatch(
    Map<String, dynamic>? patch, {
    String userInput = '',
    String aiReply = '',
  }) {
    if (patch == null) return const _ExtractedPatchEvents();

    // 构建原始对话内容
    final sourceDialog = _buildSourceDialog(userInput, aiReply);

    EventMemory? summaryEvent;
    EventMemory? briefEvent;

    // 提取 summary（往期事件总结）
    final summaryRaw = patch['summary'];
    if (summaryRaw is Map<String, dynamic>) {
      final summary = EventMemory.fromJson(summaryRaw);
      if (!summary.isEmpty) {
        summaryEvent = EventMemory(
          description: summary.description,
          keywords: summary.keywords,
          theme: summary.theme,
          sourceDialog: sourceDialog,
        );
      }
    }

    // 提取 eventBrief（本次事件缩写）
    final briefRaw = patch['eventBrief'];
    if (briefRaw is Map<String, dynamic>) {
      final brief = EventMemory.fromJson(briefRaw);
      if (!brief.isEmpty) {
        briefEvent = EventMemory(
          description: brief.description,
          keywords: brief.keywords,
          theme: brief.theme,
          sourceDialog: sourceDialog,
        );
      }
    }

    return _ExtractedPatchEvents(
      summary: summaryEvent,
      brief: briefEvent,
    );
  }

  /// 构建原始对话内容字符串
  String _buildSourceDialog(String userInput, String aiReply) {
    final buffer = StringBuffer();
    if (userInput.trim().isNotEmpty) {
      buffer.writeln('用户：$userInput');
    }
    if (aiReply.trim().isNotEmpty) {
      // 尝试提取 AI 回复中的 reply 字段内容
      final replyContent =
          StructuredOutputRegexParser.extractReply(aiReply) ?? aiReply;
      buffer.writeln('AI：$replyContent');
    }
    return buffer.toString().trim();
  }

  /// 从JSON中提取字符串列表
  List<String> _extractStrings(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Map<String, String> _extractStringMap(dynamic value) {
    if (value is! Map) return const <String, String>{};
    return _normalizeStateMap(
      value.map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? '')),
    );
  }

  Map<String, String> _normalizeStateMap(Map<String, String> value) {
    final out = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;
      out[key] = entry.value.trim();
    }
    return out;
  }

  Map<String, String> _mergeCurrentStates(
    Map<String, String> current,
    Map<String, String> patch,
  ) {
    final out = Map<String, String>.from(current);
    for (final entry in patch.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || !out.containsKey(key)) continue;
      out[key] = entry.value.trim();
    }
    return out;
  }

  List<Map<String, dynamic>> _extractSettings(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is! Map) continue;
      final map = _asMap(item);
      final key = (map['key'] ?? '').toString().trim();
      final settingValue = (map['value'] ?? '').toString().trim();
      if (key.isEmpty || settingValue.isEmpty) continue;
      final relate = _extractStrings(map['relate']);
      out.add({
        'key': key,
        'value': settingValue,
        'relate': relate,
      });
    }
    return out;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
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

  /// 从字符串列表中提取物品补丁项
  ///
  /// 解析格式：(新增)物品名 或 (提及)物品名
  List<_BelongingPatchItem> _extractBelongingPatchItems(List<String> items) {
    final out = <_BelongingPatchItem>[];
    final reg = RegExp(r'^[\(\（]\s*(新增|提及)\s*[\)\）]\s*(.+)$');
    for (final text in items) {
      final m = reg.firstMatch(text);
      if (m == null) continue;
      final tag = m.group(1)?.trim() ?? '';
      final name = m.group(2)?.trim() ?? '';
      if (name.isEmpty) continue;
      out.add(
        _BelongingPatchItem(
          type: tag == '新增'
              ? _BelongingPatchType.added
              : _BelongingPatchType.mentioned,
          name: name,
        ),
      );
    }
    return out;
  }

  /// 应用物品队列更新
  ///
  /// 将新增或提及的物品移到队列末尾（表示最近使用）
  List<String> _applyBelongingsQueueUpdate({
    required List<String> current,
    required List<_BelongingPatchItem> patch,
  }) {
    if (patch.isEmpty) return List<String>.from(current);
    final out = <String>[...current];
    for (final item in patch) {
      final idx = out.indexWhere((e) => e == item.name);
      if (idx >= 0) out.removeAt(idx);
      out.add(item.name);
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
    super.dispose();
  }
}

// ==================== 内部数据类 ====================

class _ExtractedPatchEvents {
  const _ExtractedPatchEvents({
    this.summary,
    this.brief,
  });

  final EventMemory? summary;
  final EventMemory? brief;

  bool get isNotEmpty => summary != null || brief != null;

  List<EventMemory> get all => <EventMemory>[
        if (summary != null) summary!,
        if (brief != null) brief!,
      ];
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

/// 物品补丁类型
enum _BelongingPatchType { added, mentioned }

/// 物品补丁项
class _BelongingPatchItem {
  const _BelongingPatchItem({
    required this.type,
    required this.name,
  });

  /// 补丁类型（新增或提及）
  final _BelongingPatchType type;

  /// 物品名称
  final String name;
}
