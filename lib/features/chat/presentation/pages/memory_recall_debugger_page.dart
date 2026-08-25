import 'package:flutter/material.dart';

import '../../domain/providers/chat_provider.dart';

class MemoryRecallDebuggerPage extends StatefulWidget {
  const MemoryRecallDebuggerPage({
    super.key,
    required this.provider,
    required this.eventNodeId,
  });

  final ChatProvider provider;
  final String eventNodeId;

  @override
  State<MemoryRecallDebuggerPage> createState() =>
      _MemoryRecallDebuggerPageState();
}

class _MemoryRecallDebuggerPageState extends State<MemoryRecallDebuggerPage> {
  Map<String, dynamic> get _info =>
      widget.provider.memoryRecallDebugInfo(widget.eventNodeId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('记忆召回调试')),
      body: AnimatedBuilder(
        animation: widget.provider,
        builder: (context, _) {
          final info = _info;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(context, info, theme),
              const SizedBox(height: 16),
              _buildNodeInfo(context, info, theme),
              const SizedBox(height: 16),
              _buildKeywordsAndTheme(context, info, theme),
              const SizedBox(height: 16),
              _buildEdgeRelations(context, info, theme),
              const SizedBox(height: 16),
              _buildNeighbors(context, info, theme),
              const SizedBox(height: 16),
              _buildRelationQueues(context, info, 'belongingQueues', '物品关联', theme),
              const SizedBox(height: 16),
              _buildRelationQueues(
                  context, info, 'settingQueues', '设定关联', theme),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, Map<String, dynamic> info, ThemeData theme) {
    final tier = info['tier'] as String? ?? '';
    final tierLabel = switch (tier) {
      'shortTerm' => '短期',
      'longTerm' => '长期',
      'ultraLongTerm' => '超长期',
      _ => tier,
    };
    final statuses = <String>[];
    if (info['summarized'] == true) statuses.add('已概括');
    if (info['invalidated'] == true) statuses.add('已作废');
    if (info['needsReview'] == true) statuses.add('待复核');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(tierLabel, style: const TextStyle(fontSize: 12)),
                  backgroundColor: _tierColor(tier, theme),
                ),
                const SizedBox(width: 8),
                ...statuses.map((s) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Chip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        backgroundColor: theme.colorScheme.errorContainer,
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              info['description'] as String? ?? '',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${info['nodeId']}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            if (info['createdAt'] is String)
              Text(
                '创建时间: ${info['createdAt']}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeInfo(
      BuildContext context, Map<String, dynamic> info, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('节点信息', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _infoRow('事件边数', '${info['edgeCount'] ?? 0}', theme),
            _infoRow('是否概括', info['summarized'] == true ? '是' : '否', theme),
            _infoRow('是否作废', info['invalidated'] == true ? '是' : '否', theme),
            _infoRow('是否待复核',
                info['needsReview'] == true ? '是' : '否', theme),
          ],
        ),
      ),
    );
  }

  Widget _buildKeywordsAndTheme(
      BuildContext context, Map<String, dynamic> info, ThemeData theme) {
    final keywords = (info['keywords'] as List?)?.cast<String>() ?? [];
    final themes = (info['theme'] as List?)?.cast<String>() ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('关键词与主题', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (keywords.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: keywords
                    .map((k) => Chip(
                          label: Text(k, style: const TextStyle(fontSize: 11)),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              )
            else
              Text('无关键词', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            if (themes.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: themes
                    .map((t) => Chip(
                          label: Text(t, style: const TextStyle(fontSize: 11)),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: theme.colorScheme.secondaryContainer,
                        ))
                    .toList(),
              )
            else
              Text('无主题', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildEdgeRelations(
      BuildContext context, Map<String, dynamic> info, ThemeData theme) {
    final edges = (info['edges'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('事件关系边', style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Text('${edges.length} 条',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              ],
            ),
            if (edges.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('没有关联边', style: theme.textTheme.bodySmall),
              )
            else
              ...edges.map((e) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      e['direction'] as String? ?? '',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildNeighbors(
      BuildContext context, Map<String, dynamic> info, ThemeData theme) {
    final neighbors =
        (info['neighbors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('邻居节点', style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Text('${neighbors.length} 个',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              ],
            ),
            if (neighbors.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('没有邻居节点', style: theme.textTheme.bodySmall),
              )
            else
              ...neighbors.map((n) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _neighborTile(n, theme),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _neighborTile(Map<String, dynamic> n, ThemeData theme) {
    return InkWell(
      onTap: () {
        final id = n['id'] as String?;
        if (id != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MemoryRecallDebuggerPage(
                provider: widget.provider,
                eventNodeId: id,
              ),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  n['tier'] as String? ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _tierTextColor(n['tier'] as String? ?? '', theme),
                    backgroundColor:
                        _tierColor(n['tier'] as String? ?? '', theme),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    n['description'] as String? ?? '',
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelationQueues(BuildContext context, Map<String, dynamic> info,
      String key, String label, ThemeData theme) {
    final queues = info[key] as Map<String, dynamic>? ?? const {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Text('${queues.length} 项',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              ],
            ),
            if (queues.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('无关联', style: theme.textTheme.bodySmall),
              )
            else
              ...queues.entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${entry.key}: ${(entry.value as List).length} 条事件',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Color? _tierColor(String tier, ThemeData theme) => switch (tier) {
        'shortTerm' => theme.colorScheme.tertiaryContainer,
        'longTerm' => theme.colorScheme.secondaryContainer,
        'ultraLongTerm' => theme.colorScheme.primaryContainer,
        _ => theme.colorScheme.surfaceContainerHighest,
      };

  Color? _tierTextColor(String tier, ThemeData theme) => switch (tier) {
        'shortTerm' => theme.colorScheme.onTertiaryContainer,
        'longTerm' => theme.colorScheme.onSecondaryContainer,
        'ultraLongTerm' => theme.colorScheme.onPrimaryContainer,
        _ => theme.colorScheme.onSurface,
      };

  Widget _infoRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ),
          Text(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}