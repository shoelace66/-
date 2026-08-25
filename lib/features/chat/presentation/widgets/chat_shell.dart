import 'package:flutter/material.dart';

class ChatShell extends StatelessWidget {
  const ChatShell({
    super.key,
    required this.compact,
    required this.title,
    required this.actions,
    required this.contactPanel,
    required this.chatArea,
  });

  final bool compact;
  final String title;
  final Widget actions;
  final Widget contactPanel;
  final Widget chatArea;

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: Text(title, overflow: TextOverflow.ellipsis),
      centerTitle: compact,
      leading: compact
          ? Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
                tooltip: '打开对象列表',
              ),
            )
          : null,
      actions: [actions],
      elevation: compact ? 2 : 0,
      scrolledUnderElevation: 4,
    );
    if (compact) {
      return Scaffold(
        appBar: appBar,
        drawer: Drawer(width: 280, child: contactPanel),
        body: chatArea,
        resizeToAvoidBottomInset: true,
      );
    }
    return Scaffold(
      appBar: appBar,
      body: Row(
        children: [
          contactPanel,
          const VerticalDivider(width: 1),
          Expanded(child: chatArea),
        ],
      ),
    );
  }
}
