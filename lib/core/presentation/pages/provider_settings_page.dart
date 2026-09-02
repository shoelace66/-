import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/provider_settings.dart';

class ProviderSettingsPage extends StatefulWidget {
  const ProviderSettingsPage({super.key, this.initial});

  /// 入参通常来自 ChatProvider 当前生效的 [ProviderSettings]
  final ProviderSettings? initial;

  @override
  State<ProviderSettingsPage> createState() => _ProviderSettingsPageState();
}

class _ProviderSettingsPageState extends State<ProviderSettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ProviderSettings _settings;
  LlmProfile? _disabledMemoryRecallDraft;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _settings = widget.initial ?? const ProviderSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _setLlm(LlmProfile llm) {
    setState(() => _settings = _settings.copyWith(llm: llm));
  }

  void _setMemoryRecallEnabled(bool enabled) {
    if (enabled) {
      final profile = _disabledMemoryRecallDraft ??
          _settings.llm.copyWith(
            parameters: _settings.llm.parameters.copyWith(
              temperature: 0,
              maxTokens: 128,
              timeoutSeconds: 12,
              stream: false,
            ),
          );
      setState(() {
        _settings = _settings.copyWith(memoryRecallLlm: profile);
        _disabledMemoryRecallDraft = null;
      });
      return;
    }

    setState(() {
      _disabledMemoryRecallDraft = _settings.memoryRecallLlm;
      _settings = _settings.copyWith(clearMemoryRecallLlm: true);
    });
  }

  void _setMemoryRecallLlm(LlmProfile profile) {
    setState(() {
      _settings = _settings.copyWith(memoryRecallLlm: profile);
    });
  }

  void _activateLocalLlm(LlmProfile profile) {
    final current = _settings.llm;
    if (identical(current, profile)) return;
    final fallbacks = _settings.fallbackLlmProfiles
        .where((candidate) => !identical(candidate, profile))
        .toList(growable: true)
      ..insert(0, current);
    setState(() {
      _settings = _settings.copyWith(
        llm: profile,
        fallbackLlmProfiles: fallbacks,
      );
    });
  }

  void _addLlmProfile() {
    const profile = LlmProfile(
      presetId: 'custom',
      baseUrl: '',
      model: '',
    );
    setState(() {
      _settings = _settings.copyWith(
        llm: profile,
        fallbackLlmProfiles: <LlmProfile>[
          _settings.llm,
          ..._settings.fallbackLlmProfiles,
        ],
      );
    });
  }

  void _deleteActiveLlmProfile() {
    if (_settings.fallbackLlmProfiles.isEmpty) return;
    final next = _settings.fallbackLlmProfiles.first;
    setState(() {
      _settings = _settings.copyWith(
        llm: next,
        fallbackLlmProfiles:
            _settings.fallbackLlmProfiles.skip(1).toList(growable: false),
      );
    });
  }

  void _setImage(ImageProfile image) {
    setState(() => _settings = _settings.copyWith(image: image));
  }

  void _setTts(TtsProfile tts) {
    setState(() => _settings = _settings.copyWith(tts: tts));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API 提供商'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop<ProviderSettings>(_settings);
            },
            child: const Text('保存'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'LLM'),
            Tab(icon: Icon(Icons.manage_search_outlined), text: '召回'),
            Tab(icon: Icon(Icons.image_outlined), text: '生图'),
            Tab(icon: Icon(Icons.record_voice_over_outlined), text: 'TTS'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Column(
            children: [
              SizedBox(
                height: 58,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final profile in <LlmProfile>[
                      _settings.llm,
                      ..._settings.fallbackLlmProfiles,
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: identical(profile, _settings.llm),
                          label: Text(
                            '${profile.presetId} / ${profile.model.isEmpty ? "未配置" : profile.model}',
                          ),
                          onSelected: (_) => _activateLocalLlm(profile),
                        ),
                      ),
                    IconButton(
                      onPressed: _addLlmProfile,
                      tooltip: '添加 LLM Profile',
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    IconButton(
                      onPressed: _settings.fallbackLlmProfiles.isEmpty
                          ? null
                          : _deleteActiveLlmProfile,
                      tooltip: '删除当前 Profile',
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _LlmTab(
                  key: ValueKey(_settings.llm),
                  profile: _settings.llm,
                  onChanged: _setLlm,
                ),
              ),
            ],
          ),
          _MemoryRecallLlmTab(
            enabled: _settings.memoryRecallLlm != null,
            profile: _settings.memoryRecallLlm,
            onEnabledChanged: _setMemoryRecallEnabled,
            onChanged: _setMemoryRecallLlm,
          ),
          _ImageTab(
            profile: _settings.image,
            onChanged: _setImage,
          ),
          _TtsTab(
            profile: _settings.tts,
            onChanged: _setTts,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Memory recall LLM Tab
// ============================================================

class _MemoryRecallLlmTab extends StatelessWidget {
  const _MemoryRecallLlmTab({
    required this.enabled,
    required this.profile,
    required this.onEnabledChanged,
    required this.onChanged,
  });

  final bool enabled;
  final LlmProfile? profile;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<LlmProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = profile;
    return Column(
      children: [
        SwitchListTile(
          title: const Text('使用独立事件召回模型'),
          subtitle: Text(
            enabled ? '召回失败时只使用本地结果，不会自动切换到主模型。' : '未启用时，事件召回的额外请求使用主 LLM。',
          ),
          value: enabled,
          onChanged: onEnabledChanged,
        ),
        const Divider(height: 1),
        if (current == null)
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '建议为 PLAN / JUDGE 配置便宜的小模型，'
                  '以避免占用角色对话主模型的费用。',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              '召回调用会强制使用非流式、低温度和小输出上限；'
              '此处的账号与模型配置仍与主 LLM 完全独立。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: _LlmTab(
              key: const ValueKey('memoryRecallLlm'),
              profile: current,
              onChanged: onChanged,
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// LLM Tab
// ============================================================

class _LlmTab extends StatefulWidget {
  const _LlmTab({super.key, required this.profile, required this.onChanged});

  final LlmProfile profile;
  final ValueChanged<LlmProfile> onChanged;

  @override
  State<_LlmTab> createState() => _LlmTabState();
}

class _LlmTabState extends State<_LlmTab> {
  late LlmProfile _draft;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _draft = widget.profile;
  }

  void _applyPreset(String presetId, {String? model}) {
    final next = _draft
        .copyWith(presetId: presetId)
        .withPresetDefaults(overrideModel: model);
    setState(() => _draft = next);
    widget.onChanged(_draft);
  }

  void _updateDraft(LlmProfile Function(LlmProfile) mapper) {
    final next = mapper(_draft);
    setState(() => _draft = next);
    widget.onChanged(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final preset =
        ProviderPreset.findById(_draft.presetId, ProviderPreset.llmPresets);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        _PresetDropdown(
          label: 'LLM 提供商',
          options: ProviderPreset.llmPresets,
          currentId: _draft.presetId,
          onChanged: (id) => _applyPreset(id),
        ),
        if (preset.notes != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 2),
            child: Text(
              preset.notes!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ),
        _LabeledTextField(
          label: 'API Key',
          initialValue: _draft.apiKey,
          obscure: _obscureKey,
          onChanged: (v) => _updateDraft((d) => d.copyWith(apiKey: v)),
          suffix: IconButton(
            icon: Icon(_obscureKey
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _obscureKey = !_obscureKey),
          ),
        ),
        _LabeledTextField(
          label: 'Base URL',
          initialValue: _draft.baseUrl,
          onChanged: (v) => _updateDraft((d) => d.copyWith(baseUrl: v)),
          hint: 'https://api.openai.com/v1',
        ),
        _ModelDropdownOrInput(
          models: preset.models,
          currentModel: _draft.model,
          onChanged: (v) => _updateDraft((d) => d.copyWith(model: v)),
        ),
        const SizedBox(height: 16),
        const _SectionHeader('生成参数'),
        _SliderSetting(
          title: '温度（Temperature）',
          subtitle: '越高越发散，越低越确定（0.0 - 2.0）',
          value: _draft.parameters.temperature,
          min: 0,
          max: 2,
          divisions: 40,
          decimalDigits: 2,
          onChanged: (v) => _updateDraft(
            (d) =>
                d.copyWith(parameters: d.parameters.copyWith(temperature: v)),
          ),
        ),
        _SliderSetting(
          title: 'Top P（核采样）',
          subtitle: '只从概率前 P% 的 token 中采样（0.0 - 1.0）',
          value: _draft.parameters.topP,
          min: 0,
          max: 1,
          divisions: 20,
          decimalDigits: 2,
          onChanged: (v) => _updateDraft(
            (d) => d.copyWith(parameters: d.parameters.copyWith(topP: v)),
          ),
        ),
        _NumberSetting(
          title: '最大 Token',
          subtitle: '单次回复的最大 token 数（0 = 不限制）',
          value: _draft.parameters.maxTokens,
          min: 0,
          max: 32000,
          step: 64,
          onChanged: (v) => _updateDraft(
            (d) => d.copyWith(parameters: d.parameters.copyWith(maxTokens: v)),
          ),
        ),
        _SliderSetting(
          title: '输入价格（每百万 Token）',
          subtitle: '用于本地费用估算；0 表示未配置',
          value: _draft.inputPricePerMillion.clamp(0, 100),
          min: 0,
          max: 100,
          divisions: 1000,
          decimalDigits: 2,
          onChanged: (value) => _updateDraft(
            (draft) => draft.copyWith(inputPricePerMillion: value),
          ),
        ),
        _SliderSetting(
          title: '输出价格（每百万 Token）',
          subtitle: '用于本地费用估算；0 表示未配置',
          value: _draft.outputPricePerMillion.clamp(0, 100),
          min: 0,
          max: 100,
          divisions: 1000,
          decimalDigits: 2,
          onChanged: (value) => _updateDraft(
            (draft) => draft.copyWith(outputPricePerMillion: value),
          ),
        ),
        _SliderSetting(
          title: '频率惩罚（Frequency Penalty）',
          subtitle: '降低重复已出现 token 的概率（-2.0 ~ 2.0）',
          value: _draft.parameters.frequencyPenalty,
          min: -2,
          max: 2,
          divisions: 40,
          decimalDigits: 2,
          onChanged: (v) => _updateDraft(
            (d) => d.copyWith(
                parameters: d.parameters.copyWith(frequencyPenalty: v)),
          ),
        ),
        _SliderSetting(
          title: '存在惩罚（Presence Penalty）',
          subtitle: '鼓励模型引入新主题（-2.0 ~ 2.0）',
          value: _draft.parameters.presencePenalty,
          min: -2,
          max: 2,
          divisions: 40,
          decimalDigits: 2,
          onChanged: (v) => _updateDraft(
            (d) => d.copyWith(
                parameters: d.parameters.copyWith(presencePenalty: v)),
          ),
        ),
        _NumberSetting(
          title: '请求超时（秒）',
          subtitle: '单次 HTTP 请求的最大等待时间',
          value: _draft.parameters.timeoutSeconds,
          min: 5,
          max: 600,
          step: 5,
          onChanged: (v) => _updateDraft(
            (d) => d.copyWith(
                parameters: d.parameters.copyWith(timeoutSeconds: v)),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('流式响应（SSE）'),
          subtitle: const Text('增量显示 reply；完整响应到达后再原子提交记忆。'),
          value: _draft.parameters.stream,
          onChanged: (value) => _updateDraft(
            (draft) => draft.copyWith(
              parameters: draft.parameters.copyWith(stream: value),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Image Tab
// ============================================================

class _ImageTab extends StatefulWidget {
  const _ImageTab({required this.profile, required this.onChanged});

  final ImageProfile profile;
  final ValueChanged<ImageProfile> onChanged;

  @override
  State<_ImageTab> createState() => _ImageTabState();
}

class _ImageTabState extends State<_ImageTab> {
  late ImageProfile _draft;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _draft = widget.profile;
  }

  void _applyPreset(String presetId, {String? model}) {
    final next = _draft
        .copyWith(presetId: presetId)
        .withPresetDefaults(overrideModel: model);
    setState(() => _draft = next);
    widget.onChanged(_draft);
  }

  void _updateDraft(ImageProfile Function(ImageProfile) mapper) {
    final next = mapper(_draft);
    setState(() => _draft = next);
    widget.onChanged(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final preset =
        ProviderPreset.findById(_draft.presetId, ProviderPreset.imagePresets);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        _PresetDropdown(
          label: '生图服务',
          options: ProviderPreset.imagePresets,
          currentId: _draft.presetId,
          onChanged: (id) => _applyPreset(id),
        ),
        if (preset.notes != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 2),
            child: Text(
              preset.notes!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ),
        _LabeledTextField(
          label: 'API Key（部分服务免 key）',
          initialValue: _draft.apiKey,
          obscure: _obscureKey,
          onChanged: (v) => _updateDraft((d) => d.copyWith(apiKey: v)),
          suffix: IconButton(
            icon: Icon(_obscureKey
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _obscureKey = !_obscureKey),
          ),
        ),
        _LabeledTextField(
          label: 'Base URL',
          initialValue: _draft.baseUrl,
          onChanged: (v) => _updateDraft((d) => d.copyWith(baseUrl: v)),
          hint: 'https://api.openai.com/v1',
        ),
        _ModelDropdownOrInput(
          models: preset.models,
          currentModel: _draft.model,
          onChanged: (v) => _updateDraft((d) => d.copyWith(model: v)),
        ),
        const SizedBox(height: 16),
        const _SectionHeader('生图参数'),
        _LabeledTextField(
          label: '尺寸（Size）',
          initialValue: _draft.parameters.size,
          onChanged: (v) => _updateDraft(
            (d) => d.copyWith(parameters: d.parameters.copyWith(size: v)),
          ),
          hint: '1024x1024',
        ),
        _NumberSetting(
          title: '生成数量（n）',
          subtitle: '单次请求生成图片张数',
          value: _draft.parameters.n,
          min: 1,
          max: 4,
          step: 1,
          onChanged: (v) => _updateDraft(
            (d) => d.copyWith(parameters: d.parameters.copyWith(n: v)),
          ),
        ),
        _LabeledTextField(
          label: '风格（Style）',
          initialValue: _draft.parameters.style,
          onChanged: (v) => _updateDraft(
            (d) => d.copyWith(parameters: d.parameters.copyWith(style: v)),
          ),
          hint: 'vivid / natural / 留空',
        ),
        _LabeledTextField(
          label: '质量（Quality）',
          initialValue: _draft.parameters.quality,
          onChanged: (v) => _updateDraft(
            (d) => d.copyWith(parameters: d.parameters.copyWith(quality: v)),
          ),
          hint: 'standard / hd',
        ),
        _LabeledTextField(
          label: '返回格式',
          initialValue: _draft.parameters.responseFormat,
          onChanged: (v) => _updateDraft(
            (d) => d.copyWith(
                parameters: d.parameters.copyWith(responseFormat: v)),
          ),
          hint: 'url / b64_json',
        ),
        _NumberSetting(
          title: '请求超时（秒）',
          subtitle: '生图通常需要更长时间',
          value: _draft.parameters.timeoutSeconds,
          min: 10,
          max: 600,
          step: 5,
          onChanged: (v) => _updateDraft(
            (d) => d.copyWith(
                parameters: d.parameters.copyWith(timeoutSeconds: v)),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// TTS Tab
// ============================================================

class _TtsTab extends StatefulWidget {
  const _TtsTab({required this.profile, required this.onChanged});

  final TtsProfile profile;
  final ValueChanged<TtsProfile> onChanged;

  @override
  State<_TtsTab> createState() => _TtsTabState();
}

class _TtsTabState extends State<_TtsTab> {
  late TtsProfile _draft;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _draft = widget.profile;
  }

  void _applyPreset(String presetId, {String? model}) {
    final next = _draft
        .copyWith(presetId: presetId)
        .withPresetDefaults(overrideModel: model);
    setState(() => _draft = next);
    widget.onChanged(_draft);
  }

  void _updateDraft(TtsProfile Function(TtsProfile) mapper) {
    final next = mapper(_draft);
    setState(() => _draft = next);
    widget.onChanged(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final preset =
        ProviderPreset.findById(_draft.presetId, ProviderPreset.ttsPresets);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        _PresetDropdown(
          label: 'TTS 服务',
          options: ProviderPreset.ttsPresets,
          currentId: _draft.presetId,
          onChanged: (id) => _applyPreset(id),
        ),
        if (preset.notes != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 2),
            child: Text(
              preset.notes!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ),
        _LabeledTextField(
          label: 'API Key（edge_tts 留空）',
          initialValue: _draft.apiKey,
          obscure: _obscureKey,
          onChanged: (v) => _updateDraft((d) => d.copyWith(apiKey: v)),
          suffix: IconButton(
            icon: Icon(_obscureKey
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _obscureKey = !_obscureKey),
          ),
        ),
        _LabeledTextField(
          label: 'Base URL',
          initialValue: _draft.baseUrl,
          onChanged: (v) => _updateDraft((d) => d.copyWith(baseUrl: v)),
          hint: preset.id == 'edge_tts'
              ? 'https://your-edge-tts-proxy'
              : 'https://api.openai.com/v1',
        ),
        _ModelDropdownOrInput(
          models: preset.models,
          currentModel: _draft.model,
          onChanged: (v) => _updateDraft((d) => d.copyWith(model: v)),
        ),
        const SizedBox(height: 16),
        const _SectionHeader('说明'),
        if (preset.id == 'edge_tts')
          const _HintBlock(
            '默认音色（model 字段）会作为没有自定义音色的联系人使用；'
            '联系人编辑页可单独覆盖。\n\n'
            'edge_tts 需自行搭建支持 WebSocket/HTTP 转发的代理服务，'
            '因为微软没有公开的纯 HTTP 文本转音频接口。',
          )
        else if (preset.id == 'openai_tts')
          const _HintBlock(
            '支持的 model：tts-1、tts-1-hd、gpt-4o-mini-tts。\n'
            'edge_tts 风格的音色 ID 会被自动映射到 OpenAI 的 alloy/echo/onyx/'
            'shimmer/nova 等内置 voice。',
          )
        else
          const _HintBlock(
            '自定义 TTS：POST {Base URL}，body 为 {text, voice, model} JSON，'
            '返回原始音频 bytes（mp3 / wav / pcm）。',
          ),
        _NumberSetting(
          title: '请求超时（秒）',
          subtitle: '单次合成请求的最大等待时间',
          value: _draft.timeoutSeconds,
          min: 5,
          max: 600,
          step: 5,
          onChanged: (v) => _updateDraft((d) => d.copyWith(timeoutSeconds: v)),
        ),
      ],
    );
  }
}

// ============================================================
// 通用小组件
// ============================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _HintBlock extends StatelessWidget {
  const _HintBlock(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
          height: 1.5,
        ),
      ),
    );
  }
}

class _PresetDropdown extends StatelessWidget {
  const _PresetDropdown({
    required this.label,
    required this.options,
    required this.currentId,
    required this.onChanged,
  });

  final String label;
  final List<ProviderPreset> options;
  final String currentId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = ProviderPreset.findById(currentId, options);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: selected.id,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: [
            for (final p in options)
              DropdownMenuItem<String>(
                value: p.id,
                child: Text(p.label, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ),
    );
  }
}

class _LabeledTextField extends StatefulWidget {
  const _LabeledTextField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.hint,
    this.obscure = false,
    this.suffix,
  });

  final String label;
  final String initialValue;
  final String? hint;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String> onChanged;

  @override
  State<_LabeledTextField> createState() => _LabeledTextFieldState();
}

class _LabeledTextFieldState extends State<_LabeledTextField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _ctrl,
        obscureText: widget.obscure,
        maxLines: widget.obscure ? 1 : null,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: widget.suffix,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _ModelDropdownOrInput extends StatelessWidget {
  const _ModelDropdownOrInput({
    required this.models,
    required this.currentModel,
    required this.onChanged,
  });

  final List<String> models;
  final String currentModel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) {
      return _LabeledTextField(
        label: 'Model',
        initialValue: currentModel,
        onChanged: onChanged,
        hint: '例如：gpt-4o-mini',
      );
    }
    final match = models.contains(currentModel);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Model',
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: match ? currentModel : null,
            hint: match ? null : const Text('选择模型'),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            items: [
              for (final m in models)
                DropdownMenuItem<String>(
                  value: m,
                  child: Text(m, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.decimalDigits,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final int decimalDigits;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  value.toStringAsFixed(decimalDigits),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(decimalDigits),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _NumberSetting extends StatefulWidget {
  const _NumberSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberSetting> createState() => _NumberSettingState();
}

class _NumberSettingState extends State<_NumberSetting> {
  late int _draftValue;

  @override
  void initState() {
    super.initState();
    _draftValue = widget.value;
  }

  void _bump(int delta) {
    final next = (_draftValue + delta).clamp(widget.min, widget.max);
    if (next == _draftValue) return;
    setState(() => _draftValue = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(widget.title),
      subtitle: Text(widget.subtitle),
      trailing: SizedBox(
        width: 160,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed:
                  _draftValue > widget.min ? () => _bump(-widget.step) : null,
            ),
            Expanded(
              child: TextField(
                textAlign: TextAlign.center,
                controller: TextEditingController(text: _draftValue.toString())
                  ..selection = TextSelection.collapsed(
                    offset: _draftValue.toString().length,
                  ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onSubmitted: (raw) {
                  final parsed = int.tryParse(raw) ?? _draftValue;
                  final next = parsed.clamp(widget.min, widget.max);
                  setState(() => _draftValue = next);
                  widget.onChanged(next);
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed:
                  _draftValue < widget.max ? () => _bump(widget.step) : null,
            ),
          ],
        ),
      ),
    );
  }
}
