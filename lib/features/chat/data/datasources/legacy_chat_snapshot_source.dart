import '../../domain/repositories/chat_persistence.dart';
import 'chat_local_storage.dart';

abstract interface class LegacyChatSnapshotSource {
  Future<ChatSnapshot> readSnapshot();
}

class SharedPreferencesLegacyChatSnapshotSource
    implements LegacyChatSnapshotSource {
  SharedPreferencesLegacyChatSnapshotSource(this._store);

  final ChatAgentStore _store;

  @override
  Future<ChatSnapshot> readSnapshot() async {
    return ChatSnapshot(
      contacts: await _store.readContacts(),
      messagesByContact: await _store.readMessagesByContact(),
    );
  }
}
