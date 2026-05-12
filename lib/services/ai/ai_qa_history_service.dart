import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/app_repository.dart';
import '../../models/ai_qa_message.dart';
import '../../models/note_entry.dart';

class AiQaHistoryService {
  const AiQaHistoryService();

  static const _schemaVersion = 1;
  static const _fileName = 'ai_qa_history.json';

  Future<List<AiQaSessionSummary>> loadSummaries() async {
    final data = await _readData();
    final sessions = data.sessions.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions
        .map(
          (session) => AiQaSessionSummary(
            id: session.id,
            title: session.title,
            updatedAt: session.updatedAt,
            messageCount: session.messages.length,
          ),
        )
        .toList();
  }

  Future<int> countUserQuestions() async {
    final data = await _readData();
    return data.sessions.fold<int>(0, (sum, session) {
      return sum +
          session.messages
              .where((message) => message.role == AiQaRole.user)
              .length;
    });
  }

  Future<AiQaSession?> loadSession({
    required String id,
    required AppRepository repository,
  }) async {
    final data = await _readData();
    final session = data.sessions
        .where((item) => item.id == id)
        .cast<_PersistedAiQaSession?>()
        .firstWhere((item) => item != null, orElse: () => null);
    if (session == null) {
      return null;
    }

    final notes = await repository.getNotes();
    final noteMap = {for (final note in notes) note.id: note};
    final messages = session.messages.map((message) {
      return AiQaMessage(
        id: message.id,
        role: message.role,
        content: message.content,
        citations: message.citations
            .map((citation) => _hydrateCitation(citation, noteMap))
            .whereType<AiQaCitation>()
            .toList(),
      );
    }).toList();

    return AiQaSession(
      id: session.id,
      title: session.title,
      updatedAt: session.updatedAt,
      messages: messages,
    );
  }

  Future<String?> saveSession({
    required String? sessionId,
    required List<AiQaMessage> messages,
  }) async {
    final savableMessages = messages
        .where((message) => message.id != 'welcome')
        .where((message) => message.content.trim().isNotEmpty)
        .toList();
    if (savableMessages.isEmpty) {
      return sessionId;
    }

    final data = await _readData();
    final now = DateTime.now();
    final id = sessionId ?? 'qa-${now.microsecondsSinceEpoch}';
    final title = _buildTitle(savableMessages);
    final persisted = _PersistedAiQaSession(
      id: id,
      title: title,
      createdAt: now,
      updatedAt: now,
      messages: savableMessages.map(_PersistedAiQaMessage.fromMessage).toList(),
    );

    final sessions = data.sessions.toList();
    final index = sessions.indexWhere((item) => item.id == id);
    if (index == -1) {
      sessions.add(persisted);
    } else {
      final existing = sessions[index];
      sessions[index] = persisted.copyWith(createdAt: existing.createdAt);
    }

    await _writeData(_AiQaHistoryData(sessions: sessions));
    return id;
  }

  AiQaCitation? _hydrateCitation(
    _PersistedAiQaCitation citation,
    Map<String, NoteEntry> noteMap,
  ) {
    final note = noteMap[citation.noteId];
    if (note == null) {
      return null;
    }
    return AiQaCitation(
      note: note,
      courseName: citation.courseName,
      snippet: citation.snippet,
      score: citation.score,
    );
  }

  String _buildTitle(List<AiQaMessage> messages) {
    final firstUserMessage = messages
        .where((message) => message.role == AiQaRole.user)
        .map((message) => message.content.trim())
        .firstWhere((text) => text.isNotEmpty, orElse: () => '新的问答');
    return firstUserMessage.length > 20
        ? '${firstUserMessage.substring(0, 20)}...'
        : firstUserMessage;
  }

