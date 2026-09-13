// lib/my_classrooms.dart
//
// "My Classrooms" — embeddable widget (no own Scaffold/AppBar), lives
// inside classes_home.dart alongside Discover Classes.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'classroom_home.dart';

class MyClassroomsTab extends StatefulWidget {
  const MyClassroomsTab({super.key});

  @override
  State<MyClassroomsTab> createState() => _MyClassroomsTabState();
}

class _MyClassroomsTabState extends State<MyClassroomsTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _enrollments = [];
  Map<int, ({int total, int completed})> _progress = {};
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

      final enrollments = List<Map<String, dynamic>>.from(rows);
      final progress = <int, ({int total, int completed})>{};

      for (final e in enrollments) {
        final classroom = e['classrooms'] as Map<String, dynamic>?;
        if (classroom == null) continue;
        final classroomId = classroom['id'] as int;
        try {
          final lessons = await _client.from('classroom_lessons').select('id').eq('classroom_id', classroomId);
          final lessonIds = (lessons as List).map((l) => l['id'] as int).toList();
          int completed = 0;
          if (lessonIds.isNotEmpty) {
            final completions = await _client
                .from('classroom_lesson_completions')
                .select('lesson_id')
                .eq('student_id', userId)
                .inFilter('lesson_id', lessonIds);
            completed = (completions as List).length;
          }
          progress[classroomId] = (total: lessonIds.length, completed: completed);
        } catch (_) {
          // Non-fatal — progress just won't show for this classroom.
        }
      }

      setState(() {
        _enrollments = enrollments;
        _progress = progress;
      });
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
    if (_enrollments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text("You haven't joined any classes yet"),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _enrollments.length,
        itemBuilder: (context, index) {
          final enrollment = _enrollments[index];
          final classroom = enrollment['classrooms'] as Map<String, dynamic>?;
          if (classroom == null) return const SizedBox.shrink();

          final classroomId = classroom['id'] as int;
          final expiresAt = enrollment['expires_at'] as String?;
          final p = _progress[classroomId];
          final progressValue = (p != null && p.total > 0) ? p.completed / p.total : null;

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
                            Text(
                              expiresAt != null
                                  ? 'Access expires ${DateFormat('MMM d, yyyy').format(DateTime.parse(expiresAt))}'
                                  : 'Unlimited access',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (progressValue != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progressValue, minHeight: 6)),
                    const SizedBox(height: 4),
                    Text('${p!.completed}/${p.total} lessons completed', style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClassroomHomeScreen(classroomId: classroomId))),
                      child: const Text('Open'),
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
