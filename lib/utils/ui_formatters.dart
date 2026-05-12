import 'package:flutter/material.dart';

Color colorFromHex(String hex, {Color fallback = const Color(0xFFA8EDDA)}) {
  final normalized = hex.replaceAll('#', '').trim();
  if (normalized.length != 6 && normalized.length != 8) {
    return fallback;
  }

  final value = int.tryParse(
    normalized.length == 6 ? 'FF$normalized' : normalized,
    radix: 16,
  );

  return value == null ? fallback : Color(value);
}

String formatRelativeTime(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) {
    return '刚刚';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes} 分钟前';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours} 小时前';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays} 天前';
  }
  return '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

String normalizeNoteText(String value) {
  return value
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', ' ')
      .replaceAll(RegExp(r'[ \t\u00A0]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String compactVoiceText(String value) {
  return _removeCjkSpaces(
    normalizeNoteText(
      value,
    ).replaceAll(RegExp(r'\n+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
  );
}

String formatVoiceTranscription(
  String value, {
  int lineLength = 30,
  int paragraphLines = 4,
}) {
  final normalized = compactVoiceText(value);
  if (normalized.isEmpty) {
    return '';
  }

  final buffer = StringBuffer();
  var currentLineLength = 0;
  for (var i = 0; i < normalized.length; i++) {
    final char = normalized[i];
    buffer.write(char);
    currentLineLength++;

    final isSentenceEnd = RegExp(r'[。！？!?；;，,]').hasMatch(char);
    final shouldBreak = isSentenceEnd || currentLineLength >= lineLength;
    if (shouldBreak && i < normalized.length - 1) {
      buffer.write('\n');
      currentLineLength = 0;
    }
  }

  final lines = normalizeNoteText(
    buffer.toString(),
  ).split('\n').where((line) => line.trim().isNotEmpty).toList();
  if (paragraphLines <= 0 || lines.length <= paragraphLines) {
    return lines.join('\n');
  }

  final grouped = <String>[];
  for (var i = 0; i < lines.length; i += paragraphLines) {
    grouped.add(lines.skip(i).take(paragraphLines).join('\n'));
  }
  return grouped.join('\n\n');
}

String formatVoicePreview(String value, {int maxChars = 140}) {
  final compact = compactVoiceText(value);
  if (compact.isEmpty) {
    return '';
  }
  final start = compact.length > maxChars ? compact.length - maxChars : 0;
  return formatVoiceTranscription(
    compact.substring(start),
    lineLength: 24,
    paragraphLines: 0,
  );
}

String formatTimestampedVoiceTranscription(String value) {
  final normalized = _normalizeVoiceTimestampLines(value);
  if (normalized.isEmpty) {
    return '';
  }

  final output = StringBuffer();
  final textLines = <String>[];

  void flushTextLines() {
    if (textLines.isEmpty) {
      return;
    }
    final formatted = _formatVoiceParagraphs(textLines.join('，'));
    if (formatted.isNotEmpty) {
      if (output.isNotEmpty) {
        output.write('\n');
      }
      output.writeln(formatted);
    }
    textLines.clear();
  }

  for (final rawLine in normalized.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (_isAiMetaComment(line)) {
      continue;
    }

    if (RegExp(r'^\[\d{2,}:\d{2}\]$').hasMatch(line)) {
      continue;
    }

    if (RegExp(r'^\d{4}\.\d{1,2}\.\d{1,2} \d{1,2}:\d{2}$').hasMatch(line)) {
      flushTextLines();
      if (output.isNotEmpty) {
        output.write('\n');
      }
      output.writeln(line);
      continue;
    }

    textLines.add(line);
  }

  flushTextLines();
  return _dedupeVoiceTimestampBlocks(normalizeNoteText(output.toString()));
}

String formatVoiceParagraph(String value) {
  var text = compactVoiceText(value);
  if (text.isEmpty) {
    return '';
  }

  text = text
      .replaceAll(RegExp(r'[。！？!?；;]+'), '，')
      .replaceAll(RegExp(r'[,.]+'), '，')
      .replaceAll(RegExp(r'，{2,}'), '，')
      .replaceAll(RegExp(r'，\s*，'), '，')
      .trim();
  text = _insertVoiceCommas(text);
  if (text.endsWith('，')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

String _formatVoiceParagraphs(String value) {
  final formatted = formatVoiceParagraph(value);
  if (formatted.isEmpty || formatted.length <= 150) {
    return formatted;
  }

  final parts = formatted.split('，');
  final paragraphs = <String>[];
  final current = StringBuffer();
  for (final rawPart in parts) {
    final part = rawPart.trim();
    if (part.isEmpty) {
      continue;
    }
    if (current.isNotEmpty) {
      current.write('，');
    }
    current.write(part);
    if (current.length >= 150) {
      paragraphs.add(current.toString());
      current.clear();
    }
  }
  if (current.isNotEmpty) {
    paragraphs.add(current.toString());
  }
  return paragraphs.join('\n\n');
}

String _normalizeVoiceTimestampLines(String value) {
  return normalizeNoteText(value)
      .replaceAllMapped(RegExp(r'\s*\[\d{2,}:\d{2}\]\s*'), (_) => '\n')
      .replaceAllMapped(
        RegExp(r'\s*(\d{4}\.\d{1,2}\.\d{1,2} \d{1,2}:\d{2})\s*'),
        (match) => '\n${match.group(1)}\n',
      );
}

String _dedupeVoiceTimestampBlocks(String value) {
  final normalized = normalizeNoteText(value);
  if (normalized.isEmpty) {
    return '';
  }

  final timestampPattern = RegExp(r'^\d{4}\.\d{1,2}\.\d{1,2} \d{1,2}:\d{2}$');
  final stamps = <String>[];
  final texts = <String>[];
  String? currentStamp;
  final currentText = StringBuffer();

  void flushBlock() {
    final text = normalizeNoteText(currentText.toString());
    final stamp = currentStamp;
    if (stamp == null) {
      if (text.isNotEmpty) {
        stamps.add('');
        texts.add(text);
      }
    } else {
      stamps.add(stamp);
      texts.add(text);
    }
    currentText.clear();
  }

  for (final rawLine in normalized.split('\n')) {
    final line = rawLine.trim();
    if (timestampPattern.hasMatch(line)) {
      flushBlock();
      currentStamp = line;
      continue;
    }
    if (line.isNotEmpty) {
      if (currentText.isNotEmpty) {
        currentText.writeln();
      }
      currentText.write(line);
    }
  }
  flushBlock();

  final dedupedStamps = <String>[];
  final dedupedTexts = <String>[];
  for (var i = 0; i < stamps.length; i++) {
    final stamp = stamps[i];
    final text = texts[i];
    if (stamp.isNotEmpty &&
        dedupedStamps.isNotEmpty &&
        dedupedStamps.last == stamp) {
      final previousKey = _voiceDuplicateKey(dedupedTexts.last);
      final currentKey = _voiceDuplicateKey(text);
      if (currentKey.contains(previousKey)) {
        dedupedTexts[dedupedTexts.length - 1] = text;
        continue;
      }
      if (previousKey.contains(currentKey)) {
        continue;
      }
    }
    dedupedStamps.add(stamp);
    dedupedTexts.add(text);
  }

  final output = StringBuffer();
  for (var i = 0; i < dedupedStamps.length; i++) {
    final stamp = dedupedStamps[i];
    final text = dedupedTexts[i];
    if (output.isNotEmpty) {
      output.write('\n\n');
    }
    if (stamp.isNotEmpty) {
      output.writeln(stamp);
    }
    if (text.isNotEmpty) {
      output.write(text);
    }
  }
  return normalizeNoteText(output.toString());
}

String _voiceDuplicateKey(String value) {
  return compactVoiceText(value).replaceAll(RegExp(r'[，。！？!?；;,.。\n ]+'), '');
}

String _insertVoiceCommas(String value, {int phraseLength = 60}) {
  if (value.length <= phraseLength) {
    return value;
  }

  final buffer = StringBuffer();
  var charsSinceComma = 0;
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    buffer.write(char);
    if (char == '，') {
      charsSinceComma = 0;
      continue;
    }

    charsSinceComma++;
    final next = i < value.length - 1 ? value[i + 1] : '';
    final canBreak =
        charsSinceComma >= phraseLength &&
        i < value.length - 1 &&
        char != '[' &&
        next != ']' &&
        next != '，';
    if (canBreak) {
      buffer.write('，');
      charsSinceComma = 0;
    }
  }
  return buffer.toString().replaceAll(RegExp(r'，{2,}'), '，');
}

String formatAiNoteText(String value) {
  var text = normalizeNoteText(value);
  if (text.isEmpty) {
    return '';
  }

  text = text
      .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
      .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ')
      .replaceAll(RegExp(r'^\s*[>｜]\s*', multiLine: true), '▌')
      .replaceAll(RegExp(r'^\s{2,}', multiLine: true), '');

  final output = <String>[];
  var hasHeadingInBlock = false;
  for (final rawLine in normalizeNoteText(text).split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (RegExp(r'^\[\d{2}:\d{2}\]$').hasMatch(line)) {
      hasHeadingInBlock = false;
      continue;
    }
    if (_looksLikeAiTableLine(line)) {
      output.add(_normalizeAiTableLine(line));
      continue;
    }
    if (line.startsWith('•')) {
      final body = line.substring(1).trim();
      if (_isIncompleteAiPoint(body)) {
        continue;
      }
      output.add('• $body');
      continue;
    }
    if (line.startsWith('▌')) {
      final body = line.substring(1).trim();
      if (body.length >= 6) {
        output.add('▌$body');
      }
      continue;
    }
    if (!hasHeadingInBlock && _looksLikeAiHeading(line)) {
      output.add(line);
      hasHeadingInBlock = true;
      continue;
    }
    if (_isIncompleteAiPoint(line)) {
      continue;
    }
    output.add('• $line');
  }

  return normalizeNoteText(output.join('\n'));
}

bool _looksLikeAiTableLine(String value) {
  final text = value.trim();
  if (!text.contains('|')) {
    return false;
  }
  final cells = text
      .split('|')
      .map((cell) => cell.trim())
      .where((cell) => cell.isNotEmpty)
      .toList();
  return cells.length >= 2;
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

String _normalizeAiTableLine(String value) {
  final cells = value
      .split('|')
      .map((cell) => cell.trim())
      .where((cell) => cell.isNotEmpty)
      .toList();
  return '| ${cells.join(' | ')} |';
}

bool _looksLikeAiHeading(String value) {
  if (value.length < 4) {
    return false;
  }
  return !value.contains('：') &&
      !value.contains(':') &&
      !RegExp(r'[，。！？!?；;]$').hasMatch(value);
}

bool _isIncompleteAiPoint(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return true;
  }
  if (text.length <= 4 && !text.contains('：') && !text.contains(':')) {
    return true;
  }
  if (text.length <= 8 &&
      !text.contains('：') &&
      !text.contains(':') &&
      !RegExp(r'[，。！？!?；;]$').hasMatch(text)) {
    return true;
  }
  final colonIndex = _firstColon(text);
  if (colonIndex >= 0 && colonIndex >= text.length - 2) {
    return true;
  }
  return false;
}

int _firstColon(String value) {
  final chinese = value.indexOf('：');
  final english = value.indexOf(':');
  if (chinese < 0) {
    return english;
  }
  if (english < 0) {
    return chinese;
  }
  return chinese < english ? chinese : english;
}

bool _isCjk(String char) {
  if (char.isEmpty) {
    return false;
  }
  final code = char.codeUnitAt(0);
  return (code >= 0x3400 && code <= 0x9FFF) ||
      (code >= 0xF900 && code <= 0xFAFF);
}

String _removeCjkSpaces(String value) {
  if (value.length < 3) {
    return value;
  }

  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == ' ' && i > 0 && i < value.length - 1) {
      final prev = value[i - 1];
      final next = value[i + 1];
      if (_isCjk(prev) && _isCjk(next)) {
        continue;
      }
    }
    buffer.write(char);
  }
  return buffer.toString();
}
