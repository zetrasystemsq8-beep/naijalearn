// lib/tutor_dashboard.dart
//
// Tutor-only classroom management. Every RPC call here is also checked
// server-side against classroom.tutor_id = auth.uid() — this screen
// being reachable doesn't imply the action will succeed if that's ever
// not true (e.g. a stale cached route).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'classroom_chat_widget.dart';

class TutorDashboardScreen extends StatefulWidget {
  final int classroomId;
  const TutorDashboardScreen({super.key, required this.classroomId});

  @override
  State<TutorDashboardScreen> createState() => _TutorDashboardScreenState();
}

class _TutorDashboardScreenState extends State<TutorDashboardScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _classroom;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadClassroom();
  }

  Future<void> _loadClassroom() async {
    try {
      final row = await _client.from('classrooms').select().eq('id', widget.classroomId).single();
      setState(() => _classroom = Map<String, dynamic>.from(row));
    } catch (_) {
      // handled by null check below
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_classroom == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Classroom not found')));

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_classroom!['name'] as String, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'Students'),
            Tab(text: 'Lessons'),
            Tab(text: 'Assignments'),
            Tab(text: 'Announcements'),
            Tab(text: 'Chat'),
          ]),
        ),
        body: TabBarView(children: [
          _OverviewTab(classroom: _classroom!, onChanged: _loadClassroom),
          _StudentsTab(classroomId: widget.classroomId),
          _LessonsTab(classroomId: widget.classroomId),
          _AssignmentsTab(classroomId: widget.classroomId),
          _AnnouncementsComposeTab(classroomId: widget.classroomId),
          ClassroomChatWidget(classroomId: widget.classroomId, isTutor: true),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview + revenue
// ---------------------------------------------------------------------------
class _OverviewTab extends StatefulWidget {
  final Map<String, dynamic> classroom;
  final VoidCallback onChanged;
  const _OverviewTab({required this.classroom, required this.onChanged});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  int _grossCent = 0;
  int _platformFeeCent = 0;
  int _pendingCent = 0;
  int _availableCent = 0;
  int _paidCent = 0;

  @override
  void initState() {
    super.initState();
    _loadRevenue();
  }

  Future<void> _loadRevenue() async {
    setState(() => _loading = true);
    try {
      final rows = await _client
          .from('classroom_payments')
          .select('gross_amount_cent, platform_fee_cent, tutor_amount_cent, payout_status, status')
          .eq('classroom_id', widget.classroom['id'])
          .eq('payment_type', 'enrollment');

      int gross = 0, fee = 0, pending = 0, available = 0, paid = 0;
      for (final r in rows as List) {
        if (r['status'] == 'refunded') continue;
        gross += (r['gross_amount_cent'] as int);
        fee += (r['platform_fee_cent'] as int);
        switch (r['payout_status']) {
          case 'pending':
            pending += r['tutor_amount_cent'] as int;
            break;
          case 'available':
            available += r['tutor_amount_cent'] as int;
            break;
          case 'paid':
            paid += r['tutor_amount_cent'] as int;
            break;
        }
      }
      setState(() {
        _grossCent = gross;
        _platformFeeCent = fee;
        _pendingCent = pending;
        _availableCent = available;
        _paidCent = paid;
      });
    } catch (_) {
      // Non-fatal.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.classroom;
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async {
        widget.onChanged();
        await _loadRevenue();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: _StatCard(label: 'Students', value: '${c['student_count']}/${c['capacity']}')),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(label: 'Status', value: (c['status'] as String).toUpperCase())),
            ],
          ),
          const SizedBox(height: 20),
          Text('Revenue', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  _RevenueRow('Gross revenue', _grossCent),
                  _RevenueRow('Platform fee (10%)', _platformFeeCent, isDeduction: true),
                  const Divider(height: 24),
                  _RevenueRow('Pending', _pendingCent),
                  _RevenueRow('Available for payout', _availableCent, highlight: true),
                  _RevenueRow('Paid out', _paidCent),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RevenueRow extends StatelessWidget {
  final String label;
  final int cent;
  final bool isDeduction;
  final bool highlight;
  const _RevenueRow(this.label, this.cent, {this.isDeduction = false, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: highlight ? FontWeight.bold : FontWeight.normal)),
          Text(
            '${isDeduction ? '-' : ''}₦$cent',
            style: TextStyle(fontWeight: FontWeight.bold, color: highlight ? Colors.green : (isDeduction ? Colors.red : null)),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Students
// ---------------------------------------------------------------------------
class _StudentsTab extends StatefulWidget {
  final int classroomId;
  const _StudentsTab({required this.classroomId});

  @override
  State<_StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<_StudentsTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _students = [];
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
          .from('classroom_enrollments')
          .select()
          .eq('classroom_id', widget.classroomId)
          .eq('status', 'active')
          .order('joined_at', ascending: false);
      setState(() => _students = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Non-fatal.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(String studentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove student'),
        content: const Text('This revokes their access. It does not issue a refund automatically.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _client.rpc('tutor_remove_student', params: {'p_classroom_id': widget.classroomId, 'p_student_id': studentId});
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_students.isEmpty) return const Center(child: Text('No students enrolled yet'));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _students.length,
        itemBuilder: (context, index) {
          final s = _students[index];
          final expiresAt = s['expires_at'] as String?;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
              title: Text(s['student_id'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              subtitle: Text(
                'Joined ${DateFormat('MMM d, yyyy').format(DateTime.parse(s['joined_at']))}'
                '${expiresAt != null ? ' · Expires ${DateFormat('MMM d, yyyy').format(DateTime.parse(expiresAt))}' : ''}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.person_remove_outlined, color: Colors.red),
                onPressed: () => _remove(s['student_id'] as String),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lessons (create + list)
// ---------------------------------------------------------------------------
class _LessonsTab extends StatefulWidget {
  final int classroomId;
  const _LessonsTab({required this.classroomId});

  @override
  State<_LessonsTab> createState() => _LessonsTabState();
}

class _LessonsTabState extends State<_LessonsTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _lessons = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _client.from('classroom_lessons').select().eq('classroom_id', widget.classroomId).order('position');
      setState(() => _lessons = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Non-fatal.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreateSheet() async {
    final titleController = TextEditingController();
    final urlController = TextEditingController();
    final textController = TextEditingController();
    String type = 'text';

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: StatefulBuilder(
          builder: (context, setSheetState) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('New lesson', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('Text')),
                    DropdownMenuItem(value: 'pdf', child: Text('PDF link')),
                    DropdownMenuItem(value: 'video', child: Text('Video link')),
                    DropdownMenuItem(value: 'link', child: Text('External link')),
                  ],
                  onChanged: (v) => setSheetState(() => type = v!),
                ),
                const SizedBox(height: 12),
                if (type == 'text')
                  TextField(controller: textController, maxLines: 5, decoration: const InputDecoration(labelText: 'Content', border: OutlineInputBorder()))
                else
                  TextField(controller: urlController, decoration: const InputDecoration(labelText: 'URL', border: OutlineInputBorder())),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      if (titleController.text.trim().isEmpty) return;
                      try {
                        await _client.from('classroom_lessons').insert({
                          'classroom_id': widget.classroomId,
                          'title': titleController.text.trim(),
                          'content_type': type,
                          'content_url': type == 'text' ? null : urlController.text.trim(),
                          'content_text': type == 'text' ? textController.text.trim() : null,
                          'position': _lessons.length,
                        });
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (_) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create lesson.')));
                      }
                    },
                    child: const Text('Create lesson'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (created == true) _load();
  }

  Future<void> _delete(int lessonId) async {
    try {
      await _client.from('classroom_lessons').delete().eq('id', lessonId);
      _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete lesson.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _openCreateSheet, icon: const Icon(Icons.add), label: const Text('New lesson')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lessons.isEmpty
              ? const Center(child: Text('No lessons yet — tap + to add one'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: _lessons.length,
                    itemBuilder: (context, index) {
                      final l = _lessons[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(l['title'] as String),
                          subtitle: Text((l['content_type'] as String).toUpperCase()),
                          trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red), onPressed: () => _delete(l['id'] as int)),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ---------------------------------------------------------------------------
// Assignments (create + list + view submissions/grade)
// ---------------------------------------------------------------------------
class _AssignmentsTab extends StatefulWidget {
  final int classroomId;
  const _AssignmentsTab({required this.classroomId});

  @override
  State<_AssignmentsTab> createState() => _AssignmentsTabState();
}

class _AssignmentsTabState extends State<_AssignmentsTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _assignments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _client.from('classroom_assignments').select().eq('classroom_id', widget.classroomId).order('created_at', ascending: false);
      setState(() => _assignments = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Non-fatal.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreateSheet() async {
    final titleController = TextEditingController();
    final instructionsController = TextEditingController();
    String type = 'homework';

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: StatefulBuilder(
          builder: (context, setSheetState) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('New assignment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'question', child: Text('Question')),
                    DropdownMenuItem(value: 'homework', child: Text('Homework')),
                    DropdownMenuItem(value: 'test', child: Text('Test')),
                    DropdownMenuItem(value: 'practice', child: Text('Practice')),
                  ],
                  onChanged: (v) => setSheetState(() => type = v!),
                ),
                const SizedBox(height: 12),
                TextField(controller: instructionsController, maxLines: 4, decoration: const InputDecoration(labelText: 'Instructions', border: OutlineInputBorder())),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      if (titleController.text.trim().isEmpty) return;
                      try {
                        await _client.from('classroom_assignments').insert({
                          'classroom_id': widget.classroomId,
                          'title': titleController.text.trim(),
                          'type': type,
                          'instructions': instructionsController.text.trim(),
                        });
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (_) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create assignment.')));
                      }
                    },
                    child: const Text('Create assignment'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (created == true) _load();
  }

  Future<void> _viewSubmissions(int assignmentId, String assignmentTitle) async {
    List<Map<String, dynamic>> submissions = [];
    try {
      final rows = await _client.from('classroom_assignment_submissions').select().eq('assignment_id', assignmentId);
      submissions = List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      // Show empty on failure.
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Submissions: $assignmentTitle', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Expanded(
                child: submissions.isEmpty
                    ? const Center(child: Text('No submissions yet'))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: submissions.length,
                        itemBuilder: (context, index) {
                          final s = submissions[index];
                          final scoreController = TextEditingController(text: s['score']?.toString() ?? '');
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s['student_id'] as String, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                                  const SizedBox(height: 6),
                                  Text(s['content'] as String? ?? ''),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: scoreController,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(labelText: 'Score', isDense: true, border: OutlineInputBorder()),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton(
                                        onPressed: () async {
                                          final score = double.tryParse(scoreController.text);
                                          if (score == null) return;
                                          await _client.from('classroom_assignment_submissions').update({'score': score}).eq('id', s['id']);
                                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
                                        },
                                        child: const Text('Save'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _openCreateSheet, icon: const Icon(Icons.add), label: const Text('New assignment')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _assignments.isEmpty
              ? const Center(child: Text('No assignments yet — tap + to add one'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: _assignments.length,
                    itemBuilder: (context, index) {
                      final a = _assignments[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: Chip(label: Text(a['type'] as String), visualDensity: VisualDensity.compact),
                          title: Text(a['title'] as String),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _viewSubmissions(a['id'] as int, a['title'] as String),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ---------------------------------------------------------------------------
// Announcements (compose + list)
// ---------------------------------------------------------------------------
class _AnnouncementsComposeTab extends StatefulWidget {
  final int classroomId;
  const _AnnouncementsComposeTab({required this.classroomId});

  @override
  State<_AnnouncementsComposeTab> createState() => _AnnouncementsComposeTabState();
}

class _AnnouncementsComposeTabState extends State<_AnnouncementsComposeTab> {
  final _client = Supabase.instance.client;
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _announcements = [];
  bool _loading = true;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _client.from('classroom_announcements').select().eq('classroom_id', widget.classroomId).order('created_at', ascending: false);
      setState(() => _announcements = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Non-fatal.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    try {
      await _client.from('classroom_announcements').insert({
        'classroom_id': widget.classroomId,
        'tutor_id': _client.auth.currentUser!.id,
        'message': text,
      });
      _controller.clear();
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post announcement.')));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(hintText: 'Post an update to your students...', border: OutlineInputBorder(), isDense: true),
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _posting ? null : _post, child: const Text('Post')),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _announcements.isEmpty
                  ? const Center(child: Text('No announcements yet'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                                  Text(DateFormat('MMM d, yyyy • h:mm a').format(DateTime.parse(a['created_at'])), style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
