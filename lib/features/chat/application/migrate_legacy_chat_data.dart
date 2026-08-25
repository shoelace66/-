import '../data/datasources/legacy_chat_snapshot_source.dart';
import '../domain/repositories/chat_persistence.dart';

enum LegacyMigrationOutcome {
  migrated,
  alreadyCompleted,
  targetAlreadyPopulated,
  noLegacyData,
}

class MigrateLegacyChatData {
  const MigrateLegacyChatData({
    required ChatPersistence target,
    required LegacyChatSnapshotSource source,
  })  : _target = target,
        _source = source;

  static const String migrationKey = 'legacy_shared_preferences_v1';

  final ChatPersistence _target;
  final LegacyChatSnapshotSource _source;

  Future<LegacyMigrationOutcome> execute() async {
    if (await _target.readMetadata(migrationKey) == 'completed') {
      return LegacyMigrationOutcome.alreadyCompleted;
    }
    final current = await _target.readSnapshot();
    if (!current.isEmpty) {
      await _target.writeMetadata(migrationKey, 'completed');
      return LegacyMigrationOutcome.targetAlreadyPopulated;
    }
    final legacy = await _source.readSnapshot();
    if (legacy.isEmpty) {
      await _target.writeMetadata(migrationKey, 'completed');
      return LegacyMigrationOutcome.noLegacyData;
    }

    _validateSnapshot(legacy);
    await _target.replaceSnapshot(legacy);
    final restored = await _target.readSnapshot();
    _verifyEquivalent(legacy, restored);
    await _target.writeMetadata(migrationKey, 'completed');
    return LegacyMigrationOutcome.migrated;
  }

  void _validateSnapshot(ChatSnapshot snapshot) {
    final contactIds = <String>{};
    for (final contact in snapshot.contacts) {
      if (contact.id.trim().isEmpty ||
          contact.name.trim().isEmpty ||
          !contactIds.add(contact.id)) {
        throw const FormatException('Legacy contacts contain invalid IDs');
      }
    }
    for (final entry in snapshot.messagesByContact.entries) {
      if (!contactIds.contains(entry.key)) continue;
      final ids = <String>{};
      if (entry.value.any(
        (message) => message.id.trim().isEmpty || !ids.add(message.id),
      )) {
        throw FormatException(
            'Legacy messages contain invalid IDs: ${entry.key}');
      }
    }
  }

  void _verifyEquivalent(ChatSnapshot source, ChatSnapshot restored) {
    final sourceContacts = source.contacts.map((item) => item.id).toSet();
    final restoredContacts = restored.contacts.map((item) => item.id).toSet();
    if (sourceContacts.length != restoredContacts.length ||
        !sourceContacts.containsAll(restoredContacts)) {
      throw const ChatStorageException(
        'verifyMigration',
        'Contact IDs differ after migration',
      );
    }
    for (final contactId in sourceContacts) {
      final sourceIds = (source.messagesByContact[contactId] ?? const [])
          .map((message) => message.id)
          .toList();
      final restoredIds = (restored.messagesByContact[contactId] ?? const [])
          .map((message) => message.id)
          .toList();
      if (sourceIds.length != restoredIds.length) {
        throw ChatStorageException(
          'verifyMigration',
          'Message count differs for $contactId',
        );
      }
      for (var index = 0; index < sourceIds.length; index++) {
        if (sourceIds[index] != restoredIds[index]) {
          throw ChatStorageException(
            'verifyMigration',
            'Message order differs for $contactId',
          );
        }
      }
    }
  }
}
