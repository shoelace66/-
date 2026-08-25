import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';

import '../../core/data/models/provider_settings.dart';

class ImageGenerationResult {
  const ImageGenerationResult({
    required this.success,
    this.imageUrl,
    this.imageBytes,
    this.error,
  });

  final bool success;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final String? error;
}

class ImageGenerationException implements Exception {
  const ImageGenerationException(this.userMessage, {this.cause});

  final String userMessage;
  final Object? cause;

  @override
  String toString() => userMessage;
}

class ImageGenerationService {
  ImageGenerationService._internal();

  static final ImageGenerationService instance =
      ImageGenerationService._internal();

  /// 测试 / 高级用途：注入自定义 http.Client
  /// 默认 null 时走全局 [http.Client]；调用方传 MockClient 即可在测试里拦截。
  http.Client? _clientOverride;
  http.Client? _sharedClient;

  /// 当前生效的生图 provider 配置
  ImageProfile _profile = const ImageProfile();

  void updateProfile(ImageProfile profile) {
    _profile = profile;
  }

  ImageProfile get currentProfile => _profile;

  /// 给测试 / 高级场景用：注入自定义 client。
  /// 不传时使用全局 [http.Client]，生产环境默认行为。
  // ignore: use_setters_to_change_properties
  void debugSetHttpClient(http.Client? client) {
    _clientOverride = client;
  }

  http.Client get _http => _clientOverride ?? (_sharedClient ??= http.Client());

  /// 生成图片
  ///
  /// 支持的预设：
  /// - openai_image / doubao_image / custom_image：走 OpenAI Images
  ///   兼容协议 POST {baseUrl}/images/generations
  /// - stability：POST {baseUrl}/v2beta/stable-image/generate/{model}
  /// - pollinations：免 key 的 GET {baseUrl}/prompt/{prompt}
  ///
  /// 未传 [profile] 时使用上次 [_profile] / [updateProfile] 设置的值。
  Future<ImageGenerationResult> generate({
    required String prompt,
    ImageProfile? profile,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      return const ImageGenerationResult(
        success: false,
        error: '图片描述不能为空',
      );
    }

    final effective = profile ?? _profile;
    final presetId = effective.presetId;

    try {
      switch (presetId) {
        case 'pollinations':
          return await _generatePollinations(
              profile: effective, prompt: trimmed);
        case 'stability':
          return await _generateStability(profile: effective, prompt: trimmed);
        case 'openai_image':
        case 'doubao_image':
        case 'custom_image':
        default:
          return await _generateOpenAiImages(
              profile: effective, prompt: trimmed);
      }
    } on ImageGenerationException catch (e) {
      debugPrint('[ImageGenerationService] ${e.userMessage}');
      return ImageGenerationResult(success: false, error: e.userMessage);
    } catch (e) {
      debugPrint('[ImageGenerationService] 未知错误: $e');
      return ImageGenerationResult(
        success: false,
        error: '生图失败：${e.runtimeType}',
      );
    }
  }

  // ---- OpenAI Images 兼容协议 ----

