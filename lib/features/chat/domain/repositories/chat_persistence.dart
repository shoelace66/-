import '../../data/models/contact.dart';
import '../../data/models/message.dart';
import 'conversation_timeline.dart';

class ChatSnapshot {
  const ChatSnapshot({
    this.contacts = const <Contact>[],
    this.messagesByContact = const <String, List<Message>>{},
  });

  final List<Contact> contacts;
  final Map<String, List<Message>> messagesByContact;

  bool get isEmpty =>
      contacts.isEmpty && messagesByContact.values.every((v) => v.isEmpty);
}

/// A chronologically ordered window of messages.
///
/// [startSequence] is the stable sequence of [messages.first] in storage.
/// It equals [totalCount] when the page is empty.
class MessagePage {
  const MessagePage({
    required this.messages,
    required this.startSequence,
    required this.totalCount,
    required this.hasOlder,
  });

  final List<Message> messages;
  final int startSequence;
  final int totalCount;
  final bool hasOlder;
}

class MessageSearchHit {
  const MessageSearchHit({required this.message, required this.sequence});

  final Message message;
  final int sequence;
}

abstract interface class ChatPersistence {
  Future<void> initialize();

  Future<ChatSnapshot> readSnapshot();

  Future<void> replaceSnapshot(ChatSnapshot snapshot);

  Future<void> saveConversation({
    required Contact contact,
    required List<Message> messages,
    Map<String, String> metadataUpdates = const <String, String>{},
  });

  Future<void> deleteConversation(String contactId);

  Future<String?> readMetadata(String key);

  Future<void> writeMetadata(String key, String value);

  Future<void> close();
}

/// Optional large-history capability.
///
/// Keeping this separate from [ChatPersistence] preserves compatibility with
/// lightweight in-memory implementations while allowing the production store
/// to avoid loading every message during application startup.
abstract interface class PaginatedChatPersistence {
  Future<List<Contact>> readContacts();

  Future<MessagePage> readMessagesPage({
    required String contactId,
    int? beforeSequence,
    int limit = 100,
  });

  /// Atomically replaces the loaded tail beginning at [startSequence].
  ///
  /// Rows before [startSequence] remain untouched. This lets the application
  /// edit, retry or recall recent turns without retaining the entire history
  /// in memory.
  Future<void> saveConversationTail({
    required Contact contact,
    required int startSequence,
    required List<Message> messages,
    Map<String, String> metadataUpdates = const <String, String>{},
  });
}

abstract interface class SearchableChatPersistence {
  Future<List<MessageSearchHit>> searchMessages({
    required String contactId,
    required String query,
    int limit = 50,
  });

  Future<List<Message>> readMessageContext({
    required String contactId,
    required int sequence,
    int radius = 2,
  });
}

abstract interface class ConversationTimelinePersistence {
  Future<List<ConversationBranch>> listBranches(String contactId);

  Future<List<ConversationCheckpoint>> listCheckpoints(String contactId);

  Future<ConversationCheckpoint> createCheckpoint({
    required Contact contact,
    required String sourceMessageId,
    String label = '',
    bool isKey = false,
  });

  Future<ConversationBranch> createBranchFromCheckpoint({
    required String checkpointId,
    required String name,
  });

  Future<ConversationBranchSnapshot> switchBranch({
    required String contactId,
    required String branchId,
  });

  Future<void> renameBranch(String branchId, String name);

  Future<void> deleteBranch(String branchId);

  Future<void> setCheckpointKey({
    required String checkpointId,
    required bool isKey,
  });

  Future<ConversationTimelineArchive> readTimelineArchive();

  Future<void> replaceTimelineArchive(ConversationTimelineArchive archive);
}

class ChatStorageException implements Exception {
  const ChatStorageException(this.operation, this.cause);

  final String operation;
  final Object cause;

  @override
  String toString() => 'ChatStorageException($operation): $cause';
}
