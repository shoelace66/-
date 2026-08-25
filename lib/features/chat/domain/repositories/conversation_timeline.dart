import '../../data/models/contact.dart';
import '../../data/models/message.dart';

class ConversationBranch {
  const ConversationBranch({
    required this.id,
    required this.contactId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
    this.parentBranchId,
    this.forkCheckpointId,
    this.isActive = false,
    this.isMain = false,
  });

  final String id;
  final String contactId;
  final String name;
  final String? parentBranchId;
  final String? forkCheckpointId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final bool isActive;
  final bool isMain;
}

class ConversationCheckpoint {
  const ConversationCheckpoint({
    required this.id,
    required this.contactId,
    required this.branchId,
    required this.createdAt,
    required this.messageCount,
    this.sourceMessageId,
    this.label = '',
    this.isKey = false,
  });

  final String id;
  final String contactId;
  final String branchId;
  final String? sourceMessageId;
  final String label;
  final DateTime createdAt;
  final int messageCount;
  final bool isKey;
}

class ConversationBranchSnapshot {
  const ConversationBranchSnapshot({
    required this.branch,
    required this.contact,
    required this.messages,
  });

  final ConversationBranch branch;
  final Contact contact;
  final List<Message> messages;
}

class ConversationCheckpointSnapshot {
  const ConversationCheckpointSnapshot({
    required this.checkpoint,
    required this.contact,
    required this.messages,
  });

  final ConversationCheckpoint checkpoint;
  final Contact contact;
  final List<Message> messages;
}

class ConversationTimelineArchive {
  const ConversationTimelineArchive({
    this.branches = const <ConversationBranchSnapshot>[],
    this.checkpoints = const <ConversationCheckpointSnapshot>[],
  });

  final List<ConversationBranchSnapshot> branches;
  final List<ConversationCheckpointSnapshot> checkpoints;

  bool get isEmpty => branches.isEmpty && checkpoints.isEmpty;
}
