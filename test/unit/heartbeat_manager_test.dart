import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/heartbeat_manager.dart';

void main() {
  group('HeartbeatManager', () {
    late HeartbeatManager manager;
    late List<ConnectionStatus> statuses;

    setUp(() {
      manager = HeartbeatManager();
      statuses = [];
    });

    test('start 立即回调 connected', () {
      manager.start((s) => statuses.add(s));
      expect(statuses, [ConnectionStatus.connected]);
    });

    test('status 初始为 connected', () {
      expect(manager.status, ConnectionStatus.connected);
    });

    test('markReconnecting 更新状态并回调', () {
      manager.start((s) => statuses.add(s));
      manager.markReconnecting();

      expect(manager.status, ConnectionStatus.reconnecting);
      expect(statuses,
          [ConnectionStatus.connected, ConnectionStatus.reconnecting]);
    });

    test('stop 后不再回调', () {
      manager.start((s) => statuses.add(s));
      manager.stop();
      manager.markReconnecting();

      expect(statuses.length, 1);
    });

    test('多次 start 重新绑定回调', () {
      final statuses2 = <ConnectionStatus>[];
      manager.start((s) => statuses.add(s));
      manager.start((s) => statuses2.add(s));
      manager.markReconnecting();

      // 第二次 start 会立即回调 connected，然后 markReconnecting 回调 reconnecting
      expect(statuses2,
          [ConnectionStatus.connected, ConnectionStatus.reconnecting]);
    });
  });
}
