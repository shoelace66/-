import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_chat_demo/bootstrap.dart';
import 'package:flutter_chat_demo/features/chat/application/chat_view_state.dart';
import 'package:flutter_chat_demo/features/chat/domain/providers/chat_provider.dart';

void main() {
  testWidgets('启动失败展示具体模块并允许重试', (tester) async {
    var attempts = 0;
    final provider = ChatProvider();

    Future<AppBootstrapResult> fakeBootstrap() async {
      attempts++;
      if (attempts == 1) {
        throw const ChatInitializationFailure('本地数据库', '文件损坏');
      }
      return AppBootstrapResult(chatProvider: provider);
    }

    await tester.pumpWidget(BootstrapApp(bootstrapper: fakeBootstrap));
    await tester.pumpAndSettle();
    expect(find.text('本地数据库初始化失败'), findsOneWidget);
    expect(find.text('文件损坏'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bootstrap-retry')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Chat Demo'), findsOneWidget);
  });
}
