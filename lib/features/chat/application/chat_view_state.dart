import '../data/models/contact.dart';
import '../data/models/message.dart';
import '../domain/repositories/conversation_timeline.dart';
import '../domain/services/heartbeat_manager.dart';

enum ChatInitializationStatus { initial, loading, ready, failure }

enum ChatGenerationStatus {
  idle,
  preparing,
  streaming,
  completed,
  cancelled,
  failure,
}

class ChatInitializationFailure implements Exception {
  const ChatInitializationFailure(this.module, this.cause);

  final String module;
  final Object cause;

  @override
  String toString() => '$module 初始化失败：$cause';
}

class ChatInitializationState {
  const ChatInitializationState._(
    this.status, {
    this.module,
    this.message,
  });

  const ChatInitializationState.initial()
      : this._(ChatInitializationStatus.initial);
  const ChatInitializationState.loading()
      : this._(ChatInitializationStatus.loading);
  const ChatInitializationState.ready()
      : this._(ChatInitializationStatus.ready);
  const ChatInitializationState.failure({
    required String module,
    required String message,
  }) : this._(
          ChatInitializationStatus.failure,
          module: module,
          message: message,
        );

  final ChatInitializationStatus status;
  final String? module;
  final String? message;

  bool get isReady => status == ChatInitializationStatus.ready;
}

class ChatViewState {
  ChatViewState({
    required this.initialization,
    required List<Contact> contacts,
    required List<Message> messages,
    required List<ConversationBranch> branches,
    required List<ConversationCheckpoint> checkpoints,
    required this.selectedContactId,
    required this.selectedContact,
    required this.isLoading,
    required this.isTyping,
    required this.isLoadingOlderMessages,
    required this.hasOlderMessages,
    required this.totalMessageCount,
    required this.isDebugMode,
    required this.canCancelGeneration,
    required this.canRecall,
    required this.canRegenerateLastTurn,
    required this.error,
    required this.connectionStatus,
    required this.generationStatus,
  })  : contacts = List<Contact>.unmodifiable(contacts),
        messages = List<Message>.unmodifiable(messages),
        branches = List<ConversationBranch>.unmodifiable(branches),
        checkpoints = List<ConversationCheckpoint>.unmodifiable(checkpoints);

  final ChatInitializationState initialization;
  final List<Contact> contacts;
  final List<Message> messages;
  final List<ConversationBranch> branches;
  final List<ConversationCheckpoint> checkpoints;
  final String? selectedContactId;
  final Contact? selectedContact;
  final bool isLoading;
  final bool isTyping;
  final bool isLoadingOlderMessages;
  final bool hasOlderMessages;
  final int totalMessageCount;
  final bool isDebugMode;
  final bool canCancelGeneration;
  final bool canRecall;
  final bool canRegenerateLastTurn;
  final String? error;
  final ConnectionStatus connectionStatus;
  final ChatGenerationStatus generationStatus;
}
