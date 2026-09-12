// lib/my_classrooms.dart
//
// Student's enrolled classrooms. Also surfaces classrooms the user
// teaches (as a shortcut into TutorDashboardScreen via ClassroomHomeScreen,
// which already redirects tutors there).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'classroom_home.dart';

class MyClassroomsScreen extends StatefulWidget {
  const MyClassroomsScreen({super.key});

  @override
  State<MyClassroomsScreen> createState() => _MyClassroomsScreenState();
}

class _MyClassroomsScreenState extends State<MyClassroomsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _enrollments = [];
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

      setState(() => _enrollments = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      setState(() => _error = 'Could not load your classrooms.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Classrooms')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _enrollments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.school_outlined, size: 48, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          const Text("You haven't joined any classes yet"),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _enrollments.length,
                        itemBuilder: (context, index) {
                          final enrollment = _enrollments[index];
                          final classroom = enrollment['classrooms'] as Map<String, dynamic>?;
                          if (classroom == null) return const SizedBox.shrink();

                          final expiresAt = enrollment['expires_at'] as String?;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(14),
                              leading: CircleAvatar(
                                backgroundColor: scheme.primaryContainer,
                                backgroundImage: classroom['cover_image_url'] != null ? NetworkImage(classroom['cover_image_url']) : null,
                                child: classroom['cover_image_url'] == null ? Icon(Icons.school_rounded, color: scheme.onPrimaryContainer) : null,
                              ),
                              title: Text(classroom['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                expiresAt != null
                                    ? 'Access expires ${DateFormat('MMM d, yyyy').format(DateTime.parse(expiresAt))}'
                                    : 'Unlimited access',
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ClassroomHomeScreen(classroomId: classroom['id'] as int)),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
