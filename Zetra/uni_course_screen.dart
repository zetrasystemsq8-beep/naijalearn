import 'package:flutter/material.dart';
import 'uni_controller.dart';
import 'uni_course_tabs.dart';
import 'uni_models.dart';

class UniCourseScreen extends StatefulWidget {
  const UniCourseScreen({super.key, required this.ctrl, required this.course, this.onAskNai});
  final UniversityController ctrl;
  final UniCourse course;
  final void Function(UniCourse? course)? onAskNai;
  @override
  State<UniCourseScreen> createState() => _UniCourseScreenState();
}

class _UniCourseScreenState extends State<UniCourseScreen> {
  static const tabs = ['Overview', 'Lessons', 'Practice', 'Assignments', 'Quizzes', 'Materials', 'Discussion'];

  @override
  void initState() { super.initState(); widget.ctrl.loadLessons(widget.course.id); }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ctrl,
      builder: (context, _) {
        final c = widget.ctrl.courses.firstWhere((x) => x.id == widget.course.id, orElse: () => widget.course);
        final lessons = widget.ctrl.lessonCache[c.id] ?? [];
        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(title: Text(c.code), bottom: TabBar(isScrollable: true, tabs: [for (final t in tabs) Tab(text: t)])),
            bottomNavigationBar: widget.onAskNai == null ? null : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => widget.onAskNai!(c),
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: const Text('Ask NAI about this course'),
                ),
              ),
            ),
            body: TabBarView(children: [
              _overview(c),
              _lessonsTab(c, lessons),
              UniPracticeTab(ctrl: widget.ctrl, course: c),
              UniAssignmentsTab(ctrl: widget.ctrl, course: c),
              UniQuizzesTab(ctrl: widget.ctrl, course: c),
              UniMaterialsTab(ctrl: widget.ctrl, course: c),
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Discussion connects to the tutor classroom chat.', textAlign: TextAlign.center),
              )),
            ]),
          ),
        );
      },
    );
  }

  Widget _overview(UniCourse c) => ListView(padding: const EdgeInsets.all(16), children: [
        Text(c.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('${c.code} • ${c.units} units • ${c.level} • ${c.semester}'),
        const SizedBox(height: 16),
        Text('Progress: ${(c.progress * 100).round()}%'),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: c.progress, minHeight: 8),
        const SizedBox(height: 4),
        const Text('Learning indicator only, not your official grade.', style: TextStyle(fontSize: 12)),
        if (c.nextLesson != null) ...[
          const SizedBox(height: 16),
          Card(child: ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Continue learning'),
            subtitle: Text(c.nextLesson!),
          )),
        ],
        const SizedBox(height: 16),
        Text(c.description),
        if (c.lecturer != null) Text('Tutor: ${c.lecturer}'),
        const SizedBox(height: 12),
        const Text('Course content is created by tutors on NaijaLearn. It is not official university material.', style: TextStyle(fontSize: 12)),
      ]);

  Widget _lessonsTab(UniCourse c, List<UniLesson> lessons) {
    final modules = <String, List<UniLesson>>{};
    for (final l in lessons) { modules.putIfAbsent(l.module, () => []).add(l); }
    return ListView(children: [
      for (final e in modules.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(e.key, style: Theme.of(context).textTheme.titleSmall),
        ),
        for (final l in e.value)
          CheckboxListTile(
            value: l.done, title: Text(l.title),
            onChanged: (v) => widget.ctrl.toggleLesson(c.id, l.id, v ?? false),
          ),
      ],
    ]);
  }
}
