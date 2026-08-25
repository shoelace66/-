// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_chat_demo/features/chat/domain/providers/chat_provider.dart';
import 'package:flutter_chat_demo/features/chat/presentation/pages/chat_page.dart';

void main() {
  testWidgets('Chat app smoke test', (WidgetTester tester) async {
    final provider = ChatProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ChatPage(provider: provider)),
    );

    // Verify that our app title is present
    expect(find.text('Chat Demo'), findsOneWidget);
  });
}
