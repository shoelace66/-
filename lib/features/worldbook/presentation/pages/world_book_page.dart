import 'package:flutter/material.dart';

import '../../domain/entities/world_book.dart';
import '../../domain/services/world_book_service.dart';
import '../../../chat/data/models/contact.dart';
import '../../../chat/domain/providers/chat_provider.dart';

class WorldBookPage extends StatefulWidget {
  const WorldBookPage({super.key, required this.provider});

  final ChatProvider provider;

  @override
  State<WorldBookPage> createState() => _WorldBookPageState();
}

class _WorldBookPageState extends State<WorldBookPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _service = const WorldBookService();
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  WorldBook get _book =>
      widget.provider.selectedContact?.worldBook ?? const WorldBook();

  void _saveBook(WorldBook book) {
    widget.provider.updateWorldBook(book);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.provider,
      builder: (context, _) {
        final contact = widget.provider.selectedContact;
        if (contact == null) {
          return const Scaffold(
            body: Center(child: Text('请先选择一个角色')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('世界书'),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: const [
                Tab(text: '地点'),
                Tab(text: '组织'),
                Tab(text: '规则'),
                Tab(text: '时间线'),
              ],
            ),
          ),
          body: Column(
            children: [
              _buildSearchBar(context),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLocationsTab(context, contact),
                    _buildOrganizationsTab(context, contact),
                    _buildRulesTab(context, contact),
                    _buildTimelineTab(context, contact),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '搜索世界书条目...',
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
    );
  }

  Widget _buildLocationsTab(BuildContext context, Contact contact) {
    final locations = _searchQuery.isNotEmpty
        ? _service.searchLocations(_book, _searchQuery)
        : _book.locations;
    return _EntityList(
      items: locations,
      title: (l) => l.name,
      subtitle: (l) => l.description.isNotEmpty ? l.description : l.type,
      tags: (l) => l.tags,
      isEmpty: '还没有地点，点击右下角添加',
      onAdd: () => _editLocation(context, null),
      onEdit: (l) => _editLocation(context, l),
      onDelete: (l) => _deleteLocation(l),
    );
  }

  Widget _buildOrganizationsTab(BuildContext context, Contact contact) {
    final orgs = _searchQuery.isNotEmpty
        ? _service.searchOrganizations(_book, _searchQuery)
        : _book.organizations;
    return _EntityList(
      items: orgs,
      title: (o) => o.name,
      subtitle: (o) => o.description.isNotEmpty ? o.description : '${o.memberIds.length} 名成员',
      tags: (o) => o.tags,
      isEmpty: '还没有组织，点击右下角添加',
      onAdd: () => _editOrganization(context, null),
      onEdit: (o) => _editOrganization(context, o),
      onDelete: (o) => _deleteOrganization(o),
    );
  }

  Widget _buildRulesTab(BuildContext context, Contact contact) {
    final rules = _searchQuery.isNotEmpty
        ? _service.searchRules(_book, _searchQuery)
        : _book.rules;
    return _EntityList(
      items: rules,
      title: (r) => r.name,
      subtitle: (r) => r.description.isNotEmpty ? r.description : '[${r.type}] ${r.scope}',
      tags: (r) => [r.type, r.scope].where((s) => s.isNotEmpty).toList(),
      isEmpty: '还没有世界规则，点击右下角添加',
      onAdd: () => _editRule(context, null),
      onEdit: (r) => _editRule(context, r),
      onDelete: (r) => _deleteRule(r),
    );
  }

  Widget _buildTimelineTab(BuildContext context, Contact contact) {
    final events = _searchQuery.isNotEmpty
        ? _service.searchTimelineEvents(_book, _searchQuery)
        : _service.sortedTimelineEvents(_book);
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('还没有时间线事件，点击右下角添加',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _editTimelineEvent(context, null),
              icon: const Icon(Icons.add),
              label: const Text('添加事件'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ...events.map((event) => _buildTimelineCard(context, event)),
      ],
    );
  }

  Widget _buildTimelineCard(BuildContext context, WorldTimelineEvent event) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _editTimelineEvent(context, event),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  event.year > 0 ? '${event.year}' : '??',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title,
                        style: theme.textTheme.titleSmall),
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(event.description,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    if (event.tags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: event.tags
                            .map((t) => Chip(
                                  label: Text(t,
                                      style: const TextStyle(fontSize: 10)),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _deleteTimelineEvent(event),
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editLocation(BuildContext context, WorldLocation? existing) async {
    final result = await _showEntityDialog(
      context,
      title: existing == null ? '添加地点' : '编辑地点',
      name: existing?.name ?? '',
      description: existing?.description ?? '',
      type: existing?.type ?? '',
      tags: existing?.tags ?? [],
      showType: true,
    );
    if (result == null) return;
    final book = existing == null
        ? _service.addLocation(_book, WorldLocation(
            id: '',
            name: result.name,
            description: result.description,
            type: result.type,
            tags: result.tags,
          ))
        : _service.updateLocation(_book, existing.copyWith(
            name: result.name,
            description: result.description,
            type: result.type,
            tags: result.tags,
          ));
    _saveBook(book);
  }

  Future<void> _editOrganization(
      BuildContext context, WorldOrganization? existing) async {
    final result = await _showEntityDialog(
      context,
      title: existing == null ? '添加组织' : '编辑组织',
      name: existing?.name ?? '',
      description: existing?.description ?? '',
      type: '',
      tags: existing?.tags ?? [],
      showType: false,
    );
    if (result == null) return;
    final book = existing == null
        ? _service.addOrganization(_book, WorldOrganization(
            id: '',
            name: result.name,
            description: result.description,
            tags: result.tags,
          ))
        : _service.updateOrganization(_book, existing.copyWith(
            name: result.name,
            description: result.description,
            tags: result.tags,
          ));
    _saveBook(book);
  }

  Future<void> _editRule(BuildContext context, WorldRule? existing) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final descController =
        TextEditingController(text: existing?.description ?? '');
    String type = existing?.type ?? '物理';
    String scope = existing?.scope ?? '世界';
    final result = await showDialog<_RuleResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '添加规则' : '编辑规则'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '规则名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '规则描述',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: '类型',
                      border: OutlineInputBorder(),
                    ),
                    items: <String>['物理', '魔法', '社会', '超自然']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => type = v ?? '物理'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: scope,
                    decoration: const InputDecoration(
                      labelText: '范围',
                      border: OutlineInputBorder(),
                    ),
                    items: <String>['世界', '地区', '组织', '角色']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => scope = v ?? '世界'),
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
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(context, _RuleResult(name, descController.text.trim(), type, scope));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    descController.dispose();
    if (result == null) return;
    final book = existing == null
        ? _service.addRule(_book, WorldRule(
            id: '',
            name: result.name,
            description: result.description,
            type: result.type,
            scope: result.scope,
          ))
        : _service.updateRule(_book, existing.copyWith(
            name: result.name,
            description: result.description,
            type: result.type,
            scope: result.scope,
          ));
    _saveBook(book);
  }

  Future<void> _editTimelineEvent(
      BuildContext context, WorldTimelineEvent? existing) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descController =
        TextEditingController(text: existing?.description ?? '');
    final yearController =
        TextEditingController(text: (existing?.year ?? 0) > 0 ? '${existing!.year}' : '');
    final result = await showDialog<_TimelineResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '添加时间线事件' : '编辑时间线事件'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '事件标题',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: yearController,
                  decoration: const InputDecoration(
                    labelText: '年份',
                    border: OutlineInputBorder(),
                    hintText: '例如：1024',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '事件描述',
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
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              Navigator.pop(
                context,
                _TimelineResult(
                  title,
                  descController.text.trim(),
                  int.tryParse(yearController.text.trim()) ?? 0,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    titleController.dispose();
    descController.dispose();
    yearController.dispose();
    if (result == null) return;
    final book = existing == null
        ? _service.addTimelineEvent(_book, WorldTimelineEvent(
            id: '',
            title: result.title,
            description: result.description,
            year: result.year,
          ))
        : _service.updateTimelineEvent(_book, existing.copyWith(
            title: result.title,
            description: result.description,
            year: result.year,
          ));
    _saveBook(book);
  }

  void _deleteLocation(WorldLocation location) {
    _saveBook(_service.removeLocation(_book, location.id));
  }

  void _deleteOrganization(WorldOrganization organization) {
    _saveBook(_service.removeOrganization(_book, organization.id));
  }

  void _deleteRule(WorldRule rule) {
    _saveBook(_service.removeRule(_book, rule.id));
  }

  void _deleteTimelineEvent(WorldTimelineEvent event) {
    _saveBook(_service.removeTimelineEvent(_book, event.id));
  }
}

Future<_EntityDialogResult?> _showEntityDialog(
  BuildContext context, {
  required String title,
  required String name,
  required String description,
  required String type,
  required List<String> tags,
  required bool showType,
}) async {
  final nameController = TextEditingController(text: name);
  final descController = TextEditingController(text: description);
  final typeController = TextEditingController(text: type);
  final tagsController = TextEditingController(text: tags.join('，'));
  final result = await showDialog<_EntityDialogResult>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(),
                ),
              ),
              if (showType) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: typeController,
                  decoration: const InputDecoration(
                    labelText: '类型',
                    border: OutlineInputBorder(),
                    hintText: '城市/建筑/森林等',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '描述',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(
                  labelText: '标签（逗号分隔）',
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
            final name = nameController.text.trim();
            if (name.isEmpty) return;
            final tags = tagsController.text
                .split(RegExp(r'[,，、]'))
                .map((t) => t.trim())
                .where((t) => t.isNotEmpty)
                .toList(growable: false);
            Navigator.pop(
              context,
              _EntityDialogResult(
                name: name,
                description: descController.text.trim(),
                type: showType ? typeController.text.trim() : '',
                tags: tags,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  nameController.dispose();
  descController.dispose();
  typeController.dispose();
  tagsController.dispose();
  return result;
}

class _EntityDialogResult {
  const _EntityDialogResult({
    required this.name,
    required this.description,
    required this.type,
    required this.tags,
  });
  final String name;
  final String description;
  final String type;
  final List<String> tags;
}

class _RuleResult {
  const _RuleResult(this.name, this.description, this.type, this.scope);
  final String name;
  final String description;
  final String type;
  final String scope;
}

class _TimelineResult {
  const _TimelineResult(this.title, this.description, this.year);
  final String title;
  final String description;
  final int year;
}

class _EntityList<T> extends StatelessWidget {
  const _EntityList({
    required this.items,
    required this.title,
    required this.subtitle,
    this.tags,
    required this.isEmpty,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<T> items;
  final String Function(T) title;
  final String Function(T) subtitle;
  final List<String> Function(T)? tags;
  final String isEmpty;
  final VoidCallback onAdd;
  final ValueChanged<T> onEdit;
  final ValueChanged<T> onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isEmpty, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('添加'),
            ),
          ],
        ),
      );
    }
    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final itemTags = tags?.call(item);
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                title: Text(title(item), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subtitle(item),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (itemTags != null && itemTags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          children: itemTags
                              .map((t) => Chip(
                                    label: Text(t,
                                        style: const TextStyle(fontSize: 10)),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ))
                              .toList(),
                        ),
                      ),
                  ],
                ),
                trailing: IconButton(
                  onPressed: () => onDelete(item),
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
                onTap: () => onEdit(item),
              ),
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: onAdd,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}