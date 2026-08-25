import 'package:flutter/material.dart';

import '../../data/models/message.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/repositories/chat_persistence.dart';

class ConversationSearchPage extends StatefulWidget {
  const ConversationSearchPage({super.key, required this.provider});

  final ChatProvider provider;

  @override
  State<ConversationSearchPage> createState() => _ConversationSearchPageState();
}

class _ConversationSearchPageState extends State<ConversationSearchPage> {
  final TextEditingController _controller = TextEditingController();
  List<MessageSearchHit> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.provider.searchCurrentConversation(query);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _showContext(MessageSearchHit hit) async {
    final messages = await widget.provider.readSearchContext(hit);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('上下文预览'),
        content: SizedBox(
          width: 520,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: messages.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (_, index) {
              final message = messages[index];
              return ListTile(
                selected: message.id == hit.message.id,
                title: Text(
                  message.role == MessageRole.user ? '我' : 'AI',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: SelectableText(message.content),
              );
            },
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

  @override
  Widget build(BuildContext context) {
    final usage = widget.provider.conversationUsage;
    final hasPricing =
        widget.provider.providerSettings.llm.inputPricePerMillion > 0 ||
            widget.provider.providerSettings.llm.outputPricePerMillion > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('搜索当前会话')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              controller: _controller,
              hintText: '输入关键词',
              autoFocus: true,
              onSubmitted: (_) => _search(),
              trailing: [
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    onPressed: _search,
                    tooltip: '搜索',
                    icon: const Icon(Icons.search),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.data_usage_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '当前已加载窗口估算：${usage.totalTokens} tokens '
                    '（输入 ${usage.inputTokens} / 输出 ${usage.outputTokens}）'
                    '${hasPricing ? ' · 约 ${usage.estimatedCost.toStringAsFixed(4)}' : ' · 费用单价未配置'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('输入关键词搜索完整会话历史'))
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final hit = _results[index];
                      return ListTile(
                        leading: Icon(
                          hit.message.role == MessageRole.user
                              ? Icons.person_outline
                              : Icons.auto_awesome_outlined,
                        ),
                        title: Text(
                          hit.message.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('消息位置 ${hit.sequence + 1}'),
                        onTap: () => _showContext(hit),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
