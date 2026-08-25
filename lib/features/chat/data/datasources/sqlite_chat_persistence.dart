import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/chat_persistence.dart';
import '../../domain/repositories/conversation_timeline.dart';
import '../models/contact.dart';
import '../models/message.dart';

class SqliteChatPersistence
    implements
        ChatPersistence,
        PaginatedChatPersistence,
        SearchableChatPersistence,
        ConversationTimelinePersistence {
  SqliteChatPersistence({
    DatabaseFactory? databaseFactory,
    String? databasePath,
  })  : _factory = databaseFactory ?? databaseFactorySqflitePlugin,
        _databasePath = databasePath;

  static const int schemaVersion = 3;
  static const String defaultDatabaseName = 'ai_roleplay_chat.db';

  final DatabaseFactory _factory;
  final String? _databasePath;
  Database? _database;

  @override
  Future<void> initialize() async {
    if (_database?.isOpen == true) return;
    try {
      final dbPath = _databasePath ??
          path.join(await _factory.getDatabasesPath(), defaultDatabaseName);
      _database = await _factory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) => _createSchema(db),
          onUpgrade: _upgradeSchema,
        ),
      );
    } catch (error) {
      throw ChatStorageException('initialize', error);
    }
  }

  Database get _db {
    final database = _database;
    if (database == null || !database.isOpen) {
      throw StateError('SqliteChatPersistence.initialize() has not completed');
    }
    return database;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE contacts (
  id TEXT PRIMARY KEY,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
    await db.execute('''
CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  contact_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY(contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  UNIQUE(contact_id, sequence)
)
''');
    await db.execute(
      'CREATE INDEX idx_messages_contact_sequence '
      'ON messages(contact_id, sequence)',
    );
    await db.execute('''
CREATE TABLE event_nodes (
  id TEXT PRIMARY KEY,
  contact_id TEXT NOT NULL,
  tier TEXT NOT NULL,
  position INTEGER NOT NULL,
  event_payload TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  summarized INTEGER NOT NULL DEFAULT 0,
  invalidated INTEGER NOT NULL DEFAULT 0,
  needs_review INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  UNIQUE(contact_id, tier, position)
)
''');
    await db.execute(
      'CREATE INDEX idx_event_nodes_contact_tier_position '
      'ON event_nodes(contact_id, tier, position)',
    );
    await db.execute('''
CREATE TABLE event_edges (
  contact_id TEXT NOT NULL,
  from_node_id TEXT NOT NULL,
  to_node_id TEXT NOT NULL,
  FOREIGN KEY(contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  PRIMARY KEY(contact_id, from_node_id, to_node_id)
)
''');
    await db.execute('''
CREATE TABLE event_relations (
  contact_id TEXT NOT NULL,
  relation_type TEXT NOT NULL,
  relation_key TEXT NOT NULL,
  event_node_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  FOREIGN KEY(contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  PRIMARY KEY(contact_id, relation_type, relation_key, event_node_id)
)
''');
    await db.execute(
      'CREATE INDEX idx_event_relations_lookup '
      'ON event_relations(contact_id, relation_type, relation_key, position)',
    );
    await db.execute('''
CREATE TABLE memory_meta (
  contact_id TEXT PRIMARY KEY,
  turn_count INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(contact_id) REFERENCES contacts(id) ON DELETE CASCADE
)
''');
    await db.execute('''
CREATE TABLE app_meta (
  meta_key TEXT PRIMARY KEY,
  meta_value TEXT NOT NULL
)
''');
    await _createTimelineSchema(db);
  }

  Future<void> _createTimelineSchema(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS conversation_branches (
  id TEXT PRIMARY KEY,
  contact_id TEXT NOT NULL,
  name TEXT NOT NULL,
  parent_branch_id TEXT,
  fork_checkpoint_id TEXT,
  contact_payload TEXT NOT NULL,
  messages_payload TEXT NOT NULL,
  message_count INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 0,
  is_main INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(contact_id) REFERENCES contacts(id) ON DELETE CASCADE
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_branches_contact_updated '
      'ON conversation_branches(contact_id, updated_at DESC)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_branches_one_active '
      'ON conversation_branches(contact_id) WHERE is_active = 1',
    );
    await db.execute('''
CREATE TABLE IF NOT EXISTS conversation_checkpoints (
  id TEXT PRIMARY KEY,
  contact_id TEXT NOT NULL,
  branch_id TEXT NOT NULL,
  source_message_id TEXT,
  label TEXT NOT NULL,
  contact_payload TEXT NOT NULL,
  messages_payload TEXT NOT NULL,
  message_count INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  is_key INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  FOREIGN KEY(branch_id) REFERENCES conversation_branches(id) ON DELETE CASCADE
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_checkpoints_contact_created '
      'ON conversation_checkpoints(contact_id, created_at DESC)',
    );
  }

  Future<void> _upgradeSchema(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE event_nodes ADD COLUMN invalidated INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE event_nodes ADD COLUMN needs_review INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await _createTimelineSchema(db);
    }
  }

  @override
  Future<ChatSnapshot> readSnapshot() async {
    try {
      final contacts = await readContacts();
      final messages = <String, List<Message>>{};
      final messageRows = await _db.query(
        'messages',
        orderBy: 'contact_id ASC, sequence ASC',
      );
      for (final row in messageRows) {
        final contactId = row['contact_id'] as String;
        messages.putIfAbsent(contactId, () => <Message>[]).add(
              Message.fromJson(_decodeMap(row['payload'])),
            );
      }
      return ChatSnapshot(contacts: contacts, messagesByContact: messages);
    } catch (error) {
      throw ChatStorageException('readSnapshot', error);
    }
  }

  @override
  Future<List<Contact>> readContacts() async {
    try {
      final contactRows =
          await _db.query('contacts', orderBy: 'created_at ASC');
      final contacts = <Contact>[];
      for (final row in contactRows) {
        final base = _decodeMap(row['payload']);
        final graph = await _readGraph(row['id'] as String);
        base['eventGraph'] = graph.toJson();
        contacts.add(Contact.fromJson(base));
      }
      return contacts;
    } catch (error) {
      throw ChatStorageException('readContacts', error);
    }
  }

  @override
  Future<MessagePage> readMessagesPage({
    required String contactId,
    int? beforeSequence,
    int limit = 100,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be greater than zero');
    }
    try {
      final totalCount = Sqflite.firstIntValue(await _db.rawQuery(
            'SELECT COUNT(*) FROM messages WHERE contact_id = ?',
            <Object?>[contactId],
          )) ??
          0;
      final rows = await _db.query(
        'messages',
        columns: <String>['sequence', 'payload'],
        where: beforeSequence == null
            ? 'contact_id = ?'
            : 'contact_id = ? AND sequence < ?',
        whereArgs: beforeSequence == null
            ? <Object?>[contactId]
            : <Object?>[contactId, beforeSequence],
        orderBy: 'sequence DESC',
        limit: limit,
      );
      final orderedRows = rows.reversed.toList(growable: false);
      final messages = <Message>[
        for (final row in orderedRows)
          Message.fromJson(_decodeMap(row['payload'])),
      ];
      final startSequence = orderedRows.isEmpty
          ? (beforeSequence ?? totalCount)
          : orderedRows.first['sequence'] as int;
      return MessagePage(
        messages: messages,
        startSequence: startSequence,
        totalCount: totalCount,
        hasOlder: orderedRows.isNotEmpty && startSequence > 0,
      );
    } catch (error) {
      if (error is ArgumentError) rethrow;
      throw ChatStorageException('readMessagesPage', error);
    }
  }

  @override
  Future<List<MessageSearchHit>> searchMessages({
    required String contactId,
    required String query,
    int limit = 50,
  }) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty || limit <= 0) return const <MessageSearchHit>[];
    try {
      final rows = await _db.rawQuery(
        'SELECT sequence, payload FROM messages '
        'WHERE contact_id = ? AND instr(lower(payload), ?) > 0 '
        'ORDER BY sequence DESC LIMIT ?',
        <Object?>[contactId, normalized, limit * 4],
      );
      final results = <MessageSearchHit>[];
      for (final row in rows) {
        final message = Message.fromJson(_decodeMap(row['payload']));
        if (!message.content.toLowerCase().contains(normalized)) continue;
        results.add(
          MessageSearchHit(
            message: message,
            sequence: row['sequence'] as int,
          ),
        );
        if (results.length == limit) break;
      }
      return results;
    } catch (error) {
      throw ChatStorageException('searchMessages', error);
    }
  }

  @override
  Future<List<Message>> readMessageContext({
    required String contactId,
    required int sequence,
    int radius = 2,
  }) async {
    if (radius < 0) throw ArgumentError.value(radius, 'radius');
    try {
      final rows = await _db.query(
        'messages',
        columns: <String>['payload'],
        where: 'contact_id = ? AND sequence BETWEEN ? AND ?',
        whereArgs: <Object?>[contactId, sequence - radius, sequence + radius],
        orderBy: 'sequence ASC',
      );
      return <Message>[
        for (final row in rows) Message.fromJson(_decodeMap(row['payload'])),
      ];
    } catch (error) {
      if (error is ArgumentError) rethrow;
      throw ChatStorageException('readMessageContext', error);
    }
  }

  @override
  Future<void> replaceSnapshot(ChatSnapshot snapshot) async {
    try {
      await _db.transaction((txn) async {
        await txn.delete('contacts');
        for (final contact in snapshot.contacts) {
          await _writeContact(txn, contact);
          await _writeMessages(
            txn,
            contact.id,
            snapshot.messagesByContact[contact.id] ?? const <Message>[],
          );
          await _syncActiveBranchSnapshot(txn, contact);
        }
      });
    } catch (error) {
      throw ChatStorageException('replaceSnapshot', error);
    }
  }

  @override
  Future<void> saveConversation({
    required Contact contact,
    required List<Message> messages,
    Map<String, String> metadataUpdates = const <String, String>{},
  }) async {
    try {
      await _db.transaction((txn) async {
        await _writeContact(txn, contact);
        await _writeMessages(txn, contact.id, messages);
        await _syncActiveBranchSnapshot(txn, contact);
        for (final entry in metadataUpdates.entries) {
          await txn.insert(
            'app_meta',
            <String, Object?>{
              'meta_key': entry.key,
              'meta_value': entry.value,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (error) {
      throw ChatStorageException('saveConversation', error);
    }
  }

  @override
  Future<void> saveConversationTail({
    required Contact contact,
    required int startSequence,
    required List<Message> messages,
    Map<String, String> metadataUpdates = const <String, String>{},
  }) async {
    if (startSequence < 0) {
      throw ArgumentError.value(
        startSequence,
        'startSequence',
        'must not be negative',
      );
    }
    try {
      await _db.transaction((txn) async {
        await _writeContact(txn, contact);
        await txn.delete(
          'messages',
          where: 'contact_id = ? AND sequence >= ?',
          whereArgs: <Object?>[contact.id, startSequence],
        );
        await _writeMessageRows(
          txn,
          contact.id,
          messages,
          startSequence: startSequence,
        );
        await _syncActiveBranchSnapshot(txn, contact);
        for (final entry in metadataUpdates.entries) {
          await txn.insert(
            'app_meta',
            <String, Object?>{
              'meta_key': entry.key,
              'meta_value': entry.value,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (error) {
      if (error is ArgumentError) rethrow;
      throw ChatStorageException('saveConversationTail', error);
    }
  }

  Future<List<Message>> _readMessages(
    DatabaseExecutor db,
    String contactId,
  ) async {
    final rows = await db.query(
      'messages',
      columns: <String>['payload'],
      where: 'contact_id = ?',
      whereArgs: <Object?>[contactId],
      orderBy: 'sequence ASC',
    );
    return <Message>[
      for (final row in rows) Message.fromJson(_decodeMap(row['payload'])),
    ];
  }

  Future<Contact> _readContact(
    DatabaseExecutor db,
    String contactId,
  ) async {
    final rows = await db.query(
      'contacts',
      columns: <String>['payload'],
      where: 'id = ?',
      whereArgs: <Object?>[contactId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Contact not found: $contactId');
    final payload = _decodeMap(rows.first['payload']);
    payload['eventGraph'] = (await _readGraph(contactId, db)).toJson();
    return Contact.fromJson(payload);
  }

  Future<String> _syncActiveBranchSnapshot(
    DatabaseExecutor db,
    Contact contact,
  ) async {
    final messages = await _readMessages(db, contact.id);
    final activeRows = await db.query(
      'conversation_branches',
      columns: <String>['id'],
      where: 'contact_id = ? AND is_active = 1',
      whereArgs: <Object?>[contact.id],
      limit: 1,
    );
    var branchId = activeRows.isEmpty ? '' : activeRows.first['id'] as String;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (branchId.isEmpty) {
      final mainRows = await db.query(
        'conversation_branches',
        columns: <String>['id'],
        where: 'contact_id = ? AND is_main = 1',
        whereArgs: <Object?>[contact.id],
        limit: 1,
      );
      branchId = mainRows.isEmpty
          ? 'branch-main-${contact.id}'
          : mainRows.first['id'] as String;
      if (mainRows.isEmpty) {
        await db.insert('conversation_branches', <String, Object?>{
          'id': branchId,
          'contact_id': contact.id,
          'name': '主分支',
          'parent_branch_id': null,
          'fork_checkpoint_id': null,
          'contact_payload': jsonEncode(contact.toJson()),
          'messages_payload': jsonEncode(
            messages.map((message) => message.toJson()).toList(),
          ),
          'message_count': messages.length,
          'created_at': now,
          'updated_at': now,
          'is_active': 1,
          'is_main': 1,
        });
      } else {
        await db.update(
          'conversation_branches',
          <String, Object?>{'is_active': 1},
          where: 'id = ?',
          whereArgs: <Object?>[branchId],
        );
      }
    }
    await db.update(
      'conversation_branches',
      <String, Object?>{
        'contact_payload': jsonEncode(contact.toJson()),
        'messages_payload': jsonEncode(
          messages.map((message) => message.toJson()).toList(),
        ),
        'message_count': messages.length,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: <Object?>[branchId],
    );
    return branchId;
  }

  ConversationBranch _branchFromRow(Map<String, Object?> row) {
    return ConversationBranch(
      id: row['id'] as String,
      contactId: row['contact_id'] as String,
      name: row['name'] as String,
      parentBranchId: row['parent_branch_id'] as String?,
      forkCheckpointId: row['fork_checkpoint_id'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      messageCount: row['message_count'] as int,
      isActive: row['is_active'] == 1,
      isMain: row['is_main'] == 1,
    );
  }

  ConversationCheckpoint _checkpointFromRow(Map<String, Object?> row) {
    return ConversationCheckpoint(
      id: row['id'] as String,
      contactId: row['contact_id'] as String,
      branchId: row['branch_id'] as String,
      sourceMessageId: row['source_message_id'] as String?,
      label: row['label'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      messageCount: row['message_count'] as int,
      isKey: row['is_key'] == 1,
    );
  }

  List<Message> _messagesFromPayload(Object? raw) {
    final decoded = jsonDecode(raw as String);
    if (decoded is! List) {
      throw const FormatException('messages payload must be a list');
    }
    return <Message>[
      for (final value in decoded)
        Message.fromJson(Map<String, dynamic>.from(value as Map)),
    ];
  }

  @override
  Future<List<ConversationBranch>> listBranches(String contactId) async {
    try {
      await _db.transaction((txn) async {
        final contact = await _readContact(txn, contactId);
        await _syncActiveBranchSnapshot(txn, contact);
      });
      final rows = await _db.query(
        'conversation_branches',
        where: 'contact_id = ?',
        whereArgs: <Object?>[contactId],
        orderBy: 'is_main DESC, created_at ASC',
      );
      return rows.map(_branchFromRow).toList(growable: false);
    } catch (error) {
      throw ChatStorageException('listBranches', error);
    }
  }

  @override
  Future<List<ConversationCheckpoint>> listCheckpoints(String contactId) async {
    try {
      final rows = await _db.query(
        'conversation_checkpoints',
        where: 'contact_id = ?',
        whereArgs: <Object?>[contactId],
        orderBy: 'created_at DESC',
      );
      return rows.map(_checkpointFromRow).toList(growable: false);
    } catch (error) {
      throw ChatStorageException('listCheckpoints', error);
    }
  }

  @override
  Future<ConversationCheckpoint> createCheckpoint({
    required Contact contact,
    required String sourceMessageId,
    String label = '',
    bool isKey = false,
  }) async {
    try {
      late ConversationCheckpoint checkpoint;
      await _db.transaction((txn) async {
        final branchId = await _syncActiveBranchSnapshot(txn, contact);
        final branchRows = await txn.query(
          'conversation_branches',
          where: 'id = ?',
          whereArgs: <Object?>[branchId],
          limit: 1,
        );
        final branch = branchRows.single;
        final now = DateTime.now().millisecondsSinceEpoch;
        final id = 'checkpoint-${DateTime.now().microsecondsSinceEpoch}';
        final values = <String, Object?>{
          'id': id,
          'contact_id': contact.id,
          'branch_id': branchId,
          'source_message_id': sourceMessageId,
          'label': label.trim(),
          'contact_payload': branch['contact_payload'],
          'messages_payload': branch['messages_payload'],
          'message_count': branch['message_count'],
          'created_at': now,
          'is_key': isKey ? 1 : 0,
        };
        await txn.insert('conversation_checkpoints', values);
        checkpoint = _checkpointFromRow(values);

        final staleRows = await txn.rawQuery('''
SELECT id FROM conversation_checkpoints
WHERE contact_id = ? AND is_key = 0
ORDER BY created_at DESC
LIMIT -1 OFFSET 200
''', <Object?>[contact.id]);
        for (final row in staleRows) {
          await txn.delete(
            'conversation_checkpoints',
            where: 'id = ?',
            whereArgs: <Object?>[row['id']],
          );
        }
      });
      return checkpoint;
    } catch (error) {
      throw ChatStorageException('createCheckpoint', error);
    }
  }

  @override
  Future<ConversationBranch> createBranchFromCheckpoint({
    required String checkpointId,
    required String name,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    try {
      late ConversationBranch branch;
      await _db.transaction((txn) async {
        final checkpointRows = await txn.query(
          'conversation_checkpoints',
          where: 'id = ?',
          whereArgs: <Object?>[checkpointId],
          limit: 1,
        );
        if (checkpointRows.isEmpty) {
          throw StateError('Checkpoint not found: $checkpointId');
        }
        final checkpoint = checkpointRows.single;
        final now = DateTime.now().millisecondsSinceEpoch;
        final id = 'branch-${DateTime.now().microsecondsSinceEpoch}';
        final values = <String, Object?>{
          'id': id,
          'contact_id': checkpoint['contact_id'],
          'name': normalizedName,
          'parent_branch_id': checkpoint['branch_id'],
          'fork_checkpoint_id': checkpointId,
          'contact_payload': checkpoint['contact_payload'],
          'messages_payload': checkpoint['messages_payload'],
          'message_count': checkpoint['message_count'],
          'created_at': now,
          'updated_at': now,
          'is_active': 0,
          'is_main': 0,
        };
        await txn.insert('conversation_branches', values);
        branch = _branchFromRow(values);
      });
      return branch;
    } catch (error) {
      if (error is ArgumentError) rethrow;
      throw ChatStorageException('createBranchFromCheckpoint', error);
    }
  }

  @override
  Future<ConversationBranchSnapshot> switchBranch({
    required String contactId,
    required String branchId,
  }) async {
    try {
      late ConversationBranchSnapshot snapshot;
      await _db.transaction((txn) async {
        final currentContact = await _readContact(txn, contactId);
        await _syncActiveBranchSnapshot(txn, currentContact);
        final rows = await txn.query(
          'conversation_branches',
          where: 'id = ? AND contact_id = ?',
          whereArgs: <Object?>[branchId, contactId],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('Branch not found: $branchId');
        final row = rows.single;
        final contact = Contact.fromJson(_decodeMap(row['contact_payload']));
        final messages = _messagesFromPayload(row['messages_payload']);
        await _writeContact(txn, contact);
        await _writeMessages(txn, contactId, messages);
        await txn.update(
          'conversation_branches',
          <String, Object?>{'is_active': 0},
          where: 'contact_id = ?',
          whereArgs: <Object?>[contactId],
        );
        await txn.update(
          'conversation_branches',
          <String, Object?>{
            'is_active': 1,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: <Object?>[branchId],
        );
        final updatedRow = Map<String, Object?>.from(row)
          ..['is_active'] = 1
          ..['updated_at'] = DateTime.now().millisecondsSinceEpoch;
        snapshot = ConversationBranchSnapshot(
          branch: _branchFromRow(updatedRow),
          contact: contact,
          messages: messages,
        );
      });
      return snapshot;
    } catch (error) {
      throw ChatStorageException('switchBranch', error);
    }
  }

  @override
  Future<void> renameBranch(String branchId, String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    try {
      final updated = await _db.update(
        'conversation_branches',
        <String, Object?>{
          'name': normalized,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[branchId],
      );
      if (updated == 0) throw StateError('Branch not found: $branchId');
    } catch (error) {
      if (error is ArgumentError) rethrow;
      throw ChatStorageException('renameBranch', error);
    }
  }

  @override
  Future<void> deleteBranch(String branchId) async {
    try {
      final rows = await _db.query(
        'conversation_branches',
        columns: <String>['is_main', 'is_active'],
        where: 'id = ?',
        whereArgs: <Object?>[branchId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Branch not found: $branchId');
      if (rows.single['is_main'] == 1 || rows.single['is_active'] == 1) {
        throw StateError('Main or active branch cannot be deleted');
      }
      await _db.delete(
        'conversation_branches',
        where: 'id = ?',
        whereArgs: <Object?>[branchId],
      );
    } catch (error) {
      throw ChatStorageException('deleteBranch', error);
    }
  }

  @override
  Future<void> setCheckpointKey({
    required String checkpointId,
    required bool isKey,
  }) async {
    try {
      final updated = await _db.update(
        'conversation_checkpoints',
        <String, Object?>{'is_key': isKey ? 1 : 0},
        where: 'id = ?',
        whereArgs: <Object?>[checkpointId],
      );
      if (updated == 0) {
        throw StateError('Checkpoint not found: $checkpointId');
      }
    } catch (error) {
      throw ChatStorageException('setCheckpointKey', error);
    }
  }

  @override
  Future<ConversationTimelineArchive> readTimelineArchive() async {
    try {
      final branchRows = await _db.query(
        'conversation_branches',
        orderBy: 'contact_id ASC, created_at ASC',
      );
      final checkpointRows = await _db.query(
        'conversation_checkpoints',
        orderBy: 'contact_id ASC, created_at ASC',
      );
      return ConversationTimelineArchive(
        branches: <ConversationBranchSnapshot>[
          for (final row in branchRows)
            ConversationBranchSnapshot(
              branch: _branchFromRow(row),
              contact: Contact.fromJson(_decodeMap(row['contact_payload'])),
              messages: _messagesFromPayload(row['messages_payload']),
            ),
        ],
        checkpoints: <ConversationCheckpointSnapshot>[
          for (final row in checkpointRows)
            ConversationCheckpointSnapshot(
              checkpoint: _checkpointFromRow(row),
              contact: Contact.fromJson(_decodeMap(row['contact_payload'])),
              messages: _messagesFromPayload(row['messages_payload']),
            ),
        ],
      );
    } catch (error) {
      throw ChatStorageException('readTimelineArchive', error);
    }
  }

  @override
  Future<void> replaceTimelineArchive(
    ConversationTimelineArchive archive,
  ) async {
    try {
      await _db.transaction((txn) async {
        await txn.delete('conversation_checkpoints');
        await txn.delete('conversation_branches');
        for (final snapshot in archive.branches) {
          final branch = snapshot.branch;
          await txn.insert('conversation_branches', <String, Object?>{
            'id': branch.id,
            'contact_id': branch.contactId,
            'name': branch.name,
            'parent_branch_id': branch.parentBranchId,
            'fork_checkpoint_id': branch.forkCheckpointId,
            'contact_payload': jsonEncode(snapshot.contact.toJson()),
            'messages_payload': jsonEncode(
              snapshot.messages.map((message) => message.toJson()).toList(),
            ),
            'message_count': snapshot.messages.length,
            'created_at': branch.createdAt.millisecondsSinceEpoch,
            'updated_at': branch.updatedAt.millisecondsSinceEpoch,
            'is_active': branch.isActive ? 1 : 0,
            'is_main': branch.isMain ? 1 : 0,
          });
        }
        for (final snapshot in archive.checkpoints) {
          final checkpoint = snapshot.checkpoint;
          await txn.insert('conversation_checkpoints', <String, Object?>{
            'id': checkpoint.id,
            'contact_id': checkpoint.contactId,
            'branch_id': checkpoint.branchId,
            'source_message_id': checkpoint.sourceMessageId,
            'label': checkpoint.label,
            'contact_payload': jsonEncode(snapshot.contact.toJson()),
            'messages_payload': jsonEncode(
              snapshot.messages.map((message) => message.toJson()).toList(),
            ),
            'message_count': snapshot.messages.length,
            'created_at': checkpoint.createdAt.millisecondsSinceEpoch,
            'is_key': checkpoint.isKey ? 1 : 0,
          });
        }
      });
    } catch (error) {
      throw ChatStorageException('replaceTimelineArchive', error);
    }
  }

  @override
  Future<void> deleteConversation(String contactId) async {
    try {
      await _db
          .delete('contacts', where: 'id = ?', whereArgs: <Object?>[contactId]);
    } catch (error) {
      throw ChatStorageException('deleteConversation', error);
    }
  }

  @override
  Future<String?> readMetadata(String key) async {
    try {
      final rows = await _db.query(
        'app_meta',
        columns: <String>['meta_value'],
        where: 'meta_key = ?',
        whereArgs: <Object?>[key],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['meta_value'] as String;
    } catch (error) {
      throw ChatStorageException('readMetadata', error);
    }
  }

  @override
  Future<void> writeMetadata(String key, String value) async {
    try {
      await _db.insert(
        'app_meta',
        <String, Object?>{'meta_key': key, 'meta_value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (error) {
      throw ChatStorageException('writeMetadata', error);
    }
  }

  Future<void> _writeContact(DatabaseExecutor db, Contact contact) async {
    final payload = contact.toJson()..remove('eventGraph');
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{
      'id': contact.id,
      'payload': jsonEncode(payload),
      'created_at': contact.createdAt.millisecondsSinceEpoch,
      'updated_at': now,
    };
    final updated = await db.update(
      'contacts',
      values,
      where: 'id = ?',
      whereArgs: <Object?>[contact.id],
    );
    if (updated == 0) {
      await db.insert('contacts', values);
    }
    await db.delete('event_nodes',
        where: 'contact_id = ?', whereArgs: <Object?>[contact.id]);
    await db.delete('event_edges',
        where: 'contact_id = ?', whereArgs: <Object?>[contact.id]);
    await db.delete('event_relations',
        where: 'contact_id = ?', whereArgs: <Object?>[contact.id]);
    await db.delete('memory_meta',
        where: 'contact_id = ?', whereArgs: <Object?>[contact.id]);

    await _writeNodeQueue(db, contact.id, contact.eventGraph.shortTermQueue);
    await _writeNodeQueue(db, contact.id, contact.eventGraph.longTermQueue);
    await _writeNodeQueue(
        db, contact.id, contact.eventGraph.ultraLongTermQueue);
    for (final edge in contact.eventGraph.edges.values) {
      await db.insert('event_edges', <String, Object?>{
        'contact_id': contact.id,
        'from_node_id': edge.fromNodeId,
        'to_node_id': edge.toNodeId,
      });
    }
    await _writeRelations(
        db, contact.id, 'belonging', contact.eventGraph.belongingEventQueues);
    await _writeRelations(
        db, contact.id, 'setting', contact.eventGraph.settingEventQueues);
    await db.insert('memory_meta', <String, Object?>{
      'contact_id': contact.id,
      'turn_count': contact.eventGraph.turnCount,
    });
  }

  Future<void> _writeNodeQueue(
    DatabaseExecutor db,
    String contactId,
    List<EventNode> nodes,
  ) async {
    for (var position = 0; position < nodes.length; position++) {
      final node = nodes[position];
      await db.insert('event_nodes', <String, Object?>{
        'id': node.id,
        'contact_id': contactId,
        'tier': node.tier.storageKey,
        'position': position,
        'event_payload': jsonEncode(node.event.toJson()),
        'created_at': node.createdAtMs,
        'summarized': node.summarized ? 1 : 0,
        'invalidated': node.invalidated ? 1 : 0,
        'needs_review': node.needsReview ? 1 : 0,
      });
    }
  }

  Future<void> _writeRelations(
    DatabaseExecutor db,
    String contactId,
    String type,
    Map<String, List<String>> queues,
  ) async {
    for (final entry in queues.entries) {
      for (var position = 0; position < entry.value.length; position++) {
        await db.insert(
            'event_relations',
            <String, Object?>{
              'contact_id': contactId,
              'relation_type': type,
              'relation_key': entry.key,
              'event_node_id': entry.value[position],
              'position': position,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  Future<void> _writeMessages(
    DatabaseExecutor db,
    String contactId,
    List<Message> messages,
  ) async {
    await db.delete('messages',
        where: 'contact_id = ?', whereArgs: <Object?>[contactId]);
    await _writeMessageRows(db, contactId, messages);
  }

  Future<void> _writeMessageRows(
    DatabaseExecutor db,
    String contactId,
    List<Message> messages, {
    int startSequence = 0,
  }) async {
    for (var offset = 0; offset < messages.length; offset++) {
      final message = messages[offset];
      await db.insert('messages', <String, Object?>{
        'id': message.id,
        'contact_id': contactId,
        'sequence': startSequence + offset,
        'payload': jsonEncode(message.toJson()),
        'created_at': message.createdAt.millisecondsSinceEpoch,
      });
    }
  }

  Future<EventGraphMemory> _readGraph(
    String contactId, [
    DatabaseExecutor? executor,
  ]) async {
    final database = executor ?? _db;
    final rows = await database.query(
      'event_nodes',
      where: 'contact_id = ?',
      whereArgs: <Object?>[contactId],
      orderBy: 'tier ASC, position ASC',
    );
    final queues = <EventTier, List<EventNode>>{
      for (final tier in EventTier.values) tier: <EventNode>[],
    };
    for (final row in rows) {
      final tier = _tierFromStorage(row['tier'] as String);
      queues[tier]!.add(EventNode(
        id: row['id'] as String,
        tier: tier,
        event: EventMemory.fromJson(_decodeMap(row['event_payload'])),
        createdAtMs: row['created_at'] as int,
        summarized: row['summarized'] == 1,
        invalidated: row['invalidated'] == 1,
        needsReview: row['needs_review'] == 1,
      ));
    }
    final edgeRows = await database.query('event_edges',
        where: 'contact_id = ?', whereArgs: <Object?>[contactId]);
    final edges = <String, EventEdge>{};
    for (final row in edgeRows) {
      final edge = EventEdge(
        fromNodeId: row['from_node_id'] as String,
        toNodeId: row['to_node_id'] as String,
      );
      edges[edge.toUniqueKey()] = edge;
    }
    final relationRows = await database.query(
      'event_relations',
      where: 'contact_id = ?',
      whereArgs: <Object?>[contactId],
      orderBy: 'relation_type ASC, relation_key ASC, position ASC',
    );
    final belongings = <String, List<String>>{};
    final settings = <String, List<String>>{};
    for (final row in relationRows) {
      final target =
          row['relation_type'] == 'belonging' ? belongings : settings;
      target
          .putIfAbsent(row['relation_key'] as String, () => <String>[])
          .add(row['event_node_id'] as String);
    }
    final meta = await database.query('memory_meta',
        columns: <String>['turn_count'],
        where: 'contact_id = ?',
        whereArgs: <Object?>[contactId],
        limit: 1);
    return EventGraphMemory(
      shortTermQueue: queues[EventTier.shortTerm]!,
      longTermQueue: queues[EventTier.longTerm]!,
      ultraLongTermQueue: queues[EventTier.ultraLongTerm]!,
      belongingEventQueues: belongings,
      settingEventQueues: settings,
      edges: edges,
      turnCount: meta.isEmpty ? 0 : meta.first['turn_count'] as int,
    );
  }

  EventTier _tierFromStorage(String value) {
    return EventTier.values.firstWhere(
      (tier) => tier.storageKey == value || tier.name == value,
      orElse: () => EventTier.shortTerm,
    );
  }

  Map<String, dynamic> _decodeMap(Object? raw) {
    final decoded = jsonDecode(raw as String);
    if (decoded is! Map) throw const FormatException('Expected JSON object');
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
