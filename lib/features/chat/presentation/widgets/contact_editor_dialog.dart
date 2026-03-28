import 'package:flutter/material.dart';

import '../../data/models/contact.dart';

class ContactDraft {
  const ContactDraft({
    required this.name,
    required this.avatar,
    required this.personality,
    this.appearance,
    this.personalInfo,
    this.settings,
    required this.backgroundStory,
    this.narrativeRules,
    this.otherCharacteristics,
    required this.category,
    this.jsonString,
    this.naturalLanguage,
  });

  final String name;
  final String avatar;
  final List<String> personality;
  final List<String>? appearance;
  final List<String>? personalInfo;
  final List<Map<String, dynamic>>? settings;
  final List<String> backgroundStory;
  final List<String>? narrativeRules;
  final List<String>? otherCharacteristics;
  final ContactCategory category;
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
  final TextEditingController _personalityCtrl = TextEditingController();
  final TextEditingController _appearanceCtrl = TextEditingController();
  final TextEditingController _personalInfoCtrl = TextEditingController();
  final TextEditingController _backgroundCtrl = TextEditingController();
  final TextEditingController _narrativeRulesCtrl = TextEditingController();
  final TextEditingController _otherCharacteristicsCtrl =
      TextEditingController();

  final List<String> _personality = <String>[];
  final List<String> _appearance = <String>[];
  final List<String> _personalInfo = <String>[];
  final List<String> _backgroundStory = <String>[];
  final List<String> _narrativeRules = <String>[];
  final List<String> _otherCharacteristics = <String>[];

  ContactCategory _category = ContactCategory.contact;
  _EditorMode _mode = _EditorMode.normal;

  // JSON 和自然语言模式控制器
  final TextEditingController _jsonCtrl = TextEditingController();
  final TextEditingController _nlCtrl = TextEditingController();

