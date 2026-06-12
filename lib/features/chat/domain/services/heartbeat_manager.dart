enum ConnectionStatus { connected, reconnecting }

class HeartbeatManager {
  ConnectionStatus _status = ConnectionStatus.connected;
  void Function(ConnectionStatus)? _onStatus;

  ConnectionStatus get status => _status;

  void start(void Function(ConnectionStatus status) onStatus) {
    _onStatus = onStatus;
    _status = ConnectionStatus.connected;
    onStatus(_status);
  }

  void markReconnecting() {
    _status = ConnectionStatus.reconnecting;
    _onStatus?.call(_status);
  }

  void stop() {
    _onStatus = null;
  }
}
