enum GradeScale { five, four }

extension GradeScaleX on GradeScale {
  String get label => this == GradeScale.five ? '5-point' : '4-point';
  Map<String, double> get points => this == GradeScale.five
      ? {'A': 5, 'B': 4, 'C': 3, 'D': 2, 'E': 1, 'F': 0}
      : {'A': 4, 'B': 3, 'C': 2, 'D': 1, 'F': 0};
}

class UniProfile {
  final String? university, faculty, department, level, semester;
  const UniProfile({this.university, this.faculty, this.department, this.level, this.semester});
  bool get isEmpty => [university, faculty, department, level, semester]
      .every((e) => e == null || e.trim().isEmpty);
}

class Course {
  final String id, code, title, description, level, semester;
  final int units;
  final double progress; // 0..1, learning indicator only (not an official grade)
  final String? lecturer, nextLesson;
  const Course({
    required this.id, required this.code, required this.title,
    required this.units, required this.level, required this.semester,
    this.description = '', this.progress = 0, this.lecturer, this.nextLesson,
  });
}

class Lesson {
  final String id, module, title;
  final bool done;
  const Lesson({required this.id, required this.module, required this.title, this.done = false});
  Lesson copyWith({bool? done}) =>
      Lesson(id: id, module: module, title: title, done: done ?? this.done);
}

class Deadline {
  final String title, courseCode;
  final DateTime due;
  const Deadline({required this.title, required this.courseCode, required this.due});
}

/// Personal, self-entered result. NOT a verified university record.
class ResultEntry {
  final String id, code, grade, semester;
  final int units;
  const ResultEntry({required this.id, required this.code, required this.units,
      required this.grade, required this.semester});
}
