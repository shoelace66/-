import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/data/models/app_settings.dart';
import '../../../../core/utils/chinese_tokenizer_service.dart';
import '../../../../core/utils/structured_input_prompt_composer.dart';
import '../../../../core/utils/structured_output_regex_parser.dart';
import '../../../../core/utils/vector_memory_service.dart';
import '../../../../infrastructure/services/ai_service.dart';
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
    final raw = prefs.getString('app_settings_v1');
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
  }

  /// 事件总结阈值
  int get _summaryThreshold => _appSettings.summaryThreshold;

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

  /// 向量记忆服务
  ///
  /// 用于存储和搜索向量嵌入的记忆
  final VectorMemoryService _vectorMemory = VectorMemoryService();

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

  /// 系统提示词
  ///
  /// 作为基础系统提示，会与联系人信息合并后发送给LLM
  String _systemPrompt = 'You are a helpful assistant.';

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
      // 初始化向量记忆服务
      await _vectorMemory.initialize();
    } catch (e) {
      debugPrint('ChatProvider.initialize: 向量记忆服务初始化失败: $e');
      // 继续初始化，不因为向量服务失败而中断
    }

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
      _systemPrompt = (settings['systemPrompt'] ?? _systemPrompt).toString();
      ApiConstants.runtimeApiKey = _apiKey;
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

  /// 保存API密钥
  ///
  /// 同时更新内存状态和持久化存储
  Future<void> saveApiKey(String apiKey) async {
    _apiKey = apiKey.trim();
    ApiConstants.runtimeApiKey = _apiKey;
    final settings = await _agentStore.readAgentSettings();
    settings['apiKey'] = _apiKey;
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
      personality: personality,
      appearance: appearance,
      personalInfo: personalInfo,
      settings: settings,
      backgroundStory: backgroundStory,
      narrativeRules: narrativeRules,
      otherCharacteristics: otherCharacteristics,
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

      final contact = Contact(
        id: id,
        name: name,
        avatar: (json['avatar'] ?? '').toString(),
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
    List<String>? fallbackPersonality,
    List<String>? fallbackAppearance,
    List<String>? fallbackPersonalInfo,
    List<Map<String, dynamic>>? fallbackSettings,
    List<String>? fallbackBackgroundStory,
    List<String>? fallbackNarrativeRules,
    List<String>? fallbackOtherCharacteristics,
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
      final personality = _extractStrings(json['personality']).isNotEmpty
          ? _extractStrings(json['personality'])
          : fallbackPersonality ?? <String>[];
      final appearance = _extractStrings(json['appearance']).isNotEmpty
          ? _extractStrings(json['appearance'])
          : fallbackAppearance ?? <String>[];
      final personalInfo = _extractStrings(json['personalInfo']).isNotEmpty
          ? _extractStrings(json['personalInfo'])
          : fallbackPersonalInfo ?? <String>[];
      final settings = _extractSettings(json['settings']).isNotEmpty
          ? _extractSettings(json['settings'])
          : fallbackSettings ?? <Map<String, dynamic>>[];
      final backgroundStory =
          _extractStrings(json['backgroundStory']).isNotEmpty
              ? _extractStrings(json['backgroundStory'])
              : fallbackBackgroundStory ?? <String>[];
      final narrativeRules = _extractStrings(json['narrativeRules']).isNotEmpty
          ? _extractStrings(json['narrativeRules'])
          : fallbackNarrativeRules ?? <String>[];
      final otherCharacteristics =
          _extractStrings(json['otherCharacteristics']).isNotEmpty
              ? _extractStrings(json['otherCharacteristics'])
              : fallbackOtherCharacteristics ?? <String>[];

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

    // 删除关联的向量记忆数据（与事件队列同步清理）
    await _vectorMemory.deleteContactMemories(contactId);

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

      // 步骤1: 提取关键词
      final keywords = await _extractTurnKeywords(
        contactId: selected.id,
        contactName: selected.name,
        userInput: userMessage.content,
      );

      // 构建搜索查询（用户输入 + 关键词）
      final query = _buildKeywordSearchInput(
        userInput: userMessage.content,
        keywords: keywords.mergedKeywords.isEmpty
            ? (_tempKeywordsByContact[selected.id] ?? const <String>[])
            : keywords.mergedKeywords,
      );

      // 向量搜索相关记忆（只搜索当前联系人的数据）
      final similarMemories = await _vectorMemory.searchSimilar(
        query,
        3, // 取前3个最相似的记忆
        type: 'message',
        contactId: selected.id,
      );

      // 应用向量相似度权重
      final weightedMemories = similarMemories.map((memory) {
        final weightedScore =
            memory.score * (_appSettings.vectorSimilarityWeight / 100);
        return _ScoredMemory(memory: memory.entry, score: weightedScore);
      }).toList();

      // 按加权分数排序
      weightedMemories.sort((a, b) => b.score.compareTo(a.score));

      // 步骤2: 构建Prompt联系人（包含筛选后的事件和知识）
      final promptContact =
          _buildPromptContact(currentContact, userInput: query);

      // 步骤3: 合并系统Prompt
      final systemPrompt = _mergeSystemPromptWithContact(
        basePrompt: _systemPrompt,
        contact: promptContact,
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
                '【调试信息】向量搜索结果\n${weightedMemories.map((m) => '${m.score.toStringAsFixed(2)}: ${m.memory.content}').join('\n')}\n\n'
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
      await _agentStore.saveMessagesByContact(_messagesByContact);

      // 步骤7: 更新联系人记忆
      await _updateContactFromMemoryPatch(
        selected,
        reply.content,
        userInput: input,
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
      // 将消息添加到向量数据库（关联当前联系人）
      await _vectorMemory.addMemoryEntry(
        userMessage.id,
        userMessage.content,
        'message',
        contactId: selected.id,
      );

      isLoading = false;
      isTyping = false;
      notifyListeners();
    }
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

    // 更新消息状态为发送中
    _updateMessageStatus(contactId, messageId, MessageStatus.sending);
    notifyListeners();

    // 重新发送消息
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
      // 获取当前消息列表，用于找出需要删除的向量数据
      final currentMessages = _messagesByContact[contactId] ?? [];
      final snapshotMessageIds =
          _lastMessagesSnapshot!.map((m) => m.id).toSet();

      // 找出本轮对话新增的消息ID（需要删除的向量数据）
      final newMessageIds = currentMessages
          .where((m) => !snapshotMessageIds.contains(m.id))
          .map((m) => m.id)
          .toList();

      // 从向量数据库中删除新增的消息向量
      for (final messageId in newMessageIds) {
        await _vectorMemory.deleteMemoryEntry(messageId);
      }

      debugPrint(
          '[recallLastTurn] 删除 ${newMessageIds.length} 条向量数据: $newMessageIds');

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

    // 2. 删除向量数据库中新增的消息向量
    if (_lastMessagesSnapshot != null) {
      final currentMessages = _messagesByContact[contactId] ?? [];
      final snapshotMessageIds =
          _lastMessagesSnapshot!.map((m) => m.id).toSet();

      // 找出新增的消息ID
      final newMessageIds = currentMessages
          .where((m) => !snapshotMessageIds.contains(m.id))
          .map((m) => m.id)
          .toList();

      // 删除向量数据
      for (final messageId in newMessageIds) {
        await _vectorMemory.deleteMemoryEntry(messageId);
      }

      debugPrint(
          '[_rollbackMemoryOnFailure] 删除 ${newMessageIds.length} 条向量数据: $newMessageIds');
    }

    // 3. 持久化恢复后的 Contact 状态
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

    // 将新事件加入短期队列
    String? currentEventNodeId;
    if (incomingEvents.isNotEmpty) {
      graph = _enqueueNode(
        graph,
        tier: EventTier.shortTerm,
        event: incomingEvents.first,
        contactId: contact.id,
      );
      currentEventNodeId = graph.shortTermQueue.isNotEmpty
          ? graph.shortTermQueue.first.id
          : null;
    }

    // 对所有事件队列应用LRU排序（仅本地存储部分）
    // 各层级固定输入LLM的事件不参与LRU排序
    graph = _applyLruToAllQueues(graph, userInput: userInput);

    // 更新物品关联和边关系（应用LRU排序）
    graph = _applyBelongingQueuesAndEdges(
      graph: graph,
      eventNodeId: currentEventNodeId,
      patch: patchBelongings,
      userInput: userInput,
    );

    // 更新设定关联和边关系
    graph = _applySettingQueuesAndEdges(
      graph: graph,
      eventNodeId: currentEventNodeId,
      settings: contact.settings,
      userInput: userInput,
    );

    // 触发事件总结
    graph = await _promoteBySummary(contact, graph);

    // 更新联系人数据
    final idx = _contacts.indexWhere((e) => e.id == contact.id);
    if (idx < 0) return;
    _contacts[idx] = Contact(
      id: contact.id,
      name: contact.name,
      avatar: contact.avatar,
      category: contact.category,
      personality: contact.personality,
      appearance: contact.appearance,
      backgroundStory: contact.backgroundStory,
      worldKnowledge: WorldKnowledgeBucket(world),
      selfKnowledge: SelfKnowledgeBucket(self),
      userKnowledge: UserKnowledgeBucket(user),
      events: EventLruBucket(
        _dedupeEvents(<EventMemory>[
          ...contact.events.items,
          ...incomingEvents,
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

  /// 根据总结阈值触发事件升级
  ///
  /// 检查短期和长期队列，如果未总结事件数达到阈值，
  /// 则调用LLM进行事件总结，将事件升级到更高层级
  Future<EventGraphMemory> _promoteBySummary(
    Contact contact,
    EventGraphMemory graph,
  ) async {
    var current = graph;
    // 检查短期队列是否需要总结
    if (_unsummarizedCount(current, EventTier.shortTerm) >= _summaryThreshold) {
      current = await _mergeRecentEvents(
        contact,
        current,
        EventTier.shortTerm,
        EventTier.longTerm,
      );
    }
    // 检查长期队列是否需要总结
    if (_unsummarizedCount(current, EventTier.longTerm) >= _summaryThreshold) {
      current = await _mergeRecentEvents(
        contact,
        current,
        EventTier.longTerm,
        EventTier.ultraLongTerm,
      );
    }
    return current;
  }

  /// 合并近期事件
  ///
  /// 将指定层级的未总结事件合并为一个更高层级的事件
  /// 流程：
  /// 1. 收集未总结事件
  /// 2. 构建总结Prompt并请求LLM
  /// 3. 解析LLM的总结决策（n和event）
  /// 4. 创建总结事件并加入目标队列
  /// 5. 建立边关系（总结事件 -> 被总结事件）
  /// 6. 标记被总结事件
  Future<EventGraphMemory> _mergeRecentEvents(
    Contact contact,
    EventGraphMemory graph,
    EventTier source,
    EventTier target,
  ) async {
    // 收集未总结事件
    final unsummarized =
        _queueByTier(graph, source).where((e) => !e.summarized).toList();
    if (unsummarized.length < _summaryThreshold) return graph;
    final candidates = unsummarized.take(_summaryThreshold).toList();

    // 请求LLM进行总结决策
    _MergeDecision decision;
    try {
      final raw = await _repository.askUtility(
        contactId: contact.id,
        contactName: contact.name,
        prompt: _buildSummaryPrompt(source, target, candidates),
      );
      decision = _normalizeMergeDecision(_parseMergeDecision(raw), candidates);
    } catch (_) {
      // 失败时使用强制总结（合并所有候选事件）
      decision = _MergeDecision(
        n: candidates.length,
        event: _buildForcedSummaryEvent(candidates),
      );
    }

    // 执行总结
    final sources = candidates.take(decision.n).toList();
    if (sources.isEmpty) return graph;

    // 创建总结事件节点
    final out = _enqueueNode(
      graph,
      tier: target,
      event: decision.event,
      contactId: contact.id,
    );
    final targetQueue = _queueByTier(out, target);
    if (targetQueue.isEmpty) return graph;
    final summaryNode = targetQueue.first;

    // 建立边关系（总结事件指向被总结事件）
    final edgeMap = <String, EventEdge>{
      ...out.edges,
    };
    for (final s in sources) {
      final edge = EventEdge(fromNodeId: summaryNode.id, toNodeId: s.id);
      edgeMap[edge.toUniqueKey()] = edge;
    }

    // 标记被总结事件并返回更新后的图
    return _markNodesSummarized(
      out.copyWith(edges: edgeMap),
      sourceTier: source,
      sourceNodeIds: sources.map((e) => e.id).toSet(),
    );
  }

  /// 构建事件总结Prompt
  ///
  /// 要求LLM：
  /// - 将短期事件归并为长期事件，或长期归并为超长期
  /// - 优先输出可归并的最近N条（2 <= n <= 10）
  /// - 若过于离散，输出n=10强制总结
  /// - 每个事件包含原始对话内容，帮助LLM更好地理解上下文
  String _buildSummaryPrompt(
    EventTier source,
    EventTier target,
    List<EventNode> candidates,
  ) {
    final b = StringBuffer();
    b.writeln('你是事件总结器。');
    b.writeln('任务：将以下${_tierLabel(source)}事件概括为 1 条${_tierLabel(target)}事件。');
    b.writeln(
      '只输出 JSON。格式：{"n":10,"event":{"time":"","location":"","characters":"","cause":"","process":"","result":"","attitude":""}}',
    );
    b.writeln('- n: 选择要概括的最近 N 条事件，n>=2 且 <=10。');
    b.writeln('- event: 概括总结这 N 条事件的核心内容，要求：');
    b.writeln('  * 高度概括，提炼关键信息，去除细节描述');
    b.writeln('  * 保留时间、地点、人物、起因、结果等核心要素');
    b.writeln('  * process 字段用一句话简要描述主要经过');
    b.writeln('  * 不要罗列具体细节，要抽象总结');
    b.writeln('  * 总结内容总字数控制在150字以内');
    b.writeln('- 若事件过于离散无法概括，输出 n=10 强制总结。');
    b.writeln('- 每个事件下方的【原始对话】提供了产生该事件的对话上下文，供你参考。');
    b.writeln('');
    for (int i = 0; i < candidates.length; i++) {
      b.writeln('--- 事件 ${i + 1} ---');
      b.writeln(candidates[i].event.toSummaryPromptLine());
      b.writeln('');
    }
    return b.toString();
  }

  /// 解析LLM的总结决策
  _MergeDecision? _parseMergeDecision(String raw) {
    final payload = StructuredOutputRegexParser.parsePrimaryPayload(raw);
    if (payload == null) return null;
    final n = int.tryParse((payload['n'] ?? '').toString()) ?? 0;
    final eventRaw = payload['event'];
    if (eventRaw is! Map<String, dynamic>) {
      return _MergeDecision(n: n, event: const EventMemory());
    }
    return _MergeDecision(n: n, event: EventMemory.fromJson(eventRaw));
  }

  /// 规范化总结决策
  ///
  /// 确保n在有效范围内，如果LLM返回的事件为空则使用强制总结
  _MergeDecision _normalizeMergeDecision(
    _MergeDecision? decision,
    List<EventNode> candidates,
  ) {
    final fallback = _buildForcedSummaryEvent(candidates);
    if (decision == null) {
      return _MergeDecision(n: candidates.length, event: fallback);
    }
    final n = (decision.n >= 2 && decision.n <= candidates.length)
        ? decision.n
        : candidates.length;
    final event = decision.event.isEmpty ? fallback : decision.event;
    return _MergeDecision(n: n, event: event);
  }

  /// 构建强制总结事件
  ///
  /// 当LLM总结失败时使用，自动合并候选事件的关键信息
  EventMemory _buildForcedSummaryEvent(List<EventNode> candidates) {
    if (candidates.isEmpty) return const EventMemory();
    String pick(Iterable<String> values) {
      for (final value in values) {
        final v = value.trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final newest = candidates.first.event;
    final oldest = candidates.last.event;
    final lines = candidates
        .map((e) => e.event.toPromptLine().trim())
        .where((e) => e.isNotEmpty)
        .take(3);

    // 合并所有被总结事件的原始对话内容
    final sourceDialogs = candidates
        .map((e) => e.event.sourceDialog.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final mergedSourceDialog = sourceDialogs.isEmpty
        ? ''
        : '【合并自 ${sourceDialogs.length} 个事件】\n${sourceDialogs.join('\n---\n')}';

    return EventMemory(
      time: <String>{
        if (newest.time.isNotEmpty) newest.time,
        if (oldest.time.isNotEmpty) oldest.time,
      }.join(' ~ '),
      location: pick(candidates.map((e) => e.event.location)),
      characters: pick(candidates.map((e) => e.event.characters)),
      cause: pick(candidates.map((e) => e.event.cause)),
      process: lines.isEmpty
          ? pick(candidates.map((e) => e.event.process))
          : lines.join('；'),
      result: pick(candidates.map((e) => e.event.result)),
      attitude: pick(candidates.map((e) => e.event.attitude)),
      sourceDialog: mergedSourceDialog,
    );
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
  Contact? _buildPromptContact(Contact? contact, {required String userInput}) {
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
          userInput,
          keywordWeight: _appSettings.comprehensiveKeywordWeight,
          semanticWeight: _appSettings.comprehensiveSemanticWeight,
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
    required String userInput,
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
      userInput: userInput,
    );

    // 对长期队列应用LRU
    result = _applyLruToQueue(
      result,
      tier: EventTier.longTerm,
      fixedCount: longFixed,
      userInput: userInput,
    );

    // 对超长期队列应用LRU
    result = _applyLruToQueue(
      result,
      tier: EventTier.ultraLongTerm,
      fixedCount: ultraFixed,
      userInput: userInput,
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
    required String userInput,
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
      userInput: userInput,
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
    required String userInput,
  }) {
    if (events.isEmpty) return events;

    // 提取用户输入关键词
    final keywords = _extractLocalKeywords(userInput).toSet();

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

      // 1. 检查是否与用户输入关键词匹配
      final nodeKeywords =
          _extractLocalKeywords(node.event.toSearchableText()).toSet();
      final keywordMatches = keywords.intersection(nodeKeywords).length;
      score += keywordMatches * settings.lruKeywordMatchWeight;

      // 2. 检查是否有event-event关联（与被关键词匹配的事件相连）
      final neighbors = adjacent[node.id] ?? const <String>{};
      for (final neighborId in neighbors) {
        final neighbor = allNodes[neighborId];
        if (neighbor == null) continue;
        final neighborKeywords =
            _extractLocalKeywords(neighbor.event.toSearchableText()).toSet();
        if (keywords.intersection(neighborKeywords).isNotEmpty) {
          score += settings.lruEventEventWeight;
          break;
        }
      }

      // 3. 检查是否有event-belonging关联
      for (final entry in graph.belongingEventQueues.entries) {
        final queue = entry.value;
        if (queue.contains(node.id)) {
          final belongingKeywords = _extractLocalKeywords(entry.key).toSet();
          if (keywords.intersection(belongingKeywords).isNotEmpty) {
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
          final settingKeywords = _extractLocalKeywords(entry.key).toSet();
          if (keywords.intersection(settingKeywords).isNotEmpty) {
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
  /// - 本地：使用正则表达式提取关键词
  /// - LLM：请求专门的LLM进行关键词抽取
  /// 合并结果并缓存，用于后续关联事件搜索
  Future<_KeywordExtraction> _extractTurnKeywords({
    required String contactId,
    required String contactName,
    required String userInput,
  }) async {
    // 本地关键词提取
    final local = _extractLocalKeywords(userInput).toList();

    // LLM关键词提取
    List<String> llm = const <String>[];
    try {
      final raw = await _repository.askUtility(
        contactId: contactId,
        contactName: contactName,
        prompt: _buildKeywordPrompt(userInput),
      );
      llm = _parseKeywordsFromRaw(raw);
    } catch (_) {
      llm = const <String>[];
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
    );
  }

  /// 构建关键词提取Prompt
  String _buildKeywordPrompt(String userInput) {
    return '你是关键词抽取器，总结文段keyword。只输出 JSON：{"keywords":["关键词1","关键词2"]}。最多 8 个关键词。用户输入：${userInput.trim()}';
  }

  /// 构建关键词搜索输入
  ///
  /// 将用户输入和关键词合并，用于事件搜索
  String _buildKeywordSearchInput({
    required String userInput,
    required List<String> keywords,
  }) {
    final input = userInput.trim();
    if (keywords.isEmpty) return input;
    return '$input\n${keywords.join(' ')}';
  }

  /// 从LLM响应中解析关键词列表
  List<String> _parseKeywordsFromRaw(String raw) {
    final payload = StructuredOutputRegexParser.parsePrimaryPayload(raw);
    final list = payload?['keywords'];
    if (list is! List) return const <String>[];
    final out = <String>[];
    for (final item in list) {
      final value = item?.toString().trim() ?? '';
      if (value.isEmpty || out.contains(value)) continue;
      out.add(value);
    }
    return out;
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
    required String userInput,
  }) {
    if (patch.isEmpty || eventNodeId == null || eventNodeId.isEmpty) {
      return graph;
    }

    // 提取用户输入关键词用于LRU排序
    final keywords = _extractLocalKeywords(userInput).toSet();

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

      // 建立边关系
      out = _appendEdge(
        out,
        fromNodeId: _belongingNodeId(item.name),
        toNodeId: eventNodeId,
      );
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

      // 检查是否与用户输入关键词匹配
      final nodeKeywords =
          _extractLocalKeywords(node.event.toSearchableText()).toSet();
      final keywordMatches = keywords.intersection(nodeKeywords).length;
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
    required String userInput,
  }) {
    if (eventNodeId == null ||
        eventNodeId.isEmpty ||
        settings.isEmpty ||
        userInput.trim().isEmpty) {
      return graph;
    }

    // 提取用户输入中的关键词
    final inputKeywords = _extractLocalKeywords(userInput).toSet();
    if (inputKeywords.isEmpty) return graph;

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
      final settingKeywords = _extractLocalKeywords(searchableText).toSet();

      // 检查是否有关键词匹配
      if (inputKeywords.intersection(settingKeywords).isNotEmpty) {
        // 获取或创建队列
        var queue = queues.putIfAbsent(key, () => <String>[]);

        // 添加新事件ID
        queue.add(eventNodeId);

        // 对队列应用LRU排序
        queue = _sortBelongingQueueByLru(
          queue,
          allNodes: allNodes,
          keywords: inputKeywords,
        );

        // 限制队列长度（保留最相关的100个）
        if (queue.length > 100) {
          queue = queue.sublist(0, 100);
        }

        queues[key] = queue;

        // 建立边关系
        out = _appendEdge(
          out,
          fromNodeId: _settingNodeId(key),
          toNodeId: eventNodeId,
        );
      }
    }

    return out.copyWith(settingEventQueues: queues);
  }

  /// 生成设定节点的ID
  String _settingNodeId(String key) => 'setting:${key.trim().toLowerCase()}';

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
        final prev =
            graph.shortTermQueue.isEmpty ? null : graph.shortTermQueue.first.id;
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
        // 建立时间顺序边
        if (prev != null) {
          out = _appendEdge(out, fromNodeId: node.id, toNodeId: prev);
        }
        return out;
      case EventTier.longTerm:
        final prev =
            graph.longTermQueue.isEmpty ? null : graph.longTermQueue.first.id;
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
        if (prev != null) {
          out = _appendEdge(out, fromNodeId: node.id, toNodeId: prev);
        }
        return out;
      case EventTier.ultraLongTerm:
        final prev = graph.ultraLongTermQueue.isEmpty
            ? null
            : graph.ultraLongTermQueue.first.id;
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
        if (prev != null) {
          out = _appendEdge(out, fromNodeId: node.id, toNodeId: prev);
        }
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

    // 异步删除这些事件对应的向量数据
    for (final eventNode in truncatedEvents) {
      _vectorMemory.deleteMemoryEntry(eventNode.id);
    }

    print('LRU截断: 删除 ${truncatedEvents.length} 个超长事件的向量数据');
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
  List<EventMemory> _extractEventsFromPatch(
    Map<String, dynamic>? patch, {
    String userInput = '',
    String aiReply = '',
  }) {
    final eventList = StructuredOutputRegexParser.extractEventList(patch);
    if (eventList.isEmpty) return const <EventMemory>[];

    // 构建原始对话内容
    final sourceDialog = _buildSourceDialog(userInput, aiReply);

    final out = <EventMemory>[];
    for (final map in eventList) {
      final e = EventMemory.fromJson(map);
      if (!e.isEmpty) {
        // 为事件添加原始对话内容
        out.add(EventMemory(
          time: e.time,
          location: e.location,
          characters: e.characters,
          cause: e.cause,
          process: e.process,
          result: e.result,
          attitude: e.attitude,
          sourceDialog: sourceDialog,
        ));
      }
    }
    return out;
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

  /// 获取事件层级的标签
  String _tierLabel(EventTier tier) => switch (tier) {
        EventTier.shortTerm => '短期',
        EventTier.longTerm => '长期',
        EventTier.ultraLongTerm => '超长期',
      };

  /// 合并系统提示词和联系人信息
  String _mergeSystemPromptWithContact({
    required String basePrompt,
    Contact? contact,
  }) {
    final base = basePrompt.trim();
    if (contact == null) return base;
    final composer = StructuredInputPromptComposer(settings: _appSettings);
    return composer.composeSystemPromptWithContactObject(
      basePrompt: base,
      contact: contact,
    );
  }

  /// 生成物品节点的ID
  String _belongingNodeId(String name) =>
      'belonging:${name.trim().toLowerCase()}';

  /// 生成唯一联系人ID
  ///
  /// 格式：{prefix}-{timestamp}-{random}
  /// prefix: contact 或 story 根据类别决定
  String _generateUniqueId(ContactCategory category) {
    final prefix = category == ContactCategory.story ? 'story' : 'contact';
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

/// 关键词提取结果
class _KeywordExtraction {
  const _KeywordExtraction({
    required this.localKeywords,
    required this.llmKeywords,
    required this.mergedKeywords,
  });

  /// 本地正则提取的关键词
  final List<String> localKeywords;

  /// LLM提取的关键词
  final List<String> llmKeywords;

  /// 合并后的关键词（去重）
  final List<String> mergedKeywords;
}

/// 事件总结决策
class _MergeDecision {
  const _MergeDecision({
    required this.n,
    required this.event,
  });

  /// 要合并的事件数量
  final int n;

  /// 总结后的事件
  final EventMemory event;
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

/// 带权重的记忆条目
class _ScoredMemory {
  final VectorMemoryEntity memory;
  final double score;

  _ScoredMemory({required this.memory, required this.score});
}
