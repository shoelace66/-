import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_chat_demo/core/presentation/pages/app_settings_page.dart';

void main() {
  group('AppSettingsPage', () {
    testWidgets('页面能正常实例化', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AppSettingsPage()),
      );

      // 页面应显示加载指示器（SharedPreferences 在测试中不可用）
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
