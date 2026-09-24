import 'uni_models.dart';

/// The UI only talks to this. Later: SupabaseUniversityRepository implements
/// it with RPCs (server-side scoring, deadlines, pricing, enrolment).
abstract class UniversityRepository {
  Future<UniProfile> getProfile();
  Future<void> saveProfile(UniProfile p);
  Future<List<UniCourse>> myCourses();
  Future<List<UniLesson>> lessons(String courseId);
  Future<void> setLessonDone(String courseId, String lessonId, bool done);
  Future<List<UniDeadline>> deadlines();
  Future<List<UniResult>> results();
  Future<void> saveResults(List<UniResult> r);

  Future<List<UniMaterial>> materials(String courseId);
  Future<List<UniAssignment>> assignments(String courseId);
  Future<UniAssignment> submitAssignment(String assignmentId, String text);
  Future<List<UniQuiz>> quizzes(String courseId);

  Future<UniSession> startPractice(String courseId, {required int count, required String difficulty});
  Future<UniSession> startQuiz(String quizId);
  Future<UniAttemptResult> submitSession(String sessionId, Map<String, int> answers);

  Future<List<UniListing>> search({String query = '', String? level, String? semester});
  Future<void> enroll(String courseId);
}

class _Q {
  final String id, text, topic, diff, expl;
  final List<String> opts;
  final int ans;
  const _Q(this.id, this.text, this.opts, this.ans, this.topic, this.diff, this.expl);
  UniQuestion served() => UniQuestion(id: id, text: text, options: opts, topic: topic, difficulty: diff);
}

class _Sess {
  final String title;
  final List<_Q> qs;
  final DateTime started;
  final int seconds;
  _Sess(this.title, this.qs, this.seconds) : started = DateTime.now();
}

class MockUniversityRepository implements UniversityRepository {
  UniProfile _profile = const UniProfile(
      university: 'University of Abuja', faculty: 'Science',
      department: 'Computer Science', level: '200 Level', semester: 'First Semester');
  List<UniResult> _results = [];
  final Set<String> _enrolled = {'csc201', 'mth201', 'phy201'};
  final Map<String, _Sess> _sessions = {};
  int _sid = 0;

  UniListing _l(String id, String code, String title, int units, String uni, String fac,
          String dep, String tutor, {String level = '200 Level', int price = 0}) =>
      UniListing(
          course: UniCourse(id: id, code: code, title: title, units: units, level: level,
              semester: 'First Semester', description: 'Overview of $title.', lecturer: tutor),
          university: uni, faculty: fac, department: dep, tutor: tutor, price: price);

  late final List<UniListing> _catalog = [
    _l('csc201', 'CSC 201', 'Data Structures', 3, 'University of Abuja', 'Science', 'Computer Science', 'Dr. Musa'),
    _l('mth201', 'MTH 201', 'Mathematical Methods', 3, 'University of Abuja', 'Science', 'Mathematics', 'Mrs. Bello'),
    _l('phy201', 'PHY 201', 'Electricity & Magnetism', 2, 'University of Abuja', 'Science', 'Physics', 'Mr. Okon'),
    _l('csc203', 'CSC 203', 'Computer Programming II', 3, 'University of Abuja', 'Science', 'Computer Science', 'Dr. Musa'),
    _l('gst201', 'GST 201', 'Peace & Conflict Studies', 2, 'University of Lagos', 'Arts', 'General Studies', 'Mr. Ade'),
    _l('eee201', 'EEE 201', 'Circuit Theory', 3, 'University of Lagos', 'Engineering', 'Electrical Engineering', 'Engr. Ojo', price: 500),
  ];

  final Map<String, List<UniLesson>> _lessons = {
    'csc201': [
      const UniLesson(id: 'a', module: 'Module 1', title: 'Arrays', done: true),
      const UniLesson(id: 'b', module: 'Module 1', title: 'Linked Lists'),
      const UniLesson(id: 'c', module: 'Module 2', title: 'Stacks & Queues'),
    ],
    'mth201': [
      const UniLesson(id: 'a', module: 'Module 1', title: 'Limits', done: true),
      const UniLesson(id: 'b', module: 'Module 1', title: 'Differentiation', done: true),
      const UniLesson(id: 'c', module: 'Module 2', title: 'Integration'),
    ],
    'phy201': [
      const UniLesson(id: 'a', module: 'Module 1', title: 'Electric Fields'),
      const UniLesson(id: 'b', module: 'Module 1', title: "Gauss's Law"),
    ],
  };
  List<UniLesson> _ls(String id) => _lessons.putIfAbsent(id, () => [
        const UniLesson(id: 'a', module: 'Module 1', title: 'Introduction'),
        const UniLesson(id: 'b', module: 'Module 1', title: 'Core Concepts'),
        const UniLesson(id: 'c', module: 'Module 2', title: 'Applications'),
      ]);