  Future<_AiQaHistoryData> _readData() async {
    final file = await _historyFile();
    if (!await file.exists()) {
      return const _AiQaHistoryData();
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const _AiQaHistoryData();
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if ((json['schemaVersion'] as int? ?? 0) < _schemaVersion) {
      return const _AiQaHistoryData();
    }
    return _AiQaHistoryData.fromJson(json);
  }

  Future<void> _writeData(_AiQaHistoryData data) async {
    final file = await _historyFile();
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(data.toJson()), flush: true);
  }

  Future<File> _historyFile() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final rootDir = Directory('${documentsDir.path}/shiguang_data');
    return File('${rootDir.path}/$_fileName');
  }
}

class AiQaSessionSummary {
  const AiQaSessionSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messageCount,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final int messageCount;
}

class AiQaSession {
  const AiQaSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<AiQaMessage> messages;
}

class _AiQaHistoryData {
  const _AiQaHistoryData({this.sessions = const []});

  final List<_PersistedAiQaSession> sessions;

  factory _AiQaHistoryData.fromJson(Map<String, dynamic> json) {
    return _AiQaHistoryData(
      sessions: (json['sessions'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                _PersistedAiQaSession.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': AiQaHistoryService._schemaVersion,
      'updatedAt': DateTime.now().toIso8601String(),
      'sessions': sessions.map((session) => session.toJson()).toList(),
    };
  }
}

class _PersistedAiQaSession {
  const _PersistedAiQaSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<_PersistedAiQaMessage> messages;

  _PersistedAiQaSession copyWith({DateTime? createdAt}) {
    return _PersistedAiQaSession(
      id: id,
      title: title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt,
      messages: messages,
    );
  }

  factory _PersistedAiQaSession.fromJson(Map<String, dynamic> json) {
    return _PersistedAiQaSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? '新的问答',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      messages: (json['messages'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                _PersistedAiQaMessage.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messages': messages.map((message) => message.toJson()).toList(),
    };
  }
}

class _PersistedAiQaMessage {
  const _PersistedAiQaMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.citations,
  });

  final String id;
  final AiQaRole role;
  final String content;
  final List<_PersistedAiQaCitation> citations;

  factory _PersistedAiQaMessage.fromMessage(AiQaMessage message) {
    return _PersistedAiQaMessage(
      id: message.id,
      role: message.role,
      content: message.content,
      citations: message.citations
          .map(_PersistedAiQaCitation.fromCitation)
          .toList(),
    );
  }

  factory _PersistedAiQaMessage.fromJson(Map<String, dynamic> json) {
    return _PersistedAiQaMessage(
      id: json['id'] as String,
      role: AiQaRole.values.firstWhere(
        (role) => role.name == json['role'],
        orElse: () => AiQaRole.assistant,
      ),
      content: json['content'] as String? ?? '',
      citations: (json['citations'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                _PersistedAiQaCitation.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'content': content,
      'citations': citations.map((citation) => citation.toJson()).toList(),
    };
  }
}

class _PersistedAiQaCitation {
  const _PersistedAiQaCitation({
    required this.noteId,
    required this.courseId,
    required this.courseName,
    required this.title,
    required this.snippet,
    required this.score,
  });

  final String noteId;
  final String courseId;
  final String courseName;
  final String title;
  final String snippet;
  final int score;

  factory _PersistedAiQaCitation.fromCitation(AiQaCitation citation) {
    return _PersistedAiQaCitation(
      noteId: citation.note.id,
      courseId: citation.note.courseId,
      courseName: citation.courseName,
      title: citation.note.title,
      snippet: citation.snippet,
      score: citation.score,
    );
  }

  factory _PersistedAiQaCitation.fromJson(Map<String, dynamic> json) {
    return _PersistedAiQaCitation(
      noteId: json['noteId'] as String,
      courseId: json['courseId'] as String? ?? '',
      courseName: json['courseName'] as String? ?? '未分类课程',
      title: json['title'] as String? ?? '未命名笔记',
      snippet: json['snippet'] as String? ?? '',
      score: json['score'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'noteId': noteId,
      'courseId': courseId,
      'courseName': courseName,
      'title': title,
      'snippet': snippet,
      'score': score,
    };
  }
}
