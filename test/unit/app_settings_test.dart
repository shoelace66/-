import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/data/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('默认构造包含 20 个参数', () {
      const settings = AppSettings();

      expect(settings.maxShortTermEvents, 10);
      expect(settings.maxLongTermEvents, 1);
      expect(settings.maxUltraTermEvents, 2);
      expect(settings.maxRelatedEvents, 5);
      expect(settings.maxShortQueue, 2000);
      expect(settings.maxLongQueue, 500);
      expect(settings.maxUltraQueue, 200);
      expect(settings.maxPromptListItems, 5);
      expect(settings.maxPromptLineLength, 200);
      expect(settings.summaryThreshold, 10);
      expect(settings.ultraSummaryThreshold, 5);
      expect(settings.searchDepth, 2);
      expect(settings.lruKeywordMatchWeight, 100);
      expect(settings.lruEventEventWeight, 50);
      expect(settings.lruEventBelongingKeywordWeight, 30);
      expect(settings.lruEventBelongingNormalWeight, 10);
      expect(settings.lruEventSettingKeywordWeight, 30);
      expect(settings.lruEventSettingNormalWeight, 10);
      expect(settings.vectorSimilarityWeight, 80);
      expect(settings.keywordLibrarySize, 200);
    });

    test('fromJson 反序列化正确', () {
      final json = {
        'maxShortTermEvents': 15,
        'summaryThreshold': 8,
        'searchDepth': 3,
        'keywordLibrarySize': 300,
      };

      final settings = AppSettings.fromJson(json);
      expect(settings.maxShortTermEvents, 15);
      expect(settings.summaryThreshold, 8);
      expect(settings.searchDepth, 3);
      expect(settings.keywordLibrarySize, 300);
      // 未提供的字段用默认值
      expect(settings.maxLongTermEvents, 1);
    });

    test('fromJson 缺失字段用默认值', () {
      final settings = AppSettings.fromJson({});
      expect(settings.maxShortTermEvents, 10);
      expect(settings.summaryThreshold, 10);
    });

    test('toJson 序列化后可反序列化', () {
      const original = AppSettings(
        maxShortTermEvents: 15,
        summaryThreshold: 8,
        searchDepth: 3,
      );

      final json = original.toJson();
      final restored = AppSettings.fromJson(json);

      expect(restored.maxShortTermEvents, original.maxShortTermEvents);
      expect(restored.summaryThreshold, original.summaryThreshold);
      expect(restored.searchDepth, original.searchDepth);
    });

    test('copyWith 只修改指定字段', () {
      const original = AppSettings();
      final modified = original.copyWith(
        maxShortTermEvents: 20,
        searchDepth: 5,
      );

      expect(modified.maxShortTermEvents, 20);
      expect(modified.searchDepth, 5);
      // 其他字段不变
      expect(modified.summaryThreshold, original.summaryThreshold);
      expect(modified.maxLongQueue, original.maxLongQueue);
    });
  });
}