  static const _bank = <String, List<_Q>>{
    'csc201': [
      _Q('c1', 'Which data structure uses LIFO order?', ['Queue', 'Stack', 'Array', 'Tree'], 1, 'Stacks & Queues', 'easy', 'A stack removes the most recently added item first.'),
      _Q('c2', 'Access time of an array element by index is:', ['O(n)', 'O(log n)', 'O(1)', 'O(n²)'], 2, 'Arrays', 'easy', 'Indexing computes the memory address directly.'),
      _Q('c3', 'Each node of a singly linked list stores:', ['Only data', 'Data and a pointer to the next node', 'Two pointers', 'An index'], 1, 'Linked Lists', 'medium', 'Data plus a reference to the next node.'),
      _Q('c4', 'Which structure suits FIFO processing?', ['Stack', 'Queue', 'Heap', 'Graph'], 1, 'Stacks & Queues', 'easy', 'A queue serves the oldest item first.'),
      _Q('c5', 'Inserting at the head of a singly linked list takes:', ['O(1)', 'O(n)', 'O(log n)', 'O(n²)'], 0, 'Linked Lists', 'medium', 'Only the head pointer changes.'),
      _Q('c6', 'Minimum extra pointers to reverse a singly linked list iteratively:', ['0', '1', '3 (prev, curr, next)', 'n'], 2, 'Linked Lists', 'hard', 'You need prev, curr and next to avoid losing the rest of the list.'),
    ],
    'mth201': [
      _Q('m1', 'd/dx of x² is:', ['x', '2x', '2', 'x²'], 1, 'Differentiation', 'easy', 'Power rule.'),
      _Q('m2', '∫ 2x dx =', ['x² + C', '2x² + C', 'x + C', '2 + C'], 0, 'Integration', 'easy', 'Reverse of the power rule.'),
      _Q('m3', 'lim x→0 of sin(x)/x =', ['0', '∞', '1', 'Undefined'], 2, 'Limits', 'medium', 'A standard limit.'),
      _Q('m4', 'd/dx of e^(2x) is:', ['e^(2x)', '2e^(2x)', '2x·e^(2x)', 'e^x'], 1, 'Differentiation', 'hard', 'Chain rule.'),
    ],
    'phy201': [
      _Q('p1', 'SI unit of electric charge:', ['Ampere', 'Coulomb', 'Volt', 'Ohm'], 1, 'Electric Fields', 'easy', ''),
      _Q('p2', 'Electric field is force per unit:', ['mass', 'charge', 'current', 'area'], 1, 'Electric Fields', 'easy', ''),
      _Q('p3', "Gauss's law relates flux to:", ['Enclosed charge', 'Current', 'Magnetic field', 'Resistance'], 0, "Gauss's Law", 'medium', ''),
    ],
  };

  late final Map<String, List<UniAssignment>> _asg = {
    'csc201': [UniAssignment(id: 'a1', title: 'Assignment 2', instructions: 'Implement a singly linked list and state the time complexity of each operation.', deadline: DateTime.now().add(const Duration(days: 1)), maxScore: 20)],
    'mth201': [
      UniAssignment(id: 'a2', title: 'Problem Set 1', instructions: 'Solve questions 1–10 on limits.', deadline: DateTime.now().add(const Duration(days: 6)), maxScore: 10),
      UniAssignment(id: 'a3', title: 'Tutorial 1', instructions: 'Differentiation drill.', deadline: DateTime.now().subtract(const Duration(days: 3)), maxScore: 10, status: 'graded', score: 8, feedback: 'Good work. Watch your chain rule steps.'),
    ],
  };
  final Map<String, List<UniQuiz>> _quiz = {
    'csc201': [const UniQuiz(id: 'q1', title: 'Quiz 1 — Arrays & Lists', questionCount: 5, minutes: 10, marks: 10, attemptsLeft: 2)],
    'mth201': [const UniQuiz(id: 'q2', title: 'Quiz 1 — Limits', questionCount: 3, minutes: 8, marks: 10, attemptsLeft: 1)],
  };

  @override Future<UniProfile> getProfile() async => _profile;
  @override Future<void> saveProfile(UniProfile p) async => _profile = p;

  @override
  Future<List<UniCourse>> myCourses() async => _catalog
      .where((l) => _enrolled.contains(l.course.id))
      .map((l) {
        final ls = _ls(l.course.id);
        final next = ls.where((x) => !x.done);
        final c = l.course.copyWith(progress: ls.where((x) => x.done).length / ls.length);
        return next.isEmpty ? c : c.copyWith(nextLesson: next.first.title);
      }).toList();

  @override Future<List<UniLesson>> lessons(String id) async => List.of(_ls(id));

  @override
  Future<void> setLessonDone(String c, String l, bool done) async {
    _lessons[c] = [for (final x in _ls(c)) x.id == l ? x.copyWith(done: done) : x];
  }

  @override
  Future<List<UniDeadline>> deadlines() async {
    final out = <UniDeadline>[];
    for (final l in _catalog.where((l) => _enrolled.contains(l.course.id))) {
      for (final a in _asg[l.course.id] ?? <UniAssignment>[]) {
        if (a.status == 'open' && a.deadline.isAfter(DateTime.now())) {
          out.add(UniDeadline(title: a.title, courseCode: l.course.code, due: a.deadline));
        }
      }
    }
    out.sort((a, b) => a.due.compareTo(b.due));
    return out;
  }

  @override Future<List<UniResult>> results() async => List.of(_results);
  @override Future<void> saveResults(List<UniResult> r) async => _results = List.of(r);

  @override
  Future<List<UniMaterial>> materials(String courseId) async => [
        UniMaterial(id: 'x1', title: 'Lecture Notes — Week 1', type: 'pdf', url: 'https://example.com/notes.pdf'),
        UniMaterial(id: 'x2', title: 'Slides — Introduction', type: 'slides', url: 'https://example.com/slides'),
        UniMaterial(id: 'x3', title: 'Recommended reading', type: 'link', url: 'https://example.com/reading'),
      ];

  @override
  Future<List<UniAssignment>> assignments(String courseId) async => [
        for (final a in _asg[courseId] ?? <UniAssignment>[])
          (a.status == 'open' && a.deadline.isBefore(DateTime.now())) ? a.copyWith(status: 'closed') : a
      ];

  @override
  Future<UniAssignment> submitAssignment(String id, String text) async {
    for (final e in _asg.entries) {
      final i = e.value.indexWhere((a) => a.id == id);
      if (i < 0) continue;
      final a = e.value[i];
      if (a.status != 'open' || a.deadline.isBefore(DateTime.now())) {
        throw UniException('The deadline for this assignment has passed.');
      }
      return e.value[i] = a.copyWith(status: 'submitted', submittedText: text);
    }
    throw UniException('Assignment not found.');
  }

  @override Future<List<UniQuiz>> quizzes(String courseId) async => List.of(_quiz[courseId] ?? []);

  UniSession _open(String title, List<_Q> qs, int seconds) {
    final id = 's${_sid++}';
    _sessions[id] = _Sess(title, qs, seconds);
    return UniSession(id: id, title: title, questions: [for (final q in qs) q.served()], seconds: seconds);
  }

  @override
  Future<UniSession> startPractice(String courseId, {required int count, required String difficulty}) async {
    var pool = List<_Q>.of(_bank[courseId] ?? const []);
    if (difficulty != 'mixed') pool = pool.where((q) => q.diff == difficulty).toList();
    if (pool.isEmpty) throw UniException('No questions available for this selection yet.');
    pool.shuffle();
    final qs = pool.take(count).toList();
    return _open('Practice', qs, qs.length * 90);
  }

  @override
  Future<UniSession> startQuiz(String quizId) async {
    for (final e in _quiz.entries) {
      final i = e.value.indexWhere((q) => q.id == quizId);
      if (i < 0) continue;
      final q = e.value[i];
      if (q.attemptsLeft <= 0) throw UniException('No attempts left for this quiz.');
      final pool = List<_Q>.of(_bank[e.key] ?? const [])..shuffle();
      e.value[i] = q.copyWith(attemptsLeft: q.attemptsLeft - 1);
      return _open(q.title, pool.take(q.questionCount).toList(), q.minutes * 60);
    }
    throw UniException('Quiz not found.');
  }

  @override
  Future<UniAttemptResult> submitSession(String sessionId, Map<String, int> answers) async {
    final s = _sessions.remove(sessionId);
    if (s == null) throw UniException('This attempt was already submitted.');
    final used = DateTime.now().difference(s.started).inSeconds;
    if (used > s.seconds + 20) throw UniException('Time is up. This attempt can no longer be submitted.');
    final review = [
      for (final q in s.qs)
        UniReviewItem(question: q.served(), selected: answers[q.id], correctIndex: q.ans, explanation: q.expl)
    ];
    return UniAttemptResult(
      total: review.length,
      correct: review.where((r) => r.isCorrect).length,
      seconds: used.clamp(0, s.seconds).toInt(),
      review: review,
      weakTopics: review.where((r) => !r.isCorrect).map((r) => r.question.topic).toSet().toList(),
    );
  }

  String _n(String s) => s.toLowerCase().replaceAll(' ', '');

  @override
  Future<List<UniListing>> search({String query = '', String? level, String? semester}) async {
    final q = _n(query);
    return [
      for (final l in _catalog)
        if ((q.isEmpty || _n('${l.course.code}${l.course.title}${l.tutor}${l.university}${l.department}').contains(q)) &&
            (level == null || l.course.level == level) &&
            (semester == null || l.course.semester == semester))
          l.copyWith(enrolled: _enrolled.contains(l.course.id))
    ];
  }

  @override
  Future<void> enroll(String courseId) async => _enrolled.add(courseId);
}
