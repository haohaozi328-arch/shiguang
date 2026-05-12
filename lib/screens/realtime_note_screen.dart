import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/realtime_note_provider.dart';

/// 实时语音笔记页面
/// 上半屏：AI生成的笔记内容（打字机效果）
/// 下半屏：录音控制和ASR实时转录（打字机效果）
class RealtimeNoteScreen extends StatefulWidget {
  const RealtimeNoteScreen({super.key, this.initialNoteContent});

  final String? initialNoteContent;

  @override
  State<RealtimeNoteScreen> createState() => _RealtimeNoteScreenState();
}

class _RealtimeNoteScreenState extends State<RealtimeNoteScreen>
    with SingleTickerProviderStateMixin {
  late ScrollController _noteScrollController;
  late ScrollController _transcriptionScrollController;
  late AnimationController _cursorController;
  late AnimationController _recordingController;

  Duration _recordingDuration = Duration.zero;

  // 打字机效果相关
  String _displayedNoteText = '';
  String _displayedAsrText = '';
  Timer? _noteTypewriterTimer;
  Timer? _asrTypewriterTimer;

  @override
  void initState() {
    super.initState();
    _noteScrollController = ScrollController();
    _transcriptionScrollController = ScrollController();
    _cursorController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    )..repeat();

    _recordingController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _noteTypewriterTimer?.cancel();
    _asrTypewriterTimer?.cancel();
    _noteScrollController.dispose();
    _transcriptionScrollController.dispose();
    _cursorController.dispose();
    _recordingController.dispose();
    super.dispose();
  }

  void _startRecordingTimer(RealtimeNoteProvider provider) {
    _recordingDuration = Duration.zero;
    _recordingController.repeat();

    Future.doWhile(() async {
      if (!provider.isRecording) return false;
      await Future.delayed(Duration(milliseconds: 100));
      if (mounted && provider.isRecording) {
        setState(() {
          _recordingDuration += Duration(milliseconds: 100);
        });
      }
      return provider.isRecording;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  /// 笔记打字机效果
  void _updateNoteTypewriter(String fullText) {
    if (fullText == _displayedNoteText) return;

    _noteTypewriterTimer?.cancel();

    if (fullText.length > _displayedNoteText.length) {
      // 添加新字符
      final nextChar = fullText[_displayedNoteText.length];
      _displayedNoteText += nextChar;

      _noteTypewriterTimer = Timer(Duration(milliseconds: 30), () {
        if (mounted) {
          _updateNoteTypewriter(fullText);
        }
      });
    } else {
      // 文本减少（被覆盖），直接更新
      _displayedNoteText = fullText;
    }
    setState(() {});
  }

  /// ASR打字机效果
  void _updateAsrTypewriter(String fullText, String partialText) {
    final combinedText = fullText + partialText;
    if (combinedText == _displayedAsrText) return;

    _asrTypewriterTimer?.cancel();

    if (combinedText.length > _displayedAsrText.length) {
      // 添加新字符
      final nextChar = combinedText[_displayedAsrText.length];
      _displayedAsrText += nextChar;

      _asrTypewriterTimer = Timer(Duration(milliseconds: 50), () {
        if (mounted) {
          _updateAsrTypewriter(fullText, partialText);
        }
      });
    } else {
      // 文本减少，直接更新
      _displayedAsrText = combinedText;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('实时语音笔记'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: Consumer<RealtimeNoteProvider>(
        builder: (context, provider, _) {
          // 监听录音状态变化
          if (provider.isRecording && !_recordingController.isAnimating) {
            _startRecordingTimer(provider);
          } else if (!provider.isRecording &&
              _recordingController.isAnimating) {
            _recordingController.stop();
          }

          // 更新打字机效果
          _updateNoteTypewriter(provider.generatedNoteContent);
          _updateAsrTypewriter(
            provider.transcribedText,
            provider.partialTranscribedText,
          );

          return Column(
            children: [
              // 上半屏：AI笔记区域
              Expanded(flex: 1, child: _buildNoteArea(provider)),
              // 分隔线
              Container(height: 1, color: Colors.grey[300]),
              // 下半屏：录音和ASR区域
              Expanded(flex: 1, child: _buildTranscriptionArea(provider)),
            ],
          );
        },
      ),
    );
  }

  /// 上半屏：AI笔记区域
  Widget _buildNoteArea(RealtimeNoteProvider provider) {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // 笔记头部
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 20, color: Colors.grey[600]),
                SizedBox(width: 8),
                Text(
                  'AI 笔记',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                Spacer(),
                if (provider.isGenerating)
                  Text(
                    '生成中...',
                    style: TextStyle(fontSize: 11, color: Colors.blue[400]),
                  ),
              ],
            ),
          ),
          // 笔记内容
          Expanded(
            child: SingleChildScrollView(
              controller: _noteScrollController,
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _buildNoteContent(provider),
            ),
          ),
        ],
      ),
    );
  }

  /// 笔记内容（带打字机光标）
  Widget _buildNoteContent(RealtimeNoteProvider provider) {
    if (_displayedNoteText.isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.mic,
                size: 48,
                color: provider.isRecording
                    ? Colors.blue[400]
                    : Colors.grey[400],
              ),
              SizedBox(height: 16),
              Text(
                '开始录音，AI将实时生成笔记...',
                style: TextStyle(fontSize: 14, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      );
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 15, height: 1.8, color: Colors.grey[800]),
        children: [
          TextSpan(text: _displayedNoteText),
          if (provider.isGenerating ||
              _displayedNoteText.length < provider.generatedNoteContent.length)
            WidgetSpan(
              child: AnimatedBuilder(
                animation: _cursorController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _cursorController.value > 0.5 ? 1 : 0.3,
                    child: Container(
                      width: 2,
                      height: 18,
                      color: Colors.blue[400],
                      margin: const EdgeInsets.only(left: 2),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// 下半屏：ASR转录区域
  Widget _buildTranscriptionArea(RealtimeNoteProvider provider) {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.white,
            child: SingleChildScrollView(
              controller: _transcriptionScrollController,
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ASR头部
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic, size: 18, color: Color(0xFF5ECFA0)),
                      SizedBox(width: 6),
                      Text(
                        '实时识别',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5ECFA0),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  // ASR文本内容
                  if (_displayedAsrText.isNotEmpty)
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: Colors.grey[800],
                        ),
                        children: [
                          TextSpan(text: _displayedAsrText),
                          if (provider.isRecording)
                            WidgetSpan(
                              child: AnimatedBuilder(
                                animation: _cursorController,
                                builder: (context, child) {
                                  return Opacity(
                                    opacity: _cursorController.value > 0.5
                                        ? 1
                                        : 0.3,
                                    child: Container(
                                      width: 1.5,
                                      height: 16,
                                      color: Colors.blue[400],
                                      margin: const EdgeInsets.only(left: 2),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (_displayedAsrText.isEmpty)
                    Text(
                      '点击下方按钮开始录音...',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: Colors.grey[400],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // 错误提示
        if (provider.error != null)
          Container(
            color: Colors.red[50],
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red[400], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    provider.error!,
                    style: TextStyle(color: Colors.red[600], fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        // 录音控制区域
        _buildRecordingControls(provider),
      ],
    );
  }

  /// 录音控制区域
  Widget _buildRecordingControls(RealtimeNoteProvider provider) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          // 录音时长显示
          if (provider.isRecording)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 动画录音指示器
                  Icon(
                    Icons.mic,
                    size: 16,
                    color: provider.isRecording ? Colors.red[400] : Colors.grey,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '正在录音 ${_formatDuration(_recordingDuration)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.red[400],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 清空按钮
              if (provider.transcribedText.isNotEmpty ||
                  provider.generatedNoteContent.isNotEmpty)
                FloatingActionButton(
                  onPressed: () {
                    _displayedNoteText = '';
                    _displayedAsrText = '';
                    provider.clearAll();
                  },
                  backgroundColor: Colors.grey[400],
                  mini: true,
                  child: const Icon(Icons.clear, color: Colors.white),
                ),

              // 开始/停止录音按钮
              FloatingActionButton.extended(
                onPressed: provider.isRecording
                    ? () => provider.stopRecording()
                    : () => provider.startRecording(),
                backgroundColor: provider.isRecording
                    ? Colors.red[400]
                    : Colors.blue[400],
                icon: Icon(
                  provider.isRecording ? Icons.stop : Icons.mic,
                  size: 24,
                  color: Colors.white,
                ),
                label: Text(
                  provider.isRecording ? '停止' : '开始',
                  style: const TextStyle(color: Colors.white),
                ),
              ),

              // 保存按钮
              if (provider.generatedNoteContent.isNotEmpty &&
                  !provider.isRecording)
                FloatingActionButton.extended(
                  onPressed: () => _saveNote(context, provider),
                  backgroundColor: Colors.green[400],
                  icon: const Icon(Icons.save, color: Colors.white),
                  label: const Text(
                    '保存',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _saveNote(BuildContext context, RealtimeNoteProvider provider) {
    final noteData = provider.getFinalNoteData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('笔记已保存'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green[400],
      ),
    );
    Navigator.pop(context, noteData);
  }
}
