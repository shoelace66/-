import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../constants/app_strings.dart';
import '../../data/models/app_settings.dart';

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key});

  static const String routeName = '/app-settings';

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  static const String _settingsKey = AppStrings.appSettingsKey;

  AppSettings _settings = const AppSettings();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          setState(() {
            _settings = AppSettings.fromJson(
              decoded.map((k, v) => MapEntry(k.toString(), v)),
            );
            _isLoading = false;
          });
          return;
        }
      } catch (_) {}
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(_settings.toJson()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildNumberSetting({
    required String title,
    required String subtitle,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: SizedBox(
        width: 120,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            Text(
              value.toString(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('应用设置'),
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bottomPadding = MediaQuery.of(context).padding.bottom;
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: 32 + bottomPadding),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSectionTitle('LLM 输入限制'),
                    _buildNumberSetting(
                      title: '短期事件数量',
                      subtitle: '输入到 LLM 的短期事件数量（默认: 10）',
                      value: _settings.maxShortTermEvents,
                      min: 1,
                      max: 50,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(maxShortTermEvents: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '长期事件数量',
                      subtitle: '输入到 LLM 的长期事件数量（默认: 1，只取最新 summary；老 summary 通过 2→3 cascade 进超长期不会丢）',
                      value: _settings.maxLongTermEvents,
                      min: 1,
                      max: 30,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(maxLongTermEvents: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '超长期事件数量',
                      subtitle: '输入到 LLM 的超长期事件数量（默认: 2）',
                      value: _settings.maxUltraTermEvents,
                      min: 1,
                      max: 20,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(maxUltraTermEvents: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '关联事件数量',
                      subtitle: '关键词检索返回的最大事件数（默认: 5）',
                      value: _settings.maxRelatedEvents,
                      min: 1,
                      max: 20,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(maxRelatedEvents: v);
                      }),
                    ),
                    _buildSectionTitle('本地存储限制'),
                    _buildNumberSetting(
                      title: '短期队列容量',
                      subtitle: '本地存储的短期事件最大数量（默认: 2000）',
                      value: _settings.maxShortQueue,
                      min: 100,
                      max: 10000,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(maxShortQueue: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '长期队列容量',
                      subtitle: '本地存储的长期事件最大数量（默认: 500）',
                      value: _settings.maxLongQueue,
                      min: 50,
                      max: 5000,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(maxLongQueue: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '超长期队列容量',
                      subtitle: '本地存储的超长期事件最大数量（默认: 200）',
                      value: _settings.maxUltraQueue,
                      min: 20,
                      max: 2000,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(maxUltraQueue: v);
                      }),
                    ),
                    _buildSectionTitle('Prompt 限制'),
                    _buildNumberSetting(
                      title: '列表项数量',
                      subtitle: 'Prompt 中列表项的最大数量（默认: 5）',
                      value: _settings.maxPromptListItems,
                      min: 1,
                      max: 20,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(maxPromptListItems: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '单行长度',
                      subtitle: 'Prompt 中单行的最大字符数（默认: 200）',
                      value: _settings.maxPromptLineLength,
                      min: 50,
                      max: 1000,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(maxPromptLineLength: v);
                      }),
                    ),
                    _buildSectionTitle('事件处理'),
                    _buildNumberSetting(
                      title: '总结阈值（短期→长期）',
                      subtitle: '短期事件数 ≥ 此值时让 LLM 压缩到长期（默认: 10）',
                      value: _settings.summaryThreshold,
                      min: 2,
                      max: 50,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(summaryThreshold: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '超长期阈值（长期→超长期）',
                      subtitle: '长期事件数 ≥ 此值时让 LLM 再压到超长期（默认: 5；调到 999 即可禁用超长期级联）',
                      value: _settings.ultraSummaryThreshold,
                      min: 2,
                      max: 100,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(ultraSummaryThreshold: v);
                      }),
                    ),
                    _buildSectionTitle('关联检索'),
                    _buildNumberSetting(
                      title: '检索深度',
                      subtitle: '关联检索的邻居层级深度（默认：2）',
                      value: _settings.searchDepth,
                      min: 1,
                      max: 5,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(searchDepth: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '向量相似度权重',
                      subtitle: '向量记忆相似度评分在综合排序中的权重百分比（默认：80%）',
                      value: _settings.vectorSimilarityWeight,
                      min: 0,
                      max: 100,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(vectorSimilarityWeight: v);
                      }),
                    ),
                    _buildSectionTitle('LRU 权重设置'),
                    _buildNumberSetting(
                      title: '关键词匹配权重',
                      subtitle: '事件与用户输入关键词匹配的权重（默认: 100）',
                      value: _settings.lruKeywordMatchWeight,
                      min: 1,
                      max: 500,
                      onChanged: (v) => setState(() {
                        _settings =
                            _settings.copyWith(lruKeywordMatchWeight: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '事件-事件关联权重',
                      subtitle: '与关键词匹配事件相关联的事件权重（默认: 50）',
                      value: _settings.lruEventEventWeight,
                      min: 1,
                      max: 300,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(lruEventEventWeight: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '事件-物品关联（关键词相关）权重',
                      subtitle: '与关键词相关的物品关联事件权重（默认: 30）',
                      value: _settings.lruEventBelongingKeywordWeight,
                      min: 1,
                      max: 200,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(
                            lruEventBelongingKeywordWeight: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '事件-物品关联（普通）权重',
                      subtitle: '普通物品关联事件权重（默认: 10）',
                      value: _settings.lruEventBelongingNormalWeight,
                      min: 1,
                      max: 100,
                      onChanged: (v) => setState(() {
                        _settings = _settings.copyWith(
                            lruEventBelongingNormalWeight: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '事件-设定关联（关键词相关）权重',
                      subtitle: '与关键词相关的设定关联事件权重（默认: 30）',
                      value: _settings.lruEventSettingKeywordWeight,
                      min: 1,
                      max: 200,
                      onChanged: (v) => setState(() {
                        _settings =
                            _settings.copyWith(lruEventSettingKeywordWeight: v);
                      }),
                    ),
                    _buildNumberSetting(
                      title: '事件-设定关联（普通）权重',
                      subtitle: '普通设定关联事件权重（默认: 10）',
                      value: _settings.lruEventSettingNormalWeight,
                      min: 1,
                      max: 100,
                      onChanged: (v) => setState(() {
                        _settings =
                            _settings.copyWith(lruEventSettingNormalWeight: v);
                      }),
                    ),
                    _buildSectionTitle('关键词库'),
                    _buildNumberSetting(
                      title: '关键词库容量',
                      subtitle: '每个联系人保留的最大关键词数量（默认: 200）',
                      value: _settings.keywordLibrarySize,
                      min: 50,
                      max: 1000,
                      onChanged: (v) => setState(() {
                        _settings =
                            _settings.copyWith(keywordLibrarySize: v);
                      }),
                    ),
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _settings = const AppSettings();
                          });
                        },
                        child: const Text('恢复默认设置'),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
