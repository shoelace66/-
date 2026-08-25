import 'dart:math';

import '../entities/world_book.dart';

class WorldBookService {
  const WorldBookService();

  String _generateId() =>
      'wb_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  WorldBook addLocation(WorldBook book, WorldLocation location) {
    final updated = location.id.isEmpty
        ? location.copyWith(id: _generateId(), createdAtMs: DateTime.now().millisecondsSinceEpoch)
        : location;
    return book.copyWith(
      locations: <WorldLocation>[updated, ...book.locations],
    );
  }

  WorldBook updateLocation(WorldBook book, WorldLocation location) {
    final index = book.locations.indexWhere((l) => l.id == location.id);
    if (index < 0) return book;
    final updated = <WorldLocation>[...book.locations];
    updated[index] = location;
    return book.copyWith(locations: updated);
  }

  WorldBook removeLocation(WorldBook book, String locationId) {
    return book.copyWith(
      locations: book.locations.where((l) => l.id != locationId).toList(growable: false),
    );
  }

  WorldBook addOrganization(WorldBook book, WorldOrganization organization) {
    final updated = organization.id.isEmpty
        ? organization.copyWith(id: _generateId(), createdAtMs: DateTime.now().millisecondsSinceEpoch)
        : organization;
    return book.copyWith(
      organizations: <WorldOrganization>[updated, ...book.organizations],
    );
  }

  WorldBook updateOrganization(WorldBook book, WorldOrganization organization) {
    final index = book.organizations.indexWhere((o) => o.id == organization.id);
    if (index < 0) return book;
    final updated = <WorldOrganization>[...book.organizations];
    updated[index] = organization;
    return book.copyWith(organizations: updated);
  }

  WorldBook removeOrganization(WorldBook book, String organizationId) {
    return book.copyWith(
      organizations: book.organizations.where((o) => o.id != organizationId).toList(growable: false),
    );
  }

  WorldBook addRule(WorldBook book, WorldRule rule) {
    final updated = rule.id.isEmpty
        ? rule.copyWith(id: _generateId(), createdAtMs: DateTime.now().millisecondsSinceEpoch)
        : rule;
    return book.copyWith(
      rules: <WorldRule>[updated, ...book.rules],
    );
  }

  WorldBook updateRule(WorldBook book, WorldRule rule) {
    final index = book.rules.indexWhere((r) => r.id == rule.id);
    if (index < 0) return book;
    final updated = <WorldRule>[...book.rules];
    updated[index] = rule;
    return book.copyWith(rules: updated);
  }

  WorldBook removeRule(WorldBook book, String ruleId) {
    return book.copyWith(
      rules: book.rules.where((r) => r.id != ruleId).toList(growable: false),
    );
  }

  WorldBook addTimelineEvent(WorldBook book, WorldTimelineEvent event) {
    final updated = event.id.isEmpty
        ? event.copyWith(id: _generateId(), createdAtMs: DateTime.now().millisecondsSinceEpoch)
        : event;
    return book.copyWith(
      timelineEvents: <WorldTimelineEvent>[updated, ...book.timelineEvents],
    );
  }

  WorldBook updateTimelineEvent(WorldBook book, WorldTimelineEvent event) {
    final index = book.timelineEvents.indexWhere((e) => e.id == event.id);
    if (index < 0) return book;
    final updated = <WorldTimelineEvent>[...book.timelineEvents];
    updated[index] = event;
    return book.copyWith(timelineEvents: updated);
  }

  WorldBook removeTimelineEvent(WorldBook book, String eventId) {
    return book.copyWith(
      timelineEvents: book.timelineEvents.where((e) => e.id != eventId).toList(growable: false),
    );
  }

  List<WorldLocation> searchLocations(WorldBook book, String query) {
    if (query.isEmpty) return book.locations;
    final q = query.toLowerCase();
    return book.locations.where((l) =>
        l.name.toLowerCase().contains(q) ||
        l.description.toLowerCase().contains(q) ||
        l.tags.any((t) => t.toLowerCase().contains(q))).toList(growable: false);
  }

  List<WorldOrganization> searchOrganizations(WorldBook book, String query) {
    if (query.isEmpty) return book.organizations;
    final q = query.toLowerCase();
    return book.organizations.where((o) =>
        o.name.toLowerCase().contains(q) ||
        o.description.toLowerCase().contains(q) ||
        o.goals.any((g) => g.toLowerCase().contains(q))).toList(growable: false);
  }

  List<WorldRule> searchRules(WorldBook book, String query) {
    if (query.isEmpty) return book.rules;
    final q = query.toLowerCase();
    return book.rules.where((r) =>
        r.name.toLowerCase().contains(q) ||
        r.description.toLowerCase().contains(q) ||
        r.type.toLowerCase().contains(q)).toList(growable: false);
  }

  List<WorldTimelineEvent> searchTimelineEvents(WorldBook book, String query) {
    if (query.isEmpty) return book.timelineEvents;
    final q = query.toLowerCase();
    return book.timelineEvents.where((e) =>
        e.title.toLowerCase().contains(q) ||
        e.description.toLowerCase().contains(q)).toList(growable: false);
  }

  List<WorldTimelineEvent> sortedTimelineEvents(WorldBook book) {
    final sorted = List<WorldTimelineEvent>.from(book.timelineEvents);
    sorted.sort((a, b) => a.year.compareTo(b.year));
    return sorted;
  }
}