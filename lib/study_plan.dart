// lib/study_plan.dart
//
// A real, honest study plan built entirely from data that already
// exists — no new question tagging, no AI cost, no rewriting anything.
//
//   - "Studied" = a chapter marked complete in lesson_progress (Supabase)
//   - Timetable = remaining chapters spread across days until the
//     student's NEAREST tracked exam (ExamCountdownService), pure math —
//     deterministic, free, and automatically re-spreads itself every
//     time this screen loads, so a missed day just means today's list
//     is a bit fuller. No live AI call, nothing to "burn heavy."
//   - Tapping a chapter opens the existing, unmodified LessonDetailScreen.
//
// Only requires the lesson_progress table (see accompanying SQL). Does
// not touch main.dart, textbooks.dart, or any question data.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart' show LessonDetailScreen;
import 'textbooks.dart';
import 'features5.dart' show ExamCountdownService;

class LessonProgressService extends ChangeNotifier {
  LessonProgressService._();
  static final LessonProgressService instance = LessonProgressService._();

  SupabaseClient get _client => Supabase.instance.client;

  // Keyed as "subject|||chapterTitle" for a simple, fast lookup.
  final Set<String> _completed = {};
  bool _loaded = false;
  bool get isLoaded => _loaded;

  String _key(String subject, String chapterTitle) => '$subject|||$chapterTitle';

  bool isCompleted(String subject, String chapterTitle) =>
      _completed.contains(_key(subject, chapterTitle));

  int completedCountFor(String subject) {
    return allTextbooks
        .firstWhere((b) => b.subject == subject, orElse: () => Textbook(subject: subject, icon: Icons.book, color: Colors.grey, lessons: const []))
        .lessons
        .where((l) => isCompleted(subject, l['chapterTitle'] as String))
        .length;
  }

  Future<void> load() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      final rows = await _client.from('lesson_progress').select('subject, chapter_title').eq('user_id', user.id);
      _completed
        ..clear()
        ..addAll((rows as List).map((r) => _key(r['subject'] as String, r['chapter_title'] as String)));
    } catch (e) {
      debugPrint('[LessonProgressService] load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> markCompleted(String subject, String chapterTitle) async {
    _completed.add(_key(subject, chapterTitle));
    notifyListeners();
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('lesson_progress').upsert({
        'user_id': user.id,
        'subject': subject,
        'chapter_title': chapterTitle,
      }, onConflict: 'user_id,subject,chapter_title');
    } catch (e) {
      debugPrint('[LessonProgressService] markCompleted failed: $e');
    }
  }

  Future<void> markIncomplete(String subject, String chapterTitle) async {
    _completed.remove(_key(subject, chapterTitle));
    notifyListeners();
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client
          .from('lesson_progress')
          .delete()
          .eq('user_id', user.id)
          .eq('subject', subject)
          .eq('chapter_title', chapterTitle);
    } catch (e) {
      debugPrint('[LessonProgressService] markIncomplete failed: $e');
    }
  }
}

/// One chapter, scheduled for a specific day of the plan.
class _ScheduledChapter {
  final String subject;
  final Color subjectColor;
  final Map<String, dynamic> lesson;
  const _ScheduledChapter({required this.subject, required this.subjectColor, required this.lesson});
}

class StudyPlanScreen extends StatefulWidget {
  const StudyPlanScreen({super.key});

  @override
  State<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends State<StudyPlanScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await LessonProgressService.instance.load();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// All chapters across every subject that has textbook content, minus
  /// whatever's already marked complete — in the same order the subject
  /// appears in allTextbooks and lessons appear within it (so this
  /// follows whatever study order the textbooks were already written in).
  List<_ScheduledChapter> get _remainingChapters {
    final progress = LessonProgressService.instance;
    final result = <_ScheduledChapter>[];
    for (final book in allTextbooks) {
      for (final lesson in book.lessons) {
        final title = lesson['chapterTitle'] as String;
        if (!progress.isCompleted(book.subject, title)) {
          result.add(_ScheduledChapter(subject: book.subject, subjectColor: book.color, lesson: lesson));
        }
      }
    }
    return result;
  }

  /// Deterministic day-by-day plan: divides remaining chapters evenly
  /// across days-until-nearest-exam. No AI, recomputed fresh every time
  /// this screen loads — so a missed day automatically means the plan
  /// just redistributes what's left across whatever days remain.
  List<List<_ScheduledChapter>> _buildTimetable(int daysRemaining) {
    final remaining = _remainingChapters;
    if (remaining.isEmpty || daysRemaining <= 0) return [];

    final days = daysRemaining.clamp(1, 365);
    final perDay = (remaining.length / days).ceil().clamp(1, remaining.length);

    final plan = <List<_ScheduledChapter>>[];
    for (var i = 0; i < remaining.length; i += perDay) {
      plan.add(remaining.sublist(i, (i + perDay).clamp(0, remaining.length)));
    }
    return plan;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AnimatedBuilder(
      animation: Listenable.merge([LessonProgressService.instance, ExamCountdownService.instance]),
      builder: (context, _) {
        final examService = ExamCountdownService.instance;
        final exams = examService.exams.where((e) => e.examDate.isAfter(DateTime.now())).toList();
        final nearestExam = exams.isEmpty ? null : exams.first; // exams list is already date-sorted

        if (allTextbooks.every((b) => b.lessons.isEmpty)) {
          return Scaffold(
            appBar: AppBar(title: const Text('Study Plan')),
            body: const Center(child: Text('No textbook chapters available yet.')),
          );
        }

        if (nearestExam == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Study Plan')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy_rounded, size: 56, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  const Text('Add an exam date first', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    'Your study plan spreads remaining chapters across the days until your exam. Add WAEC/JAMB/NECO in Exam Countdown to get started.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        }

        final daysRemaining = nearestExam.examDate.difference(DateTime.now()).inDays + 1;
        final timetable = _buildTimetable(daysRemaining);
        final today = timetable.isEmpty ? <_ScheduledChapter>[] : timetable.first;
        final totalChapters = allTextbooks.fold<int>(0, (sum, b) => sum + b.lessons.length);
        final doneChapters = totalChapters - _remainingChapters.length;

        return Scaffold(
          appBar: AppBar(title: const Text('📅 Study Plan')),
          body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [scheme.primary, scheme.primary.withOpacity(0.75)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${nearestExam.examName} in $daysRemaining day${daysRemaining == 1 ? '' : 's'}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text('$doneChapters of $totalChapters chapters covered',
                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13)),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: totalChapters == 0 ? 0 : doneChapters / totalChapters,
                          minHeight: 8,
                          backgroundColor: Colors.white.withOpacity(0.25),
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Today', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (today.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                    child: const Center(child: Text('🎉 All chapters covered — nothing left to schedule!')),
                  )
                else
                  ...today.map((c) => _ChapterCard(scheduled: c)),
                if (timetable.length > 1) ...[
                  const SizedBox(height: 24),
                  Text('Coming Up', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ...timetable.skip(1).take(6).toList().asMap().entries.map((entry) {
                    final dayIndex = entry.key + 2;
                    final chapters = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Day $dayIndex', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            Text(chapters.map((c) => c.lesson['chapterTitle'] as String).join(', '),
                                style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChapterCard extends StatelessWidget {
  final _ScheduledChapter scheduled;
  const _ChapterCard({required this.scheduled});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = scheduled.lesson['chapterTitle'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: scheduled.subjectColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.menu_book_rounded, color: scheduled.subjectColor, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(scheduled.subject, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        trailing: IconButton(
          icon: const Icon(Icons.check_circle_outline_rounded),
          tooltip: 'Mark as studied',
          onPressed: () async {
            await LessonProgressService.instance.markCompleted(scheduled.subject, title);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Marked "$title" as studied')),
              );
            }
          },
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LessonDetailScreen(
              title: title,
              body: scheduled.lesson['body'] as String,
            ),
          ),
        ),
      ),
    );
  }
}
