import 'package:flutter/material.dart';
import 'university_repository.dart';
import 'models.dart';
import 'university_controller.dart';
import 'course_screen.dart';
import 'gpa_screen.dart';

class UniversityHome extends StatefulWidget {
  const UniversityHome({super.key, this.repository, this.onAskNai});
  final UniversityRepository? repository;
  /// Hook into your existing NAI screen. [course] is null when asked from home.
  final void Function(Course? course)? onAskNai;
  @override
  State<UniversityHome> createState() => _UniversityHomeState();
}

class _UniversityHomeState extends State<UniversityHome> {
  late final UniversityController ctrl =
      UniversityController(widget.repository ?? MockUniversityRepository())..load();

  @override
  void dispose() { ctrl.dispose(); super.dispose(); }

  String _due(DateTime d) {
    final days = d.difference(DateTime.now()).inDays;
    return days <= 0 ? 'Due today' : days == 1 ? 'Due tomorrow' : 'Due in $days days';
  }

  Future<void> _editProfile() async {
    final p = ctrl.profile;
    final c = [p.university, p.faculty, p.department, p.level, p.semester]
        .map((e) => TextEditingController(text: e ?? '')).toList();
    const labels = ['University', 'Faculty', 'Department', 'Level', 'Semester'];
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('My University'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 5; i++)
              TextField(controller: c[i], decoration: InputDecoration(labelText: labels[i])),
            const SizedBox(height: 8),
            const Text('Optional. Selecting a university does not mean it is affiliated with NaijaLearn.',
                style: TextStyle(fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Skip for now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (save == true) {
      String? v(int i) => c[i].text.trim().isEmpty ? null : c[i].text.trim();
      await ctrl.saveProfile(UniProfile(
          university: v(0), faculty: v(1), department: v(2), level: v(3), semester: v(4)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        if (ctrl.loading) return const Center(child: CircularProgressIndicator());
        final p = ctrl.profile;
        final resume = ctrl.courses.where((c) => c.nextLesson != null).toList();
        return Scaffold(
          appBar: AppBar(title: const Text('🎓 University'), actions: [
            IconButton(
              tooltip: 'GPA / CGPA',
              icon: const Icon(Icons.calculate_outlined),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => GpaScreen(ctrl: ctrl))),
            ),
          ]),
          floatingActionButton: widget.onAskNai == null ? null : FloatingActionButton.extended(
            onPressed: () => widget.onAskNai!(null),
            icon: const Icon(Icons.smart_toy_outlined), label: const Text('Ask NAI')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Card(child: ListTile(
              title: Text(p.isEmpty ? 'Set up your university' : p.university ?? 'My University'),
              subtitle: Text(p.isEmpty
                  ? 'Optional. You can still use general university learning.'
                  : [p.department, p.level, p.semester].whereType<String>().join(' • ')),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _editProfile,
            )),
            const SizedBox(height: 12),
            Text('Overall progress', style: t.labelLarge),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: ctrl.overallProgress, minHeight: 8),
            const SizedBox(height: 20),
            Text('My courses', style: t.titleMedium),
            for (final c in ctrl.courses)
              Card(child: ListTile(
                title: Text('${c.code} — ${c.title}'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(value: c.progress),
                ),
                trailing: Text('${(c.progress * 100).round()}%'),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => CourseScreen(ctrl: ctrl, course: c, onAskNai: widget.onAskNai))),
              )),
            const SizedBox(height: 20),
            Text('Upcoming', style: t.titleMedium),
            if (ctrl.deadlines.isEmpty) const Text('Nothing due. 🎉'),
            for (final d in ctrl.deadlines)
              ListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text('${d.title} — ${d.courseCode}'),
                subtitle: Text(_due(d.due)),
              ),
            if (resume.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Continue learning', style: t.titleMedium),
              Card(child: ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(resume.first.nextLesson!),
                subtitle: Text(resume.first.code),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => CourseScreen(ctrl: ctrl, course: resume.first, onAskNai: widget.onAskNai))),
              )),
            ],
            const SizedBox(height: 80),
          ]),
        );
      },
    );
  }
}
