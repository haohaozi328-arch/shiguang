import 'ai_notes_generation_service.dart';
import 'realtime_transcription_service.dart';
import 'ai_service_config.dart';

/// AI 服务工厂 - 用于创建和管理 AI 服务实例
class AIServiceFactory {
  static AINotesGenerationService? _aiService;
  static RealtimeTranscriptionService? _transcriptionService;

  /// 获取或创建 AI 笔记生成服务
  static AINotesGenerationService getAINotesService() {
    if (_aiService == null) {
      final apiKey = AIServiceConfig.getCurrentApiKey();
      if (apiKey == null) {
        throw Exception('AI 服务未配置，请先设置 API Key');
      }

      _aiService = AINotesGenerationService.deepseek(
        apiKey,
        apiUrl: AIServiceConfig.getCurrentApiUrl(),
        model: AIServiceConfig.getCurrentModel(),
      );
    }
    return _aiService!;
  }

  /// 获取或创建实时转录服务
  static RealtimeTranscriptionService getTranscriptionService() {
    _transcriptionService ??= RealtimeTranscriptionService.instance;
    return _transcriptionService!;
  }

  /// 初始化转录服务
  static Future<bool> initializeTranscription() async {
    final service = getTranscriptionService();
    return await service.initialize();
  }

  /// 重置服务（用于切换 AI 提供商）
  static void reset() {
    _aiService?.dispose();
    _aiService = null;
  }

  /// 释放所有资源
  static void dispose() {
    _aiService?.dispose();
    _transcriptionService?.dispose();
    _aiService = null;
    _transcriptionService = null;
  }
}
