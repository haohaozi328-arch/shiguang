import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ai/realtime_transcription_service.dart';
import '../services/ai/ai_notes_generation_service.dart';
import '../services/ai/ai_error_formatter.dart';
import '../services/ai/ai_service_config.dart';
import '../services/foreground_service_handler.dart';
import '../theme/app_theme.dart';
import '../utils/app_responsive.dart';
import '../utils/ui_formatters.dart';
import '../widgets/ui_asset_icon.dart';

/// 语音笔记结果数据
class VoiceNoteResult {
  final String transcription;
  final String generatedNote;
  final String? aiError;
  final String? recordingPath;
  final int durationMs;

  VoiceNoteResult({
    required this.transcription,
    required this.generatedNote,
    this.aiError,
    required this.recordingPath,
    required this.durationMs,
  });
}

/// 语音笔记页面 - 集成 ASR + AI 笔记生成
class VoiceSheet extends StatefulWidget {
  final void Function(VoiceNoteResult)? onComplete;
  final ValueChanged<String>? onTranscriptionChanged;
  final ValueChanged<String>? onGeneratedNoteChanged;
  final VoidCallback? onClose;
  final String initialTranscription;
  final String initialGeneratedNote;
  final String courseName;
  final String noteTitle;

  const VoiceSheet({
    super.key,
    this.onComplete,
    this.onTranscriptionChanged,
    this.onGeneratedNoteChanged,
    this.onClose,
    this.initialTranscription = '',
    this.initialGeneratedNote = '',
    this.courseName = '',
    this.noteTitle = '',
  });

  @override
  State<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<VoiceSheet>
    with SingleTickerProviderStateMixin {
  static bool _hasActiveRecordingSession = false;
  static String _activeBaseTranscription = '';
  static String _activeLastSessionTranscription = '';
  static String _activeTimestampedSessionTranscription = '';
  static String _activeRecordingStartedAtLabel = '';
  static int _activeLastAiTriggerLen = 0;
  static String _activeAccumulatedText = '';
  static String _activeGeneratedNote = '';
  static String _activeLastGeneratedNoteSnapshot = '';

  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  // 录音计时
  Duration _recordingDuration = Duration.zero;
  bool _localIsRecording = false;
  Timer? _durationTimer;
  final Stopwatch _uiRecordingStopwatch = Stopwatch();
  Duration _uiRecordingOffset = Duration.zero;

  // AI 笔记状态
  String _generatedNote = '';
  String _displayedGeneratedNote = '';
  String _lastGeneratedNoteSnapshot = '';
  bool _isGenerating = false;
  String? _error;
  Timer? _noteTypewriterTimer;

  // 最终转写文本（录音停止时保存）
  String _finalTranscription = '';

  // 用于触发 AI 生成的字符数阈值
  static const int _aiTriggerChars = 1500;
  static const Duration _maxRecordingDuration = Duration(hours: 1);
  int _lastAiTriggerLen = 0;
  String _pendingChunk = '';
  bool _aiRunning = false;
  bool _isStopping = false;
  bool _isDisposed = false;
  bool _detachedAiCleanupDone = false;

  // 累计转录文本（用于计算字数）
  String _accumulatedText = '';
  String _baseTranscription = '';
  String _lastSessionTranscription = '';
  String _timestampedSessionTranscription = '';
  String _recordingStartedAtLabel = '';

  // 服务实例
  late RealtimeTranscriptionService _transcriptionService;
  late AINotesGenerationService _aiService;

  // 订阅
  StreamSubscription? _transcriptionSub;
  StreamSubscription? _noteStreamSub;
  StreamSubscription? _isRecordingSub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initServices();
  }

