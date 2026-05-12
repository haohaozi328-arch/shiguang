class PhotoRecord {
  const PhotoRecord({
    required this.id,
    required this.noteId,
    required this.filePath,
    required this.createdAt,
    this.caption = '',
  });

  final String id;
  final String noteId;
  final String filePath;
  final String caption;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'noteId': noteId,
      'filePath': filePath,
      'caption': caption,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory PhotoRecord.fromJson(Map<String, dynamic> json) {
    return PhotoRecord(
      id: json['id'] as String,
      noteId: json['noteId'] as String,
      filePath: json['filePath'] as String,
      caption: json['caption'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
