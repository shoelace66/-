import '../../../../core/utils/structured_output_regex_parser.dart';
import '../../data/models/contact.dart';

enum BelongingChangeType { added, mentioned }

class BelongingChange {
  const BelongingChange({required this.type, required this.name});

  final BelongingChangeType type;
  final String name;
}

class MemoryPatchResult {
  const MemoryPatchResult({
    this.summary,
    this.turnEvent,
    required this.worldKnowledge,
    required this.selfKnowledge,
    required this.userKnowledge,
    required this.status,
    required this.currentStates,
    required this.belongingChanges,
    required this.belongings,
    required this.mood,
    required this.time,
  });

  final EventMemory? summary;
  final EventMemory? turnEvent;
  final List<String> worldKnowledge;
  final List<String> selfKnowledge;
  final List<String> userKnowledge;
  final List<String> status;
  final Map<String, String> currentStates;
  final List<BelongingChange> belongingChanges;
  final List<String> belongings;
  final String mood;
  final String time;

  List<EventMemory> get events => <EventMemory>[
        if (summary != null) summary!,
        if (turnEvent != null) turnEvent!,
      ];
}

/// 将模型的 memoryPatch 归并为新的联系人投影。
///
/// 本服务不修改事件图、不持久化，也不依赖 Flutter，因此可以在提交事务前独立
/// 验证补丁。最低层的 [turnEvent] 来自 `eventBrief`，仍是正文前生成的规范事件。
class MemoryPatchReducer {
  const MemoryPatchReducer();

  MemoryPatchResult reduce({
    required Contact contact,
    required Map<String, dynamic> patch,
    required String userInput,
    required String rawAiResponse,
  }) {
    final sourceDialog = _buildSourceDialog(userInput, rawAiResponse);
    final summary = _readEvent(patch['summary'], sourceDialog: sourceDialog);
    final turnEvent = _readEvent(
      patch['eventBrief'],
      sourceDialog: sourceDialog,
    );
    final belongingChanges = _readBelongingChanges(
      StructuredOutputRegexParser.extractStringList(patch, 'belongings'),
    );

    return MemoryPatchResult(
      summary: summary,
      turnEvent: turnEvent,
      worldKnowledge: _mergeUnique(
        contact.worldKnowledge.items,
        StructuredOutputRegexParser.extractStringList(patch, 'worldKnowledge'),
      ),
      selfKnowledge: _mergeUnique(
        contact.selfKnowledge.items,
        StructuredOutputRegexParser.extractStringList(patch, 'selfKnowledge'),
      ),
      userKnowledge: _mergeUnique(
        contact.userKnowledge.items,
        StructuredOutputRegexParser.extractStringList(patch, 'userKnowledge'),
      ),
      status: _mergeUnique(
        contact.status,
        StructuredOutputRegexParser.extractStringList(patch, 'status'),
      ),
      currentStates: _mergeCurrentStates(
        contact.currentStates,
        StructuredOutputRegexParser.extractStringMap(patch, 'currentStates'),
      ),
      belongingChanges: belongingChanges,
      belongings: _applyBelongingChanges(
        contact.belongings,
        belongingChanges,
      ),
      mood: StructuredOutputRegexParser.extractString(patch, 'mood') ??
          contact.mood,
      time: StructuredOutputRegexParser.extractString(patch, 'time') ??
          contact.time,
    );
  }

  EventMemory? _readEvent(dynamic value, {required String sourceDialog}) {
    if (value is! Map) return null;
    final normalized = value.map(
      (key, item) => MapEntry(key.toString(), item),
    );
    final event = EventMemory.fromJson(normalized);
    if (event.isEmpty) return null;
    return EventMemory(
      description: event.description,
      keywords: event.keywords,
      theme: event.theme,
      sourceDialog: sourceDialog,
    );
  }

  String _buildSourceDialog(String userInput, String rawAiResponse) {
    final lines = <String>[];
    final normalizedInput = userInput.trim();
    if (normalizedInput.isNotEmpty) lines.add('用户：$normalizedInput');
    final normalizedResponse = rawAiResponse.trim();
    if (normalizedResponse.isNotEmpty) {
      final reply = StructuredOutputRegexParser.extractReply(rawAiResponse) ??
          normalizedResponse;
      lines.add('AI：$reply');
    }
    return lines.join('\n');
  }

  List<BelongingChange> _readBelongingChanges(List<String> values) {
    final result = <BelongingChange>[];
    final pattern = RegExp(r'^[\(（]\s*(新增|提及)\s*[\)）]\s*(.+)$');
    for (final value in values) {
      final match = pattern.firstMatch(value);
      final name = match?.group(2)?.trim() ?? '';
      if (match == null || name.isEmpty) continue;
      result.add(BelongingChange(
        type: match.group(1)?.trim() == '新增'
            ? BelongingChangeType.added
            : BelongingChangeType.mentioned,
        name: name,
      ));
    }
    return result;
  }

  List<String> _applyBelongingChanges(
    List<String> current,
    List<BelongingChange> changes,
  ) {
    final result = <String>[...current];
    for (final change in changes) {
      result.removeWhere((item) => item == change.name);
      result.add(change.name);
    }
    return result;
  }

  Map<String, String> _mergeCurrentStates(
    Map<String, String> current,
    Map<String, String> patch,
  ) {
    final result = Map<String, String>.from(current);
    for (final entry in patch.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || !result.containsKey(key)) continue;
      result[key] = entry.value.trim();
    }
    return result;
  }

  List<String> _mergeUnique(List<String> current, List<String> patch) {
    final result = <String>[];
    final seen = <String>{};
    for (final item in current.followedBy(patch)) {
      final normalized = item.trim();
      if (normalized.isNotEmpty && seen.add(normalized)) result.add(normalized);
    }
    return result;
  }
}
