import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/ai_qa_message.dart';
import 'ai_service_config.dart';

class AiQaService {
  Future<Stream<String>> ask({
    required String question,
    required List<AiQaCitation> citations,
    List<AiQaMessage> recentMessages = const [],
  }) async {
    if (!AIServiceConfig.isConfigured()) {
      throw Exception('AI 未配置，请先在设置页填写 API Key');
    }

    final prompt = _buildPrompt(
      question: question,
      citations: citations,
      recentMessages: recentMessages,
    );
    return _askDeepseek(prompt);
  }

  Stream<String> _askDeepseek(String prompt) async* {
    final apiKey = AIServiceConfig.getCurrentApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('DeepSeek API Key 为空');
    }

    final dio = Dio();
    final response = await dio.post(
      _chatCompletionsUrl(AIServiceConfig.getCurrentApiUrl()),
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
      data: {
        'model': AIServiceConfig.getCurrentModel(),
        'messages': [
          {'role': 'system', 'content': '你是拾光笔记的问答助手。'},
          {'role': 'user', 'content': prompt},
        ],
        'stream': true,
        'temperature': 0.2,
      },
    );

    await for (final line
        in response.data.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) {
        continue;
      }
      final jsonStr = line.substring(6).trim();
      if (jsonStr == '[DONE]') {
        break;
      }
      final content = _extractDeltaContent(jsonStr);
      if (content != null && content.isNotEmpty) {
        yield content;
      }
    }
  }

  String _buildPrompt({
    required String question,
    required List<AiQaCitation> citations,
    required List<AiQaMessage> recentMessages,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('你是拾光笔记的 AI 问答助手。');
    buffer.writeln('优先根据【本地笔记资料】回答用户问题。');
    buffer.writeln('如果资料不足或未检索到相关笔记，必须先说明“我没有在现有笔记里找到明确依据”，然后基于你的通用知识继续回答。');
    buffer.writeln('使用通用知识回答时，不要声称内容来自用户笔记。');
    buffer.writeln('回答要简洁、准确，适合手机阅读。');
    buffer.writeln();
    if (recentMessages.isNotEmpty) {
      buffer.writeln('【最近对话】');
      for (final message in recentMessages) {
        final role = message.role == AiQaRole.user ? '用户' : '助手';
        buffer.writeln('$role：${message.content}');
      }
      buffer.writeln();
    }
    buffer.writeln('【用户问题】');
    buffer.writeln(question);
    buffer.writeln();
    buffer.writeln('【本地笔记资料】');
    if (citations.isEmpty) {
      buffer.writeln('未检索到相关笔记。');
    } else {
      for (var i = 0; i < citations.length; i++) {
        final citation = citations[i];
        buffer.writeln('资料 ${i + 1}');
        buffer.writeln('课程：${citation.courseName}');
        buffer.writeln('标题：${citation.note.title}');
        buffer.writeln('时间：${_formatDate(citation.note.createdAt)}');
        buffer.writeln('内容：');
        buffer.writeln(citation.snippet);
        buffer.writeln();
      }
    }
    buffer.writeln('【回答格式】');
    buffer.writeln('先直接回答问题。');
    buffer.writeln('如果未检索到相关笔记，开头写：“我没有在现有笔记里找到明确依据，下面基于通用知识回答：”。');
    buffer.writeln('如果有依据，最后用“相关依据：”列出使用到的资料编号和笔记标题。');
    buffer.writeln('如果没有依据，不要输出“相关依据：”。');
    return buffer.toString();
  }

  String _chatCompletionsUrl(String configuredUrl) {
    final baseUrl = configuredUrl.trim().isEmpty
        ? AIServiceConfig.defaultAiUrl
        : configuredUrl.trim();
    if (baseUrl.endsWith('/chat/completions')) {
      return baseUrl;
    }
    if (baseUrl.endsWith('/v1')) {
      return '$baseUrl/chat/completions';
    }
    if (baseUrl.contains('/v1/')) {
      return '$baseUrl/chat/completions';
    }
    return '$baseUrl/chat/completions';
  }

  String? _extractDeltaContent(String data) {
    try {
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>? ?? const [];
      if (choices.isEmpty) {
        return null;
      }
      final choice = choices.first as Map<String, dynamic>;
      final delta = choice['delta'] as Map<String, dynamic>? ?? const {};
      return delta['content'] as String?;
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.year}-$month-$day $hour:$minute';
  }
}
