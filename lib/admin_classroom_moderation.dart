// lib/admin_classroom_moderation.dart
//
// Admin moderation surface for the Tutor Classroom system: classroom
// status control, open reports, and manual refunds. Payout batching
// (admin_mark_payout_paid) is intentionally not wired to a button here
// yet — see QUESTIONS_FOR_TEAM.md #9.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminClassroomModerationScreen extends StatefulWidget {
  const AdminClassroomModerationScreen({super.key});

  @override
  State<AdminClassroomModerationScreen> createState() => _AdminClassroomModerationScreenState();
}

class _AdminClassroomModerationScreenState extends State<AdminClassroomModerationScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classroom moderation'),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Classrooms'), Tab(text: 'Reports')]),
      ),
      body: TabBarView(controller: _tabController, children: const [_ClassroomsTab(), _ReportsTab()]),
    );
  }
}

class _ClassroomsTab extends StatefulWidget {
  const _ClassroomsTab();

  @override
  State<_ClassroomsTab> createState() => _ClassroomsTabState();
}

class _ClassroomsTabState extends State<_ClassroomsTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _classrooms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _client.from('classrooms').select().order('created_at', ascending: false).limit(100);
      setState(() => _classrooms = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Non-fatal.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(int classroomId, String status) async {
    final reason = status == 'active'
        ? null
        : await showDialog<String>(
            context: context,
            builder: (context) {
              final controller = TextEditingController();
              return AlertDialog(
                title: Text('${status == 'suspended' ? 'Suspend' : 'Disable'} classroom'),
                content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Reason')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => Navigator.pop(context, controller.text.trim()),
                    child: const Text('Confirm'),
                  ),
                ],
              );
            },
          );
    if (status != 'active' && (reason == null || reason.isEmpty)) return;

    try {
      await _client.rpc('admin_set_classroom_status', params: {
        'p_classroom_id': classroomId,
        'p_status': status,
        'p_reason': reason,
      });
      _load();
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'suspended':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_classrooms.isEmpty) return const Center(child: Text('No classrooms yet'));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _classrooms.length,
        itemBuilder: (context, index) {
          final c = _classrooms[index];
          final status = c['status'] as String;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold))),
                      Chip(label: Text(status.toUpperCase()), backgroundColor: _statusColor(status).withOpacity(0.15)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${c['student_count']}/${c['capacity']} students · ${c['subject']}'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (status != 'active')
                        OutlinedButton(onPressed: () => _setStatus(c['id'] as int, 'active'), child: const Text('Reactivate')),
                      if (status != 'suspended')
                        OutlinedButton(onPressed: () => _setStatus(c['id'] as int, 'suspended'), child: const Text('Suspend')),
                      if (status != 'disabled')
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                          onPressed: () => _setStatus(c['id'] as int, 'disabled'),
                          child: const Text('Disable'),
                        ),
                    ],
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

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _client.from('classroom_reports').select().eq('status', 'open').order('created_at', ascending: true);
      setState(() => _reports = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Non-fatal.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(int reportId, String status) async {
    try {
      await _client.from('classroom_reports').update({
        'status': status,
        'reviewed_by': _client.auth.currentUser!.id,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', reportId);
      _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update report.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_reports.isEmpty) return const Center(child: Text('No open reports'));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _reports.length,
        itemBuilder: (context, index) {
          final r = _reports[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Classroom #${r['classroom_id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(r['reason'] as String),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton(onPressed: () => _review(r['id'] as int, 'dismissed'), child: const Text('Dismiss')),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: () => _review(r['id'] as int, 'reviewed'), child: const Text('Mark reviewed')),
                    ],
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
