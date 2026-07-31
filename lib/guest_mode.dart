// lib/guest_mode.dart
//
// Guest access for NaijaLearn.
//
// A guest never touches AuthService, never gets a Supabase session, and
// never sees the bottom-nav shell (Community / Progress / Profile tabs
// all require an account — leaderboard sync, certification, career mode,
// etc). Guests get exactly two things: subject practice and Mock Exam,
// both of which are self-contained flows that don't require sign-in.
//
// Reuses SubjectInfo, kSubjects, QuestionRepository, SubjectCard,
// QuestionCountPickerSheet, and ExamInstructionsScreen straight from
// main.dart — none of that had to change to support this.

import 'package:flutter/material.dart';
import 'main.dart';
import 'app_enhancements.dart' show MockExamScreen;

class GuestHomeScreen extends StatelessWidget {
  const GuestHomeScreen({super.key});

  Future<void> _pickCountAndStart(BuildContext context, SubjectInfo subject) async {
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuestionCountPickerSheet(subject: subject),
    );
    if (count == null || !context.mounted) return;

    final allQuestions = QuestionRepository.getForSubject(subject.name);
    final shuffled = List<Question>.from(allQuestions)..shuffle();
    final questions = (count == -1 || count >= shuffled.length) ? shuffled : shuffled.take(count).toList();
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExamInstructionsScreen(subject: subject, questions: questions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NaijaLearn — Guest'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            ),
            child: const Text('Sign In'),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "You're browsing as a guest. You can practice by subject and take Mock Exams — "
                          'sign in with your ZetraMail to save progress, XP, and access the rest of the app.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Material(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MockExamScreen()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          const Icon(Icons.school_rounded, color: Colors.white, size: 32),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Text(
                              'Mock Exam',
                              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Subjects', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.15,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final subject = kSubjects[index];
                    final count = QuestionRepository.getForSubject(subject.name).length;
                    return SubjectCard(
                      subject: subject,
                      questionCount: count,
                      onTap: () => _pickCountAndStart(context, subject),
                    );
                  },
                  childCount: kSubjects.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
