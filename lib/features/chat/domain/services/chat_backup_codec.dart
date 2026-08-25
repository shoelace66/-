import 'dart:convert';

import '../repositories/chat_persistence.dart';
import '../repositories/conversation_timeline.dart';
import '../../data/models/contact.dart';
import '../../data/models/message.dart';

class ChatBackupCodec {
  const ChatBackupCodec();

  static const int currentVersion = 2;
  static const int maxImportBytes = 50 * 1024 * 1024;

  String encode(
    ChatSnapshot snapshot, {
    DateTime? exportedAt,
    ConversationTimelineArchive timeline = const ConversationTimelineArchive(),
  }) {
    final payload = <String, dynamic>{
      'format': 'ai-roleplay-chat-backup',
      'version': currentVersion,
      'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'contacts': snapshot.contacts.map((contact) => contact.toJson()).toList(),
      'messagesByContact': <String, dynamic>{
        for (final entry in snapshot.messagesByContact.entries)
          entry.key: entry.value.map((message) => message.toJson()).toList(),
      },
      'timeline': _encodeTimeline(timeline),
    };
    return jsonEncode(payload);
  }

  ChatSnapshot decode(String source) {
    return decodeBundle(source).snapshot;
  }

  ChatBackupBundle decodeBundle(String source) {
    if (utf8.encode(source).length > maxImportBytes) {
      throw const FormatException('Backup exceeds 50 MB import limit');
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Backup root must be an object');
    }
    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (json['format'] != 'ai-roleplay-chat-backup') {
      throw const FormatException('Unknown backup format');
    }
    final version = json['version'];
    if (version is! num ||
        version.toInt() < 1 ||
        version.toInt() > currentVersion) {
      throw FormatException('Unsupported backup version: $version');
    }

    final contacts = <Contact>[];
    final contactIds = <String>{};
    final rawContacts = json['contacts'];
    if (rawContacts is! List) {
      throw const FormatException('contacts must be a list');
    }
    for (final raw in rawContacts) {
      if (raw is! Map) throw const FormatException('Invalid contact entry');
      final contact = Contact.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (contact.id.trim().isEmpty ||
          contact.name.trim().isEmpty ||
          !contactIds.add(contact.id)) {
        throw const FormatException('Invalid or duplicate contact ID');
      }
      contacts.add(contact);
    }

    final messages = <String, List<Message>>{};
    final rawMessages = json['messagesByContact'];
    if (rawMessages is! Map) {
      throw const FormatException('messagesByContact must be an object');
    }
    for (final entry in rawMessages.entries) {
      final contactId = entry.key.toString();
      if (!contactIds.contains(contactId) || entry.value is! List) {
        throw FormatException('Invalid message owner: $contactId');
      }
      final messageIds = <String>{};
      final list = <Message>[];
      for (final raw in entry.value as List) {
        if (raw is! Map) throw const FormatException('Invalid message entry');
        final message = Message.fromJson(
          raw.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (message.id.trim().isEmpty || !messageIds.add(message.id)) {
          throw FormatException('Invalid or duplicate message ID: $contactId');
        }
        list.add(message);
      }
      messages[contactId] = list;
    }
    final snapshot = ChatSnapshot(
      contacts: contacts,
      messagesByContact: messages,
    );
    final timeline = version.toInt() >= 2
        ? _decodeTimeline(json['timeline'], contactIds)
        : const ConversationTimelineArchive();
    return ChatBackupBundle(snapshot: snapshot, timeline: timeline);
  }

  Map<String, dynamic> _encodeTimeline(ConversationTimelineArchive archive) {
    return <String, dynamic>{
      'branches': <Map<String, dynamic>>[
        for (final snapshot in archive.branches)
          <String, dynamic>{
            'id': snapshot.branch.id,
            'contactId': snapshot.branch.contactId,
            'name': snapshot.branch.name,
            'parentBranchId': snapshot.branch.parentBranchId,
            'forkCheckpointId': snapshot.branch.forkCheckpointId,
            'createdAt': snapshot.branch.createdAt.toUtc().toIso8601String(),
            'updatedAt': snapshot.branch.updatedAt.toUtc().toIso8601String(),
            'isActive': snapshot.branch.isActive,
            'isMain': snapshot.branch.isMain,
            'contact': snapshot.contact.toJson(),
            'messages':
                snapshot.messages.map((message) => message.toJson()).toList(),
          },
      ],
      'checkpoints': <Map<String, dynamic>>[
        for (final snapshot in archive.checkpoints)
          <String, dynamic>{
            'id': snapshot.checkpoint.id,
            'contactId': snapshot.checkpoint.contactId,
            'branchId': snapshot.checkpoint.branchId,
            'sourceMessageId': snapshot.checkpoint.sourceMessageId,
            'label': snapshot.checkpoint.label,
            'createdAt':
                snapshot.checkpoint.createdAt.toUtc().toIso8601String(),
            'isKey': snapshot.checkpoint.isKey,
            'contact': snapshot.contact.toJson(),
            'messages':
                snapshot.messages.map((message) => message.toJson()).toList(),
          },
      ],
    };
  }

  ConversationTimelineArchive _decodeTimeline(
    Object? raw,
    Set<String> contactIds,
  ) {
    if (raw is! Map) {
      throw const FormatException('timeline must be an object');
    }
    final timeline = raw.map((key, value) => MapEntry(key.toString(), value));
    final rawBranches = timeline['branches'];
    final rawCheckpoints = timeline['checkpoints'];
    if (rawBranches is! List || rawCheckpoints is! List) {
      throw const FormatException('Invalid timeline collections');
    }
    final branches = <ConversationBranchSnapshot>[];
    final branchIds = <String>{};
    for (final value in rawBranches) {
      if (value is! Map) throw const FormatException('Invalid branch entry');
      final item = value.map((key, value) => MapEntry(key.toString(), value));
      final id = (item['id'] ?? '').toString();
      final contactId = (item['contactId'] ?? '').toString();
      if (id.isEmpty || !branchIds.add(id) || !contactIds.contains(contactId)) {
        throw const FormatException('Invalid branch identity');
      }
      final contact = _decodeContactSnapshot(item['contact'], contactId);
      final branchMessages = _decodeMessages(item['messages']);
      branches.add(ConversationBranchSnapshot(
        branch: ConversationBranch(
          id: id,
          contactId: contactId,
          name: (item['name'] ?? '').toString(),
          parentBranchId: item['parentBranchId']?.toString(),
          forkCheckpointId: item['forkCheckpointId']?.toString(),
          createdAt: DateTime.parse(item['createdAt'].toString()),
          updatedAt: DateTime.parse(item['updatedAt'].toString()),
          messageCount: branchMessages.length,
          isActive: item['isActive'] == true,
          isMain: item['isMain'] == true,
        ),
        contact: contact,
        messages: branchMessages,
      ));
    }
    final checkpoints = <ConversationCheckpointSnapshot>[];
    final checkpointIds = <String>{};
    for (final value in rawCheckpoints) {
      if (value is! Map) {
        throw const FormatException('Invalid checkpoint entry');
      }
      final item = value.map((key, value) => MapEntry(key.toString(), value));
      final id = (item['id'] ?? '').toString();
      final contactId = (item['contactId'] ?? '').toString();
      final branchId = (item['branchId'] ?? '').toString();
      if (id.isEmpty ||
          !checkpointIds.add(id) ||
          !contactIds.contains(contactId) ||
          !branchIds.contains(branchId)) {
        throw const FormatException('Invalid checkpoint identity');
      }
      final contact = _decodeContactSnapshot(item['contact'], contactId);
      final checkpointMessages = _decodeMessages(item['messages']);
      checkpoints.add(ConversationCheckpointSnapshot(
        checkpoint: ConversationCheckpoint(
          id: id,
          contactId: contactId,
          branchId: branchId,
          sourceMessageId: item['sourceMessageId']?.toString(),
          label: (item['label'] ?? '').toString(),
          createdAt: DateTime.parse(item['createdAt'].toString()),
          messageCount: checkpointMessages.length,
          isKey: item['isKey'] == true,
        ),
        contact: contact,
        messages: checkpointMessages,
      ));
    }
    return ConversationTimelineArchive(
      branches: branches,
      checkpoints: checkpoints,
    );
  }

  Contact _decodeContactSnapshot(Object? raw, String contactId) {
    if (raw is! Map) throw const FormatException('Invalid contact snapshot');
    final contact = Contact.fromJson(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
    if (contact.id != contactId) {
      throw const FormatException('Snapshot contact mismatch');
    }
    return contact;
  }

  List<Message> _decodeMessages(Object? raw) {
    if (raw is! List) throw const FormatException('Invalid snapshot messages');
    return <Message>[
      for (final value in raw)
        if (value is Map)
          Message.fromJson(
            value.map((key, value) => MapEntry(key.toString(), value)),
          )
        else
          throw const FormatException('Invalid snapshot message'),
    ];
  }
}

class ChatBackupBundle {
  const ChatBackupBundle({
    required this.snapshot,
    required this.timeline,
  });

  final ChatSnapshot snapshot;
  final ConversationTimelineArchive timeline;
}
