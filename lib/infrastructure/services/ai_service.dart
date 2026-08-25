import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../../core/data/models/provider_settings.dart';
import '../../core/utils/structured_output_regex_parser.dart';

class AiServiceException implements Exception {
  const AiServiceException(this.userMessage, {this.cause, this.rawResponse});

  final String userMessage;
  final Object? cause;

  /// LLM 返回的原始响应体（如果可获取）。
  /// 用于在 debug 模式下展示用户到底拿到了什么内容，
  /// 避免"格式异常"时只看到一句空话。
  final String? rawResponse;

  @override
  String toString() => userMessage;
}

class AiService {
  AiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 单次 LLM 调用
  ///
  /// 优先使用调用方传入的 [LlmProfile]；为空时回退到运行时全局配置
  ///（[ApiConstants]），方便未迁移到 [ProviderSettings] 的旧代码继续工作。
  Future<String> ask(
    String prompt, {
    required String contactId,
    required String contactName,
    LlmProfile? profile,
  }) async {
    final effectiveProfile = profile ?? _runtimeProfile();

    if (!effectiveProfile.hasApiKey) {
      throw const AiServiceException('请先设置 API Key。');
    }

    try {
      return await _requestWithFallback(
        prompt: prompt,
        profile: effectiveProfile,
        client: _client,
      );
    } on TimeoutException catch (e) {
      throw AiServiceException('请求超时，请检查网络后重试。', cause: e);
    } on FormatException catch (e) {
      throw AiServiceException('模型返回内容格式异常，请重试。', cause: e);
    } on AiServiceException {
      rethrow;
    } catch (e) {
      final message = e.toString();
      if (message.toLowerCase().contains('xmlhttprequest')) {
        throw AiServiceException('浏览器请求失败（可能是跨域/CORS或网络问题）。', cause: e);
      }
      throw AiServiceException('请求失败：${e.runtimeType}', cause: e);
    }
  }

  Stream<String> askStream(
    String prompt, {
    required String contactId,
    required String contactName,
    LlmProfile? profile,
  }) async* {
    final effectiveProfile = profile ?? _runtimeProfile();
    if (!effectiveProfile.hasApiKey) {
      throw const AiServiceException('请先设置 API Key。');
    }
    try {
      yield* _requestStreamWithFallback(
        prompt: prompt,
        profile: effectiveProfile,
        client: _client,
      );
    } on TimeoutException catch (error) {
      throw AiServiceException('请求超时，请检查网络后重试。', cause: error);
    } on AiServiceException {
      rethrow;
    } catch (error) {
      throw AiServiceException('流式请求失败：${error.runtimeType}', cause: error);
    }
  }

  /// 从运行时 ApiConstants 派生一个临时 LlmProfile
  LlmProfile _runtimeProfile() {
    return LlmProfile(
      apiKey: ApiConstants.runtimeApiKey,
      baseUrl: ApiConstants.runtimeBaseUrl,
      model: ApiConstants.runtimeModel,
      parameters: LlmParameters(
        timeoutSeconds: ApiConstants.runtimeTimeoutSeconds,
      ),
    );
  }

  Future<String> _requestWithFallback({
    required String prompt,
    required LlmProfile profile,
    required http.Client client,
  }) async {
    final urls = <String>[
      '${profile.baseUrl}/chat/completions',
      '${profile.baseUrl.replaceAll(RegExp(r'/v1$'), '')}/v1/chat/completions',
    ];

    AiServiceException? lastError;
    for (final url in urls) {
      try {
        return await _requestOnce(
          prompt: prompt,
          url: url,
          profile: profile,
          client: client,
        );
      } on AiServiceException catch (e) {
        lastError = e;
        final retryCompat = url == urls.first &&
            (e.userMessage.contains('HTTP 404') ||
                e.userMessage.contains('HTTP 405'));
        if (!retryCompat) rethrow;
      }
    }
    throw lastError ?? const AiServiceException('API 请求失败。');
  }

  Stream<String> _requestStreamWithFallback({
    required String prompt,
    required LlmProfile profile,
    required http.Client client,
  }) async* {
    final urls = <String>[
      '${profile.baseUrl}/chat/completions',
      '${profile.baseUrl.replaceAll(RegExp(r'/v1$'), '')}/v1/chat/completions',
    ];
    AiServiceException? lastError;
    for (final url in urls) {
      var emitted = false;
      try {
        await for (final chunk in _requestStreamOnce(
          prompt: prompt,
          url: url,
          profile: profile,
          client: client,
        )) {
          emitted = true;
          yield chunk;
        }
        return;
      } on AiServiceException catch (error) {
        lastError = error;
        final retryCompatible = !emitted &&
            url == urls.first &&
            (error.userMessage.contains('HTTP 404') ||
                error.userMessage.contains('HTTP 405'));
        if (!retryCompatible) rethrow;
      }
    }
    throw lastError ?? const AiServiceException('API 流式请求失败。');
  }