  // 故事设定 key-value 编辑器相关
  final TextEditingController _settingKeyCtrl = TextEditingController();
  final TextEditingController _settingValueCtrl = TextEditingController();
  final TextEditingController _settingRelateCtrl = TextEditingController();
  final List<String> _tempRelateList = <String>[];
  final List<Map<String, dynamic>> _storySettings = <Map<String, dynamic>>[];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _avatarCtrl.dispose();
    _personalityCtrl.dispose();
    _appearanceCtrl.dispose();
    _personalInfoCtrl.dispose();
    _backgroundCtrl.dispose();
    _narrativeRulesCtrl.dispose();
    _otherCharacteristicsCtrl.dispose();
    _jsonCtrl.dispose();
    _nlCtrl.dispose();
    _settingKeyCtrl.dispose();
    _settingValueCtrl.dispose();
    _settingRelateCtrl.dispose();
    super.dispose();
  }

  void _appendItem(List<String> items, TextEditingController controller) {
    final input = controller.text.trim();
    if (input.isEmpty) return;
    setState(() {
      items.add(input);
      controller.clear();
    });
  }

  Future<void> _editItem(List<String> items, int index) async {
    final editCtrl = TextEditingController(text: items[index]);
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('修改条目'),
          content: TextField(
            controller: editCtrl,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(editCtrl.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    editCtrl.dispose();
    if (value == null || value.trim().isEmpty) return;
    setState(() => items[index] = value.trim());
  }

  Widget _buildArrayEditor({
    required String title,
    required String hint,
    required List<String> items,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(hintText: hint),
                onSubmitted: (_) => _appendItem(items, controller),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _appendItem(items, controller),
              child: const Text('添加'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (items.isEmpty)
          const Text('暂无条目', style: TextStyle(color: Colors.grey))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < items.length; i++)
                InputChip(
                  label: Text(items[i]),
                  onPressed: () => _editItem(items, i),
                  onDeleted: () => setState(() => items.removeAt(i)),
                ),
            ],
          ),
      ],
    );
  }

  /// 构建故事设定的 key-value 编辑器
  ///
  /// 用于创建故事时输入设定条目，如：
  /// - 魔法: 这片大陆的魔法基于魔法石
  /// - 魔法师: 能够激发魔法石能量的人
  Widget _buildKeyValueEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('故事设定', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _settingKeyCtrl,
                decoration: const InputDecoration(
                  hintText: '设定名称，如：魔法',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _settingValueCtrl,
                decoration: const InputDecoration(
                  hintText: '设定描述',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final key = _settingKeyCtrl.text.trim();
                final value = _settingValueCtrl.text.trim();
                if (key.isEmpty || value.isEmpty) return;
                setState(() {
                  _storySettings.add({
                    'key': key,
                    'value': value,
                    'relate': List<String>.from(_tempRelateList),
                  });
                  _settingKeyCtrl.clear();
                  _settingValueCtrl.clear();
                  _tempRelateList.clear();
                });
              },
              child: const Text('添加'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _settingRelateCtrl,
                decoration: const InputDecoration(
                  hintText: '输入关联词后点击添加',
                  isDense: true,
                  prefixIcon: Icon(Icons.link, size: 18),
                ),
                onSubmitted: (_) {
                  final input = _settingRelateCtrl.text.trim();
                  if (input.isEmpty) return;
                  setState(() {
                    _tempRelateList.add(input);
                    _settingRelateCtrl.clear();
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {
                final input = _settingRelateCtrl.text.trim();
                if (input.isEmpty) return;
                setState(() {
                  _tempRelateList.add(input);
                  _settingRelateCtrl.clear();
                });
              },
              child: const Text('添加关联词'),
            ),
          ],
        ),
        if (_tempRelateList.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _tempRelateList.length; i++)
                Chip(
                  label: Text(_tempRelateList[i]),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => setState(() => _tempRelateList.removeAt(i)),
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        if (_storySettings.isEmpty)
          const Text('暂无设定条目', style: TextStyle(color: Colors.grey))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _storySettings.length; i++)
                InputChip(
                  label: Text('${_storySettings[i]['key']}'),
                  tooltip:
                      '${_storySettings[i]['value']}${(_storySettings[i]['relate'] as List<String>?)?.isNotEmpty == true ? '\n关联: ${(_storySettings[i]['relate'] as List<String>).join(' ')}' : ''}',
                  onPressed: () async {
                    final keyCtrl = TextEditingController(
                      text: _storySettings[i]['key'],
                    );
                    final valueCtrl = TextEditingController(
                      text: _storySettings[i]['value'],
                    );
                    final relateList =
                        (_storySettings[i]['relate'] as List<dynamic>?)
                                ?.cast<String>() ??
                            <String>[];
                    final result = await showDialog<Map<String, dynamic>?>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('修改设定'),
                        content: _EditSettingDialog(
                          keyCtrl: keyCtrl,
                          valueCtrl: valueCtrl,
                          initialRelate: relateList,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.of(context).pop({
                                'key': keyCtrl.text.trim(),
                                'value': valueCtrl.text.trim(),
                                'relate': _EditSettingDialog.relateList,
                              });
                            },
                            child: const Text('保存'),
                          ),
                        ],
                      ),
                    );
                    keyCtrl.dispose();
                    valueCtrl.dispose();
                    if (result != null &&
                        result['key']!.isNotEmpty &&
                        result['value']!.isNotEmpty) {
                      setState(() => _storySettings[i] = result);
                    }
                  },
                  onDeleted: () => setState(() => _storySettings.removeAt(i)),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _category == ContactCategory.story ? '创建故事' : '创建角色',
      ),
      content: SizedBox(
        width: 480,
        child: _buildContent(),
      ),
      actions: _buildActions(),
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

  Widget _buildNormalForm() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: RadioListTile<ContactCategory>(
                  title: const Text('角色'),
                  value: ContactCategory.contact,
                  groupValue: _category,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _category = value);
                    }
                  },
                ),
              ),
              Expanded(
                child: RadioListTile<ContactCategory>(
                  title: const Text('故事'),
                  value: ContactCategory.story,
                  groupValue: _category,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _category = value);
                    }
                  },
                ),
              ),
            ],
          ),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: _category == ContactCategory.story ? '故事名称' : '角色名称',
              hintText:
                  _category == ContactCategory.story ? '请输入故事名称' : '请输入角色名称',
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
          const SizedBox(height: 16),
          if (_category == ContactCategory.contact) ...[
            _buildArrayEditor(
              title: '外貌特征',
              hint: '输入外貌特征后点击添加',
              items: _appearance,
              controller: _appearanceCtrl,
            ),
            const SizedBox(height: 16),
          ],
          _buildArrayEditor(
            title: _category == ContactCategory.story ? '风格' : '性格特点',
            hint: _category == ContactCategory.story
                ? '输入风格标签后点击添加，如：奇幻、冒险'
                : '输入性格特点后点击添加，如：理性、冷静',
            items: _personality,
            controller: _personalityCtrl,
          ),
          const SizedBox(height: 16),
          if (_category == ContactCategory.contact) ...[
            _buildArrayEditor(
              title: '个人信息',
              hint: '输入个人信息后点击添加，如：职业、年龄、能力等tag',
              items: _personalInfo,
              controller: _personalInfoCtrl,
            ),
            const SizedBox(height: 16),
          ],
          _buildArrayEditor(
            title: _category == ContactCategory.story ? '背景概述' : '背景故事',
            hint: '输入背景内容后点击添加',
            items: _backgroundStory,
            controller: _backgroundCtrl,
          ),
          const SizedBox(height: 16),
          // 故事类型显示叙事规则编辑器
          if (_category == ContactCategory.story) ...[
            _buildArrayEditor(
              title: '叙事规则',
              hint: '文风、主题、节奏等，如：暗黑压抑风格、探讨人性主题、快节奏叙事',
              items: _narrativeRules,
              controller: _narrativeRulesCtrl,
            ),
            const SizedBox(height: 16),
          ],
          // 故事类型显示 key-value 设定编辑器
          if (_category == ContactCategory.story) ...[
            _buildKeyValueEditor(),
            const SizedBox(height: 16),
          ],
          // 故事类型显示其余特征编辑器
          if (_category == ContactCategory.story) ...[
            _buildArrayEditor(
              title: '其余特征',
              hint: '角色的其余特点，如：隐藏身份、特殊习惯、内心矛盾等',
              items: _otherCharacteristics,
              controller: _otherCharacteristicsCtrl,
            ),
            const SizedBox(height: 16),
          ],
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
    final example = _category == ContactCategory.story
        ? '''{
  "id": "story-001",
  "name": "故事名称",
  "avatar": "🏰",
  "personality": ["奇幻", "冒险"],
  "backgroundStory": ["一个充满魔法的世界"],
  "settings": [
    {"key": "魔法系统", "value": "基于魔法石的能量体系", "relate": ["魔法石", "能量"]}
  ],
  "narrativeRules": ["使用第三人称视角", "注重环境描写"],
  "otherCharacteristics": ["慢热型节奏", "友情与牺牲主题"]
}'''
        : '''{
  "id": "character-001",
  "name": "角色名称",
  "avatar": "⭐",
  "personality": ["理性", "冷静"],
  "appearance": ["黑色外套", "短发"],
  "personalInfo": ["职业：侦探", "年龄：28岁"],
  "backgroundStory": ["背景故事"]
}''';
    if (_jsonCtrl.text.isEmpty) {
      _jsonCtrl.text = example;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: RadioListTile<ContactCategory>(
                title: const Text('角色'),
                value: ContactCategory.contact,
                groupValue: _category,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
            ),
            Expanded(
              child: RadioListTile<ContactCategory>(
                title: const Text('故事'),
                value: ContactCategory.story,
                groupValue: _category,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
            ),
          ],
        ),
        TextField(
          controller: _jsonCtrl,
          minLines: 10,
          maxLines: 15,
          decoration: const InputDecoration(
            labelText: 'JSON 格式',
            hintText: '请输入标准 JSON 格式',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _mode = _EditorMode.normal),
            child: const Text('返回普通模式'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () =>
                setState(() => _mode = _EditorMode.naturalLanguage),
            child: const Text('使用自然语言创建'),
          ),
        ),
      ],
    );
  }

  Widget _buildNaturalLanguageForm() {
    final example = _category == ContactCategory.story
        ? '创建一个魔法世界的故事，包含魔法师、魔法石等元素'
        : '创建一个名叫小明的侦探，性格理性冷静，穿着黑色外套';
    if (_nlCtrl.text.isEmpty) {
      _nlCtrl.text = example;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: RadioListTile<ContactCategory>(
                title: const Text('角色'),
                value: ContactCategory.contact,
                groupValue: _category,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
            ),
            Expanded(
              child: RadioListTile<ContactCategory>(
                title: const Text('故事'),
                value: ContactCategory.story,
                groupValue: _category,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
            ),
          ],
        ),
        TextField(
          controller: _nlCtrl,
          minLines: 6,
          maxLines: 10,
          decoration: InputDecoration(
            labelText: '自然语言描述',
            hintText: _category == ContactCategory.story
                ? '描述你的故事世界观和设定'
                : '描述你的角色特征和背景',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _mode = _EditorMode.normal),
            child: const Text('返回普通模式'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _mode = _EditorMode.json),
            child: const Text('使用 JSON 创建'),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _onSave,
        child: const Text('创建'),
      ),
    ];
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

  void _saveNormalMode() {
    final name = _nameCtrl.text.trim();
    final avatar = _avatarCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称不能为空')),
      );
      return;
    }

    // 构建 settings 列表（故事类型时包含 key-value 设定）
    final List<Map<String, dynamic>> settings =
        _category == ContactCategory.story
            ? _storySettings
                .map((e) => {
                      'key': e['key'],
                      'value': e['value'],
                      'relate': e['relate'] ?? <String>[],
                    })
                .toList()
            : <Map<String, dynamic>>[];

    Navigator.of(context).pop(
      ContactDraft(
        name: name,
        avatar: avatar,
        personality: List<String>.from(_personality),
        appearance: _category == ContactCategory.contact
            ? List<String>.from(_appearance)
            : null,
        personalInfo: _category == ContactCategory.contact
            ? List<String>.from(_personalInfo)
            : null,
        settings: settings,
        backgroundStory: List<String>.from(_backgroundStory),
        narrativeRules: _category == ContactCategory.story
            ? List<String>.from(_narrativeRules)
            : null,
        otherCharacteristics: _category == ContactCategory.story
            ? List<String>.from(_otherCharacteristics)
            : null,
        category: _category,
      ),
    );
  }

  void _saveJsonMode() {
    final jsonStr = _jsonCtrl.text.trim();
    if (jsonStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('JSON 不能为空')),
      );
      return;
    }
    Navigator.of(context).pop(
      ContactDraft(
        name: _nameCtrl.text.trim(),
        avatar: _avatarCtrl.text.trim(),
        personality: List<String>.from(_personality),
        appearance: List<String>.from(_appearance),
        personalInfo: List<String>.from(_personalInfo),
        settings: _storySettings
            .map((e) => {
                  'key': e['key'],
                  'value': e['value'],
                  'relate': e['relate'] ?? <String>[],
                })
            .toList(),
        backgroundStory: List<String>.from(_backgroundStory),
        narrativeRules: _category == ContactCategory.story
            ? List<String>.from(_narrativeRules)
            : null,
        otherCharacteristics: _category == ContactCategory.story
            ? List<String>.from(_otherCharacteristics)
            : null,
        category: _category,
        jsonString: jsonStr,
      ),
    );
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
        personality: List<String>.from(_personality),
        appearance: List<String>.from(_appearance),
        personalInfo: List<String>.from(_personalInfo),
        settings: _storySettings
            .map((e) => {
                  'key': e['key'],
                  'value': e['value'],
                  'relate': e['relate'] ?? <String>[],
                })
            .toList(),
        backgroundStory: List<String>.from(_backgroundStory),
        narrativeRules: _category == ContactCategory.story
            ? List<String>.from(_narrativeRules)
            : null,
        otherCharacteristics: _category == ContactCategory.story
            ? List<String>.from(_otherCharacteristics)
            : null,
        category: _category,
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