  void _initServices() {
    // 使用单例，保持后台录音状态
    _transcriptionService = RealtimeTranscriptionService.instance;

    // 如果已经在录音，恢复 UI 状态
    if (_transcriptionService.isListening) {
      _localIsRecording = true;
      _accumulatedText = _activeAccumulatedText;
      _recordingDuration = _transcriptionService.recordingDuration;
      _uiRecordingOffset = _recordingDuration;
      _baseTranscription = _hasActiveRecordingSession
          ? _activeBaseTranscription
          : formatTimestampedVoiceTranscription(widget.initialTranscription);
      _lastSessionTranscription = _activeLastSessionTranscription;
      _timestampedSessionTranscription = _activeTimestampedSessionTranscription;
      _recordingStartedAtLabel = _activeRecordingStartedAtLabel;
      _lastAiTriggerLen = _activeLastAiTriggerLen;
      _generatedNote = _activeGeneratedNote.isNotEmpty
          ? _activeGeneratedNote
          : formatAiNoteText(widget.initialGeneratedNote);
      _displayedGeneratedNote = _generatedNote;
      _lastGeneratedNoteSnapshot = _activeLastGeneratedNoteSnapshot.isNotEmpty
          ? _activeLastGeneratedNoteSnapshot
          : _generatedNote;
      // 恢复计时器
      _pulseController.repeat(reverse: true);
      _uiRecordingStopwatch
        ..reset()
        ..start();
      _startDurationTimer();
    }

    _aiService = AINotesGenerationService.deepseek(
      AIServiceConfig.deepseekApiKey ?? '',
      apiUrl: AIServiceConfig.apiUrl,
      model: AIServiceConfig.deepseekModel,
    );

    // 监听转录
    _transcriptionSub = _transcriptionService.transcriptionStream.listen((
      text,
    ) {
      if (mounted) {
        _onTranscriptionChanged(text);
        setState(() {});
      }
    });

    // 监听 AI 笔记流
    _noteStreamSub = _aiService.noteStream.listen(
      (content) {
        final formattedContent = _mergeGeneratedNoteUpdate(content);
        _generatedNote = formattedContent;
        _persistGeneratedNoteSessionState();
        widget.onGeneratedNoteChanged?.call(formattedContent);
        if (mounted && !_isDisposed) {
          _updateGeneratedNoteTypewriter(formattedContent);
        }
      },
      onError: (error) {
        final message = formatAiError(error);
        if (mounted && !_isDisposed) {
          setState(() => _error = 'AI 生成失败: $message');
        }
      },
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_localIsRecording) {
      _persistRecordingSessionState();
      _uiRecordingStopwatch.stop();
    }
    final keepAiRunningAfterClose =
        _isStopping || _aiRunning || _pendingChunk.isNotEmpty;
    _pulseController.dispose();
    _durationTimer?.cancel();
    _noteTypewriterTimer?.cancel();
    _transcriptionSub?.cancel();
    if (!keepAiRunningAfterClose) {
      _noteStreamSub?.cancel();
    }
    _isRecordingSub?.cancel();

    // 注意：不要在这里 dispose _transcriptionService
    // 它由前台服务管理，离开界面时应该继续运行
    // _transcriptionService.dispose();

    if (!keepAiRunningAfterClose) {
      _aiService.dispose();
    }
    super.dispose();
  }

