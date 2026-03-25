import 'package:flutter/material.dart';

import '../../data/models/contact.dart';

class ContactSidebar extends StatelessWidget {
  const ContactSidebar({
    super.key,
    required this.contacts,
    required this.selectedContactId,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    this.showDeleteInList = true,
    this.showDeleteInFooter = false,
  });

  final List<Contact> contacts;
  final String? selectedContactId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<String> onDelete;
  final bool showDeleteInList;
  final bool showDeleteInFooter;

  Future<void> _confirmDelete(BuildContext context, Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${contact.name}" 吗？此操作不可恢复，所有聊天记录也将被删除。'),
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
    if (confirmed == true) {
      onDelete(contact.id);
    }
  }

  Contact? get _selectedContact {
    if (selectedContactId == null) return null;
    try {
      return contacts.firstWhere((c) => c.id == selectedContactId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedContact;
    final theme = Theme.of(context);
    // 获取状态栏高度，确保与主页面AppBar对齐
    final statusBarHeight = MediaQuery.of(context).padding.top;
    // AppBar默认高度为56，确保标题栏高度一致
    const appBarHeight = 56.0;

    return Container(
      width: 260,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.surface.withValues(alpha: 1.0),
            theme.colorScheme.surface.withValues(alpha: 0.95),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // 顶部标题栏 - 高度与主页面AppBar对齐
          Container(
            height: appBarHeight + statusBarHeight,
            padding: EdgeInsets.fromLTRB(20, statusBarHeight + 16, 20, 12),
            alignment: Alignment.centerLeft,
            child: Text(
              '对象列表',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const Divider(height: 1),
          // 联系人列表
          Expanded(
            child: contacts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_add_alt_1_outlined,
                          size: 64,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '暂无对象',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '点击下方按钮创建',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.4),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: contacts.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final c = contacts[index];
                      final isSelected = c.id == selectedContactId;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primary.withValues(alpha: 0.1)
                              : theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.3),
                                  width: 2,
                                )
                              : Border.all(
                                  color: theme.colorScheme.outline
                                      .withValues(alpha: 0.1),
                                  width: 1,
                                ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: c.avatar.isNotEmpty
                                  ? Text(
                                      c.avatar,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : Icon(
                                      Icons.person_outline,
                                      size: 20,
                                      color: theme.colorScheme.primary,
                                    ),
                            ),
                          ),
                          title: Text(
                            c.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          subtitle: c.status.isNotEmpty
                              ? Text(
                                  c.status.first,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                )
                              : null,
                          onTap: () => onSelect(c.id),
                          trailing: showDeleteInList
                              ? IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: theme.colorScheme.error
                                        .withValues(alpha: 0.7),
                                  ),
                                  onPressed: () => _confirmDelete(context, c),
                                  tooltip: '删除',
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
          // 底部操作按钮区域
          const Divider(height: 1),
          // 创建对象按钮（移到最底部）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('创建对象'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          // 删除按钮（在创建按钮上方）
          if (showDeleteInFooter) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: selected != null
                    ? OutlinedButton.icon(
                        onPressed: () => _confirmDelete(context, selected),
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                          size: 18,
                        ),
                        label: Text(
                          '删除 ${selected.name}',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(
                            color:
                                theme.colorScheme.error.withValues(alpha: 0.3),
                          ),
                        ),
                      )
                    : OutlinedButton(
                        onPressed: null,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('未选择对象'),
                      ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
