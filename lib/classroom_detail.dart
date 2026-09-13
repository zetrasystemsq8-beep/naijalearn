// lib/classroom_detail.dart
//
// The student's decision page. Joining calls join_classroom, which
// debits the student's Cent wallet and activates the enrollment
// atomically — this screen never grants access on its own. The invite
// code/link opens here, never straight into the classroom.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_enhancements.dart' show GradientButton;
import 'buy_cent.dart';
import 'classroom_home.dart';
import 'classroom_shared.dart' show formatCpCent;
import 'zetra_pay.dart';

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
  List<String> _lessonTitles = [];
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
          .select('full_name, photo_url, subjects')
          .eq('user_id', classroom['tutor_id'])
          .maybeSingle();

      final lessons = await _client
          .from('classroom_lessons')
          .select('title')
          .eq('classroom_id', widget.classroomId)
          .order('position')
          .limit(6);

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
        _lessonTitles = (lessons as List).map((l) => l['title'] as String).toList();
        _alreadyEnrolled = enrolled;
        _isOwner = classroom['tutor_id'] == userId;
      });
    } catch (e) {
      setState(() => _error = 'Could not load this classroom.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showJoinConfirmation() async {
    final c = _classroom!;
    final priceCent = c['price_cent'] as int;
    final isPaid = c['is_paid'] as bool;
    final name = c['name'] as String;

    int currentBalance = 0;
    try {
      currentBalance = (await ZetraPay.getAppCurrencyBalance(ZetraPay.naijaLearnAppId)).round();
    } catch (_) {
      // If this fails, the dialog still works — it just won't show a
      // balance preview. The RPC is still the actual source of truth.
    }

    if (!mounted) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final after = currentBalance - priceCent;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Join $name?', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (isPaid)
                Text("You'll spend ${formatCpCent(priceCent)} from your NaijaLearn balance.", style: Theme.of(context).textTheme.bodyMedium)
              else
                Text('This is a free classroom — no charge to join.', style: Theme.of(context).textTheme.bodyMedium),

              if (isPaid) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Your balance'),
                          Text(formatCpCent(currentBalance), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('After joining'),
                          Text(
                            formatCpCent(after < 0 ? 0 : after),
                            style: TextStyle(fontWeight: FontWeight.bold, color: after < 0 ? scheme.error : scheme.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Text(
                "You'll get access to the classroom's lessons, assignments, tests and announcements.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),

              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Join Classroom')),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) _join();
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
          MaterialPageRoute(builder: (_) => _JoinSuccessScreen(classroomId: widget.classroomId, classroomName: _classroom!['name'] as String)),
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
        title: const Text('Not enough balance'),
        content: Text('Joining this class costs ${formatCpCent(price)}. Top up your wallet first.'),
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
    final examCategory = c['exam_category'] as String;
    final description = c['description'] as String? ?? '';
    final introInfo = c['intro_info'] as String? ?? '';
    final rules = c['rules'] as String? ?? '';
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
                // ---- Hero ----
                Row(
                  children: [
                    Expanded(child: Text(name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
                    if (examCategory != 'General/Other') Chip(label: Text(examCategory), visualDensity: VisualDensity.compact),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundImage: _tutorProfile?['photo_url'] != null ? NetworkImage(_tutorProfile!['photo_url']) : null,
                      child: _tutorProfile?['photo_url'] == null ? const Icon(Icons.person, size: 16) : null,
                    ),
                    const SizedBox(width: 8),
                    Text(tutorName, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Icon(Icons.verified_rounded, size: 15, color: scheme.primary),
                  ],
                ),
                const SizedBox(height: 4),
                Text(subject, style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _StatChip(icon: Icons.people_outline_rounded, label: '$studentCount/$capacity students'),
                    _StatChip(icon: Icons.timelapse_rounded, label: durationDays != null ? '$durationDays days' : 'Unlimited'),
                  ],
                ),

                const SizedBox(height: 20),
                Text(
                  isPaid ? formatCpCent(priceCent) : 'Free',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: isPaid ? scheme.primary : Colors.green),
                ),

                const Divider(height: 36),

                // ---- What You'll Get ----
                Text("What You'll Get", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const _FeatureRow(icon: Icons.menu_book_rounded, label: 'Structured Lessons'),
                const _FeatureRow(icon: Icons.assignment_outlined, label: 'Assignments & Tests'),
                const _FeatureRow(icon: Icons.campaign_outlined, label: 'Tutor Announcements'),
                const _FeatureRow(icon: Icons.forum_outlined, label: 'Classroom Discussion'),
                const _FeatureRow(icon: Icons.trending_up_rounded, label: 'Learning Progress'),

                if (description.isNotEmpty || introInfo.isNotEmpty) ...[
                  const Divider(height: 36),
                  Text('About This Classroom', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (description.isNotEmpty) Text(description, style: Theme.of(context).textTheme.bodyMedium),
                  if (introInfo.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(introInfo, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ],

                if (_lessonTitles.isNotEmpty) ...[
                  const Divider(height: 36),
                  Text("What You'll Learn", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ..._lessonTitles.map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 16, color: scheme.primary),
                            const SizedBox(width: 8),
                            Expanded(child: Text(t)),
                          ],
                        ),
                      )),
                ],

                if (rules.isNotEmpty) ...[
                  const Divider(height: 36),
                  Text('Classroom Rules', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(rules, style: Theme.of(context).textTheme.bodyMedium),
                ],

                const Divider(height: 36),
                Text('Tutor', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundImage: _tutorProfile?['photo_url'] != null ? NetworkImage(_tutorProfile!['photo_url']) : null,
                      child: _tutorProfile?['photo_url'] == null ? const Icon(Icons.person) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(tutorName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            Icon(Icons.verified_rounded, size: 15, color: scheme.primary),
                          ]),
                          if ((_tutorProfile?['subjects'] as List?)?.isNotEmpty ?? false)
                            Text((_tutorProfile!['subjects'] as List).join(', '), style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                ],

                const SizedBox(height: 28),
                if (_isOwner)
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClassroomHomeScreen(classroomId: widget.classroomId))),
                      icon: const Icon(Icons.dashboard_outlined),
                      label: const Text('Manage classroom'),
                    ),
                  )
                else if (_alreadyEnrolled)
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClassroomHomeScreen(classroomId: widget.classroomId))),
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Go to classroom'),
                    ),
                  )
                else if (isFull)
                  const SizedBox(
                    height: 54,
                    child: Center(child: Text('Classroom full', style: TextStyle(fontWeight: FontWeight.w600))),
                  )
                else
                  GradientButton(
                    label: _joining ? 'Joining...' : (isPaid ? 'Join for ${formatCpCent(priceCent)}' : 'Join Free Class'),
                    icon: Icons.login_rounded,
                    onPressed: _joining ? null : _showJoinConfirmation,
                    height: 54,
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _JoinSuccessScreen extends StatelessWidget {
  final int classroomId;
  final String classroomName;
  const _JoinSuccessScreen({required this.classroomId, required this.classroomName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎓', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text("You're in!", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Welcome to $classroomName.\nYour classroom is ready.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ClassroomHomeScreen(classroomId: classroomId))),
                  child: const Text('Enter Classroom', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
