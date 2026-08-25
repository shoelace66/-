import 'package:flutter/material.dart';

import '../../../../core/data/models/provider_settings.dart';

class ChatActions extends StatelessWidget {
  const ChatActions({
    super.key,
    required this.compact,
    required this.hasContact,
    required this.canRecall,
    required this.debugMode,
    required this.onCreateContact,
    required this.onRecall,
    required this.onProviders,
    required this.onMemory,
    required this.onTimeline,
    required this.onSearch,
    required this.onWorldBook,
    required this.onImageGallery,
    required this.onBackup,
    required this.onSystemPrompt,
    required this.onSettings,
    required this.onAssistantSettings,
    required this.onToggleDebug,
    required this.profiles,
    required this.activeProfile,
    required this.onActivateProfile,
    required this.onCheckProfiles,
  });

  final bool compact;
  final bool hasContact;
  final bool canRecall;
  final bool debugMode;
  final VoidCallback onCreateContact;
  final VoidCallback onRecall;
  final VoidCallback onProviders;
  final VoidCallback onMemory;
  final VoidCallback onTimeline;
  final VoidCallback onSearch;
  final VoidCallback onWorldBook;
  final VoidCallback onImageGallery;
  final VoidCallback onBackup;
  final VoidCallback onSystemPrompt;
  final VoidCallback onSettings;
  final VoidCallback onAssistantSettings;
  final VoidCallback onToggleDebug;
  final List<LlmProfile> profiles;
  final LlmProfile activeProfile;
  final ValueChanged<LlmProfile> onActivateProfile;
  final VoidCallback onCheckProfiles;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _profileSwitcher(),
          _button(Icons.health_and_safety_outlined, '检查 LLM Profiles',
              onCheckProfiles),
          PopupMenuButton<_ChatAction>(
            tooltip: '聊天操作',
            icon: const Icon(Icons.more_vert),
            onSelected: _run,
            itemBuilder: (_) => [
              _item(_ChatAction.create, Icons.person_add_alt_1, '创建对象'),
              _item(
                _ChatAction.recall,
                Icons.undo,
                '撤回上一轮',
                enabled: canRecall,
              ),
              _item(_ChatAction.memory, Icons.auto_stories_outlined, '记忆档案',
                  enabled: hasContact),
              _item(_ChatAction.timeline, Icons.account_tree_outlined, '剧情分支',
                  enabled: hasContact),
              _item(_ChatAction.search, Icons.search, '搜索会话',
                  enabled: hasContact),
              _item(_ChatAction.worldBook, Icons.public_outlined, '世界书',
                  enabled: hasContact),
              _item(_ChatAction.imageGallery, Icons.photo_library_outlined,
                  '图片画廊'),
              _item(_ChatAction.backup, Icons.backup_outlined, '本地备份'),
              _item(_ChatAction.providers, Icons.cloud_outlined, 'API 提供商'),
              _item(_ChatAction.prompt, Icons.psychology_outlined, '系统提示词'),
              _item(_ChatAction.settings, Icons.settings_outlined, '应用设置'),
              _item(_ChatAction.assistant, Icons.terminal_outlined, '助手连接配置'),
              _item(
                _ChatAction.debug,
                debugMode ? Icons.bug_report : Icons.bug_report_outlined,
                debugMode ? '关闭调试' : '开启调试',
              ),
            ],
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _profileSwitcher(),
        _button(Icons.health_and_safety_outlined, '检查 LLM Profiles',
            onCheckProfiles),
        _button(Icons.person_add_alt_1, '创建对象', onCreateContact),
        _button(Icons.cloud_outlined, 'API 提供商', onProviders),
        _button(
            Icons.auto_stories_outlined, '记忆档案', hasContact ? onMemory : null),
        _button(Icons.account_tree_outlined, '剧情分支',
            hasContact ? onTimeline : null),
        _button(Icons.search, '搜索会话', hasContact ? onSearch : null),
        _button(Icons.public_outlined, '世界书', hasContact ? onWorldBook : null),
        _button(Icons.photo_library_outlined, '图片画廊', onImageGallery),
        _button(Icons.backup_outlined, '本地备份', onBackup),
        _button(Icons.settings_outlined, '应用设置', onSettings),
        _button(Icons.terminal_outlined, '助手连接配置', onAssistantSettings),
        _button(
          debugMode ? Icons.bug_report : Icons.bug_report_outlined,
          debugMode ? '关闭调试' : '开启调试',
          onToggleDebug,
        ),
        _button(Icons.undo, '撤回最近一轮对话', canRecall ? onRecall : null),
      ],
    );
  }

  Widget _profileSwitcher() {
    return PopupMenuButton<LlmProfile>(
      tooltip: '切换 LLM Profile',
      icon: const Icon(Icons.hub_outlined),
      onSelected: onActivateProfile,
      itemBuilder: (_) => [
        for (final profile in profiles)
          CheckedPopupMenuItem<LlmProfile>(
            value: profile,
            checked: identical(profile, activeProfile),
            child: Text(
              '${profile.presetId} / ${profile.model.isEmpty ? "未配置" : profile.model}',
            ),
          ),
      ],
    );
  }

  PopupMenuItem<_ChatAction> _item(
    _ChatAction value,
    IconData icon,
    String label, {
    bool enabled = true,
  }) {
    return PopupMenuItem<_ChatAction>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _button(IconData icon, String tooltip, VoidCallback? callback) {
    return IconButton(
      onPressed: callback,
      tooltip: tooltip,
      icon: Icon(icon),
    );
  }

  void _run(_ChatAction action) {
    switch (action) {
      case _ChatAction.create:
        onCreateContact();
      case _ChatAction.recall:
        onRecall();
      case _ChatAction.providers:
        onProviders();
      case _ChatAction.memory:
        onMemory();
      case _ChatAction.timeline:
        onTimeline();
      case _ChatAction.search:
        onSearch();
      case _ChatAction.worldBook:
        onWorldBook();
      case _ChatAction.imageGallery:
        onImageGallery();
      case _ChatAction.backup:
        onBackup();
      case _ChatAction.prompt:
        onSystemPrompt();
      case _ChatAction.settings:
        onSettings();
      case _ChatAction.assistant:
        onAssistantSettings();
      case _ChatAction.debug:
        onToggleDebug();
    }
  }
}

enum _ChatAction {
  create,
  recall,
  providers,
  memory,
  timeline,
  search,
  worldBook,
  imageGallery,
  backup,
  prompt,
  settings,
  assistant,
  debug,
}
