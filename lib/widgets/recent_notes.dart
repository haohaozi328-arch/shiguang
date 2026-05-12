import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/course.dart';
import '../models/note_entry.dart';
import '../theme/app_theme.dart';
import '../utils/ui_formatters.dart';
import 'glass_card.dart';

class RecentNotesList extends StatelessWidget {
  const RecentNotesList({super.key, required this.onNote});

  final ValueChanged<NoteEntry> onNote;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AppRepository>();
    return FutureBuilder<List<Object>>(
      future: Future.wait<Object>([
        repository.getNotes(),
        repository.getCourses(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final notes = snapshot.data![0] as List<NoteEntry>;
        final courses = snapshot.data![1] as List<Course>;
        final courseMap = {for (final course in courses) course.id: course};

        if (notes.isEmpty) {
          return GlassCard(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x8CFFF8E1), Color(0x61FFE8A0)],
            ),
            padding: const EdgeInsets.all(16),
            child: const Text(
              '还没有笔记，先录一段语音或者新建一条文字笔记吧。',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSub,
                height: 1.5,
              ),
            ),
          );
        }

        final recentNotes = notes.take(4).toList();

        return GlassCard(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x8CFFF8E1), Color(0x61FFE8A0)],
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            children: List.generate(recentNotes.length, (i) {
              final note = recentNotes[i];
              final course = courseMap[note.courseId];
              return _NoteRow(
                note: _NoteItem(
                  colorFromHex(course?.colorHex ?? '#FFC857'),
                  note.title,
                  _noteTypeLabel(note),
                  _notePreview(note),
                  '${formatRelativeTime(note.updatedAt)} · ${course?.name ?? '未分类'}',
                  note,
                ),
                isLast: i == recentNotes.length - 1,
                onNote: onNote,
              );
            }),
          ),
        );
      },
    );
  }
}

class _NoteRow extends StatefulWidget {
  const _NoteRow({
    required this.note,
    required this.isLast,
    required this.onNote,
  });

  final _NoteItem note;
  final bool isLast;
  final ValueChanged<NoteEntry> onNote;

  @override
  State<_NoteRow> createState() => _NoteRowState();
}

class _NoteRowState extends State<_NoteRow> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => widget.onNote(widget.note.note),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: !widget.isLast
              ? const Border(
                  bottom: BorderSide(color: Color(0x1A96B4D2), width: 1),
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.note.dot,
                boxShadow: [
                  BoxShadow(
                    color: widget.note.dot.withValues(alpha: 0.4),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: widget.note.dot.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _iconForType(widget.note.note.type),
                              size: 11,
                              color: widget.note.dot,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.note.typeLabel,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: widget.note.dot,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.note.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textDark,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.note.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0x8A244A6E),
                      height: 1.45,
                    ),
                  ),
                  Text(
                    widget.note.time,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSub,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textSub.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteItem {
  const _NoteItem(
    this.dot,
    this.title,
    this.typeLabel,
    this.preview,
    this.time,
    this.note,
  );

  final Color dot;
  final String title;
  final String typeLabel;
  final String preview;
  final String time;
  final NoteEntry note;
}

IconData _iconForType(NoteType type) {
  switch (type) {
    case NoteType.voice:
      return Icons.mic;
    case NoteType.photo:
      return Icons.camera_alt;
    case NoteType.mixed:
      return Icons.auto_awesome;
    case NoteType.text:
      return Icons.note;
  }
}

String _noteTypeLabel(NoteEntry note) {
  switch (note.type) {
    case NoteType.voice:
      return '语音';
    case NoteType.photo:
      return '图片';
    case NoteType.mixed:
      return '混合';
    case NoteType.text:
      return '文字';
  }
}

String _notePreview(NoteEntry note) {
  switch (note.type) {
    case NoteType.photo:
      return note.photoIds.isEmpty ? '图片笔记' : '已记录 ${note.photoIds.length} 张图片';
    case NoteType.voice:
      return _firstNonEmpty([note.rawTranscription, note.aiSummary, '语音识别笔记']);
    case NoteType.mixed:
      final photoText = note.photoIds.isEmpty
          ? ''
          : '含 ${note.photoIds.length} 张图片';
      return _firstNonEmpty([
        note.aiSummary,
        note.textContent,
        note.rawTranscription,
        photoText,
        '混合内容笔记',
      ]);
    case NoteType.text:
      return _firstNonEmpty([note.textContent, note.aiSummary, '文字笔记']);
  }
}

String _firstNonEmpty(List<String> values) {
  final match = values.firstWhere(
    (value) => value.trim().isNotEmpty,
    orElse: () => '',
  );
  final normalized = match.replaceAll('\n', ' ').trim();
  if (normalized.length > 22) {
    return '${normalized.substring(0, 22)}…';
  }
  return normalized;
}
