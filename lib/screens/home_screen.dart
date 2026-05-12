import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/ai_qa_message.dart';
import '../models/course.dart';
import '../models/dashboard_stats.dart';
import '../models/note_entry.dart';
import '../models/voice_record.dart';
import '../services/ai/ai_qa_history_service.dart';
import '../services/ai/ai_qa_service.dart';
import '../services/ai/note_retrieval_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_responsive.dart';
import '../widgets/app_gif.dart';
import '../widgets/glass_card.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/stat_card.dart';
import '../widgets/section_title.dart';
import '../widgets/recent_notes.dart';
import '../widgets/course_view.dart';
import '../widgets/ui_asset_icon.dart';
import 'note_detail_screen.dart';
import 'settings_screen.dart';
import 'voice_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIdx = 0;
  late final String _homeGreetingGif = _CharGreeting
      .greetingGifs[Random().nextInt(_CharGreeting.greetingGifs.length)];

  void _onNav(int i) {
    setState(() => _navIdx = i);
  }

  void _showVoice() {
    _openVoiceSheet();
  }

  void _goNav(int index) {
    setState(() => _navIdx = index);
  }

  Future<void> _openVoiceSheet() async {
    final result = await showModalBottomSheet<VoiceNoteResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceSheet(onClose: null),
    );

    if (result == null) {
      return;
    }

    await _saveVoiceResult(result);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('语音笔记已保存')));
    }
  }

  Future<void> _saveVoiceResult(VoiceNoteResult result) async {
    final repository = context.read<AppRepository>();
    final courses = await repository.getCourses();
    final primaryCourseId = courses.isNotEmpty
        ? courses.first.id
        : 'uncategorized';
    final now = DateTime.now();
    final noteId = 'note-${now.microsecondsSinceEpoch}';
    final title = _buildVoiceNoteTitle(result);

    final note = NoteEntry(
      id: noteId,
      courseId: primaryCourseId,
      title: title,
      type: NoteType.voice,
      rawTranscription: result.transcription,
      aiSummary: result.generatedNote,
      createdAt: now,
      updatedAt: now,
    );

    await repository.saveNote(note);

    if (result.recordingPath != null && result.recordingPath!.isNotEmpty) {
      await repository.saveVoiceRecord(
        VoiceRecord(
          id: 'voice-${now.microsecondsSinceEpoch}',
          noteId: noteId,
          filePath: result.recordingPath!,
          durationMs: result.durationMs,
          transcription: result.transcription,
          createdAt: now,
        ),
      );
    }
  }

  String _buildVoiceNoteTitle(VoiceNoteResult result) {
    final candidate = result.generatedNote.trim().isNotEmpty
        ? result.generatedNote.trim()
        : result.transcription.trim();
    if (candidate.isEmpty) {
      return '新的语音笔记';
    }
    final firstLine = candidate.split('\n').first.trim();
    return firstLine.length > 18
        ? '${firstLine.substring(0, 18)}...'
        : firstLine;
  }

  Future<void> _goDetail(NoteEntry note) async {
    final repository = context.read<AppRepository>();
    final courses = await repository.getCourses();
    final course = courses
        .where((item) => item.id == note.courseId)
        .firstOrNull;
    if (!mounted) {
      return;
    }
    final updatedNote = await Navigator.push<NoteEntry>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteDetailScreen(note: note, courseName: course?.name),
      ),
    );

    if (updatedNote != null && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: _BgOverlay()),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: _navIdx == 1
                      ? CourseView(onNote: _goDetail)
                      : _navIdx == 2
                      ? _AiView(onNote: _goDetail)
                      : _navIdx == 3
                      ? const SettingsScreen(embedded: true)
                      : _TimeView(
                          onVoice: _showVoice,
                          onNote: _goDetail,
                          onNav: _goNav,
                          greetingGif: _homeGreetingGif,
                        ),
                ),
              ],
            ),
          ),
          if (_navIdx == 0) SafeArea(bottom: false, child: _Header()),
          // 浮动录音按钮 - 只在笔记页面显示
        ],
      ),
      bottomNavigationBar: AppBottomNav(currentIndex: _navIdx, onTap: _onNav),
    );
  }
}

