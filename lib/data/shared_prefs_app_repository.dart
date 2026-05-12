import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/course.dart';
import '../models/dashboard_stats.dart';
import '../models/note_entry.dart';
import '../models/photo_record.dart';
import '../models/voice_record.dart';
import '../services/ai/ai_qa_history_service.dart';
import 'app_repository.dart';

class SharedPrefsAppRepository implements AppRepository {
  SharedPrefsAppRepository._(this._rootDir);

  static const _schemaVersion = 2;
  static const _databaseFileName = 'app_data.json';
  static const _notesDirName = 'notes_by_course';
  static const _aiIndexDirName = 'ai_index';
  static const _aiIndexFileName = 'notes_index.json';

  final Directory _rootDir;

  File get _databaseFile => File('${_rootDir.path}/$_databaseFileName');
  Directory get _notesDir => Directory('${_rootDir.path}/$_notesDirName');
  Directory get _aiIndexDir => Directory('${_rootDir.path}/$_aiIndexDirName');
  File get _aiIndexFile => File('${_aiIndexDir.path}/$_aiIndexFileName');

  static Future<SharedPrefsAppRepository> create() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final rootDir = Directory('${documentsDir.path}/shiguang_data');
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }
    return SharedPrefsAppRepository._(rootDir);
  }

  @override
  Future<List<Course>> getCourses() async {
    final data = await _readData();
    return data.courses;
  }

  @override
  Future<DashboardStats> getDashboardStats() async {
    final data = await _readData();
    final notes = data.notes;
    final today = DateTime.now();
    final todayCount = notes.where((note) {
      return note.createdAt.year == today.year &&
          note.createdAt.month == today.month &&
          note.createdAt.day == today.day;
    }).length;

    final voiceMinutes = data.voiceRecords.fold<int>(
      0,
      (sum, record) => sum + (record.durationMs ~/ 60000),
    );

    final aiSummaryCount = notes
        .where((note) => note.aiSummary.trim().isNotEmpty)
        .length;
    final weekStart = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - 1));
    final weekNoteCount = notes
        .where((note) => !note.createdAt.isBefore(weekStart))
        .length;
    final aiQuestionCount = await const AiQaHistoryService()
        .countUserQuestions();

    return DashboardStats(
      todayNoteCount: todayCount,
      voiceMinutes: voiceMinutes,
      streakDays: _calculateStreak(notes),
      aiSummaryCount: aiSummaryCount,
      courseCount: data.courses.length,
      weekNoteCount: weekNoteCount,
      aiQuestionCount: aiQuestionCount,
    );
  }

  @override
  Future<List<NoteEntry>> getNotes() async {
    final data = await _readData();
    return data.notes.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<List<NoteEntry>> getNotesForCourse(String courseId) async {
    final notes = await getNotes();
    return notes.where((note) => note.courseId == courseId).toList();
  }

  @override
  Future<List<PhotoRecord>> getPhotoRecordsForNote(String noteId) async {
    final data = await _readData();
    return data.photoRecords
        .where((record) => record.noteId == noteId)
        .toList();
  }

  @override
  Future<void> saveCourse(Course course) async {
    final data = await _readData();
    final courses = data.courses.toList();
    final index = courses.indexWhere((item) => item.id == course.id);
    if (index == -1) {
      courses.add(course);
    } else {
      courses[index] = course;
    }
    await _writeData(data.copyWith(courses: courses));
  }

  @override
  Future<void> saveNote(NoteEntry note) async {
    final data = await _readData();
    final notes = data.notes.toList();
    final index = notes.indexWhere((item) => item.id == note.id);
    if (index == -1) {
      notes.add(note);
    } else {
      notes[index] = note;
    }
    await _writeData(data.copyWith(notes: notes));
  }

  @override
  Future<void> deleteCourse(String courseId) async {
    final data = await _readData();
    final noteIds = data.notes
        .where((note) => note.courseId == courseId)
        .map((note) => note.id)
        .toSet();
    final relatedPhotoRecords = data.photoRecords
        .where((record) => noteIds.contains(record.noteId))
        .toList();
    final relatedVoiceRecords = data.voiceRecords
        .where((record) => noteIds.contains(record.noteId))
        .toList();
    await _writeData(
      data.copyWith(
        courses: data.courses.where((course) => course.id != courseId).toList(),
        notes: data.notes.where((note) => note.courseId != courseId).toList(),
        photoRecords: data.photoRecords
            .where((record) => !noteIds.contains(record.noteId))
            .toList(),
        voiceRecords: data.voiceRecords
            .where((record) => !noteIds.contains(record.noteId))
            .toList(),
      ),
    );
    await _deleteStoredFiles([
      ...relatedPhotoRecords.map((record) => record.filePath),
      ...relatedVoiceRecords.map((record) => record.filePath),
    ]);
  }

  @override
  Future<void> deleteNote(String noteId) async {
    final data = await _readData();
    final relatedPhotoRecords = data.photoRecords
        .where((record) => record.noteId == noteId)
        .toList();
    final relatedVoiceRecords = data.voiceRecords
        .where((record) => record.noteId == noteId)
        .toList();
    await _writeData(
      data.copyWith(
        notes: data.notes.where((note) => note.id != noteId).toList(),
        photoRecords: data.photoRecords
            .where((record) => record.noteId != noteId)
            .toList(),
        voiceRecords: data.voiceRecords
            .where((record) => record.noteId != noteId)
            .toList(),
      ),
    );
    await _deleteStoredFiles([
      ...relatedPhotoRecords.map((record) => record.filePath),
      ...relatedVoiceRecords.map((record) => record.filePath),
    ]);
  }

  @override
  Future<void> savePhotoRecord(PhotoRecord record) async {
    final data = await _readData();
    final records = data.photoRecords.toList();
    final index = records.indexWhere((item) => item.id == record.id);
    if (index == -1) {
      records.add(record);
    } else {
      records[index] = record;
    }
    await _writeData(data.copyWith(photoRecords: records));
  }

  @override
  Future<void> saveVoiceRecord(VoiceRecord record) async {
    final data = await _readData();
    final records = data.voiceRecords.toList();
    final index = records.indexWhere((item) => item.id == record.id);
    if (index == -1) {
      records.add(record);
    } else {
      records[index] = record;
    }
    await _writeData(data.copyWith(voiceRecords: records));
  }

  Future<_AppData> _readData() async {
    if (!await _databaseFile.exists()) {
      return const _AppData();
    }

    final raw = await _databaseFile.readAsString();
    if (raw.trim().isEmpty) {
      return const _AppData();
    }

    final json = jsonDecode(raw) as Map<String, dynamic>;
    if ((json['schemaVersion'] as int? ?? 0) < _schemaVersion) {
      return const _AppData();
    }
    return _AppData.fromJson(json);
  }

  Future<void> _writeData(_AppData data) async {
    final normalized = data.normalized();
    await _writeJsonFile(_databaseFile, normalized.toJson());
    await _rebuildClassifiedNoteFiles(normalized);
    await _rebuildAiIndex(normalized);
  }

  Future<void> _rebuildClassifiedNoteFiles(_AppData data) async {
    await _replaceDirectory(_notesDir);
    final courseMap = {for (final course in data.courses) course.id: course};
    for (final note in data.notes) {
      final course = courseMap[note.courseId];
      final courseName = course?.name ?? '未分类课程';
      final datePath = _datePath(note.createdAt);
      final title = _safeSegment(note.title.isEmpty ? '未命名笔记' : note.title);
      final file = File(
        '${_notesDir.path}/${_safeSegment(courseName)}/$datePath/'
        '${_timePrefix(note.createdAt)}_${title}_${_safeSegment(note.id)}.json',
      );
      await _writeJsonFile(file, _noteMirrorJson(note, course));
    }
  }

  Future<void> _rebuildAiIndex(_AppData data) async {
    await _aiIndexDir.create(recursive: true);
    final courseMap = {for (final course in data.courses) course.id: course};
    final entries = data.notes.map((note) {
      final course = courseMap[note.courseId];
      return {
        'noteId': note.id,
        'courseId': note.courseId,
        'courseName': course?.name ?? '未分类课程',
        'title': note.title,
        'type': note.type.name,
        'createdAt': note.createdAt.toIso8601String(),
        'updatedAt': note.updatedAt.toIso8601String(),
        'dateKey': _dateKey(note.createdAt),
        'searchText': _buildSearchText(note, course),
        'rawTranscription': note.rawTranscription,
        'textContent': note.textContent,
        'aiSummary': note.aiSummary,
        'tags': note.tags,
        'photoIds': note.photoIds,
      };
    }).toList();

    await _writeJsonFile(_aiIndexFile, {
      'schemaVersion': _schemaVersion,
      'generatedAt': DateTime.now().toIso8601String(),
      'description': '按课程、名称、时间组织的笔记索引，供后续 AI 问答检索使用。',
      'entries': entries,
    });
  }

  Map<String, dynamic> _noteMirrorJson(NoteEntry note, Course? course) {
    return {
      'schemaVersion': _schemaVersion,
      'course': course?.toJson() ?? {'id': note.courseId, 'name': '未分类课程'},
      'note': note.toJson(),
      'aiSearchDocument': {
        'courseName': course?.name ?? '未分类课程',
        'title': note.title,
        'createdAt': note.createdAt.toIso8601String(),
        'updatedAt': note.updatedAt.toIso8601String(),
        'searchText': _buildSearchText(note, course),
      },
    };
  }

  String _buildSearchText(NoteEntry note, Course? course) {
    return [
      course?.name ?? '未分类课程',
      note.title,
      _dateKey(note.createdAt),
      note.rawTranscription,
      note.textContent,
      note.aiSummary,
      note.tags.join(' '),
    ].where((item) => item.trim().isNotEmpty).join('\n');
  }

  Future<void> _replaceDirectory(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
  }

  Future<void> _writeJsonFile(File file, Map<String, dynamic> json) async {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(json), flush: true);
  }

  Future<void> _deleteStoredFiles(Iterable<String> paths) async {
    for (final path in paths) {
      if (path.trim().isEmpty) {
        continue;
      }
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  String _datePath(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year/$month/$day';
  }

  String _dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _timePrefix(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');
    return '$hour$minute$second';
  }

  String _safeSegment(String value) {
    final trimmed = value.trim().isEmpty ? 'untitled' : value.trim();
    return trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  int _calculateStreak(List<NoteEntry> notes) {
    if (notes.isEmpty) {
      return 0;
    }

    final uniqueDays =
        notes
            .map(
              (note) => DateTime(
                note.createdAt.year,
                note.createdAt.month,
                note.createdAt.day,
              ),
            )
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));

    var streak = 0;
    var expected = DateTime.now();

    for (final day in uniqueDays) {
      final normalizedExpected = DateTime(
        expected.year,
        expected.month,
        expected.day,
      );
      if (day == normalizedExpected) {
        streak += 1;
        expected = expected.subtract(const Duration(days: 1));
      } else if (day.isBefore(normalizedExpected)) {
        break;
      }
    }

    return streak;
  }
}

