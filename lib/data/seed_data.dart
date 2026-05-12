import '../models/course.dart';
import '../models/note_entry.dart';
import 'app_repository.dart';

class SeedData {
  static Future<void> ensureInitialized(AppRepository repository) async {
    final courses = await repository.getCourses();
    if (courses.isNotEmpty) {
      return;
    }

    final now = DateTime.now();

    final linearAlgebra = Course(
      id: 'course-linear-algebra',
      name: '线性代数',
      colorHex: '#A359FF',
      description: '矩阵、特征值与线性变换',
      createdAt: now,
      updatedAt: now,
    );
    final ml = Course(
      id: 'course-ml',
      name: '机器学习',
      colorHex: '#00D68F',
      description: '模型训练与优化记录',
      createdAt: now,
      updatedAt: now,
    );
    final se = Course(
      id: 'course-software',
      name: '软件工程',
      colorHex: '#4FACFE',
      description: '接口设计与工程实践',
      createdAt: now,
      updatedAt: now,
    );

    await repository.saveCourse(linearAlgebra);
    await repository.saveCourse(ml);
    await repository.saveCourse(se);

    await repository.saveNote(
      NoteEntry(
        id: 'note-la-1',
        courseId: linearAlgebra.id,
        title: '线性变换与矩阵表示',
        type: NoteType.voice,
        rawTranscription: '矩阵乘法本质上是在描述线性变换的复合。',
        aiSummary: '总结了矩阵表示线性变换的核心直觉，并记录了课上的几个几何例子。',
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(hours: 2)),
      ),
    );

    await repository.saveNote(
      NoteEntry(
        id: 'note-ml-1',
        courseId: ml.id,
        title: '梯度下降优化算法对比',
        type: NoteType.text,
        textContent: '比较 SGD、Adam 和 AdamW 的收敛表现与泛化差异。',
        aiSummary: '整理了三种优化器的适用场景和调参建议。',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
    );

    await repository.saveNote(
      NoteEntry(
        id: 'note-se-1',
        courseId: se.id,
        title: 'API 设计规范',
        type: NoteType.mixed,
        textContent: '梳理 RESTful 命名规范、错误码和版本控制策略。',
        aiSummary: '形成了后续接口设计的统一检查清单。',
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
    );
  }
}
