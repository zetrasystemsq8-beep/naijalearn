import 'package:flutter/foundation.dart';
import 'university_repository.dart';
import 'models.dart';

class UniversityController extends ChangeNotifier {
  UniversityController(this.repo);
  final UniversityRepository repo;

  bool loading = true;
  UniProfile profile = const UniProfile();
  List<Course> courses = [];
  List<Deadline> deadlines = [];
  List<ResultEntry> results = [];
  final Map<String, List<Lesson>> lessonCache = {};
  GradeScale scale = GradeScale.five;

  Future<void> load() async {
    profile = await repo.getProfile();
    courses = await repo.myCourses();
    deadlines = await repo.deadlines();
    results = await repo.results();
    loading = false;
    notifyListeners();
  }

  Future<void> saveProfile(UniProfile p) async {
    await repo.saveProfile(p);
    profile = p;
    notifyListeners();
  }

  Future<void> loadLessons(String courseId) async {
    lessonCache[courseId] = await repo.lessons(courseId);
    notifyListeners();
  }

  Future<void> toggleLesson(String courseId, String lessonId, bool done) async {
    await repo.setLessonDone(courseId, lessonId, done);
    lessonCache[courseId] = await repo.lessons(courseId);
    courses = await repo.myCourses(); // refresh progress
    notifyListeners();
  }

  double get overallProgress => courses.isEmpty
      ? 0 : courses.map((c) => c.progress).reduce((a, b) => a + b) / courses.length;

  Future<void> addResult(ResultEntry r) async {
    results = [...results, r];
    await repo.saveResults(results);
    notifyListeners();
  }

  Future<void> removeResult(String id) async {
    results = results.where((r) => r.id != id).toList();
    await repo.saveResults(results);
    notifyListeners();
  }

  void setScale(GradeScale s) {
    scale = s;
    notifyListeners();
  }

  /// GPA for one semester, or CGPA when [semester] is null. Null if no data.
  double? gpa({String? semester}) {
    final pts = scale.points;
    final rows = results.where((r) =>
        (semester == null || r.semester == semester) && pts.containsKey(r.grade));
    final units = rows.fold<int>(0, (s, r) => s + r.units);
    if (units == 0) return null;
    final total = rows.fold<double>(0, (s, r) => s + pts[r.grade]! * r.units);
    return total / units;
  }
}
