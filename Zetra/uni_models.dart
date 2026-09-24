// All types are prefixed "Uni" so they never clash with existing NaijaLearn
// classes (Question, SubjectInfo, Lesson, etc. in the main app).

enum UniGradeScale { five, four }

extension UniGradeScaleX on UniGradeScale {
  String get label => this == UniGradeScale.five ? '5-point' : '4-point';
  Map<String, double> get points => this == UniGradeScale.five
      ? {'A': 5, 'B': 4, 'C': 3, 'D': 2, 'E': 1, 'F': 0}
      : {'A': 4, 'B': 3, 'C': 2, 'D': 1, 'F': 0};
}

class UniException implements Exception {
  final String message;
  UniException(this.message);
  @override
  String toString() => message;
}

class UniProfile {
  final String? university, faculty, department, level, semester;
  const UniProfile({this.university, this.faculty, this.department, this.level, this.semester});
  bool get isEmpty => [university, faculty, department, level, semester]
      .every((e) => e == null || e.trim().isEmpty);
}

class UniCourse {
  final String id, code, title, description, level, semester;
  final int units;
  final double progress; // learning indicator only, never an official grade
  final String? lecturer, nextLesson;
  const UniCourse({
    required this.id, required this.code, required this.title,
    required this.units, required this.level, required this.semester,
    this.description = '', this.progress = 0, this.lecturer, this.nextLesson,
  });
  UniCourse copyWith({double? progress, String? nextLesson, bool clearNext = false}) => UniCourse(
        id: id, code: code, title: title, units: units, level: level, semester: semester,
        description: description, lecturer: lecturer,
        progress: progress ?? this.progress,
        nextLesson: clearNext ? null : (nextLesson ?? this.nextLesson));
}

class UniLesson {
  final String id, module, title;
  final bool done;
  const UniLesson({required this.id, required this.module, required this.title, this.done = false});
  UniLesson copyWith({bool? done}) =>
      UniLesson(id: id, module: module, title: title, done: done ?? this.done);
}

class UniDeadline {
  final String title, courseCode;
  final DateTime due;
  const UniDeadline({required this.title, required this.courseCode, required this.due});
}

/// Personal, self-entered result. NOT a verified university record.
class UniResult {
  final String id, code, grade, semester;
  final int units;
  const UniResult({required this.id, required this.code, required this.units,
      required this.grade, required this.semester});
}

class UniMaterial {
  final String id, title, type, url; // type: pdf | slides | link | notes
  const UniMaterial({required this.id, required this.title, required this.type, required this.url});
}

class UniAssignment {
  final String id, title, instructions;
  final DateTime deadline; // server time in the real backend
  final int maxScore;
  final String status; // open | submitted | graded | closed
  final int? score;
  final String? feedback, submittedText;
  const UniAssignment({
    required this.id, required this.title, required this.instructions,
    required this.deadline, required this.maxScore, this.status = 'open',
    this.score, this.feedback, this.submittedText,
  });
  UniAssignment copyWith({String? status, String? submittedText}) => UniAssignment(
        id: id, title: title, instructions: instructions, deadline: deadline,
        maxScore: maxScore, score: score, feedback: feedback,
        status: status ?? this.status, submittedText: submittedText ?? this.submittedText);
}

class UniQuiz {
  final String id, title;
  final int questionCount, minutes, marks, attemptsLeft;
  const UniQuiz({required this.id, required this.title, required this.questionCount,
      required this.minutes, required this.marks, required this.attemptsLeft});
  UniQuiz copyWith({int? attemptsLeft}) => UniQuiz(id: id, title: title,
      questionCount: questionCount, minutes: minutes, marks: marks,
      attemptsLeft: attemptsLeft ?? this.attemptsLeft);
}

/// A question as SERVED to the student: no correct answer included.
class UniQuestion {
  final String id, text, topic, difficulty;
  final List<String> options;
  const UniQuestion({required this.id, required this.text, required this.options,
      this.topic = '', this.difficulty = 'medium'});
}

class UniSession {
  final String id, title;
  final List<UniQuestion> questions;
  final int seconds; // allowed time; the server enforces it on submit
  const UniSession({required this.id, required this.title, required this.questions, required this.seconds});
}

class UniReviewItem {
  final UniQuestion question;
  final int? selected;
  final int correctIndex;
  final String explanation;
  const UniReviewItem({required this.question, required this.selected,
      required this.correctIndex, this.explanation = ''});
  bool get isCorrect => selected == correctIndex;
}

/// Produced by the server after submit. The client never computes scores.
class UniAttemptResult {
  final int total, correct, seconds;
  final List<UniReviewItem> review;
  final List<String> weakTopics;
  const UniAttemptResult({required this.total, required this.correct,
      required this.seconds, required this.review, this.weakTopics = const []});
}

class UniListing {
  final UniCourse course;
  final String university, faculty, department, tutor;
  final int price; // in Cent; 0 = free. Always server-provided.
  final bool enrolled;
  const UniListing({required this.course, required this.university, required this.faculty,
      required this.department, required this.tutor, this.price = 0, this.enrolled = false});
  UniListing copyWith({bool? enrolled}) => UniListing(course: course, university: university,
      faculty: faculty, department: department, tutor: tutor, price: price,
      enrolled: enrolled ?? this.enrolled);
}
