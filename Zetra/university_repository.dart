import '../models/models.dart';

/// The UI only talks to this. Later: write SupabaseUniversityRepository
/// implementing it (RPCs/RLS), and pass it into UniversityHome(repository: ...).
abstract class UniversityRepository {
  Future<UniProfile> getProfile();
  Future<void> saveProfile(UniProfile p);
  Future<List<Course>> myCourses();
  Future<List<Lesson>> lessons(String courseId);
  Future<void> setLessonDone(String courseId, String lessonId, bool done);
  Future<List<Deadline>> deadlines();
  Future<List<ResultEntry>> results();
  Future<void> saveResults(List<ResultEntry> r);
}

class MockUniversityRepository implements UniversityRepository {
  UniProfile _profile = const UniProfile(
    university: 'University of Abuja', faculty: 'Science',
    department: 'Computer Science', level: '200 Level', semester: 'First Semester');
  List<ResultEntry> _results = [];

  final _meta = const {
    'csc201': ['CSC 201', 'Data Structures', 3],
    'mth201': ['MTH 201', 'Mathematical Methods', 3],
    'phy201': ['PHY 201', 'Electricity & Magnetism', 2],
  };
  final Map<String, List<Lesson>> _lessons = {
    'csc201': [
      const Lesson(id: 'a', module: 'Module 1', title: 'Arrays', done: true),
      const Lesson(id: 'b', module: 'Module 1', title: 'Linked Lists'),
      const Lesson(id: 'c', module: 'Module 2', title: 'Stacks & Queues'),
    ],
    'mth201': [
      const Lesson(id: 'a', module: 'Module 1', title: 'Limits', done: true),
      const Lesson(id: 'b', module: 'Module 1', title: 'Differentiation', done: true),
      const Lesson(id: 'c', module: 'Module 2', title: 'Integration'),
    ],
    'phy201': [
      const Lesson(id: 'a', module: 'Module 1', title: 'Electric Fields'),
      const Lesson(id: 'b', module: 'Module 1', title: 'Gauss\'s Law'),
    ],
  };

  @override Future<UniProfile> getProfile() async => _profile;
  @override Future<void> saveProfile(UniProfile p) async => _profile = p;

  @override
  Future<List<Course>> myCourses() async => _meta.entries.map((e) {
        final ls = _lessons[e.key]!;
        final done = ls.where((l) => l.done).length;
        final next = ls.where((l) => !l.done);
        return Course(
          id: e.key, code: e.value[0] as String, title: e.value[1] as String,
          units: e.value[2] as int, level: '200 Level', semester: 'First Semester',
          description: 'Overview of ${e.value[1]}.',
          progress: ls.isEmpty ? 0 : done / ls.length,
          nextLesson: next.isEmpty ? null : next.first.title);
      }).toList();

  @override Future<List<Lesson>> lessons(String id) async => List.of(_lessons[id] ?? []);

  @override
  Future<void> setLessonDone(String c, String l, bool done) async {
    _lessons[c] = [for (final x in _lessons[c]!) x.id == l ? x.copyWith(done: done) : x];
  }

  @override
  Future<List<Deadline>> deadlines() async => [
        Deadline(title: 'Assignment 2', courseCode: 'CSC 201',
            due: DateTime.now().add(const Duration(days: 1))),
        Deadline(title: 'Quiz 1', courseCode: 'MTH 201',
            due: DateTime.now().add(const Duration(days: 5))),
      ];

  @override Future<List<ResultEntry>> results() async => List.of(_results);
  @override Future<void> saveResults(List<ResultEntry> r) async => _results = List.of(r);
}
