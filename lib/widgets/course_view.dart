import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/course.dart';
import '../models/note_entry.dart';
import '../theme/app_theme.dart';
import '../utils/app_responsive.dart';
import '../utils/ui_formatters.dart';
import '../screens/note_detail_screen.dart';
import 'app_gif.dart';

class CourseView extends StatefulWidget {
  const CourseView({super.key, required this.onNote});

  final ValueChanged<NoteEntry> onNote;

  @override
  State<CourseView> createState() => _CourseViewState();
}

class _CourseViewState extends State<CourseView> {
  late Future<List<Object>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<List<Object>> _loadData() {
    final repository = context.read<AppRepository>();
    return Future.wait<Object>([
      repository.getCourses(),
      repository.getNotes(),
    ]);
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  Future<void> _showCourseEditor({Course? course}) async {
    final result = await showDialog<Course>(
      context: context,
      builder: (context) => _CourseEditorDialog(course: course),
    );

    if (result == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    final repository = context.read<AppRepository>();
    await repository.saveCourse(result);
    _refresh();

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(course == null ? '课程已创建' : '课程已更新')));
  }

  Future<void> _openNewNote(Course course) async {
    final createdNote = await Navigator.push<NoteEntry>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteDetailScreen(
          courseName: course.name,
          initialCourseId: course.id,
        ),
      ),
    );

    if (createdNote != null && mounted) {
      _refresh();
    }
  }

  Future<void> _deleteCourse(Course course) async {
    final confirmed = await _confirmDelete(
      title: '删除课程',
      content: '确定删除「${course.name}」吗？该课程下的笔记、语音和图片记录也会一起删除。',
    );
    if (!confirmed || !mounted) {
      return;
    }

    final repository = context.read<AppRepository>();
    await repository.deleteCourse(course.id);
    _refresh();

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('课程已删除')));
  }

  Future<void> _deleteNote(NoteEntry note) async {
    final confirmed = await _confirmDelete(
      title: '删除笔记',
      content: '确定删除「${note.title}」吗？相关语音和图片记录也会一起删除。',
    );
    if (!confirmed || !mounted) {
      return;
    }

    final repository = context.read<AppRepository>();
    await repository.deleteNote(note.id);
    _refresh();

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('笔记已删除')));
  }

  Future<bool> _confirmDelete({
    required String title,
    required String content,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE66A6A),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Object>>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final courses = snapshot.data![0] as List<Course>;
        final notes = snapshot.data![1] as List<NoteEntry>;
        final noteMap = <String, List<NoteEntry>>{};
        for (final note in notes) {
          noteMap.putIfAbsent(note.courseId, () => []).add(note);
        }

        final sections = <Widget>[];
        String? previousGif;
        for (final course in courses) {
          final courseGif = _gifForCourse(
            course.name,
            previousGif: previousGif,
          );
          previousGif = courseGif;
          sections.addAll([
            _CourseSection(
              course: course,
              gif: courseGif,
              nameColor: colorFromHex(
                course.colorHex,
                fallback: const Color(0xFF6B82A8),
              ),
              borderColor: colorFromHex(course.colorHex).withValues(alpha: 0.5),
              bgColor: colorFromHex(course.colorHex).withValues(alpha: 0.07),
              count: '${noteMap[course.id]?.length ?? 0} Notes',
              cards: (noteMap[course.id] ?? const <NoteEntry>[])
                  .take(4)
                  .toList()
                  .asMap()
                  .entries
                  .map(
                    (entry) => _HCard(
                      note: entry.value,
                      num: '${entry.key + 1}',
                      bg: colorFromHex(course.colorHex).withValues(alpha: 0.08),
                      border: colorFromHex(
                        course.colorHex,
                      ).withValues(alpha: 0.22),
                    ),
                  )
                  .toList(),
              onNote: widget.onNote,
              onNewNote: () => _openNewNote(course),
              onCourseAction: () => _showCourseActions(course),
              onDeleteNote: _deleteNote,
            ),
            const SizedBox(height: 18),
          ]);
        }

        final horizontalPadding = AppResponsive.horizontalPadding(context);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            24,
            horizontalPadding,
            AppResponsive.bottomNavReserve(context) + 18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...sections,
              _AddCourse(onTap: () => _showCourseEditor()),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCourseActions(Course course) async {
    final action = await showModalBottomSheet<_CourseAction>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('修改课程名称'),
                onTap: () => Navigator.pop(context, _CourseAction.edit),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFE66A6A),
                ),
                title: const Text(
                  '删除课程',
                  style: TextStyle(color: Color(0xFFE66A6A)),
                ),
                onTap: () => Navigator.pop(context, _CourseAction.delete),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _CourseAction.edit:
        await _showCourseEditor(course: course);
      case _CourseAction.delete:
        await _deleteCourse(course);
    }
  }
}

