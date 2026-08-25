import '../../../core/data/models/provider_settings.dart';
import '../data/models/message.dart';

class ConversationUsageEstimate {
  const ConversationUsageEstimate({
    required this.inputTokens,
    required this.outputTokens,
    required this.estimatedCost,
  });

  final int inputTokens;
  final int outputTokens;
  final double estimatedCost;

  int get totalTokens => inputTokens + outputTokens;
}

class ConversationUsageEstimator {
  const ConversationUsageEstimator();

  ConversationUsageEstimate estimate(
    Iterable<Message> messages,
    LlmProfile profile,
  ) {
    var input = 0;
    var output = 0;
    for (final message in messages) {
      final tokens = estimateTextTokens(message.content);
      if (message.role == MessageRole.user) {
        input += tokens;
      } else {
        output += tokens;
      }
    }
    final cost = input / 1000000 * profile.inputPricePerMillion +
        output / 1000000 * profile.outputPricePerMillion;
    return ConversationUsageEstimate(
      inputTokens: input,
      outputTokens: output,
      estimatedCost: cost,
    );
  }

  int estimateTextTokens(String text) {
    if (text.isEmpty) return 0;
    var weightedUnits = 0.0;
    for (final rune in text.runes) {
      final isCjk = (rune >= 0x3400 && rune <= 0x9fff) ||
          (rune >= 0xf900 && rune <= 0xfaff);
      weightedUnits += isCjk ? 1.0 : 0.25;
    }
    return weightedUnits.ceil();
  }
}