  Future<void> _startRecording() async {
    _recordingDuration = Duration.zero;
    _localIsRecording = true;
    _isStopping = false;
    _uiRecordingOffset = Duration.zero;
    _uiRecordingStopwatch
      ..reset()
      ..start();
    _pulseController.repeat(reverse: true);

    // 重置状态
    setState(() {
      _generatedNote = '';
      _displayedGeneratedNote = '';
      _lastGeneratedNoteSnapshot = '';
      _isGenerating = false;
      _error = null;
      _lastAiTriggerLen = 0;
      _pendingChunk = '';
      _accumulatedText = '';
      _baseTranscription = formatTimestampedVoiceTranscription(
        widget.initialTranscription,
      );
      _lastSessionTranscription = '';
      _timestampedSessionTranscription = '';
      _recordingStartedAtLabel = _formatRecordingStartTime(DateTime.now());
      _hasActiveRecordingSession = true;
      _aiRunning = false;
    });
    _generatedNote = formatAiNoteText(widget.initialGeneratedNote);
    _displayedGeneratedNote = _generatedNote;
    _lastGeneratedNoteSnapshot = _generatedNote;
    _persistRecordingSessionState();
    _persistGeneratedNoteSessionState();
    _startDurationTimer();

    debugPrint('[VoiceSheet] 开始录音');

    // 请求权限（用于后台录音和通知栏/锁屏提示）
    await Permission.microphone.request();
    await Permission.notification.request();

    // 启动前台服务（支持后台录音）
    await ForegroundServiceHandler.startRecordingService();

    try {
      // 开始录音
      await _transcriptionService.startListening();
    } catch (_) {
      await ForegroundServiceHandler.stopRecordingService();
      rethrow;
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_localIsRecording && mounted) {
        final visibleDuration = _visibleRecordingDuration;
        if (visibleDuration >= _maxRecordingDuration) {
          _durationTimer?.cancel();
          _stopRecording();
          return;
        }
        setState(() {
          _recordingDuration = visibleDuration;
        });
      }
    });
  }

  Duration get _visibleRecordingDuration {
    final serviceDuration = _transcriptionService.recordingDuration;
    final uiDuration = _uiRecordingOffset + _uiRecordingStopwatch.elapsed;
    return serviceDuration > uiDuration ? serviceDuration : uiDuration;
  }

  Future<void> _stopRecording() async {
    if (_isStopping) {
      return;
    }
    _isStopping = true;
    _recordingDuration = _visibleRecordingDuration;
    _localIsRecording = false;
    _uiRecordingStopwatch.stop();
    _pulseController.stop();
    _pulseController.reset();
    _durationTimer?.cancel();

    debugPrint('[VoiceSheet] 停止录音');

    // 等待最后的 ASR 处理完成
    await _transcriptionService.stopListening();

    // 保存最终转写文本
    _finalTranscription = _composeFullTranscription(
      _transcriptionService.currentTranscription,
    );
    widget.onTranscriptionChanged?.call(_finalTranscription);
    debugPrint('[VoiceSheet] 保存最终转写: ${_finalTranscription.length} 字');

    // 停止前台服务
    ForegroundServiceHandler.stopRecordingService();

    final currentText = _transcriptionService.currentTranscription;
    unawaited(_finishStopInBackground(currentText));
  }

  Future<void> _finishStopInBackground(String currentText) async {
    await _runRemainingAiAfterStop(currentText);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _runRemainingAiAfterStop(String currentText) async {
    try {
      if (_accumulatedText.trim().isNotEmpty) {
        final remainingAccumulated = _accumulatedText;
        _accumulatedText = '';
        debugPrint(
          '[VoiceSheet] 处理短录音/剩余累积文本: ${remainingAccumulated.length} 字',
        );
        await _runAi(remainingAccumulated);
      }

      // 处理最后剩余的转录文本
      if (currentText.length > _lastAiTriggerLen) {
        final remaining = currentText.substring(_lastAiTriggerLen);
        _lastAiTriggerLen = currentText.length;
        debugPrint('[VoiceSheet] 处理最后剩余文本: ${remaining.length} 字');
        await _runAi(remaining);
      }

      // 处理暂存的内容
      if (_pendingChunk.isNotEmpty) {
        debugPrint('[VoiceSheet] 处理暂存内容: ${_pendingChunk.length} 字');
        final pending = _pendingChunk;
        _pendingChunk = '';
        await _runAi(pending);
      }

      // 如果 AI 正在生成中（处理中没有新数据的情况），等待其完成
      if (_aiRunning) {
        debugPrint('[VoiceSheet] 等待进行中的 AI 生成完成...');
        while (_aiRunning) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }
    } finally {
      _isStopping = false;
      _clearRecordingSessionState();
      await _cleanupDetachedAiResourcesIfNeeded();
    }
  }

  void _onTranscriptionChanged(String text) {
    if (text.isEmpty || !_localIsRecording) return;

    debugPrint('[VoiceSheet] 转录文本更新: ${text.length} 字');
    widget.onTranscriptionChanged?.call(_composeFullTranscription(text));

    // 计算新增的字符（当 ASR 累积文本缩短时 newChars 为负，跳过处理）
    final newChars = text.length - _lastAiTriggerLen;

    if (_aiRunning) {
      // AI 运行中，暂存新内容（保护：text 可能比上次短）
      if (newChars > 0 && _lastAiTriggerLen < text.length) {
        _pendingChunk += text.substring(_lastAiTriggerLen);
        _lastAiTriggerLen = text.length;
        _persistRecordingSessionState();
        debugPrint(
          '[VoiceSheet] AI运行中，暂存 $newChars 字，当前暂存: ${_pendingChunk.length} 字',
        );
      }
    } else {
      // AI 空闲，累积文本直到阈值（保护：text 可能比上次短）
      final safeStart = _lastAiTriggerLen < text.length
          ? _lastAiTriggerLen
          : text.length;
      _accumulatedText += text.substring(safeStart);
      _lastAiTriggerLen = text.length;

      if (_accumulatedText.length >= _aiTriggerChars) {
        // 达到阈值，触发 AI
        final chunk = _accumulatedText;
        _accumulatedText = '';
        debugPrint('[VoiceSheet] 累积文本达到 ${chunk.length} 字，触发AI生成笔记');
        _runAi(chunk);
      }
      _persistRecordingSessionState();
    }
  }

  String _composeFullTranscription(String sessionText) {
    final formattedSession = _formatSessionTranscription(sessionText);
    if (_baseTranscription.isEmpty) {
      return formattedSession;
    }
    if (formattedSession.isEmpty) {
      return _baseTranscription;
    }
    return normalizeNoteText('$_baseTranscription\n\n$formattedSession');
  }

  String _formatSessionTranscription(String sessionText) {
    final compactSession = normalizeNoteText(sessionText)
        .split('\n')
        .map(compactVoiceText)
        .where((line) => line.isNotEmpty)
        .join('\n');
    if (compactSession.isEmpty) {
      return '';
    }

    final newPart = compactSession.length > _lastSessionTranscription.length
        ? compactSession.substring(_lastSessionTranscription.length)
        : compactSession;
    if (newPart.isEmpty && _timestampedSessionTranscription.isNotEmpty) {
      return _timestampedSessionTranscription;
    }
    if (compactSession.length <= _lastSessionTranscription.length) {
      _timestampedSessionTranscription = '';
    }

    _lastSessionTranscription = compactSession;
    final buffer = StringBuffer(_timestampedSessionTranscription.trim());
    if (buffer.isNotEmpty && newPart.isNotEmpty) {
      buffer.write('\n');
    }
    if (buffer.isEmpty && _recordingStartedAtLabel.isNotEmpty) {
      buffer.writeln(_recordingStartedAtLabel);
    }
    buffer.write(newPart);
    _timestampedSessionTranscription = formatTimestampedVoiceTranscription(
      buffer.toString(),
    );
    _persistRecordingSessionState();
    return _timestampedSessionTranscription;
  }

  /// 运行 AI 生成笔记，返回 Future 完成时所有处理（包括 pending chunks）均已完成
  Future<void> _runAi(String chunk) async {
    if (chunk.trim().isEmpty || _aiRunning) return;
    if (!AIServiceConfig.isConfigured()) {
      if (mounted) {
        setState(() => _error = 'AI 未配置');
      }
      debugPrint('[VoiceSheet] AI 未配置');
      return;
    }

    _aiRunning = true;
    if (mounted) {
      setState(() => _isGenerating = true);
    }

    // 记录前文笔记（用于连续性）
    final previousNote = _generatedNote;
    debugPrint('[VoiceSheet] 开始AI生成笔记');
    debugPrint('[VoiceSheet] 待处理文本: ${chunk.length} 字');
    if (previousNote.isNotEmpty) {
      debugPrint(
        '[VoiceSheet] 前文笔记 (${previousNote.length} 字): '
        '${previousNote.substring(0, previousNote.length > 50 ? 50 : previousNote.length)}...',
      );
    }

    try {
      await _aiService.generateNoteContent(
        transcription: chunk,
        existingContent: previousNote,
        previousContext: _recentAiContext(previousNote),
        courseName: widget.courseName,
        noteTitle: widget.noteTitle,
      );

      // AI 生成会在 noteStream 中收到结果
      // 等待一段时间后关闭 running 状态
      await Future.delayed(const Duration(milliseconds: 1000));

      _aiRunning = false;
      _isGenerating = false;
      debugPrint('[VoiceSheet] AI生成完成，当前笔记: ${_generatedNote.length} 字');

      if (mounted) {
        setState(() {});
      }

      // 处理暂存的内容（递归等待完成）
      if (_pendingChunk.isNotEmpty) {
        final pending = _pendingChunk;
        _pendingChunk = '';
        debugPrint('[VoiceSheet] 处理暂存内容: ${pending.length} 字');
        await _runAi(pending);
      }
    } catch (e) {
      _aiRunning = false;
      _isGenerating = false;
      final message = formatAiError(e);
      if (mounted) {
        setState(() {
          _error = 'AI 生成失败: $message';
        });
      }
      debugPrint('[VoiceSheet] AI生成失败: $message');
    } finally {
      await _cleanupDetachedAiResourcesIfNeeded();
    }
  }

  Future<void> _cleanupDetachedAiResourcesIfNeeded() async {
    if (!_isDisposed || _detachedAiCleanupDone || _aiRunning) {
      return;
    }
    _detachedAiCleanupDone = true;
    await _noteStreamSub?.cancel();
    _aiService.dispose();
  }

  String _recentAiContext(String value) {
    final text = formatAiNoteText(value).trim();
    if (text.length <= 900) {
      return text;
    }
    return text.substring(text.length - 900);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  String _formatRecordingStartTime(DateTime time) {
    final minute = time.minute.toString().padLeft(2, '0');
    return '${time.year}.${time.month}.${time.day} ${time.hour}:$minute';
  }

  void _updateGeneratedNoteTypewriter(String fullText) {
    if (fullText == _displayedGeneratedNote) {
      return;
    }

    _noteTypewriterTimer?.cancel();

    if (fullText.length > _displayedGeneratedNote.length) {
      _displayedGeneratedNote += fullText[_displayedGeneratedNote.length];
      _persistGeneratedNoteSessionState();
      if (mounted) {
        setState(() {});
      }
      _noteTypewriterTimer = Timer(const Duration(milliseconds: 18), () {
        if (mounted) {
          _updateGeneratedNoteTypewriter(fullText);
        }
      });
      return;
    }

    _displayedGeneratedNote = fullText;
    _persistGeneratedNoteSessionState();
    if (mounted) {
      setState(() {});
    }
  }

  String _mergeGeneratedNoteUpdate(String content) {
    final incoming = formatAiNoteText(content);
    if (incoming.isEmpty) {
      return _generatedNote;
    }
    if (_generatedNote.isEmpty || incoming.startsWith(_generatedNote)) {
      _lastGeneratedNoteSnapshot = incoming;
      return incoming;
    }

    final base = _lastGeneratedNoteSnapshot.isNotEmpty
        ? _lastGeneratedNoteSnapshot
        : _generatedNote;
    if (base.contains(incoming)) {
      return base;
    }
    final merged = formatAiNoteText('${base.trimRight()}\n\n$incoming');
    _lastGeneratedNoteSnapshot = merged;
    return merged;
  }

  void _persistRecordingSessionState() {
    _hasActiveRecordingSession = true;
    _activeBaseTranscription = _baseTranscription;
    _activeLastSessionTranscription = _lastSessionTranscription;
    _activeTimestampedSessionTranscription = _timestampedSessionTranscription;
    _activeRecordingStartedAtLabel = _recordingStartedAtLabel;
    _activeLastAiTriggerLen = _lastAiTriggerLen;
    _activeAccumulatedText = _accumulatedText;
    _persistGeneratedNoteSessionState();
  }

  void _persistGeneratedNoteSessionState() {
    _activeGeneratedNote = _generatedNote;
    _activeLastGeneratedNoteSnapshot = _lastGeneratedNoteSnapshot;
  }

  void _clearRecordingSessionState() {
    _hasActiveRecordingSession = false;
    _activeBaseTranscription = '';
    _activeLastSessionTranscription = '';
    _activeTimestampedSessionTranscription = '';
    _activeRecordingStartedAtLabel = '';
    _activeLastAiTriggerLen = 0;
    _activeAccumulatedText = '';
    _activeGeneratedNote = '';
    _activeLastGeneratedNoteSnapshot = '';
  }

  Future<void> _closeSheet() async {
    if (_localIsRecording) {
      _persistRecordingSessionState();
      _durationTimer?.cancel();
      _uiRecordingStopwatch.stop();
      widget.onClose?.call();
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    if (_isStopping) {
      return;
    }

    if (!mounted) {
      return;
    }

    if (_finalTranscription.trim().isEmpty && _generatedNote.trim().isEmpty) {
      widget.onClose?.call();
      Navigator.of(context).pop();
      return;
    }

    final result = VoiceNoteResult(
      transcription: _finalTranscription,
      generatedNote: formatAiNoteText(_generatedNote),
      aiError: _error,
      recordingPath: _transcriptionService.recordingPath,
      durationMs: _recordingDuration.inMilliseconds,
    );

    widget.onComplete?.call(result);
    widget.onClose?.call();
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final transcribedText = _transcriptionService.currentTranscription;
    final previewTranscribedText = _transcriptionService.partialTranscription;
    final visibleTranscribedText = previewTranscribedText.isNotEmpty
        ? formatVoicePreview(previewTranscribedText)
        : formatVoicePreview(transcribedText);
    final h = MediaQuery.of(context).size.height;
    final compact = AppResponsive.isCompact(context);

    return Container(
      height: AppResponsive.voiceSheetHeight(context),
      decoration: const BoxDecoration(
        color: Color(0xF0FFFFFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0xE6FFFFFF), width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Color(0x24506EB4),
            blurRadius: 40,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Column(
            children: [
              // Handle
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0x38648CC8),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 16,
                  0,
                  compact ? 12 : 16,
                  10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const UiAssetIcon('录音.png', size: 20),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              _localIsRecording
                                  ? '识别中...'
                                  : (_isStopping ? 'AI整理中...' : '语音笔记'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _closeSheet,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0x99FFFFFF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xCCFFFFFF),
                              ),
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 20,
                              color: AppColors.textSub,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0x1A96B4D2)),

              // Error display
              if (_error != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _error = null),
                        child: const Icon(
                          Icons.close,
                          color: Colors.red,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                ),

              // Content panels
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 16,
                    12,
                    compact ? 12 : 16,
                    0,
                  ),
                  child: Column(
                    children: [
                      Flexible(
                        child: Container(
                          constraints: BoxConstraints(maxHeight: h * 0.20),
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 9),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(
                                0xFFA8EDDA,
                              ).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const UiAssetIcon('录音.png', size: 14),
                                  const SizedBox(width: 6),
                                  const Text(
                                    '语音笔记',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF5ECFA0),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_isGenerating) ...[
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: Color(0xFF50B4A0),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'AI生成中',
                                      style: TextStyle(
                                        color: Color(0xFF50B4A0),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: h * 0.10,
                                ),
                                child: SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: Text(
                                    visibleTranscribedText.isEmpty
                                        ? (_localIsRecording
                                              ? '语音识别中，最近 50 字会显示在这里'
                                              : '点击录音按钮开始')
                                        : visibleTranscribedText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: visibleTranscribedText.isEmpty
                                          ? AppColors.textSub
                                          : AppColors.textDark,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ),
                              if (transcribedText.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '仅显示最近 50 字',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSub.withValues(
                                      alpha: 0.75,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Record button
                      GestureDetector(
                        onTap: () {
                          if (_localIsRecording) {
                            unawaited(_stopRecording());
                          } else {
                            unawaited(_startRecording());
                          }
                        },
                        child: AnimatedBuilder(
                          animation: _scaleAnimation,
                          builder: (context, child) => Transform.scale(
                            scale: _localIsRecording
                                ? _scaleAnimation.value
                                : 1.0,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: _localIsRecording
                                    ? const LinearGradient(
                                        colors: [Colors.red, Color(0xFFFF4444)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : const LinearGradient(
                                        colors: [
                                          Color(0xFFA8EDDA),
                                          Color(0xFF50B4A0),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _localIsRecording
                                        ? Colors.red.withValues(alpha: 0.4)
                                        : const Color(
                                            0xFF50B4A0,
                                          ).withValues(alpha: 0.4),
                                    blurRadius: 18,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: _localIsRecording
                                    ? const Icon(
                                        Icons.stop_rounded,
                                        size: 28,
                                        color: Colors.white,
                                      )
                                    : const UiAssetIcon('录音.png', size: 30),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Timer
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _formatDuration(_recordingDuration),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w300,
                            color: AppColors.textDark,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