enum _CourseAction { edit, delete }

String _gifForCourse(String name, {String? previousGif}) {
  const fallbackGifs = [
    '罗小黑的Q版形象-点头.gif',
    '罗小黑的Q版形象剪刀手.gif',
    '罗小黑的Q版形象-探头.gif',
    '罗小黑的Q版形象-羡慕.gif',
    '罗小黑竖大拇指.gif',
    '罗小黑的Q版形象-思考.gif',
  ];
  String selected;
  if (name.contains('机器学习')) {
    selected = '罗小黑竖大拇指.gif';
  } else if (name.contains('软件')) {
    selected = '罗小黑的Q版形象-看手机炸毛.gif';
  } else if (name.contains('数学') || name.contains('线性')) {
    selected = '罗小黑的Q版形象-思考.gif';
  } else {
    selected = fallbackGifs[name.hashCode.abs() % fallbackGifs.length];
  }
  if (selected != previousGif) {
    return selected;
  }
  final currentIndex = fallbackGifs.indexOf(selected);
  final nextIndex = currentIndex < 0
      ? name.hashCode.abs() % fallbackGifs.length
      : (currentIndex + 1) % fallbackGifs.length;
  return fallbackGifs[nextIndex];
}

class _CourseSection extends StatelessWidget {
  const _CourseSection({
    required this.course,
    required this.gif,
    required this.nameColor,
    required this.borderColor,
    required this.bgColor,
    required this.count,
    required this.cards,
    required this.onNote,
    required this.onNewNote,
    required this.onCourseAction,
    required this.onDeleteNote,
  });

  final Course course;
  final String gif;
  final String count;
  final Color nameColor;
  final Color borderColor;
  final Color bgColor;
  final List<_HCard> cards;
  final ValueChanged<NoteEntry> onNote;
  final VoidCallback onNewNote;
  final VoidCallback onCourseAction;
  final ValueChanged<NoteEntry> onDeleteNote;

