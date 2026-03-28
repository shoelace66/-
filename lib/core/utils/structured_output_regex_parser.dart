import 'dart:convert';

class StructuredOutputRegexParser {
  StructuredOutputRegexParser._();

  static final RegExp _jsonFence = RegExp(
    r'```json\s*([\s\S]*?)```',
    caseSensitive: false,
  );

  static String? extractPrimaryPayload(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final fenced = _jsonFence.firstMatch(text)?.group(1)?.trim();
    if (fenced != null && _isJsonObject(fenced)) {
      return fenced;
    }

    if (_isJsonObject(text)) {
      return text;
    }

    return _extractBestEffortJsonObject(text);
  }

  static Map<String, dynamic>? parsePrimaryPayload(String raw) {
    final payload = extractPrimaryPayload(raw);
    if (payload == null) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? extractReply(String raw) {
    final parsed = parsePrimaryPayload(raw);
    final reply = parsed?['reply']?.toString().trim();
    if (reply == null || reply.isEmpty) return null;
    return reply;
  }

  static Map<String, dynamic>? extractMemoryPatch(String raw) {
    final parsed = parsePrimaryPayload(raw);
    final patch = parsed?['memoryPatch'];
    if (patch is Map<String, dynamic>) return patch;
    return null;
  }

  /// 安全地从 memoryPatch 中提取字符串列表
  /// 如果字段不存在或为空，返回空列表
  static List<String> extractStringList(Map<String, dynamic>? patch, String key) {
    if (patch == null) return const <String>[];
    final value = patch[key];
    if (value == null) return const <String>[];
    if (value is! List) return const <String>[];
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 安全地从 memoryPatch 中提取字符串
  /// 如果字段不存在或为空，返回 null
  static String? extractString(Map<String, dynamic>? patch, String key) {
    if (patch == null) return null;
    final value = patch[key];
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty) return null;
    return str;
  }

  /// 安全地从 memoryPatch 中提取事件列表
  /// 如果字段不存在或为空，返回空列表
  static List<Map<String, dynamic>> extractEventList(Map<String, dynamic>? patch) {
    if (patch == null) return const <Map<String, dynamic>>[];
    final value = patch['events'];
    if (value == null) return const <Map<String, dynamic>>[];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map<String, dynamic>>().toList();
  }

  static bool _isJsonObject(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic>;
    } catch (_) {
      return false;
    }
  }

  static String? _extractBestEffortJsonObject(String text) {
    final starts = <int>[];
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 123) {
        // {
        starts.add(i);
      }
    }

    for (final start in starts) {
      for (int end = text.length - 1; end > start; end--) {
        if (text.codeUnitAt(end) != 125) continue; // }
        final candidate = text.substring(start, end + 1).trim();
        if (_isJsonObject(candidate)) return candidate;
      }
    }
    return null;
  }
}