class _BgOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.8, -0.9),
          radius: 0.7,
          colors: [const Color(0x8CA8EDDA), Colors.transparent],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.8, -0.8),
            radius: 0.7,
            colors: [const Color(0x80C8D2FF), Colors.transparent],
          ),
        ),
        child: Container(color: const Color(0xF0EEF8F4)),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              RichText(
                text: TextSpan(
                  style: GoogleFonts.zcoolXiaoWei(
                    fontSize: 27,
                    color: AppColors.textDark,
                  ),
                  children: [
                    const TextSpan(text: '拾光'),
                    TextSpan(
                      text: ' AI',
                      style: GoogleFonts.zcoolXiaoWei(
                        fontSize: 17,
                        foreground: Paint()
                          ..shader = const LinearGradient(
                            colors: [Color(0xFF4A90C4), Color(0xFF8B5CF6)],
                          ).createShader(const Rect.fromLTWH(0, 0, 70, 34)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeView extends StatelessWidget {
  final VoidCallback onVoice;
  final ValueChanged<NoteEntry> onNote;
  final ValueChanged<int> onNav;
  final String greetingGif;
  const _TimeView({
    required this.onVoice,
    required this.onNote,
    required this.onNav,
    required this.greetingGif,
  });

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = AppResponsive.horizontalPadding(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        AppResponsive.isCompact(context) ? 68 : 76,
        horizontalPadding,
        AppResponsive.bottomNavReserve(context) + 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CharGreeting(gifName: greetingGif),
          const SizedBox(height: 11),
          _StatsGrid(onNote: onNote, onNav: onNav),
          const SizedBox(height: 11),
          SectionTitle(icon: Icons.history, label: '最近笔记'),
          const SizedBox(height: 8),
          RecentNotesList(onNote: onNote),
        ],
      ),
    );
  }
}

class _AiView extends StatefulWidget {
  const _AiView({required this.onNote});

  final ValueChanged<NoteEntry> onNote;

  @override
  State<_AiView> createState() => _AiViewState();
}

class _AiViewState extends State<_AiView> {
  final _questionController = TextEditingController();
  final _scrollController = ScrollController();
  final _qaService = AiQaService();
  final _historyService = const AiQaHistoryService();

  List<Course> _courses = const [];
  List<AiQaMessage> _messages = _initialAiMessages();
  String? _currentSessionId;
  String? _selectedCourseId;
  bool _isLoadingCourses = true;
  bool _isAsking = false;
  String? _error;

  String get _selectedCourseLabel {
    if (_selectedCourseId == null) {
      return '全部课程';
    }
    for (final course in _courses) {
      if (course.id == _selectedCourseId) {
        return course.name;
      }
    }
    return '全部课程';
  }

  static List<AiQaMessage> _initialAiMessages() {
    return const [
      AiQaMessage(
        id: 'welcome',
        role: AiQaRole.assistant,
        content: '你好，我可以根据你的本地笔记回答问题。可以先选择课程，也可以检索全部笔记。',
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    final repository = context.read<AppRepository>();
    final courses = await repository.getCourses();
    if (!mounted) {
      return;
    }
    setState(() {
      _courses = courses;
      _isLoadingCourses = false;
    });
  }

  Future<void> _ask() async {
    final question = _questionController.text.trim();
    if (question.isEmpty || _isAsking) {
      return;
    }

    final repository = context.read<AppRepository>();
    final retrieval = NoteRetrievalService(repository);
    final recentMessages = _recentConversationMessages();
    final retrievalQuestion = _retrievalQuestion(
      currentQuestion: question,
      recentMessages: recentMessages,
    );
    final userMessage = AiQaMessage(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      role: AiQaRole.user,
      content: question,
    );
    final assistantId = 'assistant-${DateTime.now().microsecondsSinceEpoch}';
    final assistantMessage = AiQaMessage(
      id: assistantId,
      role: AiQaRole.assistant,
      content: '正在检索本地笔记...',
    );

    setState(() {
      _messages = [..._messages, userMessage, assistantMessage];
      _questionController.clear();
      _isAsking = true;
      _error = null;
    });
    _scrollToBottom();

    try {
      final citations = await retrieval.search(
        question: retrievalQuestion,
        courseId: _selectedCourseId,
      );

      _replaceAssistantMessage(assistantId, content: '', citations: citations);

      final stream = await _qaService.ask(
        question: question,
        citations: citations,
        recentMessages: recentMessages,
      );
      var answer = '';
      await for (final chunk in stream) {
        answer += chunk;
        if (!mounted) {
          return;
        }
        _replaceAssistantMessage(
          assistantId,
          content: answer,
          citations: citations,
        );
      }

      if (answer.trim().isEmpty) {
        _replaceAssistantMessage(
          assistantId,
          content: 'AI 暂时没有返回内容，请稍后重试。',
          citations: citations,
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
      });
      _replaceAssistantMessage(
        assistantId,
        content: '问答失败：$e',
        citations: const [],
      );
    } finally {
      if (mounted) {
        await _saveCurrentSession();
        setState(() => _isAsking = false);
        _scrollToBottom();
      }
    }
  }

  List<AiQaMessage> _recentConversationMessages() {
    final completedMessages = _messages
        .where((message) => message.id != 'welcome')
        .where((message) => message.content.trim().isNotEmpty)
        .toList();
    final maxMessages = 20;
    if (completedMessages.length <= maxMessages) {
      return completedMessages;
    }
    return completedMessages.sublist(completedMessages.length - maxMessages);
  }

  String _retrievalQuestion({
    required String currentQuestion,
    required List<AiQaMessage> recentMessages,
  }) {
    final recentUserQuestions = recentMessages
        .where((message) => message.role == AiQaRole.user)
        .map((message) => message.content.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    final maxQuestions = 10;
    final selectedQuestions = recentUserQuestions.length <= maxQuestions
        ? recentUserQuestions
        : recentUserQuestions.sublist(
            recentUserQuestions.length - maxQuestions,
          );
    return [...selectedQuestions, currentQuestion].join('\n');
  }

  Future<void> _saveCurrentSession() async {
    final sessionId = await _historyService.saveSession(
      sessionId: _currentSessionId,
      messages: _messages,
    );
    if (!mounted) {
      return;
    }
    _currentSessionId = sessionId;
  }

  void _replaceAssistantMessage(
    String id, {
    required String content,
    required List<AiQaCitation> citations,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _messages = _messages.map((message) {
        if (message.id != id) {
          return message;
        }
        return message.copyWith(content: content, citations: citations);
      }).toList();
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _showCoursePicker() async {
    if (_isAsking || _isLoadingCourses) {
      return;
    }
    final selected = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _CoursePickerSheet(
          courses: _courses,
          selectedCourseId: _selectedCourseId,
        );
      },
    );
    if (!mounted) {
      return;
    }
    setState(() => _selectedCourseId = selected);
  }

  Future<void> _showHistory() async {
    if (_isAsking) {
      return;
    }
    final summaries = await _historyService.loadSummaries();
    if (!mounted) {
      return;
    }
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _AiHistorySheet(
          sessions: summaries,
          selectedSessionId: _currentSessionId,
        );
      },
    );
    if (selectedId == null || !mounted) {
      return;
    }
    final repository = context.read<AppRepository>();
    final session = await _historyService.loadSession(
      id: selectedId,
      repository: repository,
    );
    if (session == null || !mounted) {
      return;
    }
    setState(() {
      _currentSessionId = session.id;
      _messages = session.messages.isEmpty
          ? _initialAiMessages()
          : session.messages;
      _error = null;
    });
    _scrollToBottom();
  }

  Future<void> _newConversation() async {
    if (_isAsking) {
      return;
    }
    await _saveCurrentSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _currentSessionId = null;
      _messages = _initialAiMessages();
      _questionController.clear();
      _error = null;
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = AppResponsive.horizontalPadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        24,
        horizontalPadding,
        AppResponsive.bottomNavReserve(context) + 8,
      ),
      child: Column(
        children: [
          _AiChatTopBar(
            isBusy: _isAsking,
            onHistory: _showHistory,
            onNewConversation: _newConversation,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              itemCount: _messages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _QaBubble(
                  message: _messages[index],
                  onCitationTap: widget.onNote,
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          if (_error != null) ...[
            _ErrorText(text: _error!),
            const SizedBox(height: 8),
          ],
          _QuestionInput(
            controller: _questionController,
            isAsking: _isAsking,
            courseLabel: _isLoadingCourses ? '加载中' : _selectedCourseLabel,
            onCourseTap: _showCoursePicker,
            onSubmit: _ask,
          ),
        ],
      ),
    );
  }
}

class _CoursePickerSheet extends StatelessWidget {
  const _CoursePickerSheet({
    required this.courses,
    required this.selectedCourseId,
  });

  final List<Course> courses;
  final String? selectedCourseId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GlassCard(
          borderRadius: 22,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '选择问答范围',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              _CoursePickerTile(
                label: '全部课程',
                selected: selectedCourseId == null,
                onTap: () => Navigator.pop<String?>(context, null),
              ),
              ...courses.map(
                (course) => _CoursePickerTile(
                  label: course.name,
                  selected: selectedCourseId == course.id,
                  onTap: () => Navigator.pop<String?>(context, course.id),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiChatTopBar extends StatelessWidget {
  const _AiChatTopBar({
    required this.isBusy,
    required this.onHistory,
    required this.onNewConversation,
  });

  final bool isBusy;
  final VoidCallback onHistory;
  final VoidCallback onNewConversation;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _AiToolbarButton(
          icon: Icons.history,
          label: '历史',
          enabled: !isBusy,
          onTap: onHistory,
        ),
        _AiToolbarButton(
          icon: Icons.add_comment_outlined,
          label: '新建',
          enabled: !isBusy,
          onTap: onNewConversation,
        ),
      ],
    );
  }
}

class _AiToolbarButton extends StatelessWidget {
  const _AiToolbarButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x8CFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xBFFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: enabled ? AppColors.textSub : const Color(0x806B82A8),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: enabled ? AppColors.textDark : const Color(0x806B82A8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiHistorySheet extends StatelessWidget {
  const _AiHistorySheet({
    required this.sessions,
    required this.selectedSessionId,
  });

  final List<AiQaSessionSummary> sessions;
  final String? selectedSessionId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GlassCard(
          borderRadius: 22,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.58,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '历史聊天',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                if (sessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      '暂无历史聊天',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSub,
                        height: 1.5,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        return _AiHistoryTile(
                          session: session,
                          selected: session.id == selectedSessionId,
                          onTap: () => Navigator.pop(context, session.id),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiHistoryTile extends StatelessWidget {
  const _AiHistoryTile({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final AiQaSessionSummary session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      leading: Icon(
        selected ? Icons.chat_bubble : Icons.chat_bubble_outline,
        color: selected ? const Color(0xFF4A90C4) : AppColors.textSub,
      ),
      title: Text(
        session.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.textDark,
        ),
      ),
      subtitle: Text(
        '${session.messageCount} 条消息 · ${_formatHistoryTime(session.updatedAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: AppColors.textSub),
      ),
      onTap: onTap,
    );
  }

  String _formatHistoryTime(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}

class _CoursePickerTile extends StatelessWidget {
  const _CoursePickerTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? const Color(0xFF4A90C4) : AppColors.textSub,
      ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _QaBubble extends StatelessWidget {
  const _QaBubble({required this.message, required this.onCitationTap});

  final AiQaMessage message;
  final ValueChanged<NoteEntry> onCitationTap;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiQaRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: GlassCard(
          borderRadius: 18,
          padding: const EdgeInsets.all(12),
          gradient: isUser
              ? AppColors.mintGrad
              : const LinearGradient(
                  colors: [Color(0xEFFFFFFF), Color(0xCFFFFFFF)],
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.content.isEmpty ? '正在生成回答...' : message.content,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: AppColors.textDark,
                ),
              ),
              if (!isUser && message.citations.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: message.citations.map((citation) {
                    return _CitationChip(
                      citation: citation,
                      onTap: () => onCitationTap(citation.note),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CitationChip extends StatelessWidget {
  const _CitationChip({required this.citation, required this.onTap});

  final AiQaCitation citation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 230),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0x78FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xBFFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.article_outlined,
              size: 16,
              color: AppColors.textSub,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '${citation.courseName} · ${citation.note.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionInput extends StatelessWidget {
  const _QuestionInput({
    required this.controller,
    required this.isAsking,
    required this.courseLabel,
    required this.onCourseTap,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool isAsking;
  final String courseLabel;
  final VoidCallback onCourseTap;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            enabled: !isAsking,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSubmit(),
            decoration: const InputDecoration(
              hintText: '问问你的笔记...',
              border: InputBorder.none,
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _CourseScopeButton(
                    label: '@$courseLabel',
                    enabled: !isAsking,
                    onTap: onCourseTap,
                  ),
                ),
              ),
              IconButton.filled(
                onPressed: isAsking ? null : onSubmit,
                icon: isAsking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const UiAssetIcon('发送键-点击触发动效.gif', size: 22),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CourseScopeButton extends StatelessWidget {
  const _CourseScopeButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x72FFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xBFFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.alternate_email,
              size: 15,
              color: AppColors.textSub,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: enabled ? AppColors.textDark : AppColors.textSub,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: AppColors.textSub,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E)),
    );
  }
}

enum _NoteFilter { today, thisWeek }

class _FilteredNotesScreen extends StatelessWidget {
  const _FilteredNotesScreen({required this.filter, required this.onNote});

  final _NoteFilter filter;
  final ValueChanged<NoteEntry> onNote;

  @override
  Widget build(BuildContext context) {
    final title = filter == _NoteFilter.today ? '今日笔记' : '本周笔记';
    final repository = context.read<AppRepository>();
    return Scaffold(
      backgroundColor: const Color(0xF0F3EEFF),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),
      body: FutureBuilder<List<Object>>(
        future: Future.wait<Object>([
          repository.getNotes(),
          repository.getCourses(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final notes = (snapshot.data![0] as List<NoteEntry>)
              .where(_matchesFilter)
              .toList();
          final courses = snapshot.data![1] as List<Course>;
          final courseMap = {for (final course in courses) course.id: course};

          if (notes.isEmpty) {
            return Center(
              child: Text(
                filter == _NoteFilter.today ? '今天还没有笔记' : '本周还没有新增笔记',
                style: const TextStyle(fontSize: 13, color: AppColors.textSub),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final note = notes[index];
              final course = courseMap[note.courseId];
              return _FilteredNoteTile(
                note: note,
                courseName: course?.name ?? '未分类',
                courseColor: _colorFromHex(course?.colorHex ?? '#FFC857'),
                onTap: () => onNote(note),
              );
            },
          );
        },
      ),
    );
  }

  bool _matchesFilter(NoteEntry note) {
    final now = DateTime.now();
    final date = note.createdAt;
    if (filter == _NoteFilter.today) {
      return date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    }
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return !date.isBefore(weekStart);
  }

  Color _colorFromHex(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) {
      buffer.write('ff');
    }
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

class _FilteredNoteTile extends StatelessWidget {
  const _FilteredNoteTile({
    required this.note,
    required this.courseName,
    required this.courseColor,
    required this.onTap,
  });

  final NoteEntry note;
  final String courseName;
  final Color courseColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: courseColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_relativeTime(note.updatedAt)} · $courseName',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSub,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) {
      return '刚刚';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} 分钟前';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} 小时前';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    }
    return '${time.month}.${time.day}';
  }
}

class _CharGreeting extends StatefulWidget {
  const _CharGreeting({required this.gifName});

  static const greetingGifs = [
    '罗小黑竖大拇指.gif',
    '罗小黑的Q版形象-点头.gif',
    '罗小黑的Q版形象剪刀手.gif',
    '罗小黑的Q版形象-思考.gif',
    '罗小黑的Q版形象-羡慕.gif',
  ];

  final String gifName;

  @override
  State<_CharGreeting> createState() => _CharGreetingState();
}

class _CharGreetingState extends State<_CharGreeting>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _y;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _y = Tween(
      begin: 0.0,
      end: -6.0,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppResponsive.isCompact(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(color: Colors.white.withValues(alpha: 0.9)),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
              child: Container(color: const Color(0x61FFFFFF)),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xBFFFFFFF), width: 1.5),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, compact ? 8 : 10, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedBuilder(
                  animation: _y,
                  child: AppGif(widget.gifName, size: compact ? 66 : 82),
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, _y.value),
                    child: child,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _Bubble(text: _DailyAiGreeting.today())),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: const Color(0x8CFFFFFF),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                ),
                border: Border.all(color: const Color(0xD9FFFFFF), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A2840),
                      height: 1.65,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFA8EDDA), Color(0xFFC2E9FB)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wb_sunny,
                          size: 18,
                          color: Color(0xFF1E5A50),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '元气满满',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E5A50),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: -8,
          bottom: 12,
          child: CustomPaint(painter: _TailPainter(), size: const Size(10, 10)),
        ),
      ],
    );
  }
}

class _DailyAiGreeting {
  static const _messages = [
    '今天也可以从一个小想法开始，我会帮你整理成清晰笔记。',
    '把零散的记录交给我，重点、结构和回顾线索都可以慢慢形成。',
    '随手记下一点内容，AI 会帮你把它变成更容易复习的笔记。',
    '不用一次写完整，先留下声音或文字，整理的部分交给我。',
    '今天的学习从一条记录开始，我会帮你提炼重点。',
    '灵感、课堂、待办都可以先放进来，我会帮你归纳成有序内容。',
    '记录不用完美，重要的是先保存下来，再一起整理清楚。',
    '有新的想法就说出来，我会帮你沉淀成可回看的笔记。',
  ];

  static String today([DateTime? now]) {
    final date = now ?? DateTime.now();
    final dayKey = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime(2026)).inDays;
    return _messages[dayKey.abs() % _messages.length];
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.drawPath(
      Path()
        ..moveTo(s.width, 0)
        ..lineTo(0, s.height / 2)
        ..lineTo(s.width, s.height)
        ..close(),
      Paint()..color = const Color(0xA6FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.onNote, required this.onNav});

  final ValueChanged<NoteEntry> onNote;
  final ValueChanged<int> onNav;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AppRepository>();
    return FutureBuilder<DashboardStats>(
      future: repository.getDashboardStats(),
      builder: (context, snapshot) {
        final stats = snapshot.data;
        final compact = AppResponsive.isCompact(context);
        return GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: compact ? 8 : 10,
          mainAxisSpacing: compact ? 8 : 10,
          childAspectRatio: compact ? 1.32 : 1.45,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            StatCard(
              iconAsset: '首页1.png',
              label: '今日笔记',
              value: '${stats?.todayNoteCount ?? 0}',
              sub: '条记录',
              bar: const [Color(0xFF7EE8C8), Color(0xFF5DCFED)],
              barW: _ratio(stats?.todayNoteCount ?? 0, 8),
              grad: const [Color(0x8CA8EDDA), Color(0x66C2E9FB)],
              onTap: () => _openFilteredNotes(context, _NoteFilter.today),
            ),
            StatCard(
              iconAsset: '首页2.png',
              label: '课程数量',
              value: '${stats?.courseCount ?? 0}',
              sub: '门课程',
              bar: const [Color(0xFFC4AAFF), Color(0xFFA0C0FF)],
              barW: _ratio(stats?.courseCount ?? 0, 8),
              grad: const [Color(0x8CDDD0FF), Color(0x66C2D2FF)],
              onTap: () => onNav(1),
            ),
            StatCard(
              iconAsset: '首页3.png',
              label: '本周笔记',
              value: '${stats?.weekNoteCount ?? 0}',
              sub: '条新增',
              bar: const [Color(0xFFFFB3D1), Color(0xFFFFCA8A)],
              barW: _ratio(stats?.weekNoteCount ?? 0, 24),
              grad: const [Color(0x8CFDD5E8), Color(0x66FFDCB9)],
              onTap: () => _openFilteredNotes(context, _NoteFilter.thisWeek),
            ),
            StatCard(
              iconAsset: '首页4.png',
              label: 'AI 问答',
              value: '${stats?.aiQuestionCount ?? 0}',
              sub: '次提问',
              bar: const [Color(0xFF88D8F8), Color(0xFFA8EDDA)],
              barW: _ratio(stats?.aiQuestionCount ?? 0, 20),
              grad: const [Color(0x8CC2E9FB), Color(0x66A8EDDA)],
              onTap: () => onNav(2),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openFilteredNotes(
    BuildContext context,
    _NoteFilter filter,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FilteredNotesScreen(filter: filter, onNote: onNote),
      ),
    );
  }
}

double _ratio(int value, int max) {
  if (max <= 0) {
    return 0.0;
  }
  final result = value / max;
  return result.clamp(0.12, 1.0);
}

extension on Iterable<Course> {
  Course? get firstOrNull => isEmpty ? null : first;
}
