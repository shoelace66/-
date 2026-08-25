abstract interface class SettingsStore {
  Future<Map<String, dynamic>?> readJson(String key);

  Future<void> writeJson(String key, Map<String, dynamic> value);

  Future<bool> contains(String key);
}
