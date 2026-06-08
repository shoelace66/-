import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 连接方式
enum ConnectionType {
  /// HTTP API 代理（推荐，在 PC 上运行代理服务）
  http,

  /// SSH 连接（需要 SSH 密钥或密码）
  ssh,
}

/// opencode 连接配置
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

  /// 是否走 HTTPS
  ///
  /// - false（默认）：用 `http://host:port` —— 适合 localhost / Tailscale / SSH 反向隧道
  /// - true：用 `https://host:port` —— 适合 cloudflare tunnel、自建 HTTPS 反代、公网域名
  ///
  /// 注：Android 9+ 默认禁明文 HTTP；走 HTTP 时 APK 已配置 network_security_config
  /// 放行常见场景（Tailscale、私有 IP 等）
  final bool useHttps;

  /// 路径前缀，便于把 opencode 放在反向代理子路径下
  /// 留空表示直接挂在根路径
  final String basePath;
  final String sshUser;
  final String sshPassword;
  final String sshKeyPath;
  final String opencodePath;
  final String workingDirectory;
  final int timeoutSeconds;

  /// HTTP Basic Auth 用户名（opencode 默认是 `opencode`）
  final String username;

  /// HTTP Basic Auth 密码（对应 `OPENCODE_SERVER_PASSWORD`）
  /// 留空表示不发送鉴权头
  final String password;

  /// opencode agent 名称（如 `build`、`plan`），对应请求体里的 `agent` 字段
  final String agent;

  /// 可选：模型 providerID（如 `anthropic`）
  final String providerID;

  /// 可选：模型 ID（如 `claude-sonnet-4-5`）
  final String modelID;

  /// 缓存的 opencode session id
  ///
  /// 同一会话里 opencode 会保留上下文，所以"助手联系人"应复用同一个 session。
  /// 留空时由服务按"选 text-capable → 建新 session"顺序自动选一个。
  final String sessionId;

  /// 拼出 `http(s)://host:port[/basePath]`
  String get httpBase {
    final path = basePath.startsWith('/') ? basePath : '/$basePath';
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$host:$port$path';
  }

  factory OpencodeConnectionConfig.fromJson(Map<String, dynamic> json) {
    return OpencodeConnectionConfig(
      type: json['type'] == 'ssh'
          ? ConnectionType.ssh
          : ConnectionType.http,
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
    'type': type == ConnectionType.ssh ? 'ssh' : 'http',
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

  /// 复制当前配置，覆写 sessionId
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

/// opencode CLI 交互服务
///
/// 通过 HTTP API 或 SSH 连接到运行 opencode 的 PC，执行命令并返回结果。
class OpencodeService {
  OpencodeService({OpencodeConnectionConfig? config})
      : _config = config ?? const OpencodeConnectionConfig();

  OpencodeConnectionConfig _config;

  OpencodeConnectionConfig get config => _config;

  /// 更新连接配置
  void updateConfig(OpencodeConnectionConfig config) {
    _config = config;
  }

  /// 执行 opencode 命令
  Future<OpencodeResult> execute(String command) async {
    switch (_config.type) {
      case ConnectionType.http:
        return _executeViaHttp(command);
      case ConnectionType.ssh:
        return _executeViaSsh(command);
    }
  }

  /// 构造带可选 Basic Auth 头和 JSON Content-Type 的请求头
  Map<String, String> _jsonHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_config.password.isNotEmpty) {
      final basic = base64Encode(
        utf8.encode('${_config.username}:${_config.password}'),
      );
      headers['Authorization'] = 'Basic $basic';
    }
    return headers;
  }

  /// 通过 HTTP API 调用 opencode
  ///
  /// 流程（opencode server API）：
  /// 1. `GET /global/health` 健康检查
  /// 2. 选一个 text-capable 的 session：
  ///    - 优先用配置里缓存的 sessionId
  ///    - 否则在 `/session` 列表里找模型是 text-capable 的第一个
  ///    - 找不到就 `POST /session` 建一个
  /// 3. 若用户没指定 model，从 `GET /config/providers` 拿**text-capable**默认 model
  /// 4. `POST /session/:id/message` 同步发送消息并等待 AI 响应
  /// 5. 解析响应：先看 `info.error`，再看 `parts` 里所有 `type === "text"` 的 part
  Future<OpencodeResult> _executeViaHttp(String command) async {
    try {
      final base = _config.httpBase;
      final headers = _jsonHeaders();

      // 1. 健康检查
      final healthResp = await http
          .get(Uri.parse('$base/global/health'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (healthResp.statusCode != 200) {
        return OpencodeResult.failure(
          'opencode 服务不可用：HTTP ${healthResp.statusCode}（请确认 `opencode serve` 已启动）',
        );
      }

      // 2. 选 session
      final sessionId = await _pickOrCreateSession(base, headers);
      if (sessionId == null || sessionId.isEmpty) {
        return OpencodeResult.failure(
          '无法获取可用的 session：请先在 opencode TUI/Web 里创建或打开一个会话',
        );
      }

      // 3. 解析 model 字段：用户指定 > opencode 默认（只挑 text-capable）
      String? providerID = _config.providerID;
      String? modelID = _config.modelID;
      if (providerID.isEmpty || modelID.isEmpty) {
        final defaultModel = await _fetchDefaultModel(base, headers);
        if (defaultModel != null) {
          providerID = defaultModel.providerID;
          modelID = defaultModel.modelID;
        } else {
          return OpencodeResult.failure(
            'opencode 没配任何 text-capable 模型——'
            '请在终端跑 `opencode auth login` 或设置 ANTHROPIC_API_KEY / OPENAI_API_KEY 等环境变量，'
            '再重启 `opencode serve`',
          );
        }
      }

      // 4. 发送消息并同步等待响应
      final body = <String, dynamic>{
        'parts': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'text': command},
        ],
      };
      if (_config.agent.isNotEmpty) body['agent'] = _config.agent;
      if (providerID.isNotEmpty && modelID.isNotEmpty) {
        body['model'] = <String, String>{
          'providerID': providerID,
          'modelID': modelID,
        };
      }

      final promptUrl = Uri.parse('$base/session/$sessionId/message');
      final promptResp = await http
          .post(
            promptUrl,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: _config.timeoutSeconds));

      if (promptResp.statusCode == 404) {
        // 缓存的 sessionId 已失效，清掉让下次重新选
        _config = _config.copyWith(sessionId: '');
        return OpencodeResult.failure(
          'opencode session 已失效（HTTP 404），请重试',
        );
      }
      if (promptResp.statusCode < 200 || promptResp.statusCode >= 300) {
        return OpencodeResult.failure(
          'opencode 返回错误：HTTP ${promptResp.statusCode} ${promptResp.body}'
          '\n提示：常见原因是 opencode 没配 model 或模型 API 调用失败——'
          '请在终端确认 `opencode` 能正常对话，再回到此页面重试',
        );
      }

      // 5. 解析响应：opencode 返回的是单个 message 对象
      //    { info: AssistantMessage, parts: [ { type: "text", text: "..." }, ... ] }
      final decoded = jsonDecode(promptResp.body);
      final info = _extractInfo(decoded);

      // 5a. 优先看 info.error 字段（API 调用失败时 error 嵌在 info 里）
      final errObj = info?['error'];
      if (errObj is Map && errObj.isNotEmpty) {
        final name = errObj['name']?.toString() ?? 'Error';
        String detail = '';
        final data = errObj['data'];
        if (data is Map) {
          detail = data['message']?.toString() ?? '';
        }
        return OpencodeResult.failure(
          'opencode 报错：$name${detail.isNotEmpty ? "：$detail" : ""}',
        );
      }

      // 5b. 拼接所有 text part
      final parts = _extractParts(decoded);
      final text = _concatTextParts(parts);
      if (text.trim().isNotEmpty) {
        return OpencodeResult.success(text);
      }

      // 5c. 兜底：取 reasoning part（部分 agent 答案放在 reasoning 里）
      final reasoning = _concatReasoningParts(parts);
      if (reasoning.trim().isNotEmpty) {
        return OpencodeResult.success(reasoning);
      }

      return OpencodeResult.failure(
        'opencode 已收到消息，但响应里没有任何文本内容'
        '\n（parts 类型：${parts.map((p) => p is Map ? p['type'] : '?').join(', ')}）'
        '\n原始响应：${_truncate(promptResp.body, 600)}',
      );
    } on TimeoutException {
      return OpencodeResult.failure('请求超时（${_config.timeoutSeconds}秒）');
    } on http.ClientException catch (e) {
      return OpencodeResult.failure('无法连接到 opencode：${e.message}');
    } on FormatException catch (e) {
      return OpencodeResult.failure('opencode 响应格式错误：${e.message}');
    } catch (e) {
      return OpencodeResult.failure('HTTP 请求失败：$e');
    }
  }

  /// 选一个可用的 session id
  ///
  /// 顺序：
  /// 1. 用配置里缓存的 sessionId（如果存在）
  /// 2. 否则在 `/session` 列表里找第一个**模型是 text-capable** 的
  /// 3. 找不到就 `POST /session` 建一个新 session
  ///
  /// 选完后写回 `_config.sessionId`，调用方应在调用结束后把 config 持久化
  Future<String?> _pickOrCreateSession(
    String base,
    Map<String, String> headers,
  ) async {
    // 1. 配置里缓存的 id 直接用
    final cached = _config.sessionId;
    if (cached.isNotEmpty) {
      // 可选：探一下 GET /session/:id 看是否真存在
      // 这里信任缓存，如果失效会在 POST message 拿到 404 时清掉
      return cached;
    }

    // 2. 拉 /config/providers 用于过滤 text-capable 模型
    final providers = await _fetchProvidersRaw(base, headers);

    // 3. 拉 session 列表，挑第一个模型是 text-capable 的
    final sessionResp = await http
        .get(Uri.parse('$base/session'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (sessionResp.statusCode == 200) {
      final sessions = jsonDecode(sessionResp.body);
      if (sessions is List) {
        for (final s in sessions) {
          if (s is! Map) continue;
          final id = s['id']?.toString();
          if (id == null || id.isEmpty) continue;
          // 检查 session.model 是不是 text-capable
          final model = s['model'];
          if (model is Map) {
            final pid = model['providerID']?.toString() ?? '';
            final mid = model['id']?.toString() ?? '';
            if (pid.isNotEmpty && mid.isNotEmpty &&
                !_isTextCapable(providers, pid, mid)) {
              continue; // 这个 session 用了 TTS/audio 模型，跳过
            }
          }
          // 命中，写回缓存
          _config = _config.copyWith(sessionId: id);
          return id;
        }
      }
    }

    // 4. 找不到合适的，自己建一个
    final createdId = await _createSession(base, headers);
    if (createdId != null) {
      _config = _config.copyWith(sessionId: createdId);
    }
    return createdId;
  }

  /// 调用 `POST /session` 建一个新会话
  Future<String?> _createSession(
    String base,
    Map<String, String> headers,
  ) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$base/session'),
            headers: headers,
            // body 可选；不传 title 让 opencode 用默认
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200 && resp.statusCode != 201) return null;
      final data = jsonDecode(resp.body);
      if (data is Map) {
        return data['id']?.toString();
      }
    } catch (_) {}
    return null;
  }

  /// 拉 `/config/providers` 的原始数据（返回 providers 数组）
  Future<dynamic> _fetchProvidersRaw(
    String base,
    Map<String, String> headers,
  ) async {
    try {
      final resp = await http
          .get(Uri.parse('$base/config/providers'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is Map) return data['providers'];
    } catch (_) {}
    return null;
  }

  /// 从 `/config/providers` 拉默认 model
  ///
  /// 返回 `{providerID, modelID}` 格式的 provider/model。
  /// 关键：只挑 `capabilities.output.text === true` 的 LLM，
  /// 自动跳过 TTS、纯 audio-only 等不会输出文本的模型。
  /// opencode 端没有配过任何 text-capable 模型时返回 null。
  Future<_ModelRef?> _fetchDefaultModel(
    String base,
    Map<String, String> headers,
  ) async {
    try {
      final resp = await http
          .get(Uri.parse('$base/config/providers'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is! Map) return null;
      final providers = data['providers'];

      // 优先用 default 字段（opencode 配过的 provider/model 组合），
      // 但要过滤掉 TTS / 纯 audio 模型
      final def = data['default'];
      if (def is Map) {
        for (final entry in def.entries) {
          final providerID = entry.key.toString();
          final modelID = entry.value.toString();
          if (providerID.isEmpty || modelID.isEmpty) continue;
          if (_isTextCapable(providers, providerID, modelID)) {
            return _ModelRef(providerID: providerID, modelID: modelID);
          }
        }
      }

      // 否则扫所有 provider，找第一个 text-capable 模型
      if (providers is List) {
        for (final p in providers) {
          if (p is! Map) continue;
          final id = p['id']?.toString();
          final models = p['models'];
          if (id == null || models is! Map) continue;
          for (final m in models.entries) {
            if (_isTextCapableModelEntry(m.value)) {
              return _ModelRef(providerID: id, modelID: m.key.toString());
            }
          }
        }
      }
    } catch (_) {
      // 取默认 model 失败不阻塞主流程
    }
    return null;
  }

  /// 检查某个 provider/model 组合是否支持文本输出
  ///
  /// 取不到能力信息时默认认为是 text-capable（保守策略，避免误判 LLM 为 TTS）
  bool _isTextCapable(dynamic providers, String providerID, String modelID) {
    if (providers is! List) return true;
    for (final p in providers) {
      if (p is! Map) continue;
      if (p['id']?.toString() != providerID) continue;
      final models = p['models'];
      if (models is! Map) return true;
      final m = models[modelID];
      return _isTextCapableModelEntry(m);
    }
    return true;
  }

  /// 从 `/config/providers` 的单个 model 对象判断 text-capable
  bool _isTextCapableModelEntry(dynamic m) {
    if (m is! Map) return true;
    // 双重保险：id 或 name 含 tts 关键字的也直接排除
    final id = m['id']?.toString().toLowerCase() ?? '';
    final name = m['name']?.toString().toLowerCase() ?? '';
    if (id.contains('tts') || name.contains('tts')) return false;

    final caps = m['capabilities'];
    if (caps is! Map) return true;
    final output = caps['output'];
    if (output is! Map) return true;
    // 显式声明 output.text === false 的就排除
    return output['text'] != false;
  }

  /// 从 opencode 响应里抽 `parts` 数组
  ///
  /// 兼容三种返回形态：
  /// - `{ info, parts }`（单条消息的标准格式）
  /// - 直接就是 `parts` 数组
  /// - 包了 `data` 字段
  List<dynamic> _extractParts(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final parts = decoded['parts'];
      if (parts is List) return parts;
      final data = decoded['data'];
      if (data is Map) {
        final p = data['parts'];
        if (p is List) return p;
      }
    }
    return const <dynamic>[];
  }

  /// 从响应里抽 `info` 对象（含 `error` 字段的 AssistantMessage）
  Map<String, dynamic>? _extractInfo(dynamic decoded) {
    if (decoded is Map) {
      final info = decoded['info'];
      if (info is Map<String, dynamic>) return info;
      if (info is Map) return info.map((k, v) => MapEntry(k.toString(), v));
      final data = decoded['data'];
      if (data is Map) {
        final info2 = data['info'];
        if (info2 is Map) return info2.map((k, v) => MapEntry(k.toString(), v));
      }
    }
    return null;
  }

  /// 拼接所有 `type === "text"` 的 part 文本
  String _concatTextParts(List<dynamic> parts) {
    final buf = StringBuffer();
    for (final p in parts) {
      if (p is! Map) continue;
      final type = p['type']?.toString();
      if (type != null && type != 'text') continue;
      final text = p['text']?.toString();
      if (text == null || text.isEmpty) continue;
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(text);
    }
    return buf.toString();
  }

  /// 拼接所有 `type === "reasoning"` 的 part 文本（兜底用）
  String _concatReasoningParts(List<dynamic> parts) {
    final buf = StringBuffer();
    for (final p in parts) {
      if (p is! Map) continue;
      final type = p['type']?.toString();
      if (type != 'reasoning') continue;
      final text = p['text']?.toString();
      if (text == null || text.isEmpty) continue;
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(text);
    }
    return buf.toString();
  }

  /// 把过长的字符串截断，避免错误信息被一坨 JSON 撑爆
  String _truncate(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}…(已截断，原长度 ${s.length})';
  }

  /// 通过 SSH 执行命令
  ///
  /// 注意：SSH 模式需要 Process.run 支持，仅在桌面平台可用
  /// 在浏览器/移动端会返回不支持的提示
  Future<OpencodeResult> _executeViaSsh(String command) async {
    return OpencodeResult.failure('SSH 模式在当前平台不可用，请使用 HTTP 模式');
  }

  /// 测试连接是否可用
  ///
  /// 顺便探一下 provider/model，方便排查"opencode 没配 model"这类问题
  Future<OpencodeResult> testConnection() async {
    try {
      final headers = _jsonHeaders();
      final base = _config.httpBase;
      final resp = await http
          .get(Uri.parse('$base/global/health'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        return OpencodeResult.failure('服务器不可用: HTTP ${resp.statusCode}');
      }

      String version = '';
      try {
        final body = jsonDecode(resp.body);
        if (body is Map && body['version'] is String) {
          version = '（v${body['version']}）';
        }
      } catch (_) {}

      // 探测 provider/model 配置
      final model = await _fetchDefaultModel(base, headers);
      final modelHint = model == null
          ? '\n⚠️ 未检测到任何 provider/model，请先在终端跑 `opencode auth login` '
              '或 `export ANTHROPIC_API_KEY=...`'
          : '\n默认 model: ${model.providerID}/${model.modelID}';

      return OpencodeResult.success('连接成功$version$modelHint');
    } on TimeoutException {
      return OpencodeResult.failure('连接超时');
    } on http.ClientException catch (e) {
      return OpencodeResult.failure('连接失败：${e.message}');
    } catch (e) {
      return OpencodeResult.failure('连接失败: $e');
    }
  }
}

/// 内部小类：描述一个 opencode 模型
class _ModelRef {
  const _ModelRef({required this.providerID, required this.modelID});
  final String providerID;
  final String modelID;
}

/// opencode 执行结果
class OpencodeResult {
  const OpencodeResult._({
    required this.success,
    required this.output,
    this.error,
  });

  factory OpencodeResult.success(String output) =>
      OpencodeResult._(success: true, output: output);

  factory OpencodeResult.failure(String error, {String rawOutput = ''}) =>
      OpencodeResult._(success: false, output: rawOutput, error: error);

  final bool success;
  final String output;
  final String? error;
}
