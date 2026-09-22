// lib/classes_home.dart
//
// Single "Classes" entry point per the navigation decision: no separate
// top-level screens for Discover/My Classrooms, and no permanent
// bottom-nav tab exclusively for tutors. This screen hosts both via a
// segmented toggle, plus the Become a Tutor CTA and (for approved
// tutors) a way into their Tutor Dashboard.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_enhancements.dart' show GradientHeader;
import 'become_tutor.dart';
import 'classroom_discovery.dart';
import 'classroom_shared.dart' show isEligibleForTutorCta;
import 'create_classroom.dart';
import 'my_classrooms.dart';
import 'tutor_dashboard.dart';

enum _ClassesTab { discover, mine }

class ClassesHomeScreen extends StatefulWidget {
  const ClassesHomeScreen({super.key});

  @override
  State<ClassesHomeScreen> createState() => _ClassesHomeScreenState();
}

class _ClassesHomeScreenState extends State<ClassesHomeScreen> {
  final _client = Supabase.instance.client;
  _ClassesTab _tab = _ClassesTab.discover;

  bool _loadingTutorStatus = true;
  bool _tutorStatusLoadFailed = false;
  String? _tutorStatus; // null | pending | approved | rejected | suspended

  @override
  void initState() {
    super.initState();
    _loadTutorStatus();
  }

  Future<void> _loadTutorStatus() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _loadingTutorStatus = false);
      return;
    }
    try {
      final row = await _client.from('tutor_profiles').select('status').eq('user_id', userId).maybeSingle();
      if (mounted) {
        setState(() {
          _tutorStatus = row?['status'] as String?;
          _tutorStatusLoadFailed = false;
        });
      }
    } catch (_) {
      // FAIL OPEN, not closed: if we can't verify status, show the
      // entry point anyway rather than silently hiding it. A real
      // non-tutor tapping it just gets told so — that's a minor UI
      // cost, far better than a genuine tutor never seeing the button
      // at all with no way to know why.
      if (mounted) setState(() => _tutorStatusLoadFailed = true);
    } finally {
      if (mounted) setState(() => _loadingTutorStatus = false);
    }
  }

  Future<void> _openTutorDashboard() async {
    // Never trust a stale/failed cached status for something this
    // important — re-check live, right now, before deciding anything.
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    String? liveStatus;
    try {
      final row = await _client.from('tutor_profiles').select('status').eq('user_id', userId).maybeSingle();
      liveStatus = row?['status'] as String?;
      if (mounted) setState(() => _tutorStatus = liveStatus);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not verify your tutor status — check your connection and try again.')),
        );
      }
      return;
    }

    if (liveStatus != 'approved') {
      if (!mounted) return;
      final message = switch (liveStatus) {
        'pending' => 'Your tutor application is still under review.',
        'rejected' => 'Your tutor application was not approved.',
        'suspended' => 'Your tutor account is currently suspended.',
        _ => "You're not an approved tutor yet.",
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    try {
      final classrooms = await _client
          .from('classrooms')
          .select('id, name, student_count, capacity')
          .eq('tutor_id', userId)
          .order('created_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(classrooms);
      if (!mounted) return;

      // Always show the picker — even with zero or one classroom —
      // so "Create new classroom" is never hidden behind a branch that
      // skips straight into managing an existing one.
      showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (rows.isNotEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Text('Your classrooms', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
              ...rows.map((c) => ListTile(
                    title: Text(c['name'] as String),
                    subtitle: Text('${c['student_count']}/${c['capacity'] ?? "Unlimited"} students'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => TutorDashboardScreen(classroomId: c['id'] as int)));
                    },
                  )),
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: Text(rows.isEmpty ? 'Create your first classroom' : 'Create another classroom'),
                onTap: () async {
                  Navigator.pop(context);
                  final created = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateClassroomScreen()));
                  if (created != null && mounted) {
                    final classroom = Map<String, dynamic>.from(created as Map);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => TutorDashboardScreen(classroomId: classroom['id'] as int)));
                  }
                },
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load your classrooms.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final showTutorDashboardIcon = _tutorStatus == 'approved' || _tutorStatusLoadFailed;

    return Scaffold(
      body: Column(
        children: [
          const GradientHeader(title: 'Learn with a tutor. Learn with a class.', subtitle: 'Join structured classrooms built for serious students.'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<_ClassesTab>(
                    segments: const [
                      ButtonSegment(value: _ClassesTab.discover, label: Text('Discover Classes')),
                      ButtonSegment(value: _ClassesTab.mine, label: Text('My Classrooms')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
                if (showTutorDashboardIcon) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _openTutorDashboard,
                    icon: const Icon(Icons.dashboard_outlined),
                    tooltip: 'Tutor Dashboard',
                  ),
                ],
              ],
            ),
          ),

          if (!_loadingTutorStatus && _tutorStatus == null && _tab == _ClassesTab.discover && isEligibleForTutorCta())
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BecomeTutorScreen())),
                icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                label: const Text('Know a subject well? Teach on NaijaLearn'),
              ),
            ),

          if (!_loadingTutorStatus && _tutorStatus == 'pending' && _tab == _ClassesTab.discover)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.amber.withOpacity(0.4))),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Your tutor application is under review.', style: TextStyle(fontSize: 12.5))),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 8),
          Expanded(
            child: _tab == _ClassesTab.discover ? const ClassroomDiscoveryTab() : const MyClassroomsTab(),
          ),
        ],
      ),
    );
  }
}
