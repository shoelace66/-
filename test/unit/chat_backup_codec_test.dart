import 'dart:io';

import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/message.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/chat_persistence.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/conversation_timeline.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/chat_backup_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = ChatBackupCodec();

  test('备份往返保留消息与事件图，且不包含 API 或设置字段', () {
    final snapshot = ChatSnapshot(
      contacts: <Contact>[
        Contact(
          id: 'role-1',
          name: '林夏',
          avatar: '',
          eventGraph: const EventGraphMemory(turnCount: 7),
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        ),
      ],
      messagesByContact: <String, List<Message>>{
        'role-1': <Message>[
          Message(
            id: 'm1',
            role: MessageRole.user,
            content: '你好',
            createdAt: DateTime.fromMillisecondsSinceEpoch(2),
          ),
        ],
      },
    );

    final encoded = codec.encode(
      snapshot,
      exportedAt: DateTime.utc(2026, 7, 27),
    );
    final restored = codec.decode(encoded);

    expect(encoded, contains('"version":2'));
    expect(encoded, isNot(contains('apiKey')));
    expect(encoded, isNot(contains('providerSettings')));
    expect(restored.contacts.single.eventGraph.turnCount, 7);
    expect(restored.messagesByContact['role-1']?.single.content, '你好');
  });

  test('拒绝未知版本和属于不存在联系人的消息', () {
    expect(
      () => codec.decode(
        '{"format":"ai-roleplay-chat-backup","version":3,"contacts":[],"messagesByContact":{}}',
      ),
      throwsFormatException,
    );
    expect(
      () => codec.decode(
        '{"format":"ai-roleplay-chat-backup","version":1,"contacts":[],"messagesByContact":{"missing":[]}}',
      ),
      throwsFormatException,
    );
  });

  test('固定脱敏备份样本可读取', () async {
    final source = await File('test/chat_backup_v1.json').readAsString();

    final restored = codec.decode(source);

    expect(restored.contacts.single.id, 'fixture-role');
    expect(
        restored.messagesByContact['fixture-role']?.single.content, '固定脱敏备份样本');
  });

  test('v2 备份往返保留分支和检查点', () {
    final contact = Contact(
      id: 'role-1',
      name: '林夏',
      avatar: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    );
    final message = Message(
      id: 'm1',
      role: MessageRole.assistant,
      content: '完成一轮',
      createdAt: DateTime.fromMillisecondsSinceEpoch(2),
    );
    final branch = ConversationBranch(
      id: 'branch-main',
      contactId: contact.id,
      name: '主分支',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
      messageCount: 1,
      isActive: true,
      isMain: true,
    );
    final checkpoint = ConversationCheckpoint(
      id: 'checkpoint-1',
      contactId: contact.id,
      branchId: branch.id,
      sourceMessageId: message.id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(2),
      messageCount: 1,
      isKey: true,
    );

    final encoded = codec.encode(
      ChatSnapshot(
        contacts: <Contact>[contact],
        messagesByContact: <String, List<Message>>{
          contact.id: <Message>[message],
        },
      ),
      timeline: ConversationTimelineArchive(
        branches: <ConversationBranchSnapshot>[
          ConversationBranchSnapshot(
            branch: branch,
            contact: contact,
            messages: <Message>[message],
          ),
        ],
        checkpoints: <ConversationCheckpointSnapshot>[
          ConversationCheckpointSnapshot(
            checkpoint: checkpoint,
            contact: contact,
            messages: <Message>[message],
          ),
        ],
      ),
    );
    final restored = codec.decodeBundle(encoded);

    expect(restored.timeline.branches.single.branch.isActive, isTrue);
    expect(restored.timeline.checkpoints.single.checkpoint.isKey, isTrue);
    expect(restored.timeline.checkpoints.single.messages.single.id, 'm1');
  });
}
