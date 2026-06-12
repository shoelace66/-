import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/constants/app_strings.dart';

void main() {
  group('AppStrings SharedPreferences keys', () {
    test('所有 key 非空且互不重复', () {
      final keys = [
        AppStrings.chatContactsKey,
        AppStrings.chatMessagesKey,
        AppStrings.chatSettingsKey,
        AppStrings.appSettingsKey,
        AppStrings.opencodeConnectionKey,
      ];

      expect(keys.every((k) => k.isNotEmpty), isTrue);
      expect(keys.toSet().length, keys.length, reason: 'keys must be unique');
    });

    test('key 以 _v1 结尾便于未来 schema 升级', () {
      expect(AppStrings.chatContactsKey, endsWith('_v1'));
      expect(AppStrings.chatMessagesKey, endsWith('_v1'));
      expect(AppStrings.chatSettingsKey, endsWith('_v1'));
      expect(AppStrings.appSettingsKey, endsWith('_v1'));
      expect(AppStrings.opencodeConnectionKey, endsWith('_v1'));
    });
  });

  group('AppStrings UI 文案', () {
    test('appTitle 非空', () {
      expect(AppStrings.appTitle.isNotEmpty, isTrue);
    });

    test('错误提示文案包含中文', () {
      expect(AppStrings.networkError, contains('重试'));
      expect(AppStrings.noContact, isNotEmpty);
    });
  });
}
