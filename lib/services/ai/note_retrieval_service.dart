import '../../data/app_repository.dart';
import '../../models/ai_qa_message.dart';
import '../../models/course.dart';
import '../../models/note_entry.dart';
import '../../utils/ui_formatters.dart';

class NoteRetrievalService {
  const NoteRetrievalService(this._repository);

  final AppRepository _repository;

  Future<List<AiQaCitation>> search({
    required String question,
    String? courseId,
    int limit = 5,
  }) async {
    final query = normalizeNoteText(question);
    if (query.isEmpty) {
      return const [];
    }

    final courses = await _repository.getCourses();
    final courseMap = {for (final course in courses) course.id: course};
    final notes = courseId == null
        ? await _repository.getNotes()
        : await _repository.getNotesForCourse(courseId);
    final terms = _queryTerms(query);

    final results = <AiQaCitation>[];
    for (final note in notes) {
      final course = courseMap[note.courseId];
      final haystack = _searchDocument(note, course);
      if (haystack.trim().isEmpty) {
        continue;
      }
      final score = _scoreNote(
        query: query,
        terms: terms,
        note: note,
        course: course,
        haystack: haystack,
      );
      if (score <= 0) {
        continue;
      }
      results.add(
        AiQaCitation(
          note: note,
          courseName: course?.name ?? '未分类课程',
          snippet: _bestSnippet(haystack, terms),
          score: score,
        ),
      );
    }

    results.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return b.note.updatedAt.compareTo(a.note.updatedAt);
    });
    return results.take(limit).toList();
  }

  List<String> _queryTerms(String query) {
    final normalized = query.toLowerCase();
    final words = RegExp(r'[a-zA-Z0-9]+|[\u4e00-\u9fa5]{2,}')
        .allMatches(normalized)
        .map((match) => match.group(0)!)
        .where((term) => term.trim().isNotEmpty)
        .toSet()
        .toList();

    final chars = normalized
        .replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), '')
        .split('')
        .where((char) => char.trim().isNotEmpty)
        .toSet();

    return [...words, ...chars].take(40).toList();
  }

  int _scoreNote({
    required String query,
    required List<String> terms,
    required NoteEntry note,
    required Course? course,
    required String haystack,
  }) {
    final lowerHaystack = haystack.toLowerCase();
    final title = note.title.toLowerCase();
    final courseName = (course?.name ?? '').toLowerCase();
    final aiSummary = note.aiSummary.toLowerCase();
    var score = 0;

    if (lowerHaystack.contains(query.toLowerCase())) {
      score += 80;
    }
    for (final term in terms) {
      if (term.length > 1 && title.contains(term)) {
        score += 24;
      }
      if (term.length > 1 && courseName.contains(term)) {
        score += 18;
      }
      if (aiSummary.contains(term)) {
        score += term.length > 1 ? 12 : 3;
      }
      if (lowerHaystack.contains(term)) {
        score += term.length > 1 ? 8 : 1;
      }
    }
    if (note.aiSummary.trim().isNotEmpty) {
      score += 3;
    }
    return score;
  }

  String _searchDocument(NoteEntry note, Course? course) {
    return [
      course?.name ?? '未分类课程',
      note.title,
      note.aiSummary,
      note.textContent,
      note.rawTranscription,
      note.tags.join(' '),
    ].where((item) => item.trim().isNotEmpty).join('\n');
  }

  String _bestSnippet(String value, List<String> terms) {
    final text = normalizeNoteText(value).replaceAll(RegExp(r'\n{3,}'), '\n\n');
    if (text.length <= 520) {
      return text;
    }

    final lower = text.toLowerCase();
    var hit = -1;
    for (final term in terms.where((term) => term.length > 1)) {
      hit = lower.indexOf(term.toLowerCase());
      if (hit != -1) {
        break;
      }
    }
    final center = hit == -1 ? 0 : hit;
    final start = (center - 180).clamp(0, text.length);
    final end = (start + 520).clamp(0, text.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < text.length ? '...' : '';
    return '$prefix${text.substring(start, end).trim()}$suffix';
  }
}