  @override
  Widget build(BuildContext context) {
    final cardHeight = AppResponsive.courseCardHeight(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  AppGif(gif, size: 48),
                  const SizedBox(width: 9),
                  Flexible(
                    fit: FlexFit.loose,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.46,
                      ),
                      child: GestureDetector(
                        onDoubleTap: onCourseAction,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x73FFFFFF),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: borderColor, width: 1.5),
                          ),
                          child: Text(
                            course.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: nameColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              count,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0x47244A6E),
              ),
            ),
          ],
        ),
        if (course.description.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            course.description,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0x73244A6E),
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: cardHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ...cards.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: GestureDetector(
                    onTap: () => onNote(c.note),
                    onDoubleTap: () => onDeleteNote(c.note),
                    child: c,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 9),
                child: _AddNoteCard(
                  borderColor: borderColor,
                  bgColor: bgColor,
                  onTap: onNewNote,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddNoteCard extends StatelessWidget {
  const _AddNoteCard({
    required this.borderColor,
    required this.bgColor,
    required this.onTap,
  });

  final Color borderColor;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = AppResponsive.addCardWidth(context);
    final height = AppResponsive.courseCardHeight(context);
    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor.withValues(alpha: 0.44),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '+ 新建',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSub,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x80FFFFFF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '+',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0x59244A6E),
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: borderColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '新建',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSub,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '新建笔记',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      '点击添加到当前课程',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0x73244A6E),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
                const Text(
                  '创建新的记录',
                  style: TextStyle(fontSize: 9, color: Color(0x52244A6E)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HCard extends StatelessWidget {
  const _HCard({
    required this.note,
    required this.num,
    required this.bg,
    required this.border,
  });

  final NoteEntry note;
  final String num;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final width = AppResponsive.courseCardWidth(context);
    final height = AppResponsive.courseCardHeight(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _typeLabel(note.type),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSub,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x80FFFFFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    num,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0x59244A6E),
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: border.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _typeLabel(note.type),
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSub,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  note.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _previewForNote(note),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0x73244A6E),
                    height: 1.4,
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                formatRelativeTime(note.updatedAt),
                style: const TextStyle(fontSize: 9, color: Color(0x52244A6E)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _previewForNote(NoteEntry note) {
  switch (note.type) {
    case NoteType.photo:
      return note.photoIds.isEmpty ? '图片笔记' : '已记录 ${note.photoIds.length} 张图片';
    case NoteType.voice:
      return _truncate([note.rawTranscription, note.aiSummary, '语音识别笔记']);
    case NoteType.mixed:
      return _truncate([
        note.aiSummary,
        note.textContent,
        note.rawTranscription,
        note.photoIds.isEmpty ? '' : '含 ${note.photoIds.length} 张图片',
        '混合内容笔记',
      ]);
    case NoteType.text:
      return _truncate([note.textContent, note.aiSummary, '点击查看笔记详情']);
  }
}

String _typeLabel(NoteType type) {
  switch (type) {
    case NoteType.voice:
      return '语音';
    case NoteType.photo:
      return '图片';
    case NoteType.mixed:
      return '混合';
    case NoteType.text:
      return '文字';
  }
}

String _truncate(List<String> values) {
  final content = values
      .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '点击查看笔记详情')
      .replaceAll('\n', ' ')
      .trim();

  return content.length > 28 ? '${content.substring(0, 28)}…' : content;
}

class _AddCourse extends StatelessWidget {
  const _AddCourse({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0x4096B4DC),
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            const Text(
              '+ ADD NEW COURSE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: Color(0x5964B4DC),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseEditorDialog extends StatefulWidget {
  const _CourseEditorDialog({this.course});

  final Course? course;

  @override
  State<_CourseEditorDialog> createState() => _CourseEditorDialogState();
}

class _CourseEditorDialogState extends State<_CourseEditorDialog> {
  static const _presetColors = [
    '#A359FF',
    '#00D68F',
    '#4FACFE',
    '#FF8A65',
    '#F9C74F',
    '#A8EDDA',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late String _selectedColor;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.course?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.course?.description ?? '',
    );
    _selectedColor = widget.course?.colorHex ?? _presetColors.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.course == null ? '新增课程' : '编辑课程'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '课程名称',
                hintText: '例如：数字电路',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '课程说明',
                hintText: '写一点课程简介或用途',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '选择主题色',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSub,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _presetColors.map((colorHex) {
                final isSelected = colorHex == _selectedColor;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = colorHex),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colorFromHex(colorHex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black87 : Colors.white,
                        width: isSelected ? 2.5 : 1.5,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final course =
        (widget.course ??
                Course(
                  id: 'course-${now.microsecondsSinceEpoch}',
                  name: name,
                  colorHex: _selectedColor,
                  createdAt: now,
                  updatedAt: now,
                ))
            .copyWith(
              name: name,
              description: _descriptionController.text.trim(),
              colorHex: _selectedColor,
              updatedAt: now,
            );

    Navigator.pop(context, course);
  }
}
