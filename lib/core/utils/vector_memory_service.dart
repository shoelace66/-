import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// 向量记忆条目实体类
class VectorMemoryEntity {
  int id;
  String entryId;
  String content;
  String type;
  String contactId;
  List<double> vector;
  int timestamp;

  VectorMemoryEntity({
    this.id = 0,
    required this.entryId,
    required this.content,
    required this.type,
    required this.contactId,
    required this.vector,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entryId': entryId,
      'content': content,
      'type': type,
      'contactId': contactId,
      'vector': vector,
      'timestamp': timestamp,
    };
  }

  factory VectorMemoryEntity.fromJson(Map<String, dynamic> json) {
    return VectorMemoryEntity(
      id: json['id'] as int? ?? 0,
      entryId: json['entryId'] as String,
      content: json['content'] as String,
      type: json['type'] as String,
      contactId: json['contactId'] as String,
      vector: (json['vector'] as List).map((e) => (e as num).toDouble()).toList(),
      timestamp: json['timestamp'] as int,
    );
  }
}

/// 向量记忆服务 - 使用 JSON 文件持久化存储
///
/// 用于存储和搜索向量嵌入的记忆，支持按联系人隔离数据
/// 数据持久化到本地 JSON 文件
class VectorMemoryService {
  // 单例模式
  static final VectorMemoryService _instance = VectorMemoryService._internal();
  factory VectorMemoryService() => _instance;
  VectorMemoryService._internal();

  final List<VectorMemoryEntity> _entries = [];
  String? _storagePath;
  bool _initialized = false;

  /// 初始化向量内存服务
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      _storagePath = path.join(docsDir.path, 'vector_memory.json');
      await _loadFromDisk();
      _initialized = true;
    } catch (e) {
      print('VectorMemoryService.initialize error: $e');
      _initialized = false;
    }
  }

  /// 从磁盘加载数据
  Future<void> _loadFromDisk() async {
    if (_storagePath == null) return;

    try {
      final file = File(_storagePath!);
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _entries.clear();
        _entries.addAll(
          jsonList.map((e) => VectorMemoryEntity.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      print('VectorMemoryService._loadFromDisk error: $e');
      _entries.clear();
    }
  }

  /// 保存数据到磁盘
  Future<void> _saveToDisk() async {
    if (_storagePath == null) return;

    try {
      final file = File(_storagePath!);
      final jsonList = _entries.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('VectorMemoryService._saveToDisk error: $e');
    }
  }

  /// 添加记忆条目
  ///
  /// [id] 条目唯一标识
  /// [content] 内容文本
  /// [type] 类型（如 'message', 'event' 等）
  /// [contactId] 关联的联系人ID，用于隔离不同联系人的数据
  Future<void> addMemoryEntry(
    String id,
    String content,
    String type, {
    required String contactId,
  }) async {
    try {
      await initialize();
      final vector = await _generateEmbedding(content);

      // 检查是否已存在相同的 entryId
      final existingIndex = _entries.indexWhere((e) => e.entryId == id);

      final entity = VectorMemoryEntity(
        id: existingIndex >= 0 ? _entries[existingIndex].id : _entries.length + 1,
        entryId: id,
        content: content,
        type: type,
        contactId: contactId,
        vector: vector,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      if (existingIndex >= 0) {
        _entries[existingIndex] = entity;
      } else {
        _entries.add(entity);
      }

      await _saveToDisk();
    } catch (e) {
      print('VectorMemoryService.addMemoryEntry error: $e');
    }
  }

  /// 搜索相似的记忆条目
  ///
  /// [query] 查询文本
  /// [topK] 返回最相似的K个结果
  /// [type] 可选的类型过滤
  /// [contactId] 必需的联系人ID，只搜索该联系人的数据
  Future<List<ScoredVectorEntry>> searchSimilar(
    String query,
    int topK, {
    String? type,
    required String contactId,
  }) async {
    try {
      await initialize();
      final queryVector = await _generateEmbedding(query);

      // 过滤并计算相似度
      final scoredEntries = <ScoredVectorEntry>[];
      for (final entry in _entries) {
        // 只搜索指定联系人的数据
        if (entry.contactId != contactId) continue;
        // 类型过滤
        if (type != null && entry.type != type) continue;

        final similarity = _cosineSimilarity(queryVector, entry.vector);
        scoredEntries.add(ScoredVectorEntry(entry: entry, score: similarity));
      }

      // 按相似度排序
      scoredEntries.sort((a, b) => b.score.compareTo(a.score));

      return scoredEntries.take(topK).toList();
    } catch (e) {
      print('VectorMemoryService.searchSimilar error: $e');
      return [];
    }
  }

  /// 删除指定联系人的所有记忆条目
  /// 通常在删除联系人时调用，与事件队列同步删除
  Future<void> deleteContactMemories(String contactId) async {
    try {
      await initialize();
      final beforeCount = _entries.length;
      _entries.removeWhere((entry) => entry.contactId == contactId);
      final afterCount = _entries.length;

      if (beforeCount != afterCount) {
        await _saveToDisk();
        print('VectorMemoryService: 删除联系人 $contactId 的 ${beforeCount - afterCount} 条向量数据');
      }
    } catch (e) {
      print('VectorMemoryService.deleteContactMemories error: $e');
    }
  }

  /// 删除指定的记忆条目
  Future<void> deleteMemoryEntry(String entryId) async {
    try {
      await initialize();
      _entries.removeWhere((entry) => entry.entryId == entryId);
      await _saveToDisk();
    } catch (e) {
      print('VectorMemoryService.deleteMemoryEntry error: $e');
    }
  }

  /// 清空所有数据
  Future<void> clearAll() async {
    try {
      await initialize();
      _entries.clear();
      await _saveToDisk();
    } catch (e) {
      print('VectorMemoryService.clearAll error: $e');
    }
  }

  /// 获取指定联系人的记忆条目数量
  Future<int> getContactMemoryCount(String contactId) async {
    try {
      await initialize();
      return _entries.where((entry) => entry.contactId == contactId).length;
    } catch (e) {
      print('VectorMemoryService.getContactMemoryCount error: $e');
      return 0;
    }
  }

  /// 获取所有记忆条目数量
  Future<int> getTotalMemoryCount() async {
    try {
      await initialize();
      return _entries.length;
    } catch (e) {
      print('VectorMemoryService.getTotalMemoryCount error: $e');
      return 0;
    }
  }

  Future<List<double>> _generateEmbedding(String text) async {
    // 这里使用简化的向量生成方法
    // 实际项目中可以使用TFLite模型或其他轻量级模型
    return _simpleEmbedding(text);
  }

  List<double> _simpleEmbedding(String text) {
    // 简化的文本向量化方法
    // 实际项目中应该使用更复杂的模型
    final words = text.split(RegExp(r'\s+'));
    final vector = List<double>.filled(32, 0.0);

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      for (int j = 0; j < word.length && j < 32; j++) {
        vector[j] += word.codeUnitAt(j) / 255.0;
      }
    }

    // 归一化
    final norm = sqrt(vector.fold(0.0, (sum, val) => sum + val * val));
    if (norm > 0) {
      return vector.map((v) => v / norm).toList();
    }
    return vector;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must have the same length');
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) {
      return 0.0;
    }

    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
}

/// 带分数的向量条目
class ScoredVectorEntry {
  final VectorMemoryEntity entry;
  final double score;

  ScoredVectorEntry({required this.entry, required this.score});
}
