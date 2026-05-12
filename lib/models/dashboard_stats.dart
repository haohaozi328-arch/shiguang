class DashboardStats {
  const DashboardStats({
    required this.todayNoteCount,
    required this.voiceMinutes,
    required this.streakDays,
    required this.aiSummaryCount,
    this.courseCount = 0,
    this.weekNoteCount = 0,
    this.aiQuestionCount = 0,
  });

  final int todayNoteCount;
  final int voiceMinutes;
  final int streakDays;
  final int aiSummaryCount;
  final int courseCount;
  final int weekNoteCount;
  final int aiQuestionCount;

  DashboardStats copyWith({
    int? todayNoteCount,
    int? voiceMinutes,
    int? streakDays,
    int? aiSummaryCount,
    int? courseCount,
    int? weekNoteCount,
    int? aiQuestionCount,
  }) {
    return DashboardStats(
      todayNoteCount: todayNoteCount ?? this.todayNoteCount,
      voiceMinutes: voiceMinutes ?? this.voiceMinutes,
      streakDays: streakDays ?? this.streakDays,
      aiSummaryCount: aiSummaryCount ?? this.aiSummaryCount,
      courseCount: courseCount ?? this.courseCount,
      weekNoteCount: weekNoteCount ?? this.weekNoteCount,
      aiQuestionCount: aiQuestionCount ?? this.aiQuestionCount,
    );
  }
}
