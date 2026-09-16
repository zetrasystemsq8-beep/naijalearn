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
  Map<String, dynamic>? _enrollment;
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
      final userId = _client.auth.currentUser?.id;
      final isTutor = classroom['tutor_id'] == userId;

      Map<String, dynamic>? enrollment;
      if (!isTutor && userId != null) {
        final row = await _client
            .from('classroom_enrollments')
            .select()
            .eq('classroom_id', widget.classroomId)
            .eq('student_id', userId)
            .eq('status', 'active')
            .maybeSingle();
        enrollment = row != null ? Map<String, dynamic>.from(row) : null;
      }

      setState(() {
        _classroom = Map<String, dynamic>.from(classroom);
        _isTutor = isTutor;
        _enrollment = enrollment;
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

    final expiresAt = _enrollment?['expires_at'] as String?;
    final expiryDate = expiresAt != null ? DateTime.tryParse(expiresAt) : null;
    final isExpired = expiryDate != null && expiryDate.isBefore(DateTime.now());

    if (isExpired) {
      return Scaffold(
        appBar: AppBar(title: Text(_classroom!['name'] as String, overflow: TextOverflow.ellipsis)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_clock_outlined, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text('Access Expired', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Your access to this classroom has ended. Contact the tutor or platform support if you believe this is a mistake.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_classroom!['name'] as String, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'Lessons'),
            Tab(text: 'Assignments'),
            Tab(text: 'Announcements'),
            Tab(text: 'Chat'),
          ]),
        ),
        body: TabBarView(children: [
          _StudentOverviewTab(classroomId: widget.classroomId),
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
    if (_lessons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('No lessons yet', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text("Your tutor hasn't published the first lesson yet.", textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

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
                onTap: () => _openLesson(context, index),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _openLesson(BuildContext context, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _LessonReaderScreen(
          lessons: _lessons,
          initialIndex: index,
          completedIds: _completedIds,
          onMarkComplete: _markComplete,
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
    if (_assignments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assignment_outlined, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('No assignments yet', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text("Your tutor hasn't posted an assignment yet.", textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

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
    if (_announcements.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.campaign_outlined, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('No announcements yet', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text("Your tutor hasn't posted an update yet.", textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

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

// ---------------------------------------------------------------------------
// Overview — "Continue Learning" + latest announcement + progress +
// pending assignments, per the polish-pass spec. Reuses simple queries
// rather than a combined RPC; acceptable at this scale.
// ---------------------------------------------------------------------------
class _StudentOverviewTab extends StatefulWidget {
  final int classroomId;
  const _StudentOverviewTab({required this.classroomId});

  @override
  State<_StudentOverviewTab> createState() => _StudentOverviewTabState();
}

class _StudentOverviewTabState extends State<_StudentOverviewTab> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _nextLesson;
  Map<String, dynamic>? _latestAnnouncement;
  int _totalLessons = 0;
  int _completedLessons = 0;
  int _pendingAssignments = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final userId = _client.auth.currentUser?.id;

      final lessons = await _client
          .from('classroom_lessons')
          .select()
          .eq('classroom_id', widget.classroomId)
          .order('position');
      final lessonList = List<Map<String, dynamic>>.from(lessons);

      Set<int> completedIds = {};
      if (userId != null && lessonList.isNotEmpty) {
        final completions = await _client
            .from('classroom_lesson_completions')
            .select('lesson_id')
            .eq('student_id', userId)
            .inFilter('lesson_id', lessonList.map((l) => l['id'] as int).toList());
        completedIds = (completions as List).map((c) => c['lesson_id'] as int).toSet();
      }

      Map<String, dynamic>? nextLesson;
      for (final l in lessonList) {
        if (!completedIds.contains(l['id'])) {
          nextLesson = l;
          break;
        }
      }

      final announcement = await _client
          .from('classroom_announcements')
          .select()
          .eq('classroom_id', widget.classroomId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      int pendingAssignments = 0;
      if (userId != null) {
        final assignments = await _client.from('classroom_assignments').select('id').eq('classroom_id', widget.classroomId);
        final assignmentIds = (assignments as List).map((a) => a['id'] as int).toList();
        if (assignmentIds.isNotEmpty) {
          final submissions = await _client
              .from('classroom_assignment_submissions')
              .select('assignment_id')
              .eq('student_id', userId)
              .inFilter('assignment_id', assignmentIds);
          final submittedIds = (submissions as List).map((s) => s['assignment_id'] as int).toSet();
          pendingAssignments = assignmentIds.where((id) => !submittedIds.contains(id)).length;
        }
      }

      setState(() {
        _nextLesson = nextLesson;
        _latestAnnouncement = announcement;
        _totalLessons = lessonList.length;
        _completedLessons = completedIds.length;
        _pendingAssignments = pendingAssignments;
      });
    } catch (_) {
      // Non-fatal — sections just show their own empty states.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    final progress = _totalLessons > 0 ? _completedLessons / _totalLessons : null;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_nextLesson != null) ...[
            Text('Continue Learning', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(Icons.play_circle_outline_rounded, color: scheme.primary),
                title: Text(_nextLesson!['title'] as String),
                subtitle: const Text('Next lesson'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => DefaultTabController.of(context).animateTo(1),
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (_latestAnnouncement != null) ...[
            Text('Latest Announcement', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_latestAnnouncement!['message'] as String, maxLines: 3, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(height: 20),
          ],

          Text('Your Progress', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (progress != null) ...[
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 8)),
            const SizedBox(height: 6),
            Text('$_completedLessons/$_totalLessons lessons completed', style: Theme.of(context).textTheme.bodySmall),
          ] else
            Text('No lessons to track yet.', style: Theme.of(context).textTheme.bodySmall),

          if (_pendingAssignments > 0) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(0.3))),
              child: Row(
                children: [
                  Icon(Icons.assignment_late_outlined, color: Colors.orange.shade800),
                  const SizedBox(width: 10),
                  Expanded(child: Text('$_pendingAssignments assignment${_pendingAssignments > 1 ? 's' : ''} pending', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600))),
                  TextButton(onPressed: () => DefaultTabController.of(context).animateTo(2), child: const Text('View')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen lesson reader. Replaces the old bottom-sheet lesson popup —
// a real reading screen with Next/Previous, not a modal that eats half
// the screen from below.
// ---------------------------------------------------------------------------
class _LessonReaderScreen extends StatefulWidget {
  final List<Map<String, dynamic>> lessons;
  final int initialIndex;
  final Set<int> completedIds;
  final Future<void> Function(int lessonId) onMarkComplete;

  const _LessonReaderScreen({
    required this.lessons,
    required this.initialIndex,
    required this.completedIds,
    required this.onMarkComplete,
  });

  @override
  State<_LessonReaderScreen> createState() => _LessonReaderScreenState();
}

class _LessonReaderScreenState extends State<_LessonReaderScreen> {
  late int _index;
  late Set<int> _completed;
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _completed = Set<int>.from(widget.completedIds);
  }

  Future<void> _markCurrentComplete() async {
    final lessonId = widget.lessons[_index]['id'] as int;
    setState(() => _marking = true);
    await widget.onMarkComplete(lessonId);
    if (mounted) {
      setState(() {
        _completed.add(lessonId);
        _marking = false;
      });
    }
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.lessons.length) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lesson = widget.lessons[_index];
    final lessonId = lesson['id'] as int;
    final isDone = _completed.contains(lessonId);
    final contentType = lesson['content_type'] as String;

    return Scaffold(
      appBar: AppBar(
        title: Text('Lesson ${_index + 1} of ${widget.lessons.length}'),
      ),
      body: Column(
        children: [
          ClipRRect(
            child: LinearProgressIndicator(value: (_index + 1) / widget.lessons.length, minHeight: 3),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lesson['title'] as String, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Chip(label: Text(contentType.toUpperCase()), visualDensity: VisualDensity.compact),
                  const SizedBox(height: 20),
                  if (lesson['content_text'] != null)
                    Text(lesson['content_text'] as String, style: const TextStyle(fontSize: 15.5, height: 1.6)),
                  if (lesson['content_url'] != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Icon(contentType == 'video' ? Icons.play_circle_outline_rounded : Icons.link_rounded, color: scheme.primary),
                          const SizedBox(width: 10),
                          Expanded(child: SelectableText(lesson['content_url'] as String, style: TextStyle(color: scheme.primary))),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  if (!isDone)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _marking ? null : _markCurrentComplete,
                        icon: _marking
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_rounded),
                        label: const Text('Mark as complete'),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [Icon(Icons.check_circle_rounded, color: Colors.green, size: 18), SizedBox(width: 8), Text('Completed', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600))],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                          label: const Text('Previous'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _index < widget.lessons.length - 1 ? () => _goTo(_index + 1) : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                          label: const Text('Next'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
