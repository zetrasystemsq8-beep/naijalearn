// lib/my_classrooms.dart
//
// "My Classrooms" — embeddable widget (no own Scaffold/AppBar), lives
// inside classes_home.dart alongside Discover Classes. Useful-at-a-glance
// per the polish pass: tutor name, progress, pending assignments,
// expiry/expired state.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'classroom_home.dart';

class MyClassroomsTab extends StatefulWidget {
  const MyClassroomsTab({super.key});

  @override
  State<MyClassroomsTab> createState() => _MyClassroomsTabState();
}

class _ClassroomCardData {
  final Map<String, dynamic> classroom;
  final Map<String, dynamic> enrollment;
  String tutorName = 'Tutor';
  int totalLessons = 0;
  int completedLessons = 0;
  int pendingAssignments = 0;
  _ClassroomCardData(this.classroom, this.enrollment);
}

class _MyClassroomsTabState extends State<MyClassroomsTab> {
  final _client = Supabase.instance.client;
  List<_ClassroomCardData> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _error = 'Please sign in.');
        return;
      }

      // classrooms(*) pulls the related classroom row via the FK —
      // adjust the embed name if your Supabase relationship alias differs.
      final rows = await _client
          .from('classroom_enrollments')
          .select('*, classrooms(*)')
          .eq('student_id', userId)
          .eq('status', 'active')
          .order('joined_at', ascending: false);

      final items = <_ClassroomCardData>[];
      final tutorIds = <String>{};

      for (final row in (rows as List)) {
        final classroom = row['classrooms'] as Map<String, dynamic>?;
        if (classroom == null) continue;
        final data = _ClassroomCardData(classroom, Map<String, dynamic>.from(row));
        items.add(data);
        tutorIds.add(classroom['tutor_id'] as String);
      }

      // Tutor names — classrooms.tutor_id and tutor_profiles.user_id both
      // reference auth.users but aren't FK-linked to each other, so this
      // is a separate lookup rather than a Postgrest embed.
      Map<String, String> tutorNames = {};
      if (tutorIds.isNotEmpty) {
        final tutorRows = await _client.from('tutor_profiles').select('user_id, full_name').inFilter('user_id', tutorIds.toList());
        tutorNames = {for (final t in (tutorRows as List)) t['user_id'] as String: t['full_name'] as String};
      }

      for (final item in items) {
        item.tutorName = tutorNames[item.classroom['tutor_id']] ?? 'Tutor';
        final classroomId = item.classroom['id'] as int;
        try {
          final lessons = await _client.from('classroom_lessons').select('id').eq('classroom_id', classroomId);
          final lessonIds = (lessons as List).map((l) => l['id'] as int).toList();
          item.totalLessons = lessonIds.length;
          if (lessonIds.isNotEmpty) {
            final completions = await _client
                .from('classroom_lesson_completions')
                .select('lesson_id')
                .eq('student_id', userId)
                .inFilter('lesson_id', lessonIds);
            item.completedLessons = (completions as List).length;
          }

          final assignments = await _client.from('classroom_assignments').select('id').eq('classroom_id', classroomId);
          final assignmentIds = (assignments as List).map((a) => a['id'] as int).toList();
          if (assignmentIds.isNotEmpty) {
            final submissions = await _client
                .from('classroom_assignment_submissions')
                .select('assignment_id')
                .eq('student_id', userId)
                .inFilter('assignment_id', assignmentIds);
            final submittedIds = (submissions as List).map((s) => s['assignment_id'] as int).toSet();
            item.pendingAssignments = assignmentIds.where((id) => !submittedIds.contains(id)).length;
          }
        } catch (_) {
          // Non-fatal — that classroom's card just shows without progress.
        }
      }

      setState(() => _items = items);
    } catch (e) {
      setState(() => _error = 'Could not load your classrooms.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text("You haven't joined any classes yet", style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Browse Discover Classes to find a tutor.', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          final classroom = item.classroom;
          final classroomId = classroom['id'] as int;
          final expiresAt = item.enrollment['expires_at'] as String?;
          final expiryDate = expiresAt != null ? DateTime.tryParse(expiresAt) : null;
          final isExpired = expiryDate != null && expiryDate.isBefore(DateTime.now());
          final progress = item.totalLessons > 0 ? item.completedLessons / item.totalLessons : null;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: scheme.primaryContainer,
                        backgroundImage: classroom['cover_image_url'] != null ? NetworkImage(classroom['cover_image_url']) : null,
                        child: classroom['cover_image_url'] == null ? Icon(Icons.school_rounded, color: scheme.onPrimaryContainer) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(classroom['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('${item.tutorName} • ${classroom['subject']}', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      if (isExpired)
                        Chip(label: const Text('Expired'), backgroundColor: scheme.errorContainer, labelStyle: TextStyle(color: scheme.error, fontSize: 11)),
                    ],
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Progress: ${(progress * 100).round()}%', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        if (!isExpired && expiryDate != null)
                          Text('Expires ${DateFormat('MMM d, yyyy').format(expiryDate)}', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 6)),
                  ] else if (!isExpired && expiryDate != null) ...[
                    const SizedBox(height: 8),
                    Text('Expires ${DateFormat('MMM d, yyyy').format(expiryDate)}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (item.pendingAssignments > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.assignment_late_outlined, size: 14, color: Colors.orange.shade800),
                        const SizedBox(width: 6),
                        Text('${item.pendingAssignments} assignment${item.pendingAssignments > 1 ? 's' : ''} pending', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClassroomHomeScreen(classroomId: classroomId))),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: Text(isExpired ? 'View classroom' : 'Continue Learning'),
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
