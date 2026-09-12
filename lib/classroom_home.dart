// lib/classroom_home.dart
//
// Student's view once enrolled (or the tutor previewing their own
// classroom). Tutor management (create lesson, post announcement, see
// revenue) lives in tutor_dashboard.dart — this screen is read/consume
// only, plus lesson-completion and assignment submission which students
// are allowed to do.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'classroom_chat_widget.dart';
import 'tutor_dashboard.dart';

class ClassroomHomeScreen extends StatefulWidget {
  final int classroomId;
  const ClassroomHomeScreen({super.key, required this.classroomId});

  @override
  State<ClassroomHomeScreen> createState() => _ClassroomHomeScreenState();
}

class _ClassroomHomeScreenState extends State<ClassroomHomeScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _classroom;
  bool _isTutor = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final classroom = await _client.from('classrooms').select().eq('id', widget.classroomId).single();
      setState(() {
        _classroom = Map<String, dynamic>.from(classroom);
        _isTutor = classroom['tutor_id'] == _client.auth.currentUser?.id;
      });
    } catch (_) {
      // handled by null _classroom below
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_classroom == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Classroom not found')));

    // Tutors get the full management dashboard instead of the student view.
    if (_isTutor) {
      return TutorDashboardScreen(classroomId: widget.classroomId);
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_classroom!['name'] as String, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(tabs: [
            Tab(text: 'Lessons'),
            Tab(text: 'Assignments'),
            Tab(text: 'Announcements'),
            Tab(text: 'Chat'),
          ]),
        ),
        body: TabBarView(children: [
          _StudentLessonsTab(classroomId: widget.classroomId),
          _StudentAssignmentsTab(classroomId: widget.classroomId),
          _AnnouncementsTab(classroomId: widget.classroomId),
          ClassroomChatWidget(classroomId: widget.classroomId, isTutor: false),
        ]),
      ),
    );
  }
}

class _StudentLessonsTab extends StatefulWidget {
  final int classroomId;
  const _StudentLessonsTab({required this.classroomId});

  @override
  State<_StudentLessonsTab> createState() => _StudentLessonsTabState();
}

class _StudentLessonsTabState extends State<_StudentLessonsTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _lessons = [];
  Set<int> _completedIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final lessons = await _client
          .from('classroom_lessons')
          .select()
          .eq('classroom_id', widget.classroomId)
          .order('position', ascending: true);

      final userId = _client.auth.currentUser?.id;
      final completions = userId == null
          ? []
          : await _client.from('classroom_lesson_completions').select('lesson_id').eq('student_id', userId);

      setState(() {
        _lessons = List<Map<String, dynamic>>.from(lessons);
        _completedIds = (completions as List).map((c) => c['lesson_id'] as int).toSet();
      });
    } catch (_) {
      // Non-fatal, empty state shown.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markComplete(int lessonId) async {
    try {
      await _client.rpc('mark_lesson_complete', params: {'p_lesson_id': lessonId});
      setState(() => _completedIds.add(lessonId));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update progress.')));
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'video':
        return Icons.play_circle_outline_rounded;
      case 'link':
        return Icons.link_rounded;
      default:
        return Icons.article_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_lessons.isEmpty) return const Center(child: Text('No lessons uploaded yet'));

    final progress = _lessons.isEmpty ? 0.0 : _completedIds.length / _lessons.length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Progress: ${(progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 8)),
                const SizedBox(height: 4),
                Text('${_completedIds.length}/${_lessons.length} lessons completed', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          ..._lessons.map((lesson) {
            final id = lesson['id'] as int;
            final done = _completedIds.contains(id);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(_iconFor(lesson['content_type'] as String)),
                title: Text(lesson['title'] as String),
                trailing: done
                    ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                    : OutlinedButton(onPressed: () => _markComplete(id), child: const Text('Mark done')),
                onTap: () => _openLesson(context, lesson),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _openLesson(BuildContext context, Map<String, dynamic> lesson) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(lesson['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              if (lesson['content_text'] != null) Text(lesson['content_text'] as String),
              if (lesson['content_url'] != null) ...[
                const SizedBox(height: 8),
                SelectableText(lesson['content_url'] as String, style: const TextStyle(color: Colors.blue)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentAssignmentsTab extends StatefulWidget {
  final int classroomId;
  const _StudentAssignmentsTab({required this.classroomId});

  @override
  State<_StudentAssignmentsTab> createState() => _StudentAssignmentsTabState();
}

class _StudentAssignmentsTabState extends State<_StudentAssignmentsTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _assignments = [];
  Map<int, Map<String, dynamic>> _submissions = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final assignments = await _client
          .from('classroom_assignments')
          .select()
          .eq('classroom_id', widget.classroomId)
          .order('created_at', ascending: false);

      final userId = _client.auth.currentUser?.id;
      final submissions = userId == null ? [] : await _client.from('classroom_assignment_submissions').select().eq('student_id', userId);

      setState(() {
        _assignments = List<Map<String, dynamic>>.from(assignments);
        _submissions = {for (final s in (submissions as List)) s['assignment_id'] as int: Map<String, dynamic>.from(s)};
      });
    } catch (_) {
      // Non-fatal.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit(int assignmentId, String content) async {
    try {
      await _client.from('classroom_assignment_submissions').upsert({
        'assignment_id': assignmentId,
        'student_id': _client.auth.currentUser!.id,
        'content': content,
      });
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submitted.'), backgroundColor: Colors.green));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not submit. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_assignments.isEmpty) return const Center(child: Text('No assignments yet'));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _assignments.length,
        itemBuilder: (context, index) {
          final a = _assignments[index];
          final id = a['id'] as int;
          final submission = _submissions[id];
          final controller = TextEditingController(text: submission?['content'] as String? ?? '');

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(label: Text(a['type'] as String), visualDensity: VisualDensity.compact),
                      const SizedBox(width: 8),
                      Expanded(child: Text(a['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold))),
                      if (submission != null && submission['score'] != null)
                        Chip(label: Text('Score: ${submission['score']}'), backgroundColor: Colors.green.withOpacity(0.15)),
                    ],
                  ),
                  if ((a['instructions'] as String?)?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 6),
                    Text(a['instructions'] as String, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: submission != null ? 'Update your answer' : 'Your answer',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => _submit(id, controller.text.trim()),
                      child: Text(submission != null ? 'Update submission' : 'Submit'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AnnouncementsTab extends StatefulWidget {
  final int classroomId;
  const _AnnouncementsTab({required this.classroomId});

  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _announcements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _client
          .from('classroom_announcements')
          .select()
          .eq('classroom_id', widget.classroomId)
          .order('created_at', ascending: false);
      setState(() => _announcements = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Non-fatal.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_announcements.isEmpty) return const Center(child: Text('No announcements yet'));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _announcements.length,
        itemBuilder: (context, index) {
          final a = _announcements[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a['message'] as String),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('MMM d, yyyy • h:mm a').format(DateTime.parse(a['created_at'])),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
