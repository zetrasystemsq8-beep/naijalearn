// lib/certification.dart
//
// Certification feature. Determines ELIGIBILITY ONLY — this app never
// generates a certificate. A student who passes the Certification Exam
// is written to the certificate_eligible table for manual certificate
// generation on the Zetra Verifier website.
//
// Uses Provider/ChangeNotifier to match the rest of the app (no Riverpod).
//
// Eligibility requires ALL of:
//  - 500+ questions completed in the subject
//  - 85%+ average score
//  - studied on 10+ distinct calendar days
//  - every unique question in the subject's bank attempted at least once
//    (this stands in for "every topic completed" — since topics are just
//    groupings of questions, full question-bank coverage is a stricter,
//    equivalent requirement that needs no extra tagging on the question
//    data itself)
//  - no active cheating flag
//
// The Certification Exam draws 100 questions at random from the full
// subject pool. Without difficulty tags on the underlying question data,
// there's no way to force a guaranteed easy/medium/hard split — this is
// a random mix by chance, not an enforced one.
//
// Progress is tracked server-side in certification_progress, updated via
// recordPracticeSession() — call this from ExamScreen._submitExam in
// main.dart (see wiring notes) so every practice session counts toward
// eligibility, not just certification attempts.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show Question, QuestionRepository, SubjectInfo, kSubjects;

/// =========================================================================
/// MODELS
/// =========================================================================

class CertificationProgress {
  final String subject;
  final int questionsCompleted;
  final int correctAnswers;
  final Set<String> studyDays; // 'YYYY-MM-DD'
  final Set<String> questionsCovered; // question ids attempted at least once
  final bool cheatingFlag;

  const CertificationProgress({
    required this.subject,
    required this.questionsCompleted,
    required this.correctAnswers,
    required this.studyDays,
    required this.questionsCovered,
    required this.cheatingFlag,
  });

  factory CertificationProgress.empty(String subject) => CertificationProgress(
        subject: subject,
        questionsCompleted: 0,
        correctAnswers: 0,
        studyDays: {},
        questionsCovered: {},
        cheatingFlag: false,
      );

  factory CertificationProgress.fromMap(Map<String, dynamic> map) {
    return CertificationProgress(
      subject: map['subject'] as String,
      questionsCompleted: (map['questions_completed'] as num?)?.toInt() ?? 0,
      correctAnswers: (map['correct_answers'] as num?)?.toInt() ?? 0,
      studyDays: ((map['study_days'] as List<dynamic>?) ?? []).map((e) => e.toString()).toSet(),
      questionsCovered: ((map['questions_covered'] as List<dynamic>?) ?? []).map((e) => e.toString()).toSet(),
      cheatingFlag: map['cheating_flag'] as bool? ?? false,
    );
  }

  double get averagePercent =>
      questionsCompleted == 0 ? 0 : (correctAnswers / questionsCompleted) * 100;
}

class CertificationEligibility {
  static const int requiredQuestions = 500;
  static const double requiredAverage = 85.0;
  static const int requiredStudyDays = 10;

  final CertificationProgress progress;
  final int totalQuestionsInSubject;

  const CertificationEligibility({
    required this.progress,
    required this.totalQuestionsInSubject,
  });

  bool get questionsMet => progress.questionsCompleted >= requiredQuestions;
  bool get averageMet => progress.averagePercent >= requiredAverage;
  bool get studyDaysMet => progress.studyDays.length >= requiredStudyDays;
  bool get coverageMet =>
      totalQuestionsInSubject > 0 && progress.questionsCovered.length >= totalQuestionsInSubject;
  bool get noCheatingFlag => !progress.cheatingFlag;

  bool get isEligible =>
      questionsMet && averageMet && studyDaysMet && coverageMet && noCheatingFlag;

  double get overallProgressFraction {
    final parts = [
      (progress.questionsCompleted / requiredQuestions).clamp(0.0, 1.0),
      (progress.averagePercent / requiredAverage).clamp(0.0, 1.0),
      (progress.studyDays.length / requiredStudyDays).clamp(0.0, 1.0),
      totalQuestionsInSubject == 0
          ? 0.0
          : (progress.questionsCovered.length / totalQuestionsInSubject).clamp(0.0, 1.0),
    ];
    return parts.reduce((a, b) => a + b) / parts.length;
  }
}

enum CertificationResultStatus { certificateEligible, almostThere, notEligible }

class CertificationAttemptResult {
  final double scorePercent;
  final CertificationResultStatus status;
  final DateTime attemptedAt;

  const CertificationAttemptResult({
    required this.scorePercent,
    required this.status,
    required this.attemptedAt,
  });

  static CertificationResultStatus statusFor(double scorePercent) {
    if (scorePercent >= 90) return CertificationResultStatus.certificateEligible;
    if (scorePercent >= 80) return CertificationResultStatus.almostThere;
    return CertificationResultStatus.notEligible;
  }

  String get label {
    switch (status) {
      case CertificationResultStatus.certificateEligible:
        return 'Certificate Eligible';
      case CertificationResultStatus.almostThere:
        return 'Almost There';
      case CertificationResultStatus.notEligible:
        return 'Not Eligible';
    }
  }
}

/// =========================================================================
/// SERVICE (Supabase access)
/// =========================================================================

class CertificationService {
  CertificationService._();
  static final CertificationService instance = CertificationService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<CertificationProgress> loadProgress(String subject) async {
    final user = _client.auth.currentUser;
    if (user == null) return CertificationProgress.empty(subject);

    final row = await _client
        .from('certification_progress')
        .select()
        .eq('user_id', user.id)
        .eq('subject', subject)
        .maybeSingle();

    if (row == null) return CertificationProgress.empty(subject);
    return CertificationProgress.fromMap(row);
  }

  /// Call after every completed practice session (not just certification
  /// attempts) so ordinary practice counts toward eligibility.
  Future<void> recordPracticeSession({
    required String subject,
    required int questionsAnswered,
    required int correctAnswers,
    required Set<String> questionIdsCovered,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final existing = await loadProgress(subject);
    final today = DateTime.now();
    final todayKey =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final updatedStudyDays = {...existing.studyDays, todayKey};
    final updatedCoverage = {...existing.questionsCovered, ...questionIdsCovered};

    await _client.from('certification_progress').upsert({
      'user_id': user.id,
      'subject': subject,
      'questions_completed': existing.questionsCompleted + questionsAnswered,
      'correct_answers': existing.correctAnswers + correctAnswers,
      'study_days': updatedStudyDays.toList(),
      'questions_covered': updatedCoverage.toList(),
      'cheating_flag': existing.cheatingFlag,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,subject');
  }

  /// Returns the most recent certification exam attempt for this subject,
  /// or null if none exists. Used to enforce the 7-day retry cooldown for
  /// "Almost There" results.
  Future<Map<String, dynamic>?> lastAttempt(String subject) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    return _client
        .from('certification_exam_attempts')
        .select()
        .eq('user_id', user.id)
        .eq('subject', subject)
        .order('attempted_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  Future<List<Set<String>>> previousQuestionSets(String subject) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final rows = await _client
        .from('certification_exam_attempts')
        .select('question_ids')
        .eq('user_id', user.id)
        .eq('subject', subject);

    return (rows as List<dynamic>)
        .map((r) => ((r['question_ids'] as List<dynamic>?) ?? []).map((e) => e.toString()).toSet())
        .toList();
  }

  Future<CertificationAttemptResult> submitCertificationAttempt({
    required String subject,
    required List<String> questionIds,
    required double scorePercent,
    required String studentName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in.');
    }

    final status = CertificationAttemptResult.statusFor(scorePercent);
    final result = CertificationAttemptResult(
      scorePercent: scorePercent,
      status: status,
      attemptedAt: DateTime.now(),
    );

    await _client.from('certification_exam_attempts').insert({
      'user_id': user.id,
      'subject': subject,
      'score': scorePercent,
      'status': result.label,
      'question_ids': questionIds,
    });

    if (status == CertificationResultStatus.certificateEligible) {
      await _client.from('certificate_eligible').insert({
        'user_id': user.id,
        'student_name': studentName,
        'subject': subject,
        'exam_score': scorePercent,
        'status': 'Pending Manual Certificate',
      });
    }

    return result;
  }
}

/// =========================================================================
/// PROVIDER
/// =========================================================================

class CertificationProvider extends ChangeNotifier {
  final Map<String, CertificationEligibility> _eligibilityBySubject = {};
  final Map<String, Map<String, dynamic>?> _lastAttemptBySubject = {};
  bool _loading = false;

  bool get loading => _loading;

  CertificationEligibility? eligibilityFor(String subject) => _eligibilityBySubject[subject];
  Map<String, dynamic>? lastAttemptFor(String subject) => _lastAttemptBySubject[subject];

  Future<void> loadFor(String subject) async {
    _loading = true;
    notifyListeners();

    final totalQuestions = QuestionRepository.getForSubject(subject).length;
    final progress = await CertificationService.instance.loadProgress(subject);
    final lastAttempt = await CertificationService.instance.lastAttempt(subject);

    _eligibilityBySubject[subject] = CertificationEligibility(
      progress: progress,
      totalQuestionsInSubject: totalQuestions,
    );
    _lastAttemptBySubject[subject] = lastAttempt;

    _loading = false;
    notifyListeners();
  }

  /// Whether a retry is currently blocked by the 7-day "Almost There"
  /// cooldown. Returns null if no cooldown applies.
  Duration? retryCooldownRemaining(String subject) {
    final last = _lastAttemptBySubject[subject];
    if (last == null) return null;
    if (last['status'] != 'Almost There') return null;

    final attemptedAt = DateTime.tryParse(last['attempted_at'] as String? ?? '');
    if (attemptedAt == null) return null;

    final unlockAt = attemptedAt.add(const Duration(days: 7));
    final remaining = unlockAt.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }
}

/// =========================================================================
/// EXAM QUESTION SELECTION
/// =========================================================================

class CertificationExamBuilder {
  static const int examSize = 100;

  /// Builds a randomized 100-question set from the full subject pool,
  /// avoiding an exact repeat of any previous attempt's question set.
  static List<Question> build(String subject, List<Set<String>> previousSets) {
    final pool = QuestionRepository.getForSubject(subject);
    if (pool.isEmpty) return [];

    final random = Random();
    List<Question> attempt = [];
    int guard = 0;

    do {
      final shuffled = List<Question>.from(pool)..shuffle(random);
      attempt = shuffled.take(min(examSize, shuffled.length)).toList();
      guard++;
    } while (guard < 5 &&
        previousSets.any((prev) =>
            prev.length == attempt.length && prev.containsAll(attempt.map((q) => q.id))));

    return attempt;
  }
}

/// =========================================================================
/// CERTIFICATION HOME (requirements + progress + eligibility + dashboard)
/// =========================================================================

class CertificationHomeScreen extends StatefulWidget {
  final SubjectInfo subject;
  const CertificationHomeScreen({super.key, required this.subject});

  @override
  State<CertificationHomeScreen> createState() => _CertificationHomeScreenState();
}

class _CertificationHomeScreenState extends State<CertificationHomeScreen> {
  late final CertificationProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = CertificationProvider();
    _provider.loadFor(widget.subject.name);
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _provider,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final eligibility = _provider.eligibilityFor(widget.subject.name);
        final lastAttempt = _provider.lastAttemptFor(widget.subject.name);
        final cooldown = _provider.retryCooldownRemaining(widget.subject.name);

        return Scaffold(
          appBar: AppBar(title: Text('${widget.subject.name} Certification')),
          body: _provider.loading
              ? const Center(child: CircularProgressIndicator())
              : eligibility == null
                  ? const Center(child: Text('Could not load certification progress.'))
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: eligibility.isEligible
                                ? Colors.green.withOpacity(0.12)
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: eligibility.isEligible ? Colors.green : scheme.outlineVariant,
                              width: 1.4,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                eligibility.isEligible ? Icons.verified_rounded : Icons.hourglass_bottom_rounded,
                                color: eligibility.isEligible ? Colors.green : scheme.onSurfaceVariant,
                                size: 32,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  eligibility.isEligible ? 'Eligible for Certification' : 'Not Eligible Yet',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: eligibility.isEligible ? Colors.green : scheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: eligibility.overallProgressFraction,
                            minHeight: 10,
                            backgroundColor: scheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(
                              eligibility.isEligible ? Colors.green : scheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text('Requirements', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _RequirementTile(
                          met: eligibility.questionsMet,
                          label:
                              '${eligibility.progress.questionsCompleted} / ${CertificationEligibility.requiredQuestions} questions completed',
                        ),
                        _RequirementTile(
                          met: eligibility.averageMet,
                          label:
                              '${eligibility.progress.averagePercent.toStringAsFixed(1)}% average score (need ${CertificationEligibility.requiredAverage.toStringAsFixed(0)}%)',
                        ),
                        _RequirementTile(
                          met: eligibility.studyDaysMet,
                          label:
                              '${eligibility.progress.studyDays.length} / ${CertificationEligibility.requiredStudyDays} distinct study days',
                        ),
                        _RequirementTile(
                          met: eligibility.coverageMet,
                          label:
                              '${eligibility.progress.questionsCovered.length} / ${eligibility.totalQuestionsInSubject} questions attempted at least once',
                        ),
                        _RequirementTile(
                          met: eligibility.noCheatingFlag,
                          label: eligibility.noCheatingFlag ? 'No active cheating flag' : 'Active cheating flag — contact support',
                        ),
                        const SizedBox(height: 24),
                        if (lastAttempt != null) ...[
                          Text('Last Certification Attempt', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                            child: Row(
                              children: [
                                Expanded(child: Text('Score: ${(lastAttempt['score'] as num).toStringAsFixed(1)}%')),
                                Text(lastAttempt['status'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.school_rounded),
                            label: Text(
                              cooldown != null
                                  ? 'Retry available in ${cooldown.inDays}d ${cooldown.inHours % 24}h'
                                  : 'Start Certification Exam',
                            ),
                            onPressed: (!eligibility.isEligible || cooldown != null)
                                ? null
                                : () async {
                                    final attempts = await CertificationService.instance.previousQuestionSets(widget.subject.name);
                                    if (!context.mounted) return;
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => CertificationExamScreen(
                                          subject: widget.subject,
                                          previousQuestionSets: attempts,
                                        ),
                                      ),
                                    ).then((_) => _provider.loadFor(widget.subject.name));
                                  },
                          ),
                        ),
                      ],
                    ),
        );
      },
    );
  }
}

class _RequirementTile extends StatelessWidget {
  final bool met;
  final String label;
  const _RequirementTile({required this.met, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: met ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

/// =========================================================================
/// CERTIFICATION EXAM
/// =========================================================================

class CertificationExamScreen extends StatefulWidget {
  final SubjectInfo subject;
  final List<Set<String>> previousQuestionSets;

  const CertificationExamScreen({
    super.key,
    required this.subject,
    required this.previousQuestionSets,
  });

  @override
  State<CertificationExamScreen> createState() => _CertificationExamScreenState();
}

class _CertificationExamScreenState extends State<CertificationExamScreen> {
  static const int durationMinutes = 90;

  late final List<Question> _questions;
  late final List<int?> _selectedAnswers;
  int _currentIndex = 0;
  late int _remainingSeconds;
  Timer? _timer;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _questions = CertificationExamBuilder.build(widget.subject.name, widget.previousQuestionSets);
    _selectedAnswers = List<int?>.filled(_questions.length, null);
    _remainingSeconds = durationMinutes * 60;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
        _submit();
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _selectOption(int i) => setState(() => _selectedAnswers[_currentIndex] = i);

  void _goTo(int index) {
    if (index < 0 || index >= _questions.length) return;
    setState(() => _currentIndex = index);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    _timer?.cancel();

    int correct = 0;
    for (int i = 0; i < _questions.length; i++) {
      if (_selectedAnswers[i] != null && _selectedAnswers[i] == _questions[i].correctIndex) {
        correct++;
      }
    }
    final scorePercent = _questions.isEmpty ? 0.0 : (correct / _questions.length) * 100;

    String studentName = 'Student';
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final row = await Supabase.instance.client.from('profiles').select('username').eq('id', userId).maybeSingle();
        studentName = row?['username'] as String? ?? 'Student';
      }
    } catch (_) {}

    final result = await CertificationService.instance.submitCertificationAttempt(
      subject: widget.subject.name,
      questionIds: _questions.map((q) => q.id).toList(),
      scorePercent: scorePercent,
      studentName: studentName,
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => CertificationResultScreen(result: result)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Certification Exam')),
        body: const Center(child: Text('Not enough questions available for this subject yet.')),
      );
    }

    final question = _questions[_currentIndex];
    final answeredCount = _selectedAnswers.where((a) => a != null).length;
    final isLowTime = _remainingSeconds <= 300;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.subject.name} Certification Exam'),
          automaticallyImplyLeading: false,
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isLowTime ? scheme.errorContainer : scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_formattedTime, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: answeredCount / _questions.length,
                      minHeight: 8,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Question ${_currentIndex + 1} of ${_questions.length}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                      child: Text(question.questionText, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
                    ),
                    const SizedBox(height: 18),
                    ...List.generate(question.options.length, (i) {
                      final isSelected = _selectedAnswers[_currentIndex] == i;
                      final letter = String.fromCharCode(65 + i);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: isSelected ? scheme.primaryContainer : scheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _selectOption(i),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isSelected ? scheme.primary : scheme.outlineVariant, width: isSelected ? 2 : 1),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
                                    child: Text(letter, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant)),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(child: Text(question.options[i], style: const TextStyle(fontSize: 15))),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    // Deliberately no explanation shown here — certification
                    // exams disable hints and explanations entirely.
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _currentIndex > 0 ? () => _goTo(_currentIndex - 1) : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('Previous'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _currentIndex == _questions.length - 1
                          ? FilledButton.icon(
                              onPressed: _submitting ? null : _submit,
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Submit'),
                            )
                          : FilledButton.icon(
                              onPressed: () => _goTo(_currentIndex + 1),
                              icon: const Icon(Icons.chevron_right_rounded),
                              label: const Text('Next'),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// CERTIFICATION RESULT
/// =========================================================================

class CertificationResultScreen extends StatelessWidget {
  final CertificationAttemptResult result;
  const CertificationResultScreen({super.key, required this.result});

  Color _statusColor(BuildContext context) {
    switch (result.status) {
      case CertificationResultStatus.certificateEligible:
        return Colors.green;
      case CertificationResultStatus.almostThere:
        return Colors.amber;
      case CertificationResultStatus.notEligible:
        return Theme.of(context).colorScheme.error;
    }
  }

  String get _message {
    switch (result.status) {
      case CertificationResultStatus.certificateEligible:
        return "Congratulations — you've qualified! Your record has been sent for manual certificate generation. You'll be notified once your certificate is issued.";
      case CertificationResultStatus.almostThere:
        return "So close! You can retry the Certification Exam in 7 days. Use the time to review your weaker topics.";
      case CertificationResultStatus.notEligible:
        return "You didn't reach the certification threshold this time. Keep practising — there's no fixed waiting period, but more practice will help.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Certification Result'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_rounded, size: 72, color: color),
            const SizedBox(height: 20),
            Text('${result.scorePercent.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(result.label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 20),
            Text(_message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Back to Home'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
