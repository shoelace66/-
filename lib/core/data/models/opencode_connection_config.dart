enum ConnectionType { http, ssh }

class OpencodeConnectionConfig {
  const OpencodeConnectionConfig({
    this.type = ConnectionType.http,
    this.host = '127.0.0.1',
    this.port = 4096,
    this.useHttps = false,
    this.basePath = '',
    this.sshUser = '',
    this.sshPassword = '',
    this.sshKeyPath = '',
    this.opencodePath = 'opencode',
    this.workingDirectory = '',
    this.timeoutSeconds = 300,
    this.username = 'opencode',
    this.password = '',
    this.agent = 'build',
    this.providerID = '',
    this.modelID = '',
    this.sessionId = '',
  });

  final ConnectionType type;
  final String host;
  final int port;
  final bool useHttps;
  final String basePath;
  final String sshUser;
  final String sshPassword;
  final String sshKeyPath;
  final String opencodePath;
  final String workingDirectory;
  final int timeoutSeconds;
  final String username;
  final String password;
  final String agent;
  final String providerID;
  final String modelID;
  final String sessionId;

  String get httpBase {
    final path = basePath.isEmpty
        ? ''
        : basePath.startsWith('/')
            ? basePath
            : '/$basePath';
    return '${useHttps ? "https" : "http"}://$host:$port$path';
  }

  factory OpencodeConnectionConfig.fromJson(Map<String, dynamic> json) {
    return OpencodeConnectionConfig(
      type: json['type'] == 'ssh' ? ConnectionType.ssh : ConnectionType.http,
      host: (json['host'] ?? '127.0.0.1').toString(),
      port: (json['port'] as num?)?.toInt() ?? 4096,
      useHttps: json['useHttps'] == true,
      basePath: (json['basePath'] ?? '').toString(),
      sshUser: (json['sshUser'] ?? '').toString(),
      sshPassword: (json['sshPassword'] ?? '').toString(),
      sshKeyPath: (json['sshKeyPath'] ?? '').toString(),
      opencodePath: (json['opencodePath'] ?? 'opencode').toString(),
      workingDirectory: (json['workingDirectory'] ?? '').toString(),
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 300,
      username: (json['username'] ?? 'opencode').toString(),
      password: (json['password'] ?? '').toString(),
      agent: (json['agent'] ?? 'build').toString(),
      providerID: (json['providerID'] ?? '').toString(),
      modelID: (json['modelID'] ?? '').toString(),
      sessionId: (json['sessionId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'host': host,
        'port': port,
        'useHttps': useHttps,
        'basePath': basePath,
        'sshUser': sshUser,
        'sshPassword': sshPassword,
        'sshKeyPath': sshKeyPath,
        'opencodePath': opencodePath,
        'workingDirectory': workingDirectory,
        'timeoutSeconds': timeoutSeconds,
        'username': username,
        'password': password,
        'agent': agent,
        'providerID': providerID,
        'modelID': modelID,
        'sessionId': sessionId,
      };

  OpencodeConnectionConfig copyWith({String? sessionId}) {
    return OpencodeConnectionConfig(
      type: type,
      host: host,
      port: port,
      useHttps: useHttps,
      basePath: basePath,
      sshUser: sshUser,
      sshPassword: sshPassword,
      sshKeyPath: sshKeyPath,
      opencodePath: opencodePath,
      workingDirectory: workingDirectory,
      timeoutSeconds: timeoutSeconds,
      username: username,
      password: password,
      agent: agent,
      providerID: providerID,
      modelID: modelID,
      sessionId: sessionId ?? this.sessionId,
    );
  }
}
