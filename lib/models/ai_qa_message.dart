import 'note_entry.dart';

class AiQaCitation {
  const AiQaCitation({
    required this.note,
    required this.courseName,
    required this.snippet,
    required this.score,
  });

  final NoteEntry note;
  final String courseName;
  final String snippet;
  final int score;
}

class AiQaMessage {
  const AiQaMessage({
    required this.id,
    required this.role,
    required this.content,
    this.citations = const [],
  });

  final String id;
  final AiQaRole role;
  final String content;
  final List<AiQaCitation> citations;

  AiQaMessage copyWith({String? content, List<AiQaCitation>? citations}) {
    return AiQaMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      citations: citations ?? this.citations,
    );
  }
}

enum AiQaRole { user, assistant }
