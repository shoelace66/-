class WorldLocation {
  const WorldLocation({
    required this.id,
    required this.name,
    this.description = '',
    this.type = '',
    this.parentId,
    this.relatedCharacterIds = const <String>[],
    this.tags = const <String>[],
    this.createdAtMs = 0,
  });

  final String id;
  final String name;
  final String description;
  final String type;
  final String? parentId;
  final List<String> relatedCharacterIds;
  final List<String> tags;
  final int createdAtMs;

  WorldLocation copyWith({
    String? id,
    String? name,
    String? description,
    String? type,
    String? parentId,
    List<String>? relatedCharacterIds,
    List<String>? tags,
    int? createdAtMs,
  }) {
    return WorldLocation(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      parentId: parentId ?? this.parentId,
      relatedCharacterIds: relatedCharacterIds ?? this.relatedCharacterIds,
      tags: tags ?? this.tags,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'type': type,
        if (parentId != null) 'parentId': parentId,
        if (relatedCharacterIds.isNotEmpty) 'relatedCharacterIds': relatedCharacterIds,
        if (tags.isNotEmpty) 'tags': tags,
        'createdAtMs': createdAtMs,
      };

  factory WorldLocation.fromJson(Map<String, dynamic> json) {
    return WorldLocation(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      parentId: json['parentId']?.toString(),
      relatedCharacterIds: json['relatedCharacterIds'] is List
          ? (json['relatedCharacterIds'] as List)
              .map((e) => e.toString())
              .toList(growable: false)
          : const <String>[],
      tags: json['tags'] is List
          ? (json['tags'] as List).map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class WorldOrganization {
  const WorldOrganization({
    required this.id,
    required this.name,
    this.description = '',
    this.leaderId,
    this.memberIds = const <String>[],
    this.goals = const <String>[],
    this.tags = const <String>[],
    this.createdAtMs = 0,
  });

  final String id;
  final String name;
  final String description;
  final String? leaderId;
  final List<String> memberIds;
  final List<String> goals;
  final List<String> tags;
  final int createdAtMs;

  WorldOrganization copyWith({
    String? id,
    String? name,
    String? description,
    String? leaderId,
    List<String>? memberIds,
    List<String>? goals,
    List<String>? tags,
    int? createdAtMs,
  }) {
    return WorldOrganization(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      leaderId: leaderId ?? this.leaderId,
      memberIds: memberIds ?? this.memberIds,
      goals: goals ?? this.goals,
      tags: tags ?? this.tags,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        if (leaderId != null) 'leaderId': leaderId,
        if (memberIds.isNotEmpty) 'memberIds': memberIds,
        if (goals.isNotEmpty) 'goals': goals,
        if (tags.isNotEmpty) 'tags': tags,
        'createdAtMs': createdAtMs,
      };

  factory WorldOrganization.fromJson(Map<String, dynamic> json) {
    return WorldOrganization(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      leaderId: json['leaderId']?.toString(),
      memberIds: json['memberIds'] is List
          ? (json['memberIds'] as List).map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      goals: json['goals'] is List
          ? (json['goals'] as List).map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      tags: json['tags'] is List
          ? (json['tags'] as List).map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class WorldRule {
  const WorldRule({
    required this.id,
    required this.name,
    this.description = '',
    this.type = '',
    this.scope = '',
    this.createdAtMs = 0,
  });

  final String id;
  final String name;
  final String description;
  final String type;
  final String scope;
  final int createdAtMs;

  WorldRule copyWith({
    String? id,
    String? name,
    String? description,
    String? type,
    String? scope,
    int? createdAtMs,
  }) {
    return WorldRule(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      scope: scope ?? this.scope,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'type': type,
        'scope': scope,
        'createdAtMs': createdAtMs,
      };

  factory WorldRule.fromJson(Map<String, dynamic> json) {
    return WorldRule(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      scope: (json['scope'] ?? '').toString(),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class WorldTimelineEvent {
  const WorldTimelineEvent({
    required this.id,
    required this.title,
    this.description = '',
    this.year = 0,
    this.locationId,
    this.participantIds = const <String>[],
    this.tags = const <String>[],
    this.createdAtMs = 0,
  });

  final String id;
  final String title;
  final String description;
  final int year;
  final String? locationId;
  final List<String> participantIds;
  final List<String> tags;
  final int createdAtMs;

  WorldTimelineEvent copyWith({
    String? id,
    String? title,
    String? description,
    int? year,
    String? locationId,
    List<String>? participantIds,
    List<String>? tags,
    int? createdAtMs,
  }) {
    return WorldTimelineEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      year: year ?? this.year,
      locationId: locationId ?? this.locationId,
      participantIds: participantIds ?? this.participantIds,
      tags: tags ?? this.tags,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'year': year,
        if (locationId != null) 'locationId': locationId,
        if (participantIds.isNotEmpty) 'participantIds': participantIds,
        if (tags.isNotEmpty) 'tags': tags,
        'createdAtMs': createdAtMs,
      };

  factory WorldTimelineEvent.fromJson(Map<String, dynamic> json) {
    return WorldTimelineEvent(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      year: (json['year'] as num?)?.toInt() ?? 0,
      locationId: json['locationId']?.toString(),
      participantIds: json['participantIds'] is List
          ? (json['participantIds'] as List)
              .map((e) => e.toString())
              .toList(growable: false)
          : const <String>[],
      tags: json['tags'] is List
          ? (json['tags'] as List).map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class WorldBook {
  const WorldBook({
    this.locations = const <WorldLocation>[],
    this.organizations = const <WorldOrganization>[],
    this.rules = const <WorldRule>[],
    this.timelineEvents = const <WorldTimelineEvent>[],
  });

  final List<WorldLocation> locations;
  final List<WorldOrganization> organizations;
  final List<WorldRule> rules;
  final List<WorldTimelineEvent> timelineEvents;

  static const empty = WorldBook();

  bool get isEmpty =>
      locations.isEmpty &&
      organizations.isEmpty &&
      rules.isEmpty &&
      timelineEvents.isEmpty;

  WorldBook copyWith({
    List<WorldLocation>? locations,
    List<WorldOrganization>? organizations,
    List<WorldRule>? rules,
    List<WorldTimelineEvent>? timelineEvents,
  }) {
    return WorldBook(
      locations: locations ?? this.locations,
      organizations: organizations ?? this.organizations,
      rules: rules ?? this.rules,
      timelineEvents: timelineEvents ?? this.timelineEvents,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (locations.isNotEmpty)
          'locations': locations.map((e) => e.toJson()).toList(),
        if (organizations.isNotEmpty)
          'organizations': organizations.map((e) => e.toJson()).toList(),
        if (rules.isNotEmpty) 'rules': rules.map((e) => e.toJson()).toList(),
        if (timelineEvents.isNotEmpty)
          'timelineEvents': timelineEvents.map((e) => e.toJson()).toList(),
      };

  factory WorldBook.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const WorldBook();
    return WorldBook(
      locations: json['locations'] is List
          ? (json['locations'] as List)
              .map((e) => WorldLocation.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <WorldLocation>[],
      organizations: json['organizations'] is List
          ? (json['organizations'] as List)
              .map((e) =>
                  WorldOrganization.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <WorldOrganization>[],
      rules: json['rules'] is List
          ? (json['rules'] as List)
              .map((e) => WorldRule.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <WorldRule>[],
      timelineEvents: json['timelineEvents'] is List
          ? (json['timelineEvents'] as List)
              .map((e) =>
                  WorldTimelineEvent.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <WorldTimelineEvent>[],
    );
  }

  String toPromptSection() {
    final parts = <String>[];
    if (locations.isNotEmpty) {
      parts.add(
        '地点：\n${locations.map((l) => '- ${l.name}${l.description.isNotEmpty ? "：${l.description}" : ""}${l.tags.isNotEmpty ? " [标签：${l.tags.join("、")}]" : ""}').join("\n")}',
      );
    }
    if (organizations.isNotEmpty) {
      parts.add(
        '组织：\n${organizations.map((o) => '- ${o.name}${o.description.isNotEmpty ? "：${o.description}" : ""}${o.goals.isNotEmpty ? " [目标：${o.goals.join("、")}]" : ""}').join("\n")}',
      );
    }
    if (rules.isNotEmpty) {
      parts.add(
        '世界规则：\n${rules.map((r) => '- ${r.name}${r.description.isNotEmpty ? "：${r.description}" : ""} [类型：${r.type}，范围：${r.scope}]').join("\n")}',
      );
    }
    return parts.join('\n\n');
  }
}