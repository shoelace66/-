import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/settings_store.dart';

class SharedPreferencesSettingsStore implements SettingsStore {
  const SharedPreferencesSettingsStore();

  @override
  Future<Map<String, dynamic>?> readJson(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (itemKey, value) => MapEntry(itemKey.toString(), value),
        );
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> writeJson(String key, Map<String, dynamic> value) async {
    await (await SharedPreferences.getInstance())
        .setString(key, jsonEncode(value));
  }

  @override
  Future<bool> contains(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    return raw != null && raw.trim().isNotEmpty;
  }
}
