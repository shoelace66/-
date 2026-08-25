import 'package:flutter/material.dart';

import '../../domain/providers/chat_provider.dart';
import '../../domain/repositories/conversation_timeline.dart';

class ConversationTimelinePage extends StatefulWidget {
  const ConversationTimelinePage({super.key, required this.provider});

  final ChatProvider provider;

  @override
  State<ConversationTimelinePage> createState() =>
      _ConversationTimelinePageState();
}

class _ConversationTimelinePageState extends State<ConversationTimelinePage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.provider.addListener(_onProviderChanged);
    widget.provider.refreshConversationTimeline();
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.provider.error ?? '操作失败')),
      );
    }
  }

  Future<String?> _askName(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '分支名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.trim().isEmpty == true ? null : result?.trim();
  }

  Future<void> _createBranch(ConversationCheckpoint checkpoint) async {
    final name = await _askName('从此检查点创建分支');
    if (name == null) return;
    await _run(() => widget.provider.createBranchFromCheckpoint(
          checkpoint.id,
          name: name,
        ));
  }

  Future<void> _renameBranch(ConversationBranch branch) async {
    final name = await _askName('重命名分支', initial: branch.name);
    if (name == null) return;
    await _run(
      () => widget.provider.renameConversationBranch(branch.id, name),
    );
  }

  Future<void> _deleteBranch(ConversationBranch branch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分支？'),
        content: Text('“${branch.name}”及其检查点将被删除。主分支和当前分支不能删除。'),
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
    if (confirmed == true) {
      await _run(() => widget.provider.deleteConversationBranch(branch.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = widget.provider.conversationBranches;
    final checkpoints = widget.provider.conversationCheckpoints;
    return Scaffold(
      appBar: AppBar(title: const Text('剧情分支与检查点')),
      body: RefreshIndicator(
        onRefresh: widget.provider.refreshConversationTimeline,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('分支', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (branches.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('尚未建立分支。完成一轮对话后会自动生成检查点。'),
                ),
              )
            else
              ...branches.map(
                (branch) => Card(
                  child: ListTile(
                    contentPadding: EdgeInsets.only(
                      left: 16.0 + _branchDepth(branch, branches) * 24,
                      right: 8,
                    ),
                    leading: Icon(
                      branch.isActive
                          ? Icons.account_tree
                          : Icons.call_split_outlined,
                    ),
                    title: Text(branch.name),
                    subtitle: Text(
                      '${branch.messageCount} 条消息'
                      '${branch.isMain ? ' · 主分支' : ''}'
                      '${branch.isActive ? ' · 当前' : ''}'
                      '${_parentLabel(branch, branches)}',
                    ),
                    onTap: branch.isActive || _busy
                        ? null
                        : () => _run(
                              () => widget.provider
                                  .switchConversationBranch(branch.id),
                            ),
                    trailing: PopupMenuButton<String>(
                      enabled: !_busy,
                      onSelected: (value) {
                        if (value == 'rename') _renameBranch(branch);
                        if (value == 'delete') _deleteBranch(branch);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('重命名'),
                        ),
                        if (!branch.isMain && !branch.isActive)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text('检查点', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (checkpoints.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('完成新对话轮次后，这里会出现可恢复的检查点。'),
                ),
              )
            else
              ...checkpoints.map(
                (checkpoint) => Card(
                  child: ListTile(
                    leading: IconButton(
                      tooltip: checkpoint.isKey ? '取消关键节点' : '标为关键节点',
                      icon: Icon(
                        checkpoint.isKey ? Icons.star : Icons.star_border,
                      ),
                      onPressed: _busy
                          ? null
                          : () => _run(
                                () => widget.provider.setCheckpointKey(
                                  checkpoint.id,
                                  !checkpoint.isKey,
                                ),
                              ),
                    ),
                    title: Text(
                      checkpoint.label.isEmpty
                          ? '完成于 ${_formatTime(checkpoint.createdAt)}'
                          : checkpoint.label,
                    ),
                    subtitle: Text('${checkpoint.messageCount} 条消息'),
                    trailing: FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => _createBranch(checkpoint),
                      icon: const Icon(Icons.call_split),
                      label: const Text('创建分支'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  int _branchDepth(
    ConversationBranch branch,
    List<ConversationBranch> branches,
  ) {
    final byId = <String, ConversationBranch>{
      for (final item in branches) item.id: item,
    };
    var depth = 0;
    var parentId = branch.parentBranchId;
    final visited = <String>{branch.id};
    while (parentId != null && visited.add(parentId) && depth < 6) {
      final parent = byId[parentId];
      if (parent == null) break;
      depth++;
      parentId = parent.parentBranchId;
    }
    return depth;
  }

  String _parentLabel(
    ConversationBranch branch,
    List<ConversationBranch> branches,
  ) {
    final parentId = branch.parentBranchId;
    if (parentId == null) return '';
    for (final parent in branches) {
      if (parent.id == parentId) return ' · 来自 ${parent.name}';
    }
    return '';
  }
}