  Stream<String> _requestStreamOnce({
    required String prompt,
    required String url,
    required LlmProfile profile,
    required http.Client client,
  }) async* {
    final params = profile.parameters;
    final payload = <String, dynamic>{
      'model': profile.model,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'user', 'content': prompt},
      ],
      'temperature': params.temperature,
      'top_p': params.topP,
      'frequency_penalty': params.frequencyPenalty,
      'presence_penalty': params.presencePenalty,
      'stream': true,
    };
    if (params.maxTokens > 0) payload['max_tokens'] = params.maxTokens;
    final request = http.Request('POST', Uri.parse(url))
      ..headers.addAll(<String, String>{
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer ${profile.apiKey.trim()}',
      })
      ..body = jsonEncode(payload);
    final response = await client
        .send(request)
        .timeout(Duration(seconds: params.timeoutSeconds));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw AiServiceException(_mapHttpStatus(response.statusCode));
    }

    final plainBody = StringBuffer();
    var emitted = false;
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(Duration(seconds: params.timeoutSeconds));
    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
      if (!trimmed.startsWith('data:')) {
        plainBody.writeln(line);
        continue;
      }
      final data = trimmed.substring(5).trim();
      if (data == '[DONE]') break;
      final chunk = _extractStreamDelta(data);
      if (chunk == null || chunk.isEmpty) continue;
      emitted = true;
      yield chunk;
    }
    if (!emitted && plainBody.isNotEmpty) {
      final content = _extractContent(plainBody.toString());
      if (content != null && content.isNotEmpty) {
        yield content;
        return;
      }
    }
    if (!emitted && plainBody.isEmpty) {
      throw const AiServiceException('模型返回了空的流式响应。');
    }
  }

  String? _extractStreamDelta(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return null;
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final first = choices.first as Map;
        final delta = first['delta'];
        if (delta is Map) {
          final content = delta['content'];
          if (content is String) return content;
        }
        final message = first['message'];
        if (message is Map && message['content'] is String) {
          return message['content'] as String;
        }
        if (first['text'] is String) return first['text'] as String;
      }
      final message = decoded['message'];
      if (message is Map && message['content'] is String) {
        return message['content'] as String;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<String> _requestOnce({
    required String prompt,
    required String url,
    required LlmProfile profile,
    required http.Client client,
  }) async {
    final uri = Uri.parse(url);
    final params = profile.parameters;
    final payload = <String, dynamic>{
      'model': profile.model,
      'messages': <Map<String, String>>[
        <String, String>{
          'role': 'user',
          'content': prompt,
        },
      ],
      'temperature': params.temperature,
      'top_p': params.topP,
      'frequency_penalty': params.frequencyPenalty,
      'presence_penalty': params.presencePenalty,
      'stream': params.stream,
    };
    if (params.maxTokens > 0) {
      payload['max_tokens'] = params.maxTokens;
    }

    final response = await client
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${profile.apiKey.trim()}',
          },
          body: jsonEncode(payload),
        )
        .timeout(Duration(seconds: params.timeoutSeconds));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiServiceException(_mapHttpStatus(response.statusCode));
    }

    final content = _extractContent(response.body);
    if (content == null || content.trim().isEmpty) {
      throw AiServiceException(
        '模型返回内容格式异常，请重试。',
        rawResponse: response.body,
      );
    }
    return content;
  }

  /// 从 LLM 原始响应体里抽出"回复文本"
  ///
  /// 解析顺序（每一步失败都继续尝试下一步）：
  /// 1. SSE 流式响应（`data: {...}` 拼接）— 即使请求是 `stream: false`，
  ///    部分服务商（如 deepseek 某些模型）仍会返回 SSE，这里把 chunk 拼起来
  ///    还原成单个 JSON 对象再处理
  /// 2. 尝试把整段 body 当 JSON parse（OpenAI 标准非流式格式）
  /// 3. 用 [StructuredOutputRegexParser] 抽取 JSON（兼容 markdown 代码块 / 文本夹杂）
  /// 4. 退路（仅当 body 不像 JSON）：直接把整段 body 当纯文本返回
  ///
  /// 返回 `null` 的唯一情况：body 完全为空，或解析出了 JSON 但里面没有有效 reply。
  String? _extractContent(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;

    // 1) SSE 流式响应拼接：body 是 "data: {...}\n\ndata: {...}\n\n..." 格式。
    //    每个 chunk 通常是 choices[0].delta.content（流式）或 choices[0].message.content（非流式首包）。
    //    把所有 chunk 的 content 拼起来后，尝试重组为单个 JSON 对象。
    if (_looksLikeSse(trimmed)) {
      final reassembled = _reassembleSseChunks(trimmed);
      if (reassembled != null && reassembled.isNotEmpty) {
        return _tryExtractFromJson(reassembled);
      }
      // SSE 拼接失败 → 退回到原始 SSE 文本（被 chat_provider 当 reply 显示）
      return trimmed.length <= 8000 ? trimmed : null;
    }

    // 2) 整段 JSON
    final fromJson = _tryExtractFromJson(trimmed);
    if (fromJson != null) return fromJson;

    // 3) 没解析出 JSON — 如果 body 不像 JSON（不以 { 或 [ 开头），
    //    LLM 是直接吐纯文本 → 整段当 reply 返回（兜底）。
    //    但太长的不返回（防止卡 UI），让上层报错。
    final looksLikeJson = trimmed.startsWith('{') || trimmed.startsWith('[');
    if (!looksLikeJson && trimmed.length <= 8000) {
      return trimmed;
    }
    return null;
  }

  /// 用 [StructuredOutputRegexParser] 等多种策略从单段 JSON / JSON-like 文本里
  /// 抽出 reply。返回 null 表示拿不到。
  String? _tryExtractFromJson(String jsonText) {
    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(jsonText);
      if (parsed is Map<String, dynamic>) {
        decoded = parsed;
      }
    } catch (_) {
      // 不是纯 JSON，尝试 markdown / 文本夹杂
    }
    decoded ??= StructuredOutputRegexParser.parsePrimaryPayload(jsonText);

    if (decoded == null) return null;

    // 标准 reply 字段（业务约定）
    final reply = (decoded['reply'] ?? '').toString().trim();
    if (reply.isNotEmpty) return reply;

    // OpenAI chat/completions 标准 choices
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map) {
          final content = (message['content'] ?? '').toString().trim();
          if (content.isNotEmpty) return content;
        }
        final text = (first['text'] ?? '').toString().trim();
        if (text.isNotEmpty) return text;
      }
    }

    // 兼容服务（Ollama / LM Studio）顶层 message
    final message = decoded['message'];
    if (message is Map) {
      final content = (message['content'] ?? '').toString().trim();
      if (content.isNotEmpty) return content;
    }

    return null;
  }

  /// 检测响应体是否像 SSE（Server-Sent Events）
  bool _looksLikeSse(String body) {
    // SSE 响应特征：以 `data:` 开头，或含 `\ndata: ` 续行
    if (body.startsWith('data:')) return true;
    return body.contains('\ndata:');
  }

  /// 把 SSE chunk 流重组为完整 JSON 字符串
  ///
  /// SSE 格式：
  /// ```
  /// data: {"choices":[{"delta":{"content":"你"}}]}
  /// data: {"choices":[{"delta":{"content":"好"}}]}
  /// data: [DONE]
  /// ```
  ///
  /// 重组成 `{"choices":[{"message":{"content":"你好"}}]}` 后，
  /// 走标准的 [jsonDecode] 路径。
  String? _reassembleSseChunks(String sseBody) {
    final contentBuffer = StringBuffer();
    final fullObjects = <Map<String, dynamic>>[];
    String? lastFinishReason;
    Map<String, dynamic>? lastUsage;

    for (final rawLine in sseBody.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || !line.startsWith('data:')) continue;
      var payload = line.substring(5).trim();
      // 跳过 SSE 注释行
      if (payload.startsWith(':')) continue;
      // 流结束标志 — [DONE] 之后的行一律忽略（OpenAI 协议保证 [DONE] 是最后一行；
      // 但某些代理会重发残包，这里仍走 break 保险起见）
      if (payload == '[DONE]') break;

      Map<String, dynamic>? chunk;
      try {
        final parsed = jsonDecode(payload);
        if (parsed is Map<String, dynamic>) chunk = parsed;
      } catch (_) {
        continue;
      }
      if (chunk == null) continue;

      // 流式 chunk 用 delta.content；非流式首包（choices[0].message.content）兼容一下
      final choices = chunk['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map) {
          final delta = first['delta'];
          if (delta is Map) {
            final c = delta['content'];
            if (c != null) contentBuffer.write(c.toString());
          }
          final message = first['message'];
          if (message is Map) {
            final c = message['content'];
            if (c != null) contentBuffer.write(c.toString());
          }
          final fr = first['finish_reason'];
          if (fr != null) lastFinishReason = fr.toString();
        }
      }
      final usage = chunk['usage'];
      if (usage is Map<String, dynamic>) lastUsage = usage;

      fullObjects.add(chunk);
    }

    if (contentBuffer.isEmpty && fullObjects.isEmpty) return null;

    // 重组一个标准 chat/completions JSON 出来
    final reassembled = <String, dynamic>{
      'object': 'chat.completion.reassembled',
      'choices': <Map<String, dynamic>>[
        <String, dynamic>{
          'index': 0,
          'message': <String, dynamic>{
            'role': 'assistant',
            'content': contentBuffer.toString()
          },
          'finish_reason': lastFinishReason,
        },
      ],
    };
    if (lastUsage != null) reassembled['usage'] = lastUsage;

    return jsonEncode(reassembled);
  }

  String _mapHttpStatus(int status) {
    if (status == 401 || status == 403) {
      return 'API Key 无效或无权限（HTTP $status）。';
    }
    if (status == 404 || status == 405) {
      return 'API 路径不匹配（HTTP $status）。';
    }
    if (status == 429) {
      return '请求过于频繁或额度不足（HTTP 429）。';
    }
    if (status >= 500) {
      return 'API 服务暂时不可用（HTTP $status）。';
    }
    return 'API 请求失败（HTTP $status）。';
  }
}
