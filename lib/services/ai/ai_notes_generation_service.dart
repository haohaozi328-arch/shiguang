import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../utils/ui_formatters.dart';
import 'ai_service_config.dart';

/// AI笔记生成服务 - 当前仅保留 DeepSeek
class AINotesGenerationService {
  AINotesGenerationService.deepseek(
    String apiKey, {
    String? apiUrl,
    String? model,
  }) : _deepseekApiKey = apiKey,
       _customApiUrl = apiUrl,
       _customModel = model;

  static const _headingEmojis = [
    '🔍',
    '📌',
    '📝',
    '💡',
    '✅',
    '📚',
    '🎯',
    '⭐',
    '🧠',
    '📎',
    '📊',
    '🧩',
  ];

  final String? _deepseekApiKey;
  final String? _customApiUrl;
  final String? _customModel;

  final _noteStreamController = StreamController<String>.broadcast();

  String _currentNoteContent = '';
  String _lastProcessedTranscription = '';

  Stream<String> get noteStream => _noteStreamController.stream;
  String get currentNoteContent => _currentNoteContent;

  Future<void> generateNoteContent({
    required String transcription,
    required String existingContent,
    String previousContext = '',
    String courseName = '',
    String noteTitle = '',
  }) async {
    if (transcription == _lastProcessedTranscription) {
      return;
    }

    _lastProcessedTranscription = transcription;

    try {
      final prompt = _buildContextAwarePrompt(
        transcription: transcription,
        existingContent: existingContent,
        previousContext: previousContext,
        courseName: courseName,
        noteTitle: noteTitle,
      );
      await _generateWithDeepseek(prompt, existingContent: existingContent);
    } catch (e) {
      _noteStreamController.addError(e);
    }
  }

