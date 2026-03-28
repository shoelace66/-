import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/contact.dart';
import '../models/message.dart';

/// 聊天数据本地存储类
///
/// 使用 SharedPreferences 持久化存储：
/// - 应用设置（API密钥、系统提示词）
/// - 联系人列表
/// - 消息历史
///
/// 注意：SharedPreferences 在安卓端使用 XML 文件存储，
/// 位于 /data/data/<package_name>/shared_prefs/ 目录下
class ChatAgentStore {
  static const String _settingsKey = 'chat_settings_v1';
  static const String _contactsKey = 'chat_contacts_v1';
  static const String _messagesKey = 'chat_messages_v1';
  static const Map<String, dynamic> _defaultSettings = <String, dynamic>{
    'apiKey': '',
    'systemPrompt': 'You are a helpful assistant.',
  };

  /// 获取 SharedPreferences 实例
  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// 读取 Agent 设置
  Future<Map<String, dynamic>> readAgentSettings() async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_settingsKey);
      if (raw == null || raw.trim().isEmpty) {
        return Map<String, dynamic>.from(_defaultSettings);
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return <String, dynamic>{
            ..._defaultSettings,
            ...decoded.map((k, v) => MapEntry(k.toString(), v)),
          };
        }
      } catch (_) {}
    } catch (e) {
      print('ChatAgentStore.readAgentSettings error: $e');
    }
    return Map<String, dynamic>.from(_defaultSettings);
  }

  /// 保存 Agent 设置
  Future<void> saveAgentSettings(Map<String, dynamic> settings) async {
    try {
      final prefs = await _prefs();
      final payload = <String, dynamic>{
        ..._defaultSettings,
        ...settings,
      };
      final success = await prefs.setString(_settingsKey, jsonEncode(payload));
      if (!success) {
        print('ChatAgentStore.saveAgentSettings: 保存失败');
      }
    } catch (e) {
      print('ChatAgentStore.saveAgentSettings error: $e');
    }
  }

  /// 读取联系人列表
  Future<List<Contact>> readContacts() async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_contactsKey);
      if (raw == null || raw.trim().isEmpty) {
        return <Contact>[];
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final contacts = <Contact>[];
          for (final item in decoded) {
            if (item is! Map) continue;
            final contact = Contact.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            );
            if (contact.id.trim().isEmpty || contact.name.trim().isEmpty) {
              continue;
            }
            contacts.add(contact);
          }
          return contacts;
        }
      } catch (e) {
        print('ChatAgentStore.readContacts parse error: $e');
      }
    } catch (e) {
      print('ChatAgentStore.readContacts error: $e');
    }
    return <Contact>[];
  }

  /// 保存联系人列表
  Future<void> saveContacts(List<Contact> contacts) async {
    try {
      final prefs = await _prefs();
      final payload = contacts.map((c) => c.toJson()).toList();
      final success = await prefs.setString(_contactsKey, jsonEncode(payload));
      if (!success) {
        print('ChatAgentStore.saveContacts: 保存失败');
      }
    } catch (e) {
      print('ChatAgentStore.saveContacts error: $e');
    }
  }

  /// 读取按联系人分组的消息
  Future<Map<String, List<Message>>> readMessagesByContact() async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_messagesKey);
      if (raw == null || raw.trim().isEmpty) {
        return const <String, List<Message>>{};
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return const <String, List<Message>>{};
        final out = <String, List<Message>>{};
        for (final entry in decoded.entries) {
          final contactId = entry.key.toString().trim();
          if (contactId.isEmpty || entry.value is! List) continue;
          final list = <Message>[];
          for (final item in (entry.value as List)) {
            if (item is! Map) continue;
            final msg = Message.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            );
            if (msg.id.trim().isEmpty || msg.content.trim().isEmpty) continue;
            list.add(msg);
          }
          out[contactId] = list;
        }
        return out;
      } catch (e) {
        print('ChatAgentStore.readMessagesByContact parse error: $e');
      }
    } catch (e) {
      print('ChatAgentStore.readMessagesByContact error: $e');
    }
    return const <String, List<Message>>{};
  }

  /// 保存按联系人分组的消息
  Future<void> saveMessagesByContact(
      Map<String, List<Message>> messages) async {
    try {
      final prefs = await _prefs();
      final payload = <String, dynamic>{};
      for (final entry in messages.entries) {
        final contactId = entry.key.trim();
        if (contactId.isEmpty) continue;
        payload[contactId] = entry.value.map((m) => m.toJson()).toList();
      }
      final success = await prefs.setString(_messagesKey, jsonEncode(payload));
      if (!success) {
        print('ChatAgentStore.saveMessagesByContact: 保存失败');
      }
    } catch (e) {
      print('ChatAgentStore.saveMessagesByContact error: $e');
    }
  }

  /// 清除所有数据（用于调试或重置）
  Future<void> clearAll() async {
    try {
      final prefs = await _prefs();
      await prefs.remove(_settingsKey);
      await prefs.remove(_contactsKey);
      await prefs.remove(_messagesKey);
    } catch (e) {
      print('ChatAgentStore.clearAll error: $e');
    }
  }
}
