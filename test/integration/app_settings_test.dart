import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_chat_demo/core/presentation/pages/app_settings_page.dart';
import 'package:flutter_chat_demo/core/data/models/app_settings.dart';

void main() {
  group('AppSettingsPage', () {
    testWidgets('页面能正常实例化', (WidgetTester tester) async {
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AppSettingsPage(
            initial: const AppSettings(),
            onSave: (_) async => saved = true,
          ),
        ),
      );

      expect(find.text('应用设置'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(saved, isTrue);
    });
  });
}
