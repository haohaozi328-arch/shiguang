import '../models/course.dart';
import '../models/dashboard_stats.dart';
import '../models/note_entry.dart';
import '../models/photo_record.dart';
import '../models/voice_record.dart';
import 'app_repository.dart';

class InMemoryAppRepository implements AppRepository {
  final List<Course> _courses = [];
  final List<NoteEntry> _notes = [];
  final List<VoiceRecord> _voiceRecords = [];
  final List<PhotoRecord> _photoRecords = [];

  @override
  Future<List<Course>> getCourses() async => List.unmodifiable(_courses);

  @override
  Future<DashboardStats> getDashboardStats() async {
    final now = DateTime.now();
    final todayCount = _notes.where((note) {
      return note.createdAt.year == now.year &&
          note.createdAt.month == now.month &&
          note.createdAt.day == now.day;
    }).length;
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    return DashboardStats(
      todayNoteCount: todayCount,
      voiceMinutes: _voiceRecords.fold(
        0,
        (sum, item) => sum + (item.durationMs ~/ 60000),
      ),
      streakDays: _notes.isEmpty ? 0 : 1,
      aiSummaryCount: _notes
          .where((note) => note.aiSummary.trim().isNotEmpty)
          .length,
      courseCount: _courses.length,
      weekNoteCount: _notes
          .where((note) => !note.createdAt.isBefore(weekStart))
          .length,
      aiQuestionCount: 0,
    );
  }

  @override
  Future<List<NoteEntry>> getNotes() async => List.unmodifiable(_notes);

  @override
  Future<List<NoteEntry>> getNotesForCourse(String courseId) async {
    return _notes.where((note) => note.courseId == courseId).toList();
  }

  @override
  Future<List<PhotoRecord>> getPhotoRecordsForNote(String noteId) async {
    return _photoRecords.where((record) => record.noteId == noteId).toList();
  }

  @override
  Future<void> saveCourse(Course course) async {
    final index = _courses.indexWhere((item) => item.id == course.id);
    if (index == -1) {
      _courses.add(course);
    } else {
      _courses[index] = course;
    }
  }

  @override
  Future<void> saveNote(NoteEntry note) async {
    final index = _notes.indexWhere((item) => item.id == note.id);
    if (index == -1) {
      _notes.add(note);
    } else {
      _notes[index] = note;
    }
  }

  @override
  Future<void> deleteCourse(String courseId) async {
    final noteIds = _notes
        .where((note) => note.courseId == courseId)
        .map((note) => note.id)
        .toSet();
    _courses.removeWhere((course) => course.id == courseId);
    _notes.removeWhere((note) => note.courseId == courseId);
    _photoRecords.removeWhere((record) => noteIds.contains(record.noteId));
    _voiceRecords.removeWhere((record) => noteIds.contains(record.noteId));
  }

  @override
  Future<void> deleteNote(String noteId) async {
    _notes.removeWhere((note) => note.id == noteId);
    _photoRecords.removeWhere((record) => record.noteId == noteId);
    _voiceRecords.removeWhere((record) => record.noteId == noteId);
  }

  @override
  Future<void> savePhotoRecord(PhotoRecord record) async {
    final index = _photoRecords.indexWhere((item) => item.id == record.id);
    if (index == -1) {
      _photoRecords.add(record);
    } else {
      _photoRecords[index] = record;
    }
  }

  @override
  Future<void> saveVoiceRecord(VoiceRecord record) async {
    final index = _voiceRecords.indexWhere((item) => item.id == record.id);
    if (index == -1) {
      _voiceRecords.add(record);
    } else {
      _voiceRecords[index] = record;
    }
  }
}
