import 'package:shared_preferences/shared_preferences.dart';

/// AI 服务配置（当前仅保留 DeepSeek）
class AIServiceConfig {
  static const String providerDeepseek = 'deepseek';

  static const String defaultAiUrl = 'https://api.deepseek.com';
  static const String defaultAiModel = 'deepseek-v4-pro';

  static String currentProvider = providerDeepseek;
  static String? deepseekApiKey;
  static String? apiUrl;
  static String? deepseekModel;

  static bool _isLoaded = false;

  static Future<void> loadConfig() async {
    if (_isLoaded) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      currentProvider = providerDeepseek;
      deepseekApiKey = prefs.getString('deepseek_api_key');
      apiUrl = prefs.getString('ai_api_url') ?? defaultAiUrl;
      deepseekModel = prefs.getString('deepseek_model') ?? defaultAiModel;

      // 清理已废弃的 Gemini / 在线 ASR 配置，避免旧数据继续干扰逻辑。
      await prefs.remove('ai_provider');
      await prefs.remove('gemini_api_key');
      await prefs.remove('gemini_model');
      await prefs.remove('asr_url');
      await prefs.remove('asr_api_key');
      await prefs.remove('asr_model');

      await _saveConfig();
      _isLoaded = true;
    } catch (_) {}
  }

  static void ensureLoaded() {
    if (_isLoaded) {
      return;
    }
    currentProvider = providerDeepseek;
    apiUrl ??= defaultAiUrl;
    deepseekModel ??= defaultAiModel;
  }

  static Future<void> initDeepseek(
    String apiKey, {
    String? url,
    String? model,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('API Key 不能为空');
    }

    currentProvider = providerDeepseek;
    deepseekApiKey = apiKey.trim();
    apiUrl = (url == null || url.trim().isEmpty) ? defaultAiUrl : url.trim();
    deepseekModel = (model == null || model.trim().isEmpty)
        ? defaultAiModel
        : model.trim();

    await _saveConfig();
  }

  static Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider', providerDeepseek);

    if (deepseekApiKey != null && deepseekApiKey!.isNotEmpty) {
      await prefs.setString('deepseek_api_key', deepseekApiKey!);
    }
    if (apiUrl != null && apiUrl!.isNotEmpty) {
      await prefs.setString('ai_api_url', apiUrl!);
    }
    if (deepseekModel != null && deepseekModel!.isNotEmpty) {
      await prefs.setString('deepseek_model', deepseekModel!);
    }
  }

  static String? getCurrentApiKey() => deepseekApiKey;

  static String getCurrentApiUrl() => apiUrl ?? defaultAiUrl;

  static String getCurrentModel() => deepseekModel ?? defaultAiModel;

  static bool isConfigured() {
    return deepseekApiKey != null && deepseekApiKey!.trim().isNotEmpty;
  }

  // 兼容旧调用方；语音识别已固定为本地模型。
  static String getAsrUrl() => '';
  static String? getAsrApiKey() => null;
  static String getAsrModel() =>
      'speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-online-onnx';

  static Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_provider');
    await prefs.remove('deepseek_api_key');
    await prefs.remove('ai_api_url');
    await prefs.remove('deepseek_model');
    await prefs.remove('gemini_api_key');
    await prefs.remove('gemini_model');
    await prefs.remove('asr_url');
    await prefs.remove('asr_api_key');
    await prefs.remove('asr_model');

    currentProvider = providerDeepseek;
    deepseekApiKey = null;
    apiUrl = defaultAiUrl;
    deepseekModel = defaultAiModel;
    _isLoaded = false;
  }
}
