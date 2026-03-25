import 'dart:async';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';

import '../../../../core/presentation/pages/app_settings_page.dart';
import '../../data/models/contact.dart';
import '../../data/models/message.dart';
import '../../domain/providers/chat_provider.dart';
import '../widgets/contact_sidebar.dart';
import '../widgets/contact_editor_dialog.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatProvider _provider = ChatProvider();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _provider.addListener(_scrollToBottom);
    unawaited(_provider.initialize());
  }

  @override
  void dispose() {
    _provider.removeListener(_scrollToBottom);
    _provider.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    scheduleMicrotask(() {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final input = _inputController.text;
    if (input.trim().isEmpty) return;
    _inputController.clear();
    await _provider.sendMessage(input);
  }

  Future<void> _openApiSettingDialog() async {
    final keyCtrl = TextEditingController(text: _provider.currentApiKey);
    final promptCtrl = TextEditingController(
      text: _provider.currentSystemPrompt,
    );

    final result = await showDialog<ApiConfigDraft>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('API 配置'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: keyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    hintText: '请输入 API Key',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: promptCtrl,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '系统提示词',
                    hintText: '可选：定义全局系统提示词',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  ApiConfigDraft(
                    apiKey: keyCtrl.text,
                    systemPrompt: promptCtrl.text,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    await _provider.saveApiKey(result.apiKey);
    await _provider.saveSystemPrompt(result.systemPrompt);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('API 配置已保存')));
  }

  Future<void> _openCreateContactDialog() async {
    final result = await showDialog<ContactDraft>(
      context: context,
      builder: (context) => const ContactEditorDialog(),
    );
    if (result == null) return;

    final categoryLabel =
        result.category == ContactCategory.story ? '故事' : '角色';

    // 判断是否是自然语言模式
    if (result.isNaturalLanguageMode) {
      // 显示加载提示
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('正在使用 AI 生成$categoryLabel...')));
      }

      // 调用 LLM 转换
      final jsonStr = await _provider.convertNaturalLanguageToJson(
        result.naturalLanguage!,
        isStory: result.category == ContactCategory.story,
      );

      if (!mounted) return;

      if (jsonStr == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 转换失败，请检查描述或稍后重试')));
        return;
      }

      // 使用转换后的 JSON 创建，合并表单中填写的字段
      final ok = await _provider.addContactFromJsonWithFallback(
        jsonStr,
        category: result.category,
        fallbackName: result.name.isNotEmpty ? result.name : null,
        fallbackId: result.id.isNotEmpty ? result.id : null,
        fallbackAvatar: result.avatar.isNotEmpty ? result.avatar : null,
        fallbackPersonality:
            result.personality.isNotEmpty ? result.personality : null,
        fallbackAppearance:
            result.appearance?.isNotEmpty == true ? result.appearance : null,
        fallbackPersonalInfo: result.personalInfo?.isNotEmpty == true
            ? result.personalInfo
            : null,
        fallbackSettings:
            result.settings?.isNotEmpty == true ? result.settings : null,
        fallbackBackgroundStory:
            result.backgroundStory.isNotEmpty ? result.backgroundStory : null,
      );
      if (!mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建失败：生成的 JSON 无效或 ID 已存在')),
        );
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AI 生成$categoryLabel成功')));
      return;
    }

    // 判断是否是 JSON 模式
    if (result.isJsonMode) {
      // 使用 JSON 创建，合并表单中填写的字段作为后备
      final ok = await _provider.addContactFromJsonWithFallback(
        result.jsonString!,
        category: result.category,
        fallbackName: result.name.isNotEmpty ? result.name : null,
        fallbackId: result.id.isNotEmpty ? result.id : null,
        fallbackAvatar: result.avatar.isNotEmpty ? result.avatar : null,
        fallbackPersonality:
            result.personality.isNotEmpty ? result.personality : null,
        fallbackAppearance:
            result.appearance?.isNotEmpty == true ? result.appearance : null,
        fallbackPersonalInfo: result.personalInfo?.isNotEmpty == true
            ? result.personalInfo
            : null,
        fallbackSettings:
            result.settings?.isNotEmpty == true ? result.settings : null,
        fallbackBackgroundStory:
            result.backgroundStory.isNotEmpty ? result.backgroundStory : null,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('创建失败：JSON 格式错误或 ID 已存在')));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$categoryLabel创建成功')));
    } else {
      final ok = await _provider.addContact(
        name: result.name,
        contactId: result.id,
        avatar: result.avatar,
        personality: result.personality,
        appearance: result.appearance ?? [],
        personalInfo: result.personalInfo ?? [],
        settings: result.settings ?? [],
        backgroundStory: result.backgroundStory,
        category: result.category,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建失败：名称/ID 不能为空，且 ID 不能重复')),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$categoryLabel创建成功')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _provider,
      builder: (context, _) {
        final selected = _provider.selectedContact;
        final isCompact = MediaQuery.of(context).size.width < 900;

        // 移动端使用独立Scaffold，桌面端使用嵌套布局
        if (isCompact) {
          return _buildMobileLayout(selected);
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              selected == null ? 'Chat Demo' : selected.name,
            ),
            actions: [
              IconButton(
                onPressed: _openCreateContactDialog,
                tooltip: '创建对象',
                icon: const Icon(Icons.person_add_alt_1),
              ),
              IconButton(
                onPressed: _openApiSettingDialog,
                tooltip: 'API 配置',
                icon: const Icon(Icons.key_outlined),
              ),
              IconButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AppSettingsPage(),
                    ),
                  );
                },
                tooltip: '应用设置',
                icon: const Icon(Icons.settings_outlined),
              ),
              IconButton(
                onPressed: _provider.toggleDebugMode,
                tooltip: '切换调试模式',
                icon: Icon(
                  _provider.isDebugMode
                      ? Icons.bug_report
                      : Icons.bug_report_outlined,
                ),
              ),
              // 撤回按钮（调试用：总是显示）
              IconButton(
                onPressed: _provider.canRecall
                    ? () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('确认撤回'),
                            content:
                                const Text('确定要撤回最近一轮对话吗？这将恢复角色到对话前的记忆状态。'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.orange),
                                child: const Text('撤回'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          final ok = await _provider.recallLastTurn();
                          if (!mounted) return;
                          if (ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已撤回最近一轮对话')),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('撤回失败')),
                            );
                          }
                        }
                      }
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'canRecall=${_provider.canRecall}，快照为空，无法撤回'),
                          ),
                        );
                      },
                tooltip: '撤回最近一轮对话',
                icon: Icon(
                  Icons.undo,
                  color: _provider.canRecall ? null : Colors.grey,
                ),
              ),
            ],
          ),
          body: _buildDesktopLayout(selected),
        );
      },
    );
  }

  Future<void> _deleteContact(String contactId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除此角色吗？所有聊天记录也将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await _provider.deleteContact(contactId);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('角色已删除')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败')),
      );
    }
  }

  /// 处理联系人选择
  ///
  /// 选择联系人后滚动聊天栏到最底部
  void _onSelectContact(String contactId) {
    _provider.selectContact(contactId);
    // 延迟执行滚动，等待UI更新完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Widget _buildDesktopLayout(Contact? selected) {
    return Row(
      children: [
        ContactSidebar(
          contacts: _provider.contacts,
          selectedContactId: _provider.selectedContactId,
          onSelect: _onSelectContact,
          onAdd: _openCreateContactDialog,
          onDelete: _deleteContact,
          showDeleteInList: true,
          showDeleteInFooter: false,
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildChatArea(selected)),
      ],
    );
  }

  Widget _buildMobileLayout(Contact? selected) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        title: Text(
          selected == null ? 'Chat Demo' : selected.name,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: '打开对象列表',
            padding: const EdgeInsets.all(12),
          ),
        ),
        actions: [
          // 移动端菜单按钮
          PopupMenuButton<String>(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            icon: const Icon(Icons.more_vert),
            tooltip: '更多选项',
            onSelected: (value) async {
              switch (value) {
                case 'recall':
                  if (_provider.canRecall) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('确认撤回'),
                        content: const Text('确定要撤回最近一轮对话吗？这将恢复角色到对话前的记忆状态。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange),
                            child: const Text('撤回'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      final ok = await _provider.recallLastTurn();
                      if (!mounted) return;
                      if (ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已撤回最近一轮对话')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('撤回失败')),
                        );
                      }
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('没有可撤回的内容'),
                      ),
                    );
                  }
                  break;
                case 'api':
                  _openApiSettingDialog();
                  break;
                case 'settings':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AppSettingsPage(),
                    ),
                  );
                  break;
                case 'debug':
                  _provider.toggleDebugMode();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'recall',
                enabled: _provider.canRecall,
                child: Row(
                  children: [
                    Icon(
                      Icons.undo,
                      color: _provider.canRecall ? null : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '撤回',
                      style: TextStyle(
                        color: _provider.canRecall ? null : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'api',
                child: Row(
                  children: [
                    Icon(Icons.key_outlined),
                    SizedBox(width: 8),
                    Text('API 配置'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined),
                    SizedBox(width: 8),
                    Text('应用设置'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'debug',
                child: Row(
                  children: [
                    Icon(
                      _provider.isDebugMode
                          ? Icons.bug_report
                          : Icons.bug_report_outlined,
                    ),
                    const SizedBox(width: 8),
                    Text(_provider.isDebugMode ? '关闭调试' : '开启调试'),
                  ],
                ),
              ),
            ],
          ),
        ],
        elevation: 2,
        scrolledUnderElevation: 4,
      ),
      drawer: Drawer(
        width: 280,
        child: ContactSidebar(
          contacts: _provider.contacts,
          selectedContactId: _provider.selectedContactId,
          onSelect: (id) {
            _onSelectContact(id);
            Navigator.of(context).pop(); // 选择后自动关闭侧边栏
          },
          onAdd: () {
            Navigator.of(context).pop();
            _openCreateContactDialog();
          },
          onDelete: (id) {
            Navigator.of(context).pop();
            _deleteContact(id);
          },
          showDeleteInList: false,
          showDeleteInFooter: true,
        ),
      ),
      body: _buildChatArea(selected),
      resizeToAvoidBottomInset: true,
    );
  }

  Widget _buildChatArea(Contact? selected) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (selected == null)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '暂无对象，请先创建',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: _provider.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.message_outlined,
                          size: 64,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '开始聊天吧',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    itemCount: _provider.messages.length +
                        (_provider.isTyping ? 1 : 0),
                    itemBuilder: (_, index) {
                      if (_provider.isTyping &&
                          index == _provider.messages.length) {
                        return const _TypingBubble();
                      }
                      final m = _provider.messages[index];
                      return _AnimatedMessageBubble(
                        child: _MessageBubble(
                          message: m,
                          onRetry: () {
                            if (_provider.selectedContactId != null) {
                              _provider.resendMessage(
                                  _provider.selectedContactId!, m.id);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        if (_provider.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  _provider.error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        const Divider(height: 1),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                spreadRadius: 0,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 6,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: selected == null ? '请先创建对象' : '输入消息...',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed:
                      _provider.isLoading || selected == null ? null : _send,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    elevation: 0,
                  ),
                  child: const Text('发送'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ApiConfigDraft {
  const ApiConfigDraft({required this.apiKey, required this.systemPrompt});

  final String apiKey;
  final String systemPrompt;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onRetry});

  final Message message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';
    final theme = Theme.of(context);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser)
              Container(
                margin: const EdgeInsets.only(right: 8),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    'AI',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: isUser
                      ? message.status == MessageStatus.failed
                          ? Colors.red.shade50
                          : theme.colorScheme.primary.withValues(alpha: 0.15)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: isUser
                        ? const Radius.circular(18)
                        : const Radius.circular(4),
                    bottomRight: isUser
                        ? const Radius.circular(4)
                        : const Radius.circular(18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      spreadRadius: 0,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: GestureDetector(
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('消息操作'),
                        content: Text(message.content),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () {
                              // 复制文本到剪贴板
                              Clipboard.setData(
                                  ClipboardData(text: message.content));
                              // 显示复制成功提示
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('文本已复制到剪贴板')),
                              );
                              Navigator.of(context).pop();
                            },
                            child: const Text('复制'),
                          ),
                          if (isUser)
                            TextButton(
                              onPressed: onRetry,
                              child: const Text('重发'),
                            ),
                        ],
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        message.content,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              time,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isUser && message.status == MessageStatus.sending)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      theme.colorScheme.primary),
                                ),
                              ),
                            ),
                          if (isUser && message.status == MessageStatus.sent)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.check,
                                size: 16,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          if (isUser && message.status == MessageStatus.failed)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.error_outline,
                                size: 16,
                                color: Colors.red,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (isUser)
              Container(
                margin: const EdgeInsets.only(left: 8),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.person,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedMessageBubble extends StatefulWidget {
  const _AnimatedMessageBubble({required this.child});

  final Widget child;

  @override
  State<_AnimatedMessageBubble> createState() => _AnimatedMessageBubbleState();
}

class _AnimatedMessageBubbleState extends State<_AnimatedMessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacityAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  'AI',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: const Radius.circular(4),
                  bottomRight: const Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    spreadRadius: 0,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDot(theme, delay: 0),
                  _buildDot(theme, delay: 150),
                  _buildDot(theme, delay: 300),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(ThemeData theme, {int delay = 0}) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            delay / 1200, // 开始时间
            (delay + 400) / 1200, // 结束时间
            curve: Curves.easeInOut,
          ),
        ),
      ),
      child: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
