import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CachedImage {
  const CachedImage({
    required this.localPath,
    required this.sourceUrl,
    required this.contactId,
    required this.prompt,
    required this.cachedAtMs,
  });

  final String localPath;
  final String sourceUrl;
  final String contactId;
  final String prompt;
  final int cachedAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'localPath': localPath,
        'sourceUrl': sourceUrl,
        'contactId': contactId,
        'prompt': prompt,
        'cachedAtMs': cachedAtMs,
      };

  factory CachedImage.fromJson(Map<String, dynamic> json) => CachedImage(
        localPath: (json['localPath'] ?? '').toString(),
        sourceUrl: (json['sourceUrl'] ?? '').toString(),
        contactId: (json['contactId'] ?? '').toString(),
        prompt: (json['prompt'] ?? '').toString(),
        cachedAtMs: (json['cachedAtMs'] as num?)?.toInt() ?? 0,
      );
}

class ImageCacheService extends ChangeNotifier {
  ImageCacheService._internal();

  static final ImageCacheService instance = ImageCacheService._internal();

  final List<CachedImage> _images = [];
  Directory? _cacheDir;
  http.Client? _httpClient;
  Future<void>? _initFuture;
  static const int _maxCacheEntries = 200;

  List<CachedImage> get images => List<CachedImage>.unmodifiable(_images);

  bool get isInitialized => _cacheDir != null;

  Future<void> _ensureInit() {
    if (_initFuture != null) return _initFuture!;
    _initFuture = _init();
    return _initFuture!;
  }

  Future<void> _init() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory(p.join(appDir.path, 'image_cache'));
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      _httpClient = http.Client();
      await _loadIndex();
    } catch (e) {
      debugPrint('ImageCacheService init failed: $e');
    }
  }

  Future<void> _loadIndex() async {
    final indexFile = File(p.join(_cacheDir!.path, 'index.json'));
    if (await indexFile.exists()) {
      try {
        final content = await indexFile.readAsString();
        final list = jsonDecode(content) as List;
        for (final item in list) {
          _images.add(CachedImage.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (e) {
        debugPrint('ImageCache index load failed: $e');
      }
    }
  }

  Future<void> _saveIndex() async {
    try {
      final indexFile = File(p.join(_cacheDir!.path, 'index.json'));
      await indexFile.writeAsString(
        jsonEncode(_images.map((i) => i.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('ImageCache index save failed: $e');
    }
  }

  Future<String?> cacheImage({
    required String url,
    required String contactId,
    required String prompt,
  }) async {
    await _ensureInit();
    if (_cacheDir == null || _httpClient == null) return null;

    final existing = _images.where((i) => i.sourceUrl == url).firstOrNull;
    if (existing != null) return existing.localPath;

    try {
      final response = await _httpClient!.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final ext = p.extension(Uri.parse(url).path);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}$ext';
      final filePath = p.join(_cacheDir!.path, fileName);
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      final cached = CachedImage(
        localPath: filePath,
        sourceUrl: url,
        contactId: contactId,
        prompt: prompt,
        cachedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _images.insert(0, cached);
      _enforceLimits();
      await _saveIndex();
      notifyListeners();
      return filePath;
    } catch (e) {
      debugPrint('ImageCache cache failed: $e');
      return null;
    }
  }

  Future<String?> getLocalPath(String url) async {
    final existing = _images.where((i) => i.sourceUrl == url).firstOrNull;
    if (existing != null) {
      final file = File(existing.localPath);
      if (await file.exists()) return existing.localPath;
      _images.remove(existing);
      await _saveIndex();
    }
    return null;
  }

  List<CachedImage> getByContact(String contactId) =>
      _images.where((i) => i.contactId == contactId).toList(growable: false);

  Future<void> deleteImage(String localPath) async {
    final file = File(localPath);
    if (await file.exists()) await file.delete();
    _images.removeWhere((i) => i.localPath == localPath);
    await _saveIndex();
    notifyListeners();
  }

  Future<void> deleteByContact(String contactId) async {
    final toRemove = _images.where((i) => i.contactId == contactId).toList();
    for (final img in toRemove) {
      final file = File(img.localPath);
      if (await file.exists()) await file.delete();
    }
    _images.removeWhere((i) => i.contactId == contactId);
    await _saveIndex();
    notifyListeners();
  }

  Future<void> clearAll() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return;
    await for (final entity in _cacheDir!.list()) {
      if (entity is File && p.basename(entity.path) != 'index.json') {
        await entity.delete();
      }
    }
    _images.clear();
    await _saveIndex();
    notifyListeners();
  }

  void _enforceLimits() {
    while (_images.length > _maxCacheEntries) {
      final removed = _images.removeLast();
      final file = File(removed.localPath);
      if (file.existsSync()) file.deleteSync();
    }
  }

  FileImageProvider? fileImageProvider(String url) {
    final path = _images.where((i) => i.sourceUrl == url).firstOrNull?.localPath;
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return FileImageProvider(file);
  }
}

class FileImageProvider {
  const FileImageProvider(this.file);
  final File file;
  Uint8List? get bytes {
    try {
      return file.readAsBytesSync();
    } catch (_) {
      return null;
    }
  }
}