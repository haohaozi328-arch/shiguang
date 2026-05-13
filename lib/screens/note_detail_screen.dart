import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/course.dart';
import '../models/note_entry.dart';
import '../models/photo_record.dart';
import '../services/ai_note_export_service.dart';
import '../services/ai/ai_error_formatter.dart';
import '../services/ai/ai_notes_generation_service.dart';
import '../services/ai/ai_service_config.dart';
import '../services/ai/realtime_transcription_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_responsive.dart';
import '../utils/ui_formatters.dart';
import '../widgets/ui_asset_icon.dart';
import 'voice_sheet.dart';

class NoteDetailScreen extends StatefulWidget {
  const NoteDetailScreen({
    super.key,
    this.note,
    this.courseName,
    this.initialCourseId,
  });

  final NoteEntry? note;
  final String? courseName;
  final String? initialCourseId;

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  int _selectedTab = 3;
  bool _isSaving = false;
  bool _isLoadingPhotos = false;
  bool _isExportingAi = false;
  bool _isRetryingAi = false;
  bool _isEditingTitle = false;
  bool _pendingSilentSave = false;
  Timer? _autoSaveTimer;
  String _lastSavedFingerprint = '';
  late final TextEditingController _titleController;
  late final TextEditingController _voiceController;
  late final TextEditingController _textController;
  late final TextEditingController _aiController;
  late final FocusNode _titleFocusNode;
  final ImagePicker _imagePicker = ImagePicker();
  StreamSubscription<String>? _retryAiSub;
  NoteEntry? _currentNote;
  List<PhotoRecord> _photoRecords = const [];
  AiGenerationState _aiGenerationState = AiGenerationState.idle;
  String _aiGenerationSource = '';
  String _aiGenerationError = '';

  final _tabs = ['语音笔记', '文字笔记', '拍照记录', 'AI整理'];
  final _tabAssets = ['录音.png', '笔记.png', '拍照.png', 'ai.png'];

  @override
  void initState() {
    super.initState();
    _currentNote = widget.note;
    _aiGenerationState =
        widget.note?.aiGenerationState ?? AiGenerationState.idle;
    _aiGenerationSource = widget.note?.aiGenerationSource ?? '';
    _aiGenerationError = widget.note?.aiGenerationError ?? '';
    if (_aiGenerationState == AiGenerationState.generating &&
        !_hasActiveVoiceRecording) {
      _aiGenerationState = AiGenerationState.failed;
      _aiGenerationError = '上次 AI 整理被中断，可以重新生成。';
    }
    if (widget.note == null) {
      _selectedTab = 1;
    }
    _titleFocusNode = FocusNode();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _voiceController = TextEditingController(
      text: widget.note?.rawTranscription ?? '',
    );
    _textController = TextEditingController(
      text: widget.note?.textContent ?? '',
    );
    _aiController = TextEditingController(text: widget.note?.aiSummary ?? '');
    _lastSavedFingerprint = _saveFingerprint();
    _titleController.addListener(_scheduleTextAutoSave);
    _textController.addListener(_scheduleTextAutoSave);
    _loadPhotoRecords();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _retryAiSub?.cancel();
    _titleFocusNode.dispose();
    _titleController.dispose();
    _voiceController.dispose();
    _textController.dispose();
    _aiController.dispose();
    super.dispose();
  }

  Future<void> _loadPhotoRecords() async {
    final noteId = _currentNote?.id;
    if (noteId == null) {
      return;
    }

    final repository = context.read<AppRepository>();
    final records = await repository.getPhotoRecordsForNote(noteId);
    if (!mounted) {
      return;
    }

    setState(() {
      _photoRecords = records;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.8, -0.9),
                  radius: 0.8,
                  colors: [Color(0x8CA8EDDA), Colors.transparent],
                ),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.9, 0.9),
                    radius: 0.7,
                    colors: [Color(0x80DDD0FF), Colors.transparent],
                  ),
                ),
                child: Container(color: const Color(0xF0F3EEFF)),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(context),
                const SizedBox(height: 4),
                _buildTitleEditor(),
                Expanded(child: _buildContent()),
                _buildBottom(context),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: AppResponsive.noteFabBottom(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FloatingPhotoBtn(onTap: _showPhotoOptions),
                const SizedBox(width: 12),
                _FloatingRecordBtn(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => VoiceSheet(
                        initialTranscription: _voiceController.text,
                        initialGeneratedNote: _aiController.text,
                        courseName: widget.courseName ?? '',
                        noteTitle: _titleController.text.trim(),
                        onTranscriptionChanged: (text) {
                          if (!mounted) {
                            return;
                          }
                          final formattedText =
                              formatTimestampedVoiceTranscription(text);
                          setState(() {
                            _voiceController.text = formattedText;
                            _markAiGenerating(formattedText);
                            if (_titleController.text.trim().isEmpty) {
                              _titleController.text = _buildSuggestedTitle(
                                formattedText,
                              );
                            }
                          });
                          _scheduleGeneratedAutoSave();
                        },
                        onGeneratedNoteChanged: (content) {
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _aiController.text = formatAiNoteText(content);
                            _aiGenerationState = AiGenerationState.generating;
                            _aiGenerationError = '';
                          });
                          _scheduleGeneratedAutoSave();
                        },
                        onComplete: (result) {
                          setState(() {
                            _voiceController.text =
                                formatTimestampedVoiceTranscription(
                                  result.transcription,
                                );
                            _aiController.text = formatAiNoteText(
                              result.generatedNote,
                            );
                            _aiGenerationState = result.aiError == null
                                ? AiGenerationState.completed
                                : AiGenerationState.failed;
                            _aiGenerationSource = _voiceController.text.trim();
                            _aiGenerationError = result.aiError ?? '';
                            if (_titleController.text.trim().isEmpty) {
                              _titleController.text = _buildSuggestedTitle(
                                _voiceController.text,
                              );
                            }
                            _selectedTab = 3;
                          });
                          unawaited(_saveNote(silent: true));
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () async {
              await _flushPendingAutoSave();
              if (context.mounted) {
                Navigator.pop(context, _currentNote);
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0x8CFFFFFF),
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(
                      color: const Color(0xCCFFFFFF),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    size: 22,
                    color: AppColors.textSub,
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0x8CA8EDDA), Color(0x66C2E9FB)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x99A8EDDA)),
            ),
            child: Text(
              widget.courseName ?? '未分类课程',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E5A50),
              ),
            ),
          ),
          GestureDetector(
            onTap: _isSaving ? null : _saveNote,
            child: Opacity(
              opacity: _isSaving ? 0.7 : 1,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0x8CA8EDDA), Color(0x66C2E9FB)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x99A8EDDA)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isSaving
                        ? const Icon(
                            Icons.hourglass_top,
                            size: 16,
                            color: Color(0xFF1E5A50),
                          )
                        : const UiAssetIcon('保存.png', size: 16),
                    const SizedBox(width: 5),
                    Text(
                      _isSaving ? '保存中' : '保存',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E5A50),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleEditor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      child: _isEditingTitle
          ? TextField(
              controller: _titleController,
              focusNode: _titleFocusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _finishTitleEditing(),
              onEditingComplete: _finishTitleEditing,
              onTapOutside: (_) => _finishTitleEditing(),
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
                height: 1.3,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '输入笔记标题',
                hintStyle: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSub,
                ),
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _startTitleEditing,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: AnimatedBuilder(
                  animation: _titleController,
                  builder: (context, _) {
                    final title = _titleController.text.trim();
                    return Text(
                      title.isEmpty ? '双击输入笔记标题' : title,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: title.isEmpty
                            ? AppColors.textSub
                            : AppColors.textDark,
                        height: 1.3,
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }

  void _startTitleEditing() {
    setState(() => _isEditingTitle = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_titleFocusNode.hasFocus) {
        _titleFocusNode.requestFocus();
      }
      _titleController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _titleController.text.length,
      );
    });
  }

  void _finishTitleEditing() {
    if (!_isEditingTitle) {
      return;
    }
    _titleFocusNode.unfocus();
    setState(() => _isEditingTitle = false);
    _scheduleTextAutoSave();
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppResponsive.horizontalPadding(context) + 6,
        4,
        AppResponsive.horizontalPadding(context) + 6,
        126,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(_tabs.length, (i) {
              final selected = _selectedTab == i;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == _tabs.length - 1 ? 0 : 8,
                  ),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTab = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(
                                colors: [Color(0xFFA8EDDA), Color(0xFFC2E9FB)],
                              )
                            : null,
                        color: selected
                            ? null
                            : Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x30A8EDDA)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          UiAssetIcon(_tabAssets[i], size: selected ? 18 : 14),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _tabs[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? const Color(0xFF1E5A50)
                                    : AppColors.textSub,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          _buildTabContent(),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0:
        return _buildReadonlyPanel(
          text: formatTimestampedVoiceTranscription(_voiceController.text),
          emptyHint: '暂无语音记录，点击右下角开始录音',
        );
      case 1:
        return _buildEditablePanel(
          controller: _textController,
          hint: '点击这里开始编辑文字笔记...',
          minLines: 12,
        );
      case 2:
        return _buildPhotoContent();
      default:
        return _buildAiPanel(
          text: formatAiNoteText(_aiController.text),
          emptyHint: '暂无 AI 整理结果，录音结束后将自动生成',
        );
    }
  }

  Widget _buildEditablePanel({
    required TextEditingController controller,
    required String hint,
    int minLines = 8,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x35A8EDDA)),
      ),
      child: TextField(
        controller: controller,
        maxLines: null,
        minLines: minLines,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textDark,
          height: 1.6,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textSub),
        ),
      ),
    );
  }

  Widget _buildReadonlyPanel({
    required String text,
    required String emptyHint,
  }) {
    final content = text.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x35A8EDDA)),
      ),
      child: SelectableText(
        content.isEmpty ? emptyHint : content,
        style: TextStyle(
          fontSize: content.isEmpty ? 12.5 : 13,
          color: content.isEmpty ? AppColors.textSub : AppColors.textDark,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildAiPanel({required String text, required String emptyHint}) {
    final content = formatAiNoteText(text);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x35A8EDDA)),
      ),
      child: content.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAiGenerationStatusCard(),
                Text(
                  emptyHint,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSub,
                    height: 1.6,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAiGenerationStatusCard(),
                Align(
                  alignment: Alignment.centerRight,
                  child: _AiExportButton(
                    isExporting: _isExportingAi,
                    onPressed: (buttonContext) =>
                        _exportAiNote(buttonContext, content),
                  ),
                ),
                const SizedBox(height: 8),
                ..._buildAiBlocks(content),
              ],
            ),
    );
  }

  Widget _buildAiGenerationStatusCard() {
    final source = _aiGenerationSource.trim().isNotEmpty
        ? _aiGenerationSource
        : _voiceController.text.trim();
    final hasSource = source.trim().isNotEmpty;
    final state = _aiGenerationState;
    if (state == AiGenerationState.idle ||
        state == AiGenerationState.completed ||
        !hasSource) {
      return const SizedBox.shrink();
    }

    final isRecording = _hasActiveVoiceRecording;
    final isGenerating =
        state == AiGenerationState.generating || _isRetryingAi || isRecording;
    final title = isGenerating ? 'AI 正在整理笔记' : 'AI 整理未完成';
    final message = isRecording
        ? '录音仍在进行，AI整理会继续追加；录音结束前不触发重试。'
        : isGenerating
        ? '如果退出 App 或网络中断，下次打开可在这里继续重试。'
        : (_aiGenerationError.trim().isEmpty
              ? '上次生成可能被打断，可以重新生成。'
              : _aiGenerationError.trim());

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF5D58C)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isGenerating ? Icons.hourglass_top : Icons.error_outline,
            size: 18,
            color: const Color(0xFFB7791F),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSub,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!isGenerating)
            TextButton(
              onPressed: _retryAiGeneration,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('重试'),
            )
          else
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Future<void> _retryAiGeneration() async {
    if (_isRetryingAi) {
      return;
    }
    if (_hasActiveVoiceRecording) {
      return;
    }
    if (!AIServiceConfig.isConfigured()) {
      setState(() {
        _aiGenerationState = AiGenerationState.failed;
        _aiGenerationError = 'AI 未配置，请先在设置页配置 DeepSeek。';
      });
      await _saveNote(silent: true, force: true);
      return;
    }

    final source =
        (_aiGenerationSource.trim().isNotEmpty
                ? _aiGenerationSource
                : _voiceController.text)
            .trim();
    if (source.isEmpty) {
      return;
    }

    final service = AINotesGenerationService.deepseek(
      AIServiceConfig.getCurrentApiKey() ?? '',
      apiUrl: AIServiceConfig.getCurrentApiUrl(),
      model: AIServiceConfig.getCurrentModel(),
    );
    final repository = context.read<AppRepository>();

    setState(() {
      _isRetryingAi = true;
      _aiGenerationState = AiGenerationState.generating;
      _aiGenerationSource = source;
      _aiGenerationError = '';
    });
    await _saveNote(silent: true, force: true);

    try {
      await _retryAiSub?.cancel();
      _retryAiSub = service.noteStream.listen(
        (content) {
          if (!mounted) {
            return;
          }
          setState(() {
            _aiController.text = formatAiNoteText(content);
          });
          _scheduleGeneratedAutoSave();
        },
        onError: (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _aiGenerationState = AiGenerationState.failed;
            _aiGenerationError = 'AI 生成失败：${formatAiError(error)}';
            _isRetryingAi = false;
          });
        },
      );

      final courses = await repository.getCourses();
      final course = _resolveCourse(courses);
      await service.generateNoteContent(
        transcription: source,
        existingContent: _aiController.text,
        previousContext: _aiController.text,
        courseName: course.name,
        noteTitle: _titleController.text.trim(),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _aiController.text = formatAiNoteText(service.currentNoteContent);
        _aiGenerationState = AiGenerationState.completed;
        _aiGenerationError = '';
        _isRetryingAi = false;
      });
      await _saveNote(silent: true, force: true);
    } catch (e) {
      if (!mounted) {
        return;
      }
      final message = formatAiError(e);
      setState(() {
        _aiGenerationState = AiGenerationState.failed;
        _aiGenerationError = 'AI 生成失败：$message';
        _isRetryingAi = false;
      });
      await _saveNote(silent: true, force: true);
    } finally {
      await _retryAiSub?.cancel();
      _retryAiSub = null;
      service.dispose();
    }
  }

  Future<void> _exportAiNote(BuildContext buttonContext, String content) async {
    if (_isExportingAi) {
      return;
    }
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _isExportingAi = true);
    try {
      final repository = context.read<AppRepository>();
      final courses = await repository.getCourses();
      final course = _resolveCourse(courses);

      await const AiNoteExportService().exportMarkdown(
        title: _resolvedTitle(),
        courseName: course.name,
        aiContent: content,
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    } finally {
      if (mounted) {
        setState(() => _isExportingAi = false);
      }
    }
  }

  List<Widget> _buildAiBlocks(String content) {
    final widgets = <Widget>[];
    final lines = _normalizeAiDisplayLines(
      content
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(),
    );

    if (_shouldAddAutoAiHeading(lines)) {
      widgets.add(_AiHeadingLine(text: _deriveAutoAiHeading(lines)));
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (RegExp(r'^\[\d{2}:\d{2}\]$').hasMatch(line)) {
        continue;
      }
      if (_looksLikeAiTableLine(line)) {
        final tableLines = <String>[];
        while (i < lines.length && _looksLikeAiTableLine(lines[i])) {
          tableLines.add(lines[i]);
          i++;
        }
        i--;
        final rows = tableLines
            .map(_parseAiTableRow)
            .where((row) => row.length >= 2 && !_isAiTableDivider(row))
            .toList();
        if (rows.length >= 2) {
          widgets.add(_AiTableBlock(rows: rows));
        }
        continue;
      }
      if (line.startsWith('▌')) {
        widgets.add(_AiQuoteBlock(text: line.substring(1).trim()));
        continue;
      }
      if (line.startsWith('•')) {
        final body = line.substring(1).trim();
        if (_looksLikeAiHeading(body)) {
          widgets.add(_AiHeadingLine(text: body));
        } else if (_looksLikeAiDefinition(body)) {
          widgets.add(_AiQuoteBlock(text: body));
        } else {
          widgets.add(_AiBulletLine(text: body));
        }
        continue;
      }
      if (_looksLikeAiDefinition(line)) {
        widgets.add(_AiQuoteBlock(text: line));
        continue;
      }
      widgets.add(_AiHeadingLine(text: line));
    }

    return widgets;
  }

  List<String> _normalizeAiDisplayLines(List<String> lines) {
    final cleaned = <String>[];
    for (final line in lines) {
      final currentKey = _compactAiDisplayKey(line);
      if (currentKey.isEmpty) {
        continue;
      }

      if (cleaned.isNotEmpty) {
        final previous = cleaned.last;
        final previousKey = _compactAiDisplayKey(previous);
        if (currentKey == previousKey) {
          continue;
        }
        if (_isProgressiveAiRewrite(previousKey, currentKey)) {
          cleaned[cleaned.length - 1] = currentKey.length >= previousKey.length
              ? line
              : previous;
          continue;
        }
      }

      cleaned.add(line);
    }
    return cleaned;
  }

  bool _isProgressiveAiRewrite(String previous, String current) {
    if (previous.length < 8 || current.length < 8) {
      return false;
    }
    return previous.startsWith(current) || current.startsWith(previous);
  }

  String _compactAiDisplayKey(String value) {
    return value
        .replaceAll(RegExp(r'^\[\d{2}:\d{2}\]$'), '')
        .replaceAll(RegExp(r'^[•▌\-\d.、\s]+'), '')
        .replaceAll('|', '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  bool _shouldAddAutoAiHeading(List<String> lines) {
    if (lines.length < 2) {
      return false;
    }
    var bulletCount = 0;
    for (final line in lines) {
      if (RegExp(r'^\[\d{2}:\d{2}\]$').hasMatch(line)) {
        continue;
      }
      if (_looksLikeAiTableLine(line) ||
          line.startsWith('▌') ||
          _looksLikeAiDefinition(line)) {
        return false;
      }
      if (line.startsWith('•')) {
        bulletCount++;
        continue;
      }
      return false;
    }
    return bulletCount >= 2;
  }

  String _deriveAutoAiHeading(List<String> lines) {
    final firstBullet = lines
        .map((line) => line.replaceFirst(RegExp(r'^[•\-\s]+'), '').trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '课堂整理');
    final firstPhrase = firstBullet
        .split(RegExp(r'[，。；;,.!?！？]'))
        .map((part) => part.trim())
        .firstWhere((part) => part.isNotEmpty, orElse: () => firstBullet);
    if (firstPhrase.length <= 18) {
      return firstPhrase;
    }
    return firstPhrase.substring(0, 18);
  }

  bool _looksLikeAiTableLine(String value) {
    final cells = _parseAiTableRow(value);
    return cells.length >= 2;
  }

  bool _looksLikeAiHeading(String value) {
    final text = value.trim();
    if (text.isEmpty || text.contains('|')) {
      return false;
    }
    if (_AiHeadingLine.hasLeadingIcon(text)) {
      return true;
    }
    return text.length <= 24 &&
        !text.endsWith('。') &&
        !text.endsWith('；') &&
        !text.endsWith(';');
  }

  List<String> _parseAiTableRow(String value) {
    return value
        .split('|')
        .map((cell) => cell.trim())
        .where((cell) => cell.isNotEmpty)
        .toList();
  }

  bool _isAiTableDivider(List<String> row) {
    return row.every((cell) => RegExp(r'^:?-{2,}:?$').hasMatch(cell));
  }

  bool _looksLikeAiDefinition(String value) {
    final text = value.trim();
    if (text.isEmpty || text.length < 16) {
      return false;
    }
    if (text.startsWith('📌') ||
        text.startsWith('🔍') ||
        text.startsWith('📝') ||
        text.startsWith('💡')) {
      return false;
    }
    if (text.contains('|')) {
      return false;
    }
    return text.contains('指的是') ||
        text.contains('是指') ||
        text.contains('意味着') ||
        text.contains('可以理解为') ||
        text.contains('本质是') ||
        text.contains('核心是');
  }

  Widget _buildPhotoContent() {
    final compact = AppResponsive.isCompact(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x35A8EDDA)),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '拍照记录会保存到当前笔记中，支持拍照和从相册选择。',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSub,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: _isLoadingPhotos ? null : _showPhotoOptions,
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                        label: Text(_isLoadingPhotos ? '处理中' : '添加'),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '拍照记录会保存到当前笔记中，支持拍照和从相册选择。',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSub,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonalIcon(
                      onPressed: _isLoadingPhotos ? null : _showPhotoOptions,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: Text(_isLoadingPhotos ? '处理中' : '添加'),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        if (_photoRecords.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x35A8EDDA)),
            ),
            child: const Text(
              '还没有图片记录，点击“添加”或右下角相机按钮开始。',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSub,
                height: 1.6,
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _photoRecords.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: AppResponsive.isWide(context) ? 3 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.92,
            ),
            itemBuilder: (context, index) {
              final record = _photoRecords[index];
              return _PhotoCard(record: record);
            },
          ),
      ],
    );
  }

  Widget _buildBottom(BuildContext context) {
    return const SizedBox.shrink();
  }

  Future<void> _saveNote({bool silent = false, bool force = false}) async {
    if (silent && !force && !_hasSavableContent() && _currentNote == null) {
      return;
    }

    final fingerprint = _saveFingerprint();
    if (silent && fingerprint == _lastSavedFingerprint) {
      return;
    }

    if (_isSaving) {
      if (silent) {
        _pendingSilentSave = true;
      }
      return;
    }

    if (mounted) {
      setState(() => _isSaving = true);
    }
    try {
      final repository = context.read<AppRepository>();
      final courses = await repository.getCourses();
      final selectedCourse = _resolveCourse(courses);
      final now = DateTime.now();
      final title = _resolvedTitle();

      final note =
          (_currentNote ??
                  NoteEntry(
                    id: 'note-${now.microsecondsSinceEpoch}',
                    courseId: selectedCourse.id,
                    title: title,
                    type: _resolveType(),
                    createdAt: now,
                    updatedAt: now,
                  ))
              .copyWith(
                courseId: selectedCourse.id,
                title: title,
                type: _resolveType(),
                rawTranscription: formatTimestampedVoiceTranscription(
                  _voiceController.text,
                ),
                textContent: _textController.text.trim(),
                aiSummary: formatAiNoteText(_aiController.text),
                aiGenerationState: _aiGenerationState,
                aiGenerationSource: _aiGenerationSource,
                aiGenerationError: _aiGenerationError,
                photoIds: _photoRecords.map((record) => record.id).toList(),
                updatedAt: now,
              );

      await repository.saveNote(note);
      _currentNote = note;
      _lastSavedFingerprint = _saveFingerprint();

      if (!mounted) {
        return;
      }
      if (!silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('笔记已保存')));
      }
      setState(() {});
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
      if (_pendingSilentSave) {
        _pendingSilentSave = false;
        unawaited(_saveNote(silent: true));
      }
    }
  }

  void _scheduleTextAutoSave() {
    if (!_hasSavableContent()) {
      return;
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(
      const Duration(seconds: 2),
      () => unawaited(_saveNote(silent: true)),
    );
  }

  void _scheduleGeneratedAutoSave() {
    if (!_hasSavableContent()) {
      return;
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(
      const Duration(milliseconds: 900),
      () => unawaited(_saveNote(silent: true)),
    );
  }

  Future<void> _flushPendingAutoSave() async {
    _autoSaveTimer?.cancel();
    if (_hasSavableContent()) {
      await _saveNote(silent: true);
    }
  }

  bool _hasSavableContent() {
    return _titleController.text.trim().isNotEmpty ||
        _voiceController.text.trim().isNotEmpty ||
        _textController.text.trim().isNotEmpty ||
        _aiController.text.trim().isNotEmpty ||
        _aiGenerationState != AiGenerationState.idle ||
        _photoRecords.isNotEmpty;
  }

  String _saveFingerprint() {
    return [
      _titleController.text.trim(),
      formatTimestampedVoiceTranscription(_voiceController.text),
      _textController.text.trim(),
      formatAiNoteText(_aiController.text),
      _aiGenerationState.name,
      _aiGenerationSource,
      _aiGenerationError,
      _photoRecords.map((record) => record.id).join(','),
    ].join('\u001f');
  }

  void _markAiGenerating(String source) {
    final normalizedSource = formatTimestampedVoiceTranscription(source);
    if (normalizedSource.trim().isEmpty) {
      return;
    }
    _aiGenerationState = AiGenerationState.generating;
    _aiGenerationSource = normalizedSource;
    _aiGenerationError = '';
  }

  bool get _hasActiveVoiceRecording =>
      RealtimeTranscriptionService.instance.isListening;

  Future<void> _showPhotoOptions() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const UiAssetIcon('拍照.png', size: 22),
                title: const Text('拍照'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) {
      return;
    }

    await _addPhoto(source);
  }

  Future<void> _addPhoto(ImageSource source) async {
    final repository = context.read<AppRepository>();

    if (_currentNote == null) {
      await _saveNote(silent: true, force: true);
    }

    final note = _currentNote;
    if (note == null) {
      return;
    }

    setState(() => _isLoadingPhotos = true);
    try {
      final hasPermission = await _ensurePhotoPermission(source);
      if (!hasPermission) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有图片权限，无法继续')));
        return;
      }

      final pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 88,
      );

      if (pickedFile == null) {
        return;
      }

      final storedPath = await _copyPhotoToAppDir(pickedFile, note.id);
      final now = DateTime.now();
      final record = PhotoRecord(
        id: 'photo-${now.microsecondsSinceEpoch}',
        noteId: note.id,
        filePath: storedPath,
        createdAt: now,
        caption: '',
      );

      await repository.savePhotoRecord(record);

      final updatedPhotos = [..._photoRecords, record];
      final updatedNote = note.copyWith(
        type: _resolveType(photoCount: updatedPhotos.length),
        photoIds: updatedPhotos.map((item) => item.id).toList(),
        updatedAt: now,
      );
      await repository.saveNote(updatedNote);

      if (!mounted) {
        return;
      }

      setState(() {
        _photoRecords = updatedPhotos;
        _currentNote = updatedNote;
        _lastSavedFingerprint = _saveFingerprint();
        _selectedTab = 2;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片已加入笔记')));
    } finally {
      if (mounted) {
        setState(() => _isLoadingPhotos = false);
      }
    }
  }

  Future<bool> _ensurePhotoPermission(ImageSource source) async {
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      return status.isGranted;
    }
    return true;
  }

  Future<String> _copyPhotoToAppDir(XFile file, String noteId) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${baseDir.path}/note_photos/$noteId');
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }

    final extension = file.path.contains('.')
        ? file.path.substring(file.path.lastIndexOf('.'))
        : '.jpg';
    final targetPath =
        '${photoDir.path}/photo_${DateTime.now().microsecondsSinceEpoch}$extension';
    await File(file.path).copy(targetPath);
    return targetPath;
  }

  Course _resolveCourse(List<Course> courses) {
    if (_currentNote != null) {
      for (final course in courses) {
        if (course.id == _currentNote!.courseId) {
          return course;
        }
      }
    }

    final initialCourseId = widget.initialCourseId;
    if (initialCourseId != null) {
      for (final course in courses) {
        if (course.id == initialCourseId) {
          return course;
        }
      }
    }

    if (courses.isNotEmpty) {
      return courses.first;
    }

    final now = DateTime.now();
    return Course(
      id: 'uncategorized',
      name: widget.courseName ?? '未分类课程',
      colorHex: '#A8EDDA',
      createdAt: now,
      updatedAt: now,
    );
  }

  NoteType _resolveType({int? photoCount}) {
    final hasVoice = _voiceController.text.trim().isNotEmpty;
    final hasText = _textController.text.trim().isNotEmpty;
    final hasAi = _aiController.text.trim().isNotEmpty;
    final hasPhotos = (photoCount ?? _photoRecords.length) > 0;
    final contentKinds = [
      hasVoice,
      hasText || hasAi,
      hasPhotos,
    ].where((value) => value).length;

    if (contentKinds > 1) {
      return NoteType.mixed;
    }
    if (hasPhotos) {
      return NoteType.photo;
    }
    if (hasVoice) {
      return NoteType.voice;
    }
    return NoteType.text;
  }

  String _resolvedTitle() {
    final text = _titleController.text.trim();
    if (text.isNotEmpty) {
      return text;
    }
    if (_textController.text.trim().isNotEmpty) {
      return _buildSuggestedTitle(_textController.text);
    }
    if (_voiceController.text.trim().isNotEmpty) {
      return _buildSuggestedTitle(_voiceController.text);
    }
    if (_aiController.text.trim().isNotEmpty) {
      return _buildSuggestedTitle(_aiController.text);
    }
    return '未命名笔记';
  }

  String _buildSuggestedTitle(String value) {
    final firstLine = value
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '未命名笔记');
    return firstLine.length > 18
        ? '${firstLine.substring(0, 18)}...'
        : firstLine;
  }
}

class _AiHeadingLine extends StatelessWidget {
  const _AiHeadingLine({required this.text});

  final String text;

  static const _headingEmojis = [
    '🔍',
    '📌',
    '📝',
    '💡',
    '✅',
    '📚',
    '🎯',
    '⭐',
    '🧠',
    '📎',
    '📊',
    '🧩',
  ];

  @override
  Widget build(BuildContext context) {
    final displayText = _withDisplayEmoji(text);
    final parts = _splitLeadingIcon(displayText);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: parts.$1),
            TextSpan(
              text: parts.$2,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
          height: 1.35,
        ),
      ),
    );
  }

  String _withDisplayEmoji(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    if (hasLeadingIcon(trimmed)) {
      return trimmed;
    }
    final emoji =
        _headingEmojis[trimmed.hashCode.abs() % _headingEmojis.length];
    return '$emoji $trimmed';
  }

  static bool hasLeadingIcon(String value) {
    if (_headingEmojis.any(value.startsWith)) {
      return true;
    }
    if (value.runes.isEmpty) {
      return false;
    }
    final firstRune = value.runes.first;
    return firstRune >= 0x1F000 || firstRune == 0x2600 || firstRune == 0x2705;
  }

  (String, String) _splitLeadingIcon(String value) {
    final trimmed = value.trimLeft();
    if (trimmed.runes.isEmpty) {
      return ('', trimmed);
    }
    final firstRune = trimmed.runes.first;
    final firstChar = String.fromCharCode(firstRune);
    final rest = trimmed.substring(firstChar.length);
    if (hasLeadingIcon(firstChar)) {
      return ('$firstChar ', rest.trimLeft());
    }
    return ('', trimmed);
  }
}

class _AiBulletLine extends StatelessWidget {
  const _AiBulletLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colonIndex = _firstColon(text);
    final hasLead = colonIndex > 0 && colonIndex < text.length - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Text(
              '•',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 17,
                  color: AppColors.textDark,
                  height: 1.65,
                ),
                children: hasLead
                    ? [
                        TextSpan(
                          text: text.substring(0, colonIndex + 1),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        TextSpan(text: text.substring(colonIndex + 1)),
                      ]
                    : [TextSpan(text: text)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _firstColon(String value) {
    final chinese = value.indexOf('：');
    final english = value.indexOf(':');
    if (chinese < 0) {
      return english;
    }
    if (english < 0) {
      return chinese;
    }
    return chinese < english ? chinese : english;
  }
}

class _AiQuoteBlock extends StatelessWidget {
  const _AiQuoteBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6, bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        color: Color(0x66FFFFFF),
        border: Border(left: BorderSide(color: Color(0xFFB06AF3), width: 5)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
          height: 1.7,
        ),
      ),
    );
  }
}

class _AiTableBlock extends StatelessWidget {
  const _AiTableBlock({required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final columnCount = rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    if (columnCount < 2 || rows.length < 2) {
      return const SizedBox.shrink();
    }

    final normalizedRows = rows
        .map(
          (row) => [
            ...row,
            ...List<String>.filled(columnCount - row.length, ''),
          ],
        )
        .toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0x66FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE3E8F2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: const Color(0xFFE3E8F2), width: 1),
          children: [
            for (var rowIndex = 0; rowIndex < normalizedRows.length; rowIndex++)
              TableRow(
                decoration: BoxDecoration(
                  color: rowIndex == 0
                      ? const Color(0xFFF5F7FB)
                      : rowIndex.isEven
                      ? const Color(0x33F7FAFF)
                      : Colors.transparent,
                ),
                children: [
                  for (final cell in normalizedRows[rowIndex])
                    _AiTableCell(text: cell, isHeader: rowIndex == 0),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AiTableCell extends StatelessWidget {
  const _AiTableCell({required this.text, required this.isHeader});

  final String text;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 178),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isHeader ? FontWeight.w900 : FontWeight.w500,
            color: AppColors.textDark,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _AiExportButton extends StatelessWidget {
  const _AiExportButton({required this.isExporting, required this.onPressed});

  final bool isExporting;
  final ValueChanged<BuildContext> onPressed;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) {
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isExporting ? null : () => onPressed(buttonContext),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE9F8F4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x66A8EDDA)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isExporting)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(
                    Icons.ios_share_outlined,
                    size: 13,
                    color: Color(0xFF3C8F7D),
                  ),
                const SizedBox(width: 4),
                Text(
                  isExporting ? '导出中' : '导出',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3C8F7D),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.record});

  final PhotoRecord record;

  @override
  Widget build(BuildContext context) {
    final imageFile = File(record.filePath);
    return GestureDetector(
      onTap: imageFile.existsSync()
          ? () => _showPhotoPreview(context, imageFile)
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageFile.existsSync())
              Image.file(imageFile, fit: BoxFit.cover)
            else
              Container(
                color: Colors.white.withValues(alpha: 0.6),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textSub,
                  size: 30,
                ),
              ),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.36),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.zoom_out_map,
                  color: Colors.white,
                  size: 15,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
                child: Text(
                  record.caption.trim().isEmpty ? '图片记录' : record.caption,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoPreview(BuildContext context, File imageFile) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.86),
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.transparent,
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Center(
                      child: Image.file(imageFile, fit: BoxFit.contain),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 12,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FloatingRecordBtn extends StatelessWidget {
  const _FloatingRecordBtn({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFA8EDDA), Color(0xFF7DD3C0)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF50B4A0).withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(child: UiAssetIcon('录音.png', size: 42)),
      ),
    );
  }
}

class _FloatingPhotoBtn extends StatelessWidget {
  const _FloatingPhotoBtn({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFB347), Color(0xFFFF6B6B)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6B6B).withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(child: UiAssetIcon('拍照.png', size: 42)),
      ),
    );
  }
}
