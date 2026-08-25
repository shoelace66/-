import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/services/image_cache_service.dart';
import '../../../chat/domain/providers/chat_provider.dart';

class ImageGalleryPage extends StatefulWidget {
  const ImageGalleryPage({super.key, required this.provider});

  final ChatProvider provider;

  @override
  State<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<ImageGalleryPage> {
  final _service = ImageCacheService.instance;
  String? _selectedContactId;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onCacheChanged);
    _selectedContactId = widget.provider.selectedContact?.id;
  }

  @override
  void dispose() {
    _service.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() => setState(() {});

  List<CachedImage> get _images {
    final all = _service.images;
    if (_selectedContactId == null) return all;
    return all.where((i) => i.contactId == _selectedContactId).toList();
  }

  String _contactName(String contactId) {
    for (final c in widget.provider.contacts) {
      if (c.id == contactId) return c.name;
    }
    return contactId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('图片画廊'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '筛选角色',
            icon: const Icon(Icons.filter_list),
            onSelected: (id) => setState(() {
              _selectedContactId = _selectedContactId == id ? null : id;
            }),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: '',
                child: Text('全部角色'),
              ),
              ...widget.provider.contacts.map((c) => PopupMenuItem(
                    value: c.id,
                    child: Row(
                      children: [
                        if (_selectedContactId == c.id)
                          const Icon(Icons.check, size: 18),
                        const SizedBox(width: 8),
                        Text(c.name),
                      ],
                    ),
                  )),
            ],
          ),
          IconButton(
            onPressed: _confirmClearAll,
            tooltip: '清除缓存',
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final images = _images;
    if (images.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('还没有缓存图片',
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('在聊天中长按消息选择"生成图片"',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }
    return Column(
      children: [
        _buildInfoBar(images),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: images.length,
            itemBuilder: (context, index) =>
                _buildGridTile(context, images[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBar(List<CachedImage> images) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Text('${images.length} 张',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const Spacer(),
          Text(
            _selectedContactId != null
                ? _contactName(_selectedContactId!)
                : '全部角色',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridTile(BuildContext context, CachedImage cached) {
    final file = File(cached.localPath);
    if (!file.existsSync()) {
      return const Card(
        child: Center(child: Icon(Icons.broken_image_outlined)),
      );
    }
    final contactName = _contactName(cached.contactId);
    return GestureDetector(
      onTap: () => _openPreview(context, cached),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(file, fit: BoxFit.cover),
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  contactName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPreview(BuildContext context, CachedImage cached) {
    final file = File(cached.localPath);
    if (!file.existsSync()) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ImagePreviewPage(
          image: cached,
          contactName: _contactName(cached.contactId),
          onDelete: () {
            _service.deleteImage(cached.localPath);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除图片缓存'),
        content: Text('将删除 ${_service.images.length} 张缓存图片，此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.clearAll();
    }
  }
}

class _ImagePreviewPage extends StatelessWidget {
  const _ImagePreviewPage({
    required this.image,
    required this.contactName,
    required this.onDelete,
  });

  final CachedImage image;
  final String contactName;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = File(image.localPath);
    return Scaffold(
      appBar: AppBar(
        title: Text(contactName),
        actions: [
          IconButton(
            onPressed: onDelete,
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: InteractiveViewer(
                child: Image.file(file, fit: BoxFit.contain),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Prompt',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
                const SizedBox(height: 4),
                Text(image.prompt, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Text(
                  '缓存时间: ${DateTime.fromMillisecondsSinceEpoch(image.cachedAtMs).toLocal().toString().substring(0, 19)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '文件大小: ${_formatSize(file.lengthSync())}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}