class ApiConstants {
  ApiConstants._();

  static String runtimeApiKey = '';
  static String runtimeBaseUrl = 'https://api.deepseek.com';
  static String runtimeModel = 'deepseek-chat';
  static const String fallbackBaseUrl = 'https://api.deepseek.com';
  static const String fallbackCompatBaseUrl = 'https://api.deepseek.com/v1';
  static const int requestTimeoutSeconds = 60;

  static bool get hasApiKey => runtimeApiKey.trim().isNotEmpty;

  static String get chatCompletionsUrl => '$runtimeBaseUrl/chat/completions';
  static String get chatCompletionsCompatUrl =>
      '${runtimeBaseUrl.replaceAll(RegExp(r'/v1$'), '')}/v1/chat/completions';
}
