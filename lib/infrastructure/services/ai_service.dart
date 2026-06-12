import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';

class AiServiceException implements Exception {
  const AiServiceException(this.userMessage, {this.cause});

  final String userMessage;
  final Object? cause;

  @override
  String toString() => userMessage;
}

class AiService {
  Future<String> ask(
    String prompt, {
    required String contactId,
    required String contactName,
  }) async {
    if (!ApiConstants.hasApiKey) {
      throw const AiServiceException('请先设置 API Key。');
    }

    try {
      return await _requestWithFallback(prompt);
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

  Future<String> _requestWithFallback(String prompt) async {
    final urls = <String>[
      ApiConstants.chatCompletionsUrl,
      ApiConstants.chatCompletionsCompatUrl,
    ];

    AiServiceException? lastError;
    for (final url in urls) {
      try {
        return await _requestOnce(prompt: prompt, url: url);
      } on AiServiceException catch (e) {
        lastError = e;
        final retryCompat = url == ApiConstants.chatCompletionsUrl &&
            (e.userMessage.contains('HTTP 404') ||
                e.userMessage.contains('HTTP 405'));
        if (!retryCompat) rethrow;
      }
    }
    throw lastError ?? const AiServiceException('API 请求失败。');
  }

  Future<String> _requestOnce({
    required String prompt,
    required String url,
  }) async {
    final uri = Uri.parse(url);
    final payload = <String, dynamic>{
      'model': ApiConstants.runtimeModel,
      'messages': <Map<String, String>>[
        <String, String>{
          'role': 'user',
          'content': prompt,
        },
      ],
      'temperature': 0.7,
      'stream': false,
    };

    final response = await http
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${ApiConstants.runtimeApiKey.trim()}',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: ApiConstants.requestTimeoutSeconds));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiServiceException(_mapHttpStatus(response.statusCode));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('LLM response is not a JSON object');
    }

    final content = _extractContent(decoded);
    if (content.trim().isEmpty) {
      throw const FormatException('LLM response content is empty');
    }
    return content;
  }

  String _extractContent(Map<String, dynamic> json) {
    final direct = (json['reply'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final choices = json['choices'];
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

    final message = json['message'];
    if (message is Map) {
      final content = (message['content'] ?? '').toString().trim();
      if (content.isNotEmpty) return content;
    }

    return '';
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
