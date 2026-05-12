import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/ui_formatters.dart';

class AiNoteExportService {
  const AiNoteExportService();

  Future<void> exportMarkdown({
    required String title,
    required String courseName,
    required String aiContent,
    Rect? sharePositionOrigin,
  }) async {
    final content = formatAiNoteText(aiContent);
    if (content.isEmpty) {
      throw StateError('AI整理内容为空，无法导出');
    }

    final exportedAt = DateTime.now();
    final fileName =
        '${_safeFileName(title.isEmpty ? 'AI整理' : title)}_${_fileTime(exportedAt)}.md';
    final directory = await getTemporaryDirectory();
    final exportDir = Directory('${directory.path}/shiguang_ai_exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final file = File('${exportDir.path}/$fileName');
    await file.writeAsString(
      _buildMarkdown(
        title: title,
        courseName: courseName,
        exportedAt: exportedAt,
        content: content,
      ),
      flush: true,
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/markdown')],
        subject: title.isEmpty ? 'AI整理' : title,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  String _buildMarkdown({
    required String title,
    required String courseName,
    required DateTime exportedAt,
    required String content,
  }) {
    final normalizedTitle = title.trim().isEmpty ? 'AI整理' : title.trim();
    final normalizedCourse = courseName.trim().isEmpty
        ? '未分类课程'
        : courseName.trim();
    return [
      '# ${_escapeHeading(normalizedTitle)}',
      '',
      '- 课程：$normalizedCourse',
      '- 导出时间：${_displayTime(exportedAt)}',
      '',
      '---',
      '',
      _markdownBody(content),
      '',
    ].join('\n');
  }

  String _markdownBody(String content) {
    return content
        .split('\n')
        .map((line) {
          final trimmed = line.trim();
          if (trimmed.startsWith('▌')) {
            return '> ${trimmed.substring(1).trim()}';
          }
          return line;
        })
        .join('\n');
  }

  String _displayTime(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '${time.year}-$month-$day $hour:$minute';
  }

  String _fileTime(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '${time.year}$month$day-$hour$minute$second';
  }

  String _safeFileName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (cleaned.isEmpty) {
      return 'AI整理';
    }
    return cleaned.length > 36 ? cleaned.substring(0, 36) : cleaned;
  }

  String _escapeHeading(String value) {
    return value.replaceAll(RegExp(r'^[#]+\s*'), '');
  }
}
