import 'package:flutter_chat_demo/features/chat/domain/services/character_behavior_policy.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/story_control_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('角色策略同时约束认知边界、渐进反应和重大后果', () {
    final rules = const CharacterBehaviorPolicy().promptRules().join('\n');

    expect(rules, contains('不能使用叙事者或系统掌握的全局信息'));
    expect(rules, contains('犹豫或追问、协商、隐瞒或转移、拒绝、离开'));
    expect(rules, contains('重大且难以逆转的后果'));
  });

  test('故事策略保留用户的主线推进权', () {
    final rules = const StoryControlPolicy().promptRules().join('\n');

    expect(rules, contains('用户负责推动主线'));
    expect(rules, contains('不得擅自引入主要角色'));
    expect(rules, contains('不得让重要角色无依据死亡'));
  });
}
