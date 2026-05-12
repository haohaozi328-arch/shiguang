enum NoteType { voice, text, photo, mixed }

enum AiGenerationState { idle, generating, failed, completed }

class NoteEntry {
  const NoteEntry({
    required this.id,
    required this.courseId,
    required this.title,
    required this.type,
    this.rawTranscription = '',
    this.textContent = '',
    this.aiSummary = '',
    this.aiGenerationState = AiGenerationState.idle,
    this.aiGenerationSource = '',
    this.aiGenerationError = '',
    this.photoIds = const [],
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String courseId;
  final String title;
  final NoteType type;
  final String rawTranscription;
  final String textContent;
  final String aiSummary;
  final AiGenerationState aiGenerationState;
  final String aiGenerationSource;
  final String aiGenerationError;
  final List<String> photoIds;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  NoteEntry copyWith({
    String? id,
    String? courseId,
    String? title,
    NoteType? type,
    String? rawTranscription,
    String? textContent,
    String? aiSummary,
    AiGenerationState? aiGenerationState,
    String? aiGenerationSource,
    String? aiGenerationError,
    List<String>? photoIds,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteEntry(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      title: title ?? this.title,
      type: type ?? this.type,
      rawTranscription: rawTranscription ?? this.rawTranscription,
      textContent: textContent ?? this.textContent,
      aiSummary: aiSummary ?? this.aiSummary,
      aiGenerationState: aiGenerationState ?? this.aiGenerationState,
      aiGenerationSource: aiGenerationSource ?? this.aiGenerationSource,
      aiGenerationError: aiGenerationError ?? this.aiGenerationError,
      photoIds: photoIds ?? this.photoIds,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'courseId': courseId,
      'title': title,
      'type': type.name,
      'rawTranscription': rawTranscription,
      'textContent': textContent,
      'aiSummary': aiSummary,
      'aiGenerationState': aiGenerationState.name,
      'aiGenerationSource': aiGenerationSource,
      'aiGenerationError': aiGenerationError,
      'photoIds': photoIds,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory NoteEntry.fromJson(Map<String, dynamic> json) {
    return NoteEntry(
      id: json['id'] as String,
      courseId: json['courseId'] as String,
      title: json['title'] as String,
      type: NoteType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => NoteType.text,
      ),
      rawTranscription: json['rawTranscription'] as String? ?? '',
      textContent: json['textContent'] as String? ?? '',
      aiSummary: json['aiSummary'] as String? ?? '',
      aiGenerationState: AiGenerationState.values.firstWhere(
        (value) => value.name == json['aiGenerationState'],
        orElse: () => AiGenerationState.idle,
      ),
      aiGenerationSource: json['aiGenerationSource'] as String? ?? '',
      aiGenerationError: json['aiGenerationError'] as String? ?? '',
      photoIds: (json['photoIds'] as List<dynamic>? ?? const [])
          .map((item) => item as String)
          .toList(),
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((item) => item as String)
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
