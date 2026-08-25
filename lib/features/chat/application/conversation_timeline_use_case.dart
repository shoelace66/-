import '../data/models/contact.dart';
import '../domain/repositories/chat_persistence.dart';
import '../domain/repositories/conversation_timeline.dart';

class ConversationTimelineState {
  ConversationTimelineState({
    required List<ConversationBranch> branches,
    required List<ConversationCheckpoint> checkpoints,
  })  : branches = List<ConversationBranch>.unmodifiable(branches),
        checkpoints = List<ConversationCheckpoint>.unmodifiable(checkpoints);

  final List<ConversationBranch> branches;
  final List<ConversationCheckpoint> checkpoints;
}

class ConversationTimelineUseCase {
  const ConversationTimelineUseCase(this.persistence);

  final ChatPersistence persistence;

  ConversationTimelinePersistence? get _timeline =>
      persistence is ConversationTimelinePersistence
          ? persistence as ConversationTimelinePersistence
          : null;

  bool get isAvailable => _timeline != null;

  Future<ConversationTimelineState> load(String contactId) async {
    final timeline = _timeline;
    if (timeline == null) {
      return ConversationTimelineState(
          branches: const [], checkpoints: const []);
    }
    final results = await Future.wait<Object>([
      timeline.listBranches(contactId),
      timeline.listCheckpoints(contactId),
    ]);
    return ConversationTimelineState(
      branches: results[0] as List<ConversationBranch>,
      checkpoints: results[1] as List<ConversationCheckpoint>,
    );
  }

  Future<ConversationCheckpoint?> createCheckpoint({
    required Contact contact,
    required String sourceMessageId,
    required String label,
    bool isKey = false,
  }) {
    final timeline = _timeline;
    if (timeline == null) return Future.value();
    return timeline.createCheckpoint(
      contact: contact,
      sourceMessageId: sourceMessageId,
      label: label,
      isKey: isKey,
    );
  }

  Future<ConversationBranch?> createBranch({
    required String checkpointId,
    required String name,
  }) {
    final timeline = _timeline;
    if (timeline == null) return Future.value();
    return timeline.createBranchFromCheckpoint(
      checkpointId: checkpointId,
      name: name,
    );
  }

  Future<ConversationBranchSnapshot?> switchBranch({
    required String contactId,
    required String branchId,
  }) {
    final timeline = _timeline;
    if (timeline == null) return Future.value();
    return timeline.switchBranch(contactId: contactId, branchId: branchId);
  }

  Future<void> renameBranch(String branchId, String name) async {
    await _timeline?.renameBranch(branchId, name);
  }

  Future<void> deleteBranch(String branchId) async {
    await _timeline?.deleteBranch(branchId);
  }

  Future<void> setCheckpointKey(String checkpointId, bool isKey) async {
    await _timeline?.setCheckpointKey(
      checkpointId: checkpointId,
      isKey: isKey,
    );
  }

  Future<ConversationTimelineArchive> exportArchive() async {
    return await _timeline?.readTimelineArchive() ??
        const ConversationTimelineArchive();
  }

  Future<void> restoreArchive(ConversationTimelineArchive archive) async {
    await _timeline?.replaceTimelineArchive(archive);
  }
}
