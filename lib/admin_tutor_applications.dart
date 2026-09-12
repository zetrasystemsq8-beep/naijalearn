// lib/admin_tutor_applications.dart
//
// Admin review queue for tutor applications. Separate screen from
// admin_panel.dart (which is scoped to payment verification) — wire this
// into your admin menu/navigation.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const List<String> _rejectionReasons = [
  'Incomplete information',
  'Unclear teaching description',
  'Subjects not currently accepted',
  'Suspicious or fake profile',
  'Other',
];

class AdminTutorApplicationsScreen extends StatefulWidget {
  const AdminTutorApplicationsScreen({super.key});

  @override
  State<AdminTutorApplicationsScreen> createState() => _AdminTutorApplicationsScreenState();
}

class _AdminTutorApplicationsScreenState extends State<AdminTutorApplicationsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _applications = [];
  bool _loading = true;
  String? _error;
  final Map<int, bool> _busy = {};

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
      final rows = await _client
          .from('tutor_profiles')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: true);
      setState(() => _applications = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      setState(() => _error = 'Failed to load applications: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(int id) async {
    setState(() => _busy[id] = true);
    try {
      await _client.rpc('admin_review_tutor_application', params: {
        'p_tutor_profile_id': id,
        'p_decision': 'approve',
      });
      _snack('Tutor approved', Colors.green);
      await _load();
    } on PostgrestException catch (e) {
      _snack(e.message, Colors.red);
    } finally {
      if (mounted) setState(() => _busy[id] = false);
    }
  }

  Future<void> _reject(int id) async {
    String selected = _rejectionReasons.first;
    final otherController = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reject application'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._rejectionReasons.map((r) => RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r),
                    value: r,
                    groupValue: selected,
                    onChanged: (v) => setDialogState(() => selected = v!),
                  )),
              if (selected == 'Other')
                TextField(controller: otherController, decoration: const InputDecoration(hintText: 'Reason')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, selected == 'Other' ? otherController.text.trim() : selected),
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty) return;

    setState(() => _busy[id] = true);
    try {
      await _client.rpc('admin_review_tutor_application', params: {
        'p_tutor_profile_id': id,
        'p_decision': 'reject',
        'p_rejection_reason': reason,
      });
      _snack('Application rejected', Colors.orange);
      await _load();
    } on PostgrestException catch (e) {
      _snack(e.message, Colors.red);
    } finally {
      if (mounted) setState(() => _busy[id] = false);
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tutor applications'),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _applications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 48, color: scheme.primary),
                          const SizedBox(height: 12),
                          const Text('No pending applications'),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _applications.length,
                        itemBuilder: (context, index) {
                          final app = _applications[index];
                          final id = app['id'] as int;
                          final subjects = (app['subjects'] as List?)?.cast<String>() ?? [];
                          final busy = _busy[id] ?? false;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: scheme.outline),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundImage: app['photo_url'] != null ? NetworkImage(app['photo_url']) : null,
                                      child: app['photo_url'] == null ? const Icon(Icons.person) : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(app['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                          Text(
                                            DateFormat('MMM d, yyyy').format(DateTime.parse(app['created_at'])),
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(spacing: 6, runSpacing: 6, children: subjects.map((s) => Chip(label: Text(s), visualDensity: VisualDensity.compact)).toList()),
                                if ((app['description'] as String?)?.isNotEmpty ?? false) ...[
                                  const SizedBox(height: 8),
                                  Text('About: ${app['description']}', style: Theme.of(context).textTheme.bodySmall),
                                ],
                                if ((app['experience'] as String?)?.isNotEmpty ?? false) ...[
                                  const SizedBox(height: 6),
                                  Text('Experience: ${app['experience']}', style: Theme.of(context).textTheme.bodySmall),
                                ],
                                const SizedBox(height: 6),
                                Text('Motivation: ${app['motivation']}', style: Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: busy ? null : () => _approve(id),
                                        style: FilledButton.styleFrom(backgroundColor: Colors.green),
                                        child: const Text('Approve'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton.tonal(
                                        onPressed: busy ? null : () => _reject(id),
                                        style: FilledButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1), foregroundColor: Colors.red),
                                        child: const Text('Reject'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
