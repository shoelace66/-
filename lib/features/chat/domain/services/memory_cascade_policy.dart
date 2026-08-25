import '../../data/models/contact.dart';

/// 三级记忆级联的纯业务决策。
///
/// 只决定“本轮是否需要概括、概括哪一层、向 Prompt 提供哪些源事件”，
/// 不负责调用模型或修改事件图。
class MemoryCascadeDecision {
  const MemoryCascadeDecision({
    required this.sourceTier,
    required this.pendingEvents,
  });

  const MemoryCascadeDecision.none()
      : sourceTier = null,
        pendingEvents = const <EventMemory>[];

  final EventTier? sourceTier;
  final List<EventMemory> pendingEvents;

  bool get needsSummary => sourceTier != null;
}

class MemoryCascadePolicy {
  const MemoryCascadePolicy();

  MemoryCascadeDecision evaluate({
    required EventGraphMemory graph,
    required int shortTermThreshold,
    required int longTermThreshold,
  }) {
    final shortPending = _unsummarized(graph.shortTermQueue);
    if (shortPending.length >= shortTermThreshold) {
      return MemoryCascadeDecision(
        sourceTier: EventTier.shortTerm,
        pendingEvents: shortPending
            .take(shortTermThreshold)
            .map((node) => node.event)
            .toList(growable: false),
      );
    }

    final longPending = _unsummarized(graph.longTermQueue);
    if (longPending.length >= longTermThreshold) {
      return MemoryCascadeDecision(
        sourceTier: EventTier.longTerm,
        pendingEvents: longPending
            .take(longTermThreshold)
            .map((node) => node.event)
            .toList(growable: false),
      );
    }

    return const MemoryCascadeDecision.none();
  }

  List<EventNode> _unsummarized(List<EventNode> queue) => queue
      .where((node) => !node.summarized && !node.invalidated)
      .toList(growable: false);
}
