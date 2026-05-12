import '../models/course.dart';
import '../models/dashboard_stats.dart';
import '../models/note_entry.dart';
import '../models/photo_record.dart';
import '../models/voice_record.dart';

abstract class AppRepository {
  Future<List<Course>> getCourses();

  Future<List<NoteEntry>> getNotes();

  Future<List<NoteEntry>> getNotesForCourse(String courseId);

  Future<DashboardStats> getDashboardStats();

  Future<List<PhotoRecord>> getPhotoRecordsForNote(String noteId);

  Future<void> saveCourse(Course course);

  Future<void> saveNote(NoteEntry note);

  Future<void> deleteCourse(String courseId);

  Future<void> deleteNote(String noteId);

  Future<void> saveVoiceRecord(VoiceRecord record);

  Future<void> savePhotoRecord(PhotoRecord record);
}
