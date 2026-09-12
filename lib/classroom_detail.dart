// lib/classroom_detail.dart
//
// Public classroom page. Joining calls join_classroom, which debits the
// student's Cent wallet and activates the enrollment atomically — this
// screen never grants access on its own. The invite link
// (NLCLASS-xxxxx style) should deep-link here with the classroom id; it
// must never skip the Join button, per spec ("the link must NOT
// automatically grant access").

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'buy_cent.dart';
import 'classroom_home.dart';

class ClassroomDetailScreen extends StatefulWidget {
  final int classroomId;
  const ClassroomDetailScreen({super.key, required this.classroomId});

  @override
  State<ClassroomDetailScreen> createState() => _ClassroomDetailScreenState();
}

class _ClassroomDetailScreenState extends State<ClassroomDetailScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _classroom;
  Map<String, dynamic>? _tutorProfile;
  bool _loading = true;
  bool _joining = false;
  bool _alreadyEnrolled = false;
  bool _isOwner = false;
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
      final classroom = await _client.from('classrooms').select().eq('id', widget.classroomId).single();
      final tutorProfile = await _client
          .from('tutor_profiles')
          .select('full_name, photo_url')
          .eq('user_id', classroom['tutor_id'])
          .maybeSingle();

      final userId = _client.auth.currentUser?.id;
      bool enrolled = false;
      if (userId != null) {
        final enrollment = await _client
            .from('classroom_enrollments')
            .select('id')
            .eq('classroom_id', widget.classroomId)
            .eq('student_id', userId)
            .eq('status', 'active')
            .maybeSingle();
        enrolled = enrollment != null;
      }

      setState(() {
        _classroom = Map<String, dynamic>.from(classroom);
        _tutorProfile = tutorProfile != null ? Map<String, dynamic>.from(tutorProfile) : null;
        _alreadyEnrolled = enrolled;
        _isOwner = classroom['tutor_id'] == userId;
      });
    } catch (e) {
      setState(() => _error = 'Could not load this classroom.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      await _client.rpc('join_classroom', params: {'p_classroom_id': widget.classroomId});
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ClassroomHomeScreen(classroomId: widget.classroomId)),
        );
      }
    } on PostgrestException catch (e) {
      if (e.message.toLowerCase().contains('insufficient')) {
        _showInsufficientBalanceDialog();
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      setState(() => _error = 'Could not join this classroom. Please try again.');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _showInsufficientBalanceDialog() {
    final price = _classroom?['price_cent'] as int? ?? 0;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Not enough Cent'),
        content: Text('Joining this class costs $price Cent. Your wallet balance is too low — top up first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const BuyCentScreen()));
            },
            child: const Text('Buy Cent'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_classroom == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(_error ?? 'Classroom not found')));
    }

    final scheme = Theme.of(context).colorScheme;
    final c = _classroom!;
    final name = c['name'] as String;
    final subject = c['subject'] as String;
    final description = c['description'] as String? ?? '';
    final studentCount = c['student_count'] as int;
    final capacity = c['capacity'] as int;
    final isPaid = c['is_paid'] as bool;
    final priceCent = c['price_cent'] as int;
    final durationDays = c['duration_days'] as int?;
    final coverUrl = c['cover_image_url'] as String?;
    final tutorName = _tutorProfile?['full_name'] as String? ?? 'Tutor';
    final isFull = studentCount >= capacity;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: coverUrl != null
                  ? Image.network(coverUrl, fit: BoxFit.cover)
                  : Container(color: scheme.primaryContainer, child: Icon(Icons.school_rounded, size: 48, color: scheme.onPrimaryContainer)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundImage: _tutorProfile?['photo_url'] != null ? NetworkImage(_tutorProfile!['photo_url']) : null,
                      child: _tutorProfile?['photo_url'] == null ? const Icon(Icons.person, size: 16) : null,
                    ),
                    const SizedBox(width: 8),
                    Text('Tutor: $tutorName', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
                const SizedBox(height: 16),
                if (description.isNotEmpty) ...[
                  Text(description, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                ],

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    children: [
                      _InfoRow(icon: Icons.subject_rounded, label: 'Subject', value: subject),
                      const Divider(height: 20),
                      _InfoRow(icon: Icons.people_outline_rounded, label: 'Students', value: '$studentCount/$capacity'),
                      const Divider(height: 20),
                      _InfoRow(icon: Icons.payments_outlined, label: 'Price', value: isPaid ? '₦$priceCent' : 'Free'),
                      const Divider(height: 20),
                      _InfoRow(
                        icon: Icons.timelapse_rounded,
                        label: 'Access',
                        value: durationDays != null ? '$durationDays-day access' : 'Unlimited access',
                      ),
                    ],
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  height: 54,
                  child: _isOwner
                      ? FilledButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClassroomHomeScreen(classroomId: widget.classroomId))),
                          icon: const Icon(Icons.dashboard_outlined),
                          label: const Text('Manage classroom'),
                        )
                      : _alreadyEnrolled
                          ? FilledButton.icon(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClassroomHomeScreen(classroomId: widget.classroomId))),
                              icon: const Icon(Icons.login_rounded),
                              label: const Text('Go to classroom'),
                            )
                          : FilledButton(
                              onPressed: (isFull || _joining) ? null : _join,
                              child: _joining
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                  : Text(
                                      isFull ? 'Classroom full' : (isPaid ? 'Join Class — ₦$priceCent' : 'Join Free Class'),
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                            ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
