import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/contact.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/services/memory_revision_service.dart';
import 'memory_recall_debugger_page.dart';

class MemoryArchivePage extends StatefulWidget {
  const MemoryArchivePage({super.key, required this.provider});

  final ChatProvider provider;

  @override
  State<MemoryArchivePage> createState() => _MemoryArchivePageState();
}

class _MemoryArchivePageState extends State<MemoryArchivePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<EventTier> _tierFilter = {};
  final Set<String> _statusFilter = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  List<EventNode> _filteredNodes(List<EventNode> nodes) {
    var result = nodes;
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((node) {
        final desc = node.event.description.toLowerCase();
        final keywords = node.event.keywords.join(' ').toLowerCase();
        final themes = node.event.theme.join(' ').toLowerCase();
        return desc.contains(query) ||
            keywords.contains(query) ||
            themes.contains(query);
      }).toList(growable: false);
    }
    if (_tierFilter.isNotEmpty) {
      result = result
          .where((node) => _tierFilter.contains(node.tier))
          .toList(growable: false);
    }
    if (_statusFilter.contains('invalidated')) {
      result =
          result.where((node) => node.invalidated).toList(growable: false);
    }
    if (_statusFilter.contains('needsReview')) {
      result =
          result.where((node) => node.needsReview).toList(growable: false);
    }
    if (_statusFilter.contains('locked')) {
      result = result
          .where((node) => widget.provider.isMemoryLocked(node.id))
          .toList(growable: false);
    }
    if (_statusFilter.contains('normal')) {
      result = result
          .where(
              (node) => !node.invalidated && !widget.provider.isMemoryLocked(node.id))
          .toList(growable: false);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.provider,
      builder: (context, _) {
        final nodes = widget.provider.memoryNodes;
        return Scaffold(
          appBar: AppBar(
            title: const Text('记忆档案'),
            actions: [
              IconButton(
                onPressed:
                    widget.provider.canUndoMemoryRevision ? _undo : null,
                tooltip: '撤销最近一次记忆修改',
                icon: const Icon(Icons.undo),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '列表', icon: Icon(Icons.list)),
                Tab(text: '时间线', icon: Icon(Icons.timeline)),
                Tab(text: '召回调试', icon: Icon(Icons.search)),
              ],
            ),
          ),
          body: nodes.isEmpty
              ? const Center(child: Text('当前角色还没有形成事件记忆'))
              : Column(
                  children: [
                    _buildStatsBar(context, nodes),
                    _buildFilterBar(context, nodes),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildListView(context, nodes),
                          _buildTimelineView(context, nodes),
                          _buildRecallDebugView(context, nodes),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildStatsBar(BuildContext context, List<EventNode> nodes) {
    final stats = widget.provider.memoryStats;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          _statChip('总计', '${stats['total'] ?? 0}', theme),
          const SizedBox(width: 8),
          _statChip('短期', '${stats['shortTerm'] ?? 0}', theme,
              color: theme.colorScheme.tertiaryContainer),
          const SizedBox(width: 8),
          _statChip('长期', '${stats['longTerm'] ?? 0}', theme,
              color: theme.colorScheme.secondaryContainer),
          const SizedBox(width: 8),
          _statChip('超长期', '${stats['ultraLongTerm'] ?? 0}', theme,
              color: theme.colorScheme.primaryContainer),
          const SizedBox(width: 8),
          if ((stats['locked'] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _statChip('锁定', '${stats['locked']}', theme,
                  color: theme.colorScheme.errorContainer),
            ),
          if ((stats['invalidated'] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _statChip('作废', '${stats['invalidated']}', theme,
                  color: theme.colorScheme.errorContainer),
            ),
          if ((stats['needsReview'] ?? 0) > 0)
            _statChip('待复核', '${stats['needsReview']}', theme,
                color: theme.colorScheme.tertiaryContainer),
          const Spacer(),
          Text(
            '${stats['edges'] ?? 0} 条关系边',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, ThemeData theme,
      {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 11,
          color: color != null
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, List<EventNode> nodes) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索记忆内容、关键词或主题...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('短期', EventTier.shortTerm, theme),
                const SizedBox(width: 4),
                _filterChip('长期', EventTier.longTerm, theme),
                const SizedBox(width: 4),
                _filterChip('超长期', EventTier.ultraLongTerm, theme),
                const SizedBox(width: 8),
                Container(
                  width: 1,
                  height: 24,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(width: 8),
                _statusChip('正常', 'normal', theme),
                const SizedBox(width: 4),
                _statusChip('已作废', 'invalidated', theme),
                const SizedBox(width: 4),
                _statusChip('待复核', 'needsReview', theme),
                const SizedBox(width: 4),
                _statusChip('已锁定', 'locked', theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, EventTier tier, ThemeData theme) {
    final selected = _tierFilter.contains(tier);
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (v) {
        setState(() {
          if (v) {
            _tierFilter.add(tier);
          } else {
            _tierFilter.remove(tier);
          }
        });
      },
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _statusChip(String label, String key, ThemeData theme) {
    final selected = _statusFilter.contains(key);
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (v) {
        setState(() {
          if (v) {
            _statusFilter.add(key);
          } else {
            _statusFilter.remove(key);
          }
        });
      },
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildListView(BuildContext context, List<EventNode> nodes) {
    final filtered = _filteredNodes(nodes);
    if (filtered.isEmpty) {
      return const Center(child: Text('没有匹配的记忆'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final node = filtered[index];
        return _buildMemoryCard(context, node);
      },
    );
  }

  Widget _buildMemoryCard(BuildContext context, EventNode node) {
    final locked = widget.provider.isMemoryLocked(node.id);
    return Card(
      color: node.invalidated
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      child: ExpansionTile(
        leading: Icon(
          node.invalidated
              ? Icons.block
              : node.needsReview
                  ? Icons.rate_review_outlined
                  : Icons.auto_stories_outlined,
        ),
        title: Text(
          node.event.description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            decoration:
                node.invalidated ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text([
          _tierLabel(node.tier),
          if (node.invalidated) '已作废',
          if (node.needsReview) '待复核',
          if (locked) '已锁定',
        ].join(' · ')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
        children: [
          if (node.event.keywords.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('关键词：${node.event.keywords.join('、')}'),
            ),
          if (node.event.theme.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('主题：${node.event.theme.join('、')}'),
            ),
          if (node.event.sourceDialog.trim().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: _sourceDialogWidget(context, node),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _navigateToDebug(context, node.id),
                icon: const Icon(Icons.hub_outlined, size: 18),
                label: const Text('追踪'),
              ),
              TextButton.icon(
                onPressed: () => _revise(node),
                icon: const Icon(Icons.edit_outlined),
                label: Text(node.invalidated ? '恢复并修改' : '修改'),
              ),
              IconButton(
                onPressed: () => _toggleLock(node),
                tooltip: locked ? '解除锁定' : '锁定记忆',
                icon: Icon(
                  locked ? Icons.lock : Icons.lock_open,
                ),
              ),
              if (!node.invalidated)
                TextButton.icon(
                  onPressed: locked ? null : () => _invalidate(node),
                  icon: const Icon(Icons.block),
                  label: const Text('作废'),
                ),
              IconButton(
                onPressed: locked ? null : () => _delete(node),
                tooltip: '删除记忆',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sourceDialogWidget(BuildContext context, EventNode node) {
    final source = node.event.sourceDialog;
    final lines = source.split('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          _showSourceDialog(context, source);
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    '来源对话',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.open_in_new,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                lines.length > 3
                    ? '${lines.take(3).join("\n")}\n...'
                    : source,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSourceDialog(BuildContext context, String source) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('来源对话'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              source,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineView(BuildContext context, List<EventNode> nodes) {
    final filtered = _filteredNodes(nodes);
    if (filtered.isEmpty) {
      return const Center(child: Text('没有匹配的记忆'));
    }
    final sorted = List<EventNode>.from(filtered)
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    final grouped = <String, List<EventNode>>{};
    for (final node in sorted) {
      final date = DateTime.fromMillisecondsSinceEpoch(node.createdAtMs);
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(node);
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entry.value.length} 条',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ...entry.value.map((node) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _tierColor(node.tier),
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 30,
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant,
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () => _navigateToDebug(context, node.id),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: node.invalidated
                                  ? Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  node.event.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    decoration: node.invalidated
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      _tierLabel(node.tier),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    if (node.invalidated) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        '已作废',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                    ],
                                    if (node.needsReview) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        '待复核',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .tertiary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildRecallDebugView(BuildContext context, List<EventNode> nodes) {
    final filtered = _filteredNodes(nodes);
    if (filtered.isEmpty) {
      return const Center(child: Text('没有匹配的记忆'));
    }
    final theme = Theme.of(context);
    final graph = widget.provider.selectedContact?.eventGraph;
    final edges = graph?.edges ?? const <String, EventEdge>{};

    final nodeEdgeCount = <String, int>{};
    for (final edge in edges.values) {
      nodeEdgeCount[edge.fromNodeId] =
          (nodeEdgeCount[edge.fromNodeId] ?? 0) + 1;
      nodeEdgeCount[edge.toNodeId] =
          (nodeEdgeCount[edge.toNodeId] ?? 0) + 1;
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '选择节点查看详细召回调试信息',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ...filtered.map((node) {
          final edgeCount = nodeEdgeCount[node.id] ?? 0;
          final locked = widget.provider.isMemoryLocked(node.id);
          return Card(
            color: node.invalidated
                ? theme.colorScheme.surfaceContainerHighest
                : null,
            child: ListTile(
              leading: Icon(
                node.invalidated
                    ? Icons.block
                    : node.needsReview
                        ? Icons.rate_review_outlined
                        : Icons.auto_stories_outlined,
                size: 20,
              ),
              title: Text(
                node.event.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  decoration: node.invalidated
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              subtitle: Text(
                '${_tierLabel(node.tier)}${edgeCount > 0 ? ' · $edgeCount 条边' : ''}${node.invalidated ? ' · 已作废' : ''}${locked ? ' · 已锁定' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _navigateToDebug(context, node.id),
            ),
          );
        }),
      ],
    );
  }

  void _navigateToDebug(BuildContext context, String nodeId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemoryRecallDebuggerPage(
          provider: widget.provider,
          eventNodeId: nodeId,
        ),
      ),
    );
  }

  String _tierLabel(EventTier tier) => switch (tier) {
        EventTier.shortTerm => '原始事件',
        EventTier.longTerm => '阶段概括',
        EventTier.ultraLongTerm => '长期档案',
      };

  Color _tierColor(EventTier tier) => switch (tier) {
        EventTier.shortTerm => Colors.orange,
        EventTier.longTerm => Colors.blue,
        EventTier.ultraLongTerm => Colors.purple,
      };

  Future<EventMemory?> _editEvent(EventNode node) async {
    final description = TextEditingController(text: node.event.description);
    final keywords = TextEditingController(text: node.event.keywords.join('，'));
    final themes = TextEditingController(text: node.event.theme.join('，'));
    final result = await showDialog<EventMemory>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(node.invalidated ? '恢复并修改记忆' : '修改记忆'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: description,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: '事件内容',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keywords,
                  decoration: const InputDecoration(
                    labelText: '关键词（逗号分隔）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: themes,
                  decoration: const InputDecoration(
                    labelText: '主题（逗号分隔）',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = description.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(
                context,
                EventMemory(
                  description: text,
                  keywords: _splitTags(keywords.text),
                  theme: _splitTags(themes.text),
                  sourceDialog: node.event.sourceDialog,
                ),
              );
            },
            child: const Text('继续'),
          ),
        ],
      ),
    );
    description.dispose();
    keywords.dispose();
    themes.dispose();
    return result;
  }

  List<String> _splitTags(String raw) => raw
      .split(RegExp(r'[,，、]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);

  Future<bool> _confirmImpact(
    EventNode node,
    MemoryRevisionImpact? impact, {
    required bool invalidate,
  }) async {
    if (impact == null) return false;
    final details = <String>[
      if (impact.edgeCount > 0) '${impact.edgeCount} 条事件关系将暂时失效',
      if (impact.belongingKeys.isNotEmpty)
        '${impact.belongingKeys.length} 项物品关联将待重建',
      if (impact.settingKeys.isNotEmpty)
        '${impact.settingKeys.length} 项设定关联将待重建',
      if (impact.affectedSummaryNodeIds.isNotEmpty)
        '${impact.affectedSummaryNodeIds.length} 条上层概括会标记为待复核',
    ];
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(invalidate ? '确认作废记忆' : '确认修改记忆'),
            content: Text(
              details.isEmpty
                  ? '这条记忆没有检测到关联数据。操作完成后仍可撤销一次。'
                  : '${details.join('；')}。\n\n操作完成后仍可撤销一次；产生新对话后将不能撤销。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(invalidate ? '确认作废' : '确认修改'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _revise(EventNode node) async {
    final revised = await _editEvent(node);
    if (revised == null || !mounted) return;
    final confirmed = await _confirmImpact(
      node,
      widget.provider.previewMemoryRevision(node.id),
      invalidate: false,
    );
    if (!confirmed) return;
    final ok = await widget.provider.reviseMemory(node.id, revised);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '记忆已修改' : '修改失败')),
    );
  }

  Future<void> _invalidate(EventNode node) async {
    final confirmed = await _confirmImpact(
      node,
      widget.provider.previewMemoryRevision(node.id),
      invalidate: true,
    );
    if (!confirmed) return;
    final ok = await widget.provider.invalidateMemory(node.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '记忆已作废，不再参与召回' : '作废失败')),
    );
  }

  Future<void> _toggleLock(EventNode node) async {
    final locked = widget.provider.isMemoryLocked(node.id);
    await widget.provider.setMemoryLocked(node.id, !locked);
  }

  Future<void> _delete(EventNode node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记忆'),
        content: const Text('删除后会同步清理相关关系边，且不能撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.provider.deleteMemory(node.id);
  }

  Future<void> _undo() async {
    final ok = await widget.provider.undoLastMemoryRevision();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已撤销最近一次记忆修改' : '现在无法撤销')),
    );
  }
}