import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'uni_controller.dart';
import 'uni_models.dart';
import 'uni_test_screen.dart';

String uniDue(DateTime d) {
  final diff = d.difference(DateTime.now());
  if (diff.isNegative) return 'Closed';
  if (diff.inDays == 0) return 'Due today';
  if (diff.inDays == 1) return 'Due tomorrow';
  return 'Due in ${diff.inDays} days';
}

Widget _async<T>(Future<List<T>> f, String empty, Widget Function(List<T>) build) =>
    FutureBuilder<List<T>>(
      future: f,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return Center(child: Text('${s.error}'));
        final d = s.data ?? <T>[];
        return d.isEmpty ? Center(child: Text(empty)) : build(d);
      },
    );

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

// ───────────────────────────── PRACTICE ─────────────────────────────
class UniPracticeTab extends StatefulWidget {
  const UniPracticeTab({super.key, required this.ctrl, required this.course});
  final UniversityController ctrl;
  final UniCourse course;
  @override
  State<UniPracticeTab> createState() => _UniPracticeTabState();
}

class _UniPracticeTabState extends State<UniPracticeTab> {
  int count = 10;
  String diff = 'Mixed';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${widget.course.code} Practice', style: t.titleLarge),
      const SizedBox(height: 16),
      Text('Number of questions', style: t.labelLarge),
      Wrap(spacing: 8, children: [
        for (final n in [10, 20, 50])
          ChoiceChip(label: Text('$n'), selected: count == n, onSelected: (_) => setState(() => count = n)),
      ]),
      const SizedBox(height: 16),
      Text('Difficulty', style: t.labelLarge),
      Wrap(spacing: 8, children: [
        for (final d in ['Easy', 'Medium', 'Hard', 'Mixed'])
          ChoiceChip(label: Text(d), selected: diff == d, onSelected: (_) => setState(() => diff = d)),
      ]),
      const SizedBox(height: 24),
      FilledButton.icon(
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Start practice'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => UniTestScreen(
            ctrl: widget.ctrl,
            title: '${widget.course.code} Practice',
            start: () => widget.ctrl.repo.startPractice(widget.course.id, count: count, difficulty: diff.toLowerCase()),
          ),
        )),
      ),
    ]);
  }
}

// ──────────────────────────── ASSIGNMENTS ────────────────────────────
class UniAssignmentsTab extends StatefulWidget {
  const UniAssignmentsTab({super.key, required this.ctrl, required this.course});
  final UniversityController ctrl;
  final UniCourse course;
  @override
  State<UniAssignmentsTab> createState() => _UniAssignmentsTabState();
}

class _UniAssignmentsTabState extends State<UniAssignmentsTab> {
  late Future<List<UniAssignment>> _f = widget.ctrl.repo.assignments(widget.course.id);
  void _reload() => setState(() => _f = widget.ctrl.repo.assignments(widget.course.id));

  Future<void> _open(UniAssignment a) async {
    final tc = TextEditingController(text: a.submittedText ?? '');
    final canSubmit = a.status == 'open';
    final send = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(a.title, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(a.instructions),
            const SizedBox(height: 8),
            Text('${uniDue(a.deadline)} • Max score ${a.maxScore}', style: Theme.of(ctx).textTheme.bodySmall),
            if (a.score != null) Text('Score: ${a.score}/${a.maxScore}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (a.feedback != null) Text('Feedback: ${a.feedback}'),
            const SizedBox(height: 12),
            TextField(
              controller: tc, enabled: canSubmit, maxLines: 6,
              decoration: const InputDecoration(labelText: 'Your answer', border: OutlineInputBorder()),
            ),
            if (canSubmit) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
            ],
          ],
        )),
      ),
    );
    if (send != true || !mounted) return;
    if (tc.text.trim().isEmpty) { _snack(context, 'Write your answer first.'); return; }
    try {
      await widget.ctrl.repo.submitAssignment(a.id, tc.text.trim());
      await widget.ctrl.refreshDeadlines();
      if (mounted) { _snack(context, 'Submitted.'); _reload(); }
    } on UniException catch (e) {
      if (mounted) { _snack(context, e.message); _reload(); }
    }
  }

  @override
  Widget build(BuildContext context) => _async<UniAssignment>(_f, 'No assignments yet.', (list) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final a in list)
            Card(child: ListTile(
              title: Text(a.title),
              subtitle: Text(a.status == 'graded' ? 'Score ${a.score}/${a.maxScore}' : uniDue(a.deadline)),
              trailing: Chip(label: Text(a.status)),
              onTap: () => _open(a),
            )),
        ],
      ));
}

// ───────────────────────────── QUIZZES ─────────────────────────────
class UniQuizzesTab extends StatefulWidget {
  const UniQuizzesTab({super.key, required this.ctrl, required this.course});
  final UniversityController ctrl;
  final UniCourse course;
  @override
  State<UniQuizzesTab> createState() => _UniQuizzesTabState();
}

class _UniQuizzesTabState extends State<UniQuizzesTab> {
  late Future<List<UniQuiz>> _f = widget.ctrl.repo.quizzes(widget.course.id);

  Future<void> _start(UniQuiz q) async {
    if (q.attemptsLeft <= 0) { _snack(context, 'No attempts left.'); return; }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(q.title),
        content: Text('${q.questionCount} questions • ${q.minutes} min\nThe timer starts immediately and cannot be paused.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => UniTestScreen(ctrl: widget.ctrl, title: q.title, start: () => widget.ctrl.repo.startQuiz(q.id)),
    ));
    if (mounted) setState(() => _f = widget.ctrl.repo.quizzes(widget.course.id));
  }

  @override
  Widget build(BuildContext context) => _async<UniQuiz>(_f, 'No quizzes yet.', (list) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final q in list)
            Card(child: ListTile(
              title: Text(q.title),
              subtitle: Text('${q.questionCount} questions • ${q.minutes} min • ${q.marks} marks'),
              trailing: Text('${q.attemptsLeft} left'),
              onTap: () => _start(q),
            )),
        ],
      ));
}

// ───────────────────────────── MATERIALS ─────────────────────────────
class UniMaterialsTab extends StatelessWidget {
  const UniMaterialsTab({super.key, required this.ctrl, required this.course});
  final UniversityController ctrl;
  final UniCourse course;

  IconData _icon(String t) => t == 'pdf' ? Icons.picture_as_pdf_outlined
      : t == 'slides' ? Icons.slideshow_outlined : t == 'link' ? Icons.link : Icons.description_outlined;

  @override
  Widget build(BuildContext context) => _async<UniMaterial>(ctrl.repo.materials(course.id), 'No materials yet.', (list) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final m in list)
            Card(child: ListTile(
              leading: Icon(_icon(m.type)),
              title: Text(m.title),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () async {
                final ok = await launchUrl(Uri.parse(m.url), mode: LaunchMode.externalApplication);
                if (!ok && context.mounted) _snack(context, 'Could not open this material.');
              },
            )),
        ],
      ));
}
