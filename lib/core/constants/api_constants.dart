/// 运行时 LLM 配置（由 ChatProvider 在初始化时从 ProviderSettings 注入）
///
/// 这层是历史遗留的"全局静态变量"：UI 直接读它来展示当前生效的 baseUrl / model。
/// 真正完整的配置见 [LlmProfile]。
class ApiConstants {
  ApiConstants._();

  static String runtimeApiKey = '';
  static String runtimeBaseUrl = 'https://api.deepseek.com';
  static String runtimeModel = 'deepseek-chat';

  /// 默认超时（秒），从 [LlmParameters.timeoutSeconds] 同步过来
  static int runtimeTimeoutSeconds = 60;

  static const String fallbackBaseUrl = 'https://api.deepseek.com';
  static const String fallbackCompatBaseUrl = 'https://api.deepseek.com/v1';

  static bool get hasApiKey => runtimeApiKey.trim().isNotEmpty;

  static String get chatCompletionsUrl => '$runtimeBaseUrl/chat/completions';
  static String get chatCompletionsCompatUrl =>
      '${runtimeBaseUrl.replaceAll(RegExp(r'/v1$'), '')}/v1/chat/completions';
}
