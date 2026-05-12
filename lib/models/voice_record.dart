class VoiceRecord {
  const VoiceRecord({
    required this.id,
    required this.noteId,
    required this.filePath,
    required this.durationMs,
    required this.createdAt,
    this.sampleRate = 16000,
    this.transcription = '',
  });

  final String id;
  final String noteId;
  final String filePath;
  final int durationMs;
  final int sampleRate;
  final String transcription;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'noteId': noteId,
      'filePath': filePath,
      'durationMs': durationMs,
      'sampleRate': sampleRate,
      'transcription': transcription,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory VoiceRecord.fromJson(Map<String, dynamic> json) {
    return VoiceRecord(
      id: json['id'] as String,
      noteId: json['noteId'] as String,
      filePath: json['filePath'] as String,
      durationMs: json['durationMs'] as int? ?? 0,
      sampleRate: json['sampleRate'] as int? ?? 16000,
      transcription: json['transcription'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