/// 编辑设定对话框内容组件
///
/// 用于编辑设定的关联词列表，支持逐个添加和删除
class _EditSettingDialog extends StatefulWidget {
  const _EditSettingDialog({
    required this.keyCtrl,
    required this.valueCtrl,
    required this.initialRelate,
  });

  final TextEditingController keyCtrl;
  final TextEditingController valueCtrl;
  final List<String> initialRelate;

  static List<String> relateList = <String>[];

  @override
  State<_EditSettingDialog> createState() => _EditSettingDialogState();
}

class _EditSettingDialogState extends State<_EditSettingDialog> {
  final TextEditingController _relateCtrl = TextEditingController();
  final List<String> _relateList = <String>[];

  @override
  void initState() {
    super.initState();
    _relateList.addAll(widget.initialRelate);
    _EditSettingDialog.relateList = _relateList;
  }

  @override
  void dispose() {
    _relateCtrl.dispose();
    super.dispose();
  }

  void _addRelate() {
    final input = _relateCtrl.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _relateList.add(input);
      _EditSettingDialog.relateList = _relateList;
      _relateCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.keyCtrl,
          decoration: const InputDecoration(
            labelText: '设定名称',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.valueCtrl,
          decoration: const InputDecoration(
            labelText: '设定描述',
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        const Text('关联词'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _relateCtrl,
                decoration: const InputDecoration(
                  hintText: '输入关联词',
                  isDense: true,
                ),
                onSubmitted: (_) => _addRelate(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _addRelate,
              child: const Text('添加'),
            ),
          ],
        ),
        if (_relateList.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _relateList.length; i++)
                Chip(
                  label: Text(_relateList[i]),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () {
                    setState(() {
                      _relateList.removeAt(i);
                      _EditSettingDialog.relateList = _relateList;
                    });
                  },
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