  Future<void> _generateWithDeepseek(
    String prompt, {
    required String existingContent,
  }) async {
    if (_deepseekApiKey == null || _deepseekApiKey.trim().isEmpty) {
      throw Exception('DeepSeek API Key 为空');
    }

    final dio = Dio();
    final response = await dio.post(
      _chatCompletionsUrl(_customApiUrl ?? AIServiceConfig.getCurrentApiUrl()),
      options: Options(
        headers: {
          'Authorization': 'Bearer $_deepseekApiKey',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
      data: {
        'model': _customModel ?? AIServiceConfig.getCurrentModel(),
        'messages': [
          {'role': 'system', 'content': '你是拾光笔记的课堂笔记整理助手。'},
          {'role': 'user', 'content': prompt},
        ],
        'stream': true,
        'temperature': 0.25,
      },
    );

    String generatedContent = '';
    final baseContent = formatAiNoteText(existingContent);
    String lastStableContent = '';

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

      final content = _extractDeepseekDeltaContent(jsonStr);
      if (content == null || content.isEmpty) {
        continue;
      }

      generatedContent += content;
      final stableContent = _stableStreamingContent(generatedContent);
      if (stableContent.isEmpty) {
        continue;
      }

      if (_isEquivalentStableContent(
        previous: lastStableContent,
        current: stableContent,
      )) {
        continue;
      }

      lastStableContent = stableContent;

      final mergedContent = _mergeNoteContent(
        existingContent: baseContent,
        incrementalContent: _sanitizeGeneratedBlock(stableContent),
      );
      _currentNoteContent = mergedContent;
      _noteStreamController.add(mergedContent);
    }

    _emitFinalMergedContent(
      existingContent: baseContent,
      generatedContent: _sanitizeGeneratedBlock(generatedContent),
    );
  }

  String _buildContextAwarePrompt({
    required String transcription,
    required String existingContent,
    required String previousContext,
    required String courseName,
    required String noteTitle,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('你是一个专业的课堂笔记整理助手。');
    buffer.writeln('你的任务是把这一次新增的语音识别文本整理成适合手机阅读的新增笔记段落。');
    buffer.writeln();

    final trimmedCourseName = courseName.trim();
    final trimmedNoteTitle = noteTitle.trim();
    final existingContext = _recentGeneratedContext(existingContent);
    if (trimmedCourseName.isNotEmpty || trimmedNoteTitle.isNotEmpty) {
      buffer.writeln('【课程与标题线索】');
      if (trimmedCourseName.isNotEmpty) {
        buffer.writeln('课程名称：$trimmedCourseName');
      }
      if (trimmedNoteTitle.isNotEmpty) {
        buffer.writeln('笔记标题：$trimmedNoteTitle');
      }
      buffer.writeln();
    }

    buffer.writeln('【识别说明】');
    buffer.writeln('以下内容来自 ASR 语音识别，可能存在同音字、断句和专业术语误识别。');
    buffer.writeln('请只修正明显识别错误，不要补充原文没有的信息。');
    buffer.writeln();

    if (existingContext.isNotEmpty) {
      buffer.writeln('【当前已生成的部分笔记，仅用于避免重复和承接上下文】');
      buffer.writeln(existingContext);
      buffer.writeln();
    }

    if (previousContext.isNotEmpty) {
      buffer.writeln('【最近已整理内容，仅用于承接上下文，禁止重复输出】');
      buffer.writeln(previousContext);
      buffer.writeln();
    }

    buffer.writeln('【用户最新说的内容】');
    buffer.writeln(transcription);
    buffer.writeln();

    buffer.writeln('输出要求：');
    buffer.writeln('1. 只输出这一次新增内容对应的笔记段落，不要重复已有内容。');
    buffer.writeln('2. 内容不足时也要尽量整理成简短、完整的可读句子。');
    buffer.writeln('3. 不要输出解释、前言、总结性客套话。');
    buffer.writeln('4. 不要输出 Markdown 代码块。');
    buffer.writeln('5. 优先输出适合手机阅读的结构化笔记，不要只输出一长串普通项目符号。');
    buffer.writeln('6. 如果你在生成过程中想修改上一句，只输出修改后的最终版本，不要把旧版本和新版本同时输出。');
    buffer.writeln('7. 严禁出现“前一行是后一行前缀”的重复，例如同一句话不断补几个字重新输出。');
    buffer.writeln('8. 同一条要点只能出现一次，不要重复改写同一句。');
    buffer.writeln('9. 第一行输出一个简短主题标题，不要带时间戳。');
    buffer.writeln(
      '10. 标题或小节标题可以从这些 emoji 中选择一个作为前缀，但不固定只用某几个：${_headingEmojis.join('、')}。',
    );
    buffer.writeln('11. 如果内容包含概念解释或定义句，把定义单独放一行，并以“▌”开头。');
    buffer.writeln('12. 普通要点以“•”开头，每条必须是完整句。');
    buffer.writeln(
      '13. 如果内容包含具体例子、对比、步骤参数或结果关系，使用表格行输出，例如“| 事项 | 说明 |”，不要输出 Markdown 分隔线。',
    );
    buffer.writeln('14. 没有足够信息时可以删减小节，不要编造表格或定义。');
    buffer.writeln('15. 只返回新增笔记内容。');

    return buffer.toString();
  }

  String _recentGeneratedContext(String value) {
    final normalized = formatAiNoteText(value);
    if (normalized.isEmpty) {
      return '';
    }

    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return '';
    }

    final selected = <String>[];
    var totalChars = 0;
    for (final line in lines.reversed) {
      if (selected.length >= 24 || totalChars >= 900) {
        break;
      }
      selected.add(line);
      totalChars += line.length;
    }
    return selected.reversed.join('\n');
  }

  String _mergeNoteContent({
    required String existingContent,
    required String incrementalContent,
  }) {
    final existing = formatAiNoteText(existingContent);
    final formattedBlock = _stripRepeatedExistingContent(
      existingContent: existing,
      generatedContent: formatAiNoteText(incrementalContent),
    );
    if (formattedBlock.isEmpty) {
      return existing;
    }
    if (existing.isEmpty) {
      return formattedBlock;
    }
    return formatAiNoteText('${existing.trimRight()}\n\n$formattedBlock');
  }

  void _emitFinalMergedContent({
    required String existingContent,
    required String generatedContent,
  }) {
    final mergedContent = _mergeNoteContent(
      existingContent: existingContent,
      incrementalContent: generatedContent,
    );
    _currentNoteContent = mergedContent;
    _noteStreamController.add(mergedContent);
  }

  String _stableStreamingContent(String value) {
    final normalized = normalizeNoteText(value).trim();
    if (normalized.isEmpty) {
      return '';
    }

    final punctuation = RegExp(r'[。！？；;.!?]\s*$');
    if (punctuation.hasMatch(normalized)) {
      return normalized;
    }

    final lastBreak = normalized.lastIndexOf('\n');
    if (lastBreak > 0) {
      return normalized.substring(0, lastBreak).trim();
    }

    return '';
  }

  bool _isEquivalentStableContent({
    required String previous,
    required String current,
  }) {
    final left = _compactForCompare(previous);
    final right = _compactForCompare(current);
    if (left.isEmpty || right.isEmpty) {
      return false;
    }
    return left == right || right.startsWith(left);
  }

  String _sanitizeGeneratedBlock(String value) {
    final normalized = normalizeNoteText(value);
    if (normalized.isEmpty) {
      return '';
    }

    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final cleaned = <String>[];

    for (final line in lines) {
      if (_isAiMetaComment(line)) {
        continue;
      }

      if (cleaned.isEmpty) {
        cleaned.add(line);
        continue;
      }

      final previous = cleaned.last;
      final previousKey = _compactForCompare(previous);
      final currentKey = _compactForCompare(line);

      if (currentKey.isEmpty) {
        continue;
      }

      if (currentKey == previousKey) {
        continue;
      }

      if (_looksLikeProgressiveRewrite(previousKey, currentKey)) {
        cleaned[cleaned.length - 1] = currentKey.length >= previousKey.length
            ? line
            : previous;
        continue;
      }

      cleaned.add(line);
    }

    return normalizeNoteText(cleaned.join('\n'));
  }

  bool _looksLikeProgressiveRewrite(String previous, String current) {
    if (previous.isEmpty || current.isEmpty) {
      return false;
    }
    if (previous.length < 8 || current.length < 8) {
      return false;
    }
    return previous.startsWith(current) || current.startsWith(previous);
  }

  String _compactForCompare(String value) {
    return compactVoiceText(
      value
          .replaceAll(RegExp(r'^[•▌]+'), '')
          .replaceAll(RegExp(r'[| \t]+'), '')
          .trim(),
    );
  }

  bool _isAiMetaComment(String value) {
    final text = value.trim();
    return text.contains('用户明确表示') ||
        text.contains('不希望继续讨论') ||
        text.contains('不再重复或展开说明') ||
        text.contains('根据用户要求') ||
        text.contains('根据要求') ||
        text.contains('因此不再重复');
  }

  String _stripRepeatedExistingContent({
    required String existingContent,
    required String generatedContent,
  }) {
    if (generatedContent.isEmpty || existingContent.isEmpty) {
      return generatedContent;
    }
    if (generatedContent.startsWith(existingContent)) {
      return generatedContent.substring(existingContent.length).trim();
    }

    final existingLines = existingContent
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(_compactForCompare)
        .where((line) => line.isNotEmpty)
        .toSet();
    final newLines = generatedContent
        .split('\n')
        .map((line) => line.trim())
        .where((line) {
          if (line.isEmpty) {
            return false;
          }
          final key = _compactForCompare(line);
          if (key.isEmpty || existingLines.contains(key)) {
            return false;
          }
          return !existingLines.any((existingKey) {
            if (existingKey.length < 8 || key.length < 8) {
              return false;
            }
            return existingKey.startsWith(key) || key.startsWith(existingKey);
          });
        })
        .toList();
    return newLines.join('\n');
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

  String? _extractDeepseekDeltaContent(String data) {
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

  Future<String> optimizeNoteContent(String content) async {
    final prompt =
        '''
请优化以下笔记内容：
1. 去除重复表述
2. 改进语句，使其更流畅
3. 保持原意不变
4. 只返回优化后的内容

$content
''';
    return _callDeepseekAPI(prompt, fallback: content);
  }

  Future<String> generateTitle(String content) async {
    final prompt =
        '''
请为以下笔记生成一个简洁标题，不超过20个字，只返回标题：

$content
''';
    final title = await _callDeepseekAPI(prompt, fallback: '新笔记');
    final trimmed = title.trim();
    return trimmed.isEmpty ? '新笔记' : trimmed;
  }

  Future<List<String>> extractTags(String content) async {
    final prompt =
        '''
请从以下笔记提取3到5个关键词标签，用逗号分隔，只返回标签：

$content
''';
    final response = await _callDeepseekAPI(prompt, fallback: '');
    return response
        .split(RegExp(r'[，,]'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  Future<String> _callDeepseekAPI(
    String prompt, {
    required String fallback,
  }) async {
    if (_deepseekApiKey == null || _deepseekApiKey.trim().isEmpty) {
      return fallback;
    }

    try {
      final dio = Dio();
      final response = await dio.post(
        _chatCompletionsUrl(
          _customApiUrl ?? AIServiceConfig.getCurrentApiUrl(),
        ),
        options: Options(
          headers: {
            'Authorization': 'Bearer $_deepseekApiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': _customModel ?? AIServiceConfig.getCurrentModel(),
          'messages': [
            {'role': 'system', 'content': '你是拾光笔记的课堂笔记整理助手。'},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.25,
        },
      );

      final choices = response.data['choices'] as List<dynamic>? ?? const [];
      if (choices.isEmpty) {
        return fallback;
      }
      final message =
          choices.first['message'] as Map<String, dynamic>? ?? const {};
      final content = message['content'] as String? ?? fallback;
      return content.trim().isEmpty ? fallback : content;
    } catch (_) {
      return fallback;
    }
  }

  void clearNoteContent() {
    _currentNoteContent = '';
    _lastProcessedTranscription = '';
  }

  void dispose() {
    _noteStreamController.close();
  }
}