class _AppData {
  const _AppData({
    this.courses = const [],
    this.notes = const [],
    this.photoRecords = const [],
    this.voiceRecords = const [],
  });

  final List<Course> courses;
  final List<NoteEntry> notes;
  final List<PhotoRecord> photoRecords;
  final List<VoiceRecord> voiceRecords;

  factory _AppData.fromJson(Map<String, dynamic> json) {
    return _AppData(
      courses: (json['courses'] as List<dynamic>? ?? const [])
          .map((item) => Course.fromJson(item as Map<String, dynamic>))
          .toList(),
      notes: (json['notes'] as List<dynamic>? ?? const [])
          .map((item) => NoteEntry.fromJson(item as Map<String, dynamic>))
          .toList(),
      photoRecords: (json['photoRecords'] as List<dynamic>? ?? const [])
          .map((item) => PhotoRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
      voiceRecords: (json['voiceRecords'] as List<dynamic>? ?? const [])
          .map((item) => VoiceRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  _AppData copyWith({
    List<Course>? courses,
    List<NoteEntry>? notes,
    List<PhotoRecord>? photoRecords,
    List<VoiceRecord>? voiceRecords,
  }) {
    return _AppData(
      courses: courses ?? this.courses,
      notes: notes ?? this.notes,
      photoRecords: photoRecords ?? this.photoRecords,
      voiceRecords: voiceRecords ?? this.voiceRecords,
    );
  }

  _AppData normalized() {
    return _AppData(
      courses: courses.toList()
        ..sort(
          (a, b) => (a.createdAt ?? DateTime(0)).compareTo(
            b.createdAt ?? DateTime(0),
          ),
        ),
      notes: notes.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      photoRecords: photoRecords.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      voiceRecords: voiceRecords.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': SharedPrefsAppRepository._schemaVersion,
      'updatedAt': DateTime.now().toIso8601String(),
      'courses': courses.map((item) => item.toJson()).toList(),
      'notes': notes.map((item) => item.toJson()).toList(),
      'photoRecords': photoRecords.map((item) => item.toJson()).toList(),
      'voiceRecords': voiceRecords.map((item) => item.toJson()).toList(),
    };
  }
}
