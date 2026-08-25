import 'package:flutter/material.dart';

import '../../../../infrastructure/services/tts_service.dart';
import '../../data/models/contact.dart';

class ContactDraft {
  const ContactDraft({
    required this.name,
    required this.avatar,
    required this.fixedInput,
    required this.currentStates,
    required this.category,
    this.voice = '',
    this.jsonString,
    this.naturalLanguage,
  });

  final String name;
  final String avatar;
  final String fixedInput;
  final Map<String, String> currentStates;
  final ContactCategory category;
  final String voice;
  final String? jsonString;
  final String? naturalLanguage;

  bool get isJsonMode => jsonString != null;
  bool get isNaturalLanguageMode => naturalLanguage != null;
}

class ContactEditorDialog extends StatefulWidget {
  const ContactEditorDialog({super.key});

  @override
  State<ContactEditorDialog> createState() => _ContactEditorDialogState();
}

class _ContactEditorDialogState extends State<ContactEditorDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _avatarCtrl = TextEditingController();
  final TextEditingController _fixedInputCtrl = TextEditingController();
  final TextEditingController _stateKeyCtrl = TextEditingController();
  final TextEditingController _jsonCtrl = TextEditingController();
  final TextEditingController _nlCtrl = TextEditingController();

  final Map<String, String> _currentStates = <String, String>{};
  ContactCategory _category = ContactCategory.contact;
  String _voiceId = VoiceOption.fallback.id;
  _EditorMode _mode = _EditorMode.normal;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _avatarCtrl.dispose();
    _fixedInputCtrl.dispose();
    _stateKeyCtrl.dispose();
    _jsonCtrl.dispose();
    _nlCtrl.dispose();
    super.dispose();
  }

  void _addStateKey() {
    final key = _stateKeyCtrl.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _currentStates.putIfAbsent(key, () => '');
      _stateKeyCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_category == ContactCategory.story
          ? '创建故事'
          : _category == ContactCategory.assistant
              ? '创建助手'
              : '创建角色'),
      content: SizedBox(
        width: 520,
        child: _buildContent(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _onSave,
          child: const Text('创建'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_mode) {
      case _EditorMode.normal:
        return _buildNormalForm();
      case _EditorMode.json:
        return _buildJsonForm();
      case _EditorMode.naturalLanguage:
        return _buildNaturalLanguageForm();
    }
  }

  Widget _buildTypeSelector() {
    return RadioGroup<ContactCategory>(
      groupValue: _category,
      onChanged: (value) {
        if (value != null) setState(() => _category = value);
      },
      child: const Row(
        children: [
          Expanded(
            child: RadioListTile<ContactCategory>(
              title: Text('角色'),
              value: ContactCategory.contact,
            ),
          ),
          Expanded(
            child: RadioListTile<ContactCategory>(
              title: Text('故事'),
              value: ContactCategory.story,
            ),
          ),
          Expanded(
            child: RadioListTile<ContactCategory>(
              title: Text('助手'),
              value: ContactCategory.assistant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharedFields() {
    return Column(
      children: [
        _buildTypeSelector(),
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: _category == ContactCategory.story
                ? '故事名称'
                : _category == ContactCategory.assistant
                    ? '助手名称'
                    : '角色名称',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _avatarCtrl,
          decoration: const InputDecoration(
            labelText: '头像',
            hintText: '一个 emoji 或简短符号',
          ),
        ),
        const SizedBox(height: 12),
        _buildVoiceSelector(),
      ],
    );
  }

  Widget _buildVoiceSelector() {
    final selected = VoiceOption.findById(_voiceId) ?? VoiceOption.fallback;
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: '语音音色',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selected.id,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _voiceId = value);
                },
                items: [
                  for (final v in VoiceOption.presets)
                    DropdownMenuItem<String>(
                      value: v.id,
                      child: Row(
                        children: [
                          const Icon(Icons.record_voice_over_outlined,
                              size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              v.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            v.locale,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: () => _previewVoice(selected),
            tooltip: '试听音色',
            icon: const Icon(Icons.volume_up_outlined, size: 20),
          ),
        ],
      ),
    );
  }

  void _previewVoice(VoiceOption voice) {
    final tts = TtsService.instance;
    tts.stop();
    tts.speak(
      messageId: '__preview__',
      text: '你好，我是语音助手。这是$voice',
      voice: voice,
    );
  }

  Widget _buildNormalForm() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSharedFields(),
          const SizedBox(height: 16),
          TextField(
            controller: _fixedInputCtrl,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: '固定输入内容',
              hintText: '每轮对话固定输入的提示词',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('需要记录的状态', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _stateKeyCtrl,
                  decoration: const InputDecoration(
                    hintText: '例如：好感度、体力、当前位置',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addStateKey(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _addStateKey,
                child: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_currentStates.isEmpty)
            const Text('暂无状态 key', style: TextStyle(color: Colors.grey))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final key in _currentStates.keys)
                  InputChip(
                    label: Text(key),
                    onDeleted: () => setState(() => _currentStates.remove(key)),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() => _mode = _EditorMode.json),
                child: const Text('使用 JSON 创建'),
              ),
              const SizedBox(width: 20),
              TextButton(
                onPressed: () =>
                    setState(() => _mode = _EditorMode.naturalLanguage),
                child: const Text('使用自然语言创建'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJsonForm() {
    if (_jsonCtrl.text.isEmpty) {
      _jsonCtrl.text = '''{
  "name": "角色名称",
  "avatar": "★",
  "fixedInput": "你是...",
  "currentStates": {
    "好感度": "",
    "当前位置": ""
  }
}''';
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSharedFields(),
          const SizedBox(height: 12),
          TextField(
            controller: _jsonCtrl,
            minLines: 10,
            maxLines: 15,
            decoration: const InputDecoration(
              labelText: 'JSON 格式',
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _mode = _EditorMode.normal),
              child: const Text('返回普通模式'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNaturalLanguageForm() {
    if (_nlCtrl.text.isEmpty) {
      _nlCtrl.text = '创建一个角色，固定输入内容是：你是...；需要记录的状态有：好感度、当前位置。';
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSharedFields(),
          const SizedBox(height: 12),
          TextField(
            controller: _nlCtrl,
            minLines: 6,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: '自然语言描述',
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _mode = _EditorMode.normal),
              child: const Text('返回普通模式'),
            ),
          ),
        ],
      ),
    );
  }

  void _onSave() {
    switch (_mode) {
      case _EditorMode.normal:
        _saveNormalMode();
        break;
      case _EditorMode.json:
        _saveJsonMode();
        break;
      case _EditorMode.naturalLanguage:
        _saveNaturalLanguageMode();
        break;
    }
  }

  ContactDraft _draft({String? jsonString, String? naturalLanguage}) {
    // 助手类型如果没有 fixedInput，设置默认值
    String fixedInput = _fixedInputCtrl.text.trim();
    if (fixedInput.isEmpty && _category == ContactCategory.assistant) {
      fixedInput = '你是一个AI助手，专注于帮助用户完成任务。';
    }

    return ContactDraft(
      name: _nameCtrl.text.trim(),
      avatar: _avatarCtrl.text.trim(),
      fixedInput: fixedInput,
      currentStates: Map<String, String>.from(_currentStates),
      category: _category,
      voice: _voiceId,
      jsonString: jsonString,
      naturalLanguage: naturalLanguage,
    );
  }

  void _saveNormalMode() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称不能为空')),
      );
      return;
    }
    Navigator.of(context).pop(_draft());
  }

  void _saveJsonMode() {
    final jsonStr = _jsonCtrl.text.trim();
    if (jsonStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('JSON 不能为空')),
      );
      return;
    }
    Navigator.of(context).pop(_draft(jsonString: jsonStr));
  }

  void _saveNaturalLanguageMode() {
    final nlText = _nlCtrl.text.trim();
    if (nlText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('描述不能为空')),
      );
      return;
    }
    Navigator.of(context).pop(
      ContactDraft(
        name: _nameCtrl.text.trim(),
        avatar: _avatarCtrl.text.trim(),
        fixedInput: _fixedInputCtrl.text.trim().isEmpty
            ? nlText
            : _fixedInputCtrl.text.trim(),
        currentStates: Map<String, String>.from(_currentStates),
        category: _category,
        voice: _voiceId,
        naturalLanguage: nlText,
      ),
    );
  }
}

enum _EditorMode {
  normal,
  json,
  naturalLanguage,
}