  Future<ImageGenerationResult> _generateOpenAiImages({
    required ImageProfile profile,
    required String prompt,
  }) async {
    if (profile.baseUrl.trim().isEmpty) {
      return const ImageGenerationResult(
        success: false,
        error: '请先在"应用设置 → API 提供商 → 生图"里填写 Base URL',
      );
    }
    final url = '${profile.baseUrl}/images/generations';
    final params = profile.parameters;
    final payload = <String, dynamic>{
      'model': profile.model,
      'prompt': prompt,
      'n': params.n,
      'size': params.size,
      'response_format': params.responseFormat,
    };
    if (params.style.isNotEmpty) {
      payload['style'] = params.style;
    }
    if (params.quality.isNotEmpty) {
      payload['quality'] = params.quality;
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (profile.apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${profile.apiKey.trim()}';
    }

    final response = await _http
        .post(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(Duration(seconds: params.timeoutSeconds));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ImageGenerationException(
        _mapHttpStatus('生图接口', response.statusCode, response.body),
      );
    }

    final decoded = jsonDecode(response.body);
    final list = decoded is Map ? decoded['data'] : null;
    if (list is! List || list.isEmpty) {
      throw const ImageGenerationException('生图接口返回数据格式异常');
    }
    final first = list.first;
    if (first is! Map) {
      throw const ImageGenerationException('生图接口返回数据格式异常');
    }

    final urlField = (first['url'] ?? '').toString();
    final b64Field = (first['b64_json'] ?? '').toString();
    if (urlField.isNotEmpty) {
      return ImageGenerationResult(success: true, imageUrl: urlField);
    }
    if (b64Field.isNotEmpty) {
      final bytes = base64Decode(b64Field);
      return ImageGenerationResult(
        success: true,
        imageBytes: Uint8List.fromList(bytes),
      );
    }
    throw const ImageGenerationException('生图接口未返回图片数据');
  }

  // ---- Pollinations（GET，免 key） ----

  Future<ImageGenerationResult> _generatePollinations({
    required ImageProfile profile,
    required String prompt,
  }) async {
    final base = profile.baseUrl.isEmpty
        ? 'https://image.pollinations.ai'
        : profile.baseUrl;
    final params = profile.parameters;
    final size = params.size.contains('x') ? params.size : '1024x1024';
    final encoded = Uri.encodeComponent(prompt);
    final url = '$base/prompt/$encoded?width=${size.split('x').first}'
        '&height=${size.split('x').last}'
        '&nologo=true'
        '&model=${profile.model.isEmpty ? 'flux' : profile.model}';

    final response = await _http.get(Uri.parse(url)).timeout(
          Duration(seconds: params.timeoutSeconds),
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ImageGenerationException(
        _mapHttpStatus('Pollinations', response.statusCode, response.body),
      );
    }
    if (response.bodyBytes.isEmpty) {
      throw const ImageGenerationException('Pollinations 返回空内容');
    }
    return ImageGenerationResult(
      success: true,
      imageUrl: url,
      imageBytes: response.bodyBytes,
    );
  }

  // ---- Stability ----

  Future<ImageGenerationResult> _generateStability({
    required ImageProfile profile,
    required String prompt,
  }) async {
    if (profile.apiKey.trim().isEmpty) {
      return const ImageGenerationResult(
        success: false,
        error: 'Stability 需要 API Key',
      );
    }
    final params = profile.parameters;
    final url =
        '${profile.baseUrl}/v2beta/stable-image/generate/${profile.model}';
    final response = await _http
        .post(
          Uri.parse(url),
          headers: <String, String>{
            'Authorization': 'Bearer ${profile.apiKey.trim()}',
            'Accept': 'image/*',
          },
          body: jsonEncode(<String, dynamic>{
            'prompt': prompt,
            'output_format': 'png',
            'aspect_ratio': params.size.contains('x')
                ? _aspectRatioFromSize(params.size)
                : '1:1',
          }),
        )
        .timeout(Duration(seconds: params.timeoutSeconds));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ImageGenerationException(
        _mapHttpStatus('Stability', response.statusCode, response.body),
      );
    }
    return ImageGenerationResult(
      success: true,
      imageBytes: response.bodyBytes,
    );
  }

  String _aspectRatioFromSize(String size) {
    final parts = size.split('x');
    if (parts.length != 2) return '1:1';
    final w = double.tryParse(parts[0]) ?? 1;
    final h = double.tryParse(parts[1]) ?? 1;
    final r = w / h;
    if ((r - 1).abs() < 0.05) return '1:1';
    if ((r - 16 / 9).abs() < 0.05) return '16:9';
    if ((r - 9 / 16).abs() < 0.05) return '9:16';
    if ((r - 3 / 2).abs() < 0.05) return '3:2';
    if ((r - 2 / 3).abs() < 0.05) return '2:3';
    if ((r - 4 / 3).abs() < 0.05) return '4:3';
    if ((r - 3 / 4).abs() < 0.05) return '3:4';
    if ((r - 21 / 9).abs() < 0.05) return '21:9';
    return '1:1';
  }

  String _mapHttpStatus(String tag, int status, String body) {
    if (status == 401 || status == 403) {
      return '$tag：API Key 无效或无权限（HTTP $status）';
    }
    if (status == 404) {
      return '$tag：路径不存在（HTTP 404）— 检查 baseUrl / model 拼写';
    }
    if (status == 429) {
      return '$tag：请求过于频繁或额度不足（HTTP 429）';
    }
    if (status >= 500) {
      return '$tag：服务暂时不可用（HTTP $status）';
    }
    final snippet = body.length > 160 ? '${body.substring(0, 160)}…' : body;
    return '$tag：HTTP $status $snippet';
  }
}
