import 'package:flutter/material.dart';
import 'dart:async';
import '../services/ai/realtime_transcription_service.dart';
import '../services/ai/ai_notes_generation_service.dart';
import '../services/ai/ai_service_config.dart';

/// 实时笔记生成Provider - 管理语音转录和AI笔记生成的状态
class RealtimeNoteProvider extends ChangeNotifier {
  final RealtimeTranscriptionService _transcriptionService;
  final AINotesGenerationService _aiService;

  // 状态变量
  String _transcribedText = '';
  String _partialTranscribedText = '';
  String _generatedNoteContent = '';
  String _noteTitle = '';
  List<String> _noteTags = [];
  bool _isRecording = false;
  bool _isGenerating = false;
  String? _error;

  // 上下文管理
  String _transcriptionHistory = '';
  final int _maxHistoryLength = 500;

  // 流订阅
  StreamSubscription? _transcriptionSubscription;
  StreamSubscription? _partialTranscriptionSubscription;
  StreamSubscription? _isListeningSubscription;
  StreamSubscription? _noteStreamSubscription;

  // 生成控制
  Timer? _generateDebounceTimer;
  final Duration _generateDebounce = Duration(milliseconds: 500);

  // Getters
  String get transcribedText => _transcribedText;
  String get partialTranscribedText => _partialTranscribedText;
  String get generatedNoteContent => _generatedNoteContent;
  String get noteTitle => _noteTitle;
  List<String> get noteTags => _noteTags;
  bool get isRecording => _isRecording;
  bool get isGenerating => _isGenerating;
  String? get error => _error;

  RealtimeNoteProvider(this._transcriptionService, this._aiService) {
    _setupListeners();
  }

  /// 设置流监听
  void _setupListeners() {
    // 监听完整转录文本
    _transcriptionSubscription = _transcriptionService.transcriptionStream
        .listen(
          (text) {
            _transcribedText = text;
            _error = null;
            notifyListeners();
            _debouncedGenerateNote();
          },
          onError: (error) {
            _error = error.toString();
            notifyListeners();
          },
        );

    // 监听部分转录文本（用于实时显示）
    _partialTranscriptionSubscription = _transcriptionService
        .partialTranscriptionStream
        .listen((text) {
          _partialTranscribedText = text;
          notifyListeners();
        });

    // 监听录音状态
    _isListeningSubscription = _transcriptionService.isListeningStream.listen((
      isListening,
    ) {
      _isRecording = isListening;
      notifyListeners();
    });

    // 监听 AI 生成的笔记内容
    _noteStreamSubscription = _aiService.noteStream.listen(
      (content) {
        _generatedNoteContent = content;
        _isGenerating = false;
        _error = null;
        notifyListeners();
      },
      onError: (error) {
        _error = error.toString();
        _isGenerating = false;
        notifyListeners();
      },
    );
  }

  /// 防抖生成笔记
  void _debouncedGenerateNote() {
    _generateDebounceTimer?.cancel();
    _generateDebounceTimer = Timer(_generateDebounce, () {
      _generateNoteFromTranscription();
    });
  }

  /// 生成笔记内容
  Future<void> _generateNoteFromTranscription() async {
    if (_transcribedText.isEmpty) return;

    _isGenerating = true;
    notifyListeners();

    try {
      await _aiService.generateNoteContent(
        transcription: _transcribedText,
        existingContent: _generatedNoteContent,
        previousContext: _transcriptionHistory,
      );

      _updateTranscriptionHistory(_transcribedText);
    } catch (e) {
      _error = e.toString();
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// 更新转录历史
  void _updateTranscriptionHistory(String newText) {
    _transcriptionHistory += '$newText ';

    if (_transcriptionHistory.length > _maxHistoryLength) {
      _transcriptionHistory = _transcriptionHistory.substring(
        _transcriptionHistory.length - _maxHistoryLength,
      );
    }
  }

  /// 开始录音
  Future<void> startRecording() async {
    try {
      _error = null;
      _transcribedText = '';
      _generatedNoteContent = '';
      _transcriptionHistory = '';
      _isRecording = true;
      notifyListeners();

      // 配置云端 ASR 参数
      _transcriptionService.configure(
        url: AIServiceConfig.getAsrUrl(),
        key: AIServiceConfig.getAsrApiKey(),
        model: AIServiceConfig.getAsrModel(),
      );

      await _transcriptionService.startListening();
    } catch (e) {
      _error = e.toString();
      _isRecording = false;
      notifyListeners();
    }
  }

  /// 停止录音
  Future<void> stopRecording() async {
    try {
      _generateDebounceTimer?.cancel();
      _isRecording = false;
      notifyListeners();

      await _transcriptionService.stopListening();

      if (_generatedNoteContent.isNotEmpty) {
        await _finalizeNote();
      }
    } catch (e) {
      _error = e.toString();
      _isRecording = false;
      notifyListeners();
    }
  }

  /// 最终化笔记
  Future<void> _finalizeNote() async {
    try {
      _isGenerating = true;
      notifyListeners();

      final results = await Future.wait([
        _aiService.optimizeNoteContent(_generatedNoteContent),
        _aiService.generateTitle(_generatedNoteContent),
        _aiService.extractTags(_generatedNoteContent),
      ]);

      _generatedNoteContent = results[0] as String;
      _noteTitle = results[1] as String;
      _noteTags = results[2] as List<String>;

      _isGenerating = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// 手动优化笔记
  Future<void> optimizeNote() async {
    if (_generatedNoteContent.isEmpty) return;

    try {
      _isGenerating = true;
      notifyListeners();

      _generatedNoteContent = await _aiService.optimizeNoteContent(
        _generatedNoteContent,
      );

      _isGenerating = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// 重新生成标题
  Future<void> regenerateTitle() async {
    if (_generatedNoteContent.isEmpty) return;

    try {
      _noteTitle = await _aiService.generateTitle(_generatedNoteContent);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 重新提取标签
  Future<void> regenerateTags() async {
    if (_generatedNoteContent.isEmpty) return;

    try {
      _noteTags = await _aiService.extractTags(_generatedNoteContent);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 清空所有内容
  void clearAll() {
    _generateDebounceTimer?.cancel();
    _transcribedText = '';
    _partialTranscribedText = '';
    _generatedNoteContent = '';
    _noteTitle = '';
    _noteTags = [];
    _transcriptionHistory = '';
    _error = null;
    _isRecording = false;
    _isGenerating = false;

    _transcriptionService.clearTranscription();
    _aiService.clearNoteContent();

    notifyListeners();
  }

  /// 获取最终笔记数据
  Map<String, dynamic> getFinalNoteData() {
    return {
      'title': _noteTitle.isEmpty ? '新笔记' : _noteTitle,
      'content': _generatedNoteContent,
      'tags': _noteTags,
      'transcription': _transcribedText,
      'createdAt': DateTime.now(),
    };
  }

  @override
  void dispose() {
    _generateDebounceTimer?.cancel();
    _transcriptionSubscription?.cancel();
    _partialTranscriptionSubscription?.cancel();
    _isListeningSubscription?.cancel();
    _noteStreamSubscription?.cancel();
    _transcriptionService.dispose();
    _aiService.dispose();
    super.dispose();
  }
}
