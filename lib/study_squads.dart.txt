// lib/study_squads.dart
//
// Study Squads — small (2-20 member) study communities. A student can
// now belong to MULTIPLE squads at once. One squad is marked "active"
// at a time — that's the one that earns study XP when you answer
// questions, complete lessons, etc. Switch which squad is active from
// the squad list (tap "Set Active") or from a squad's Settings screen.
//
// MONETIZATION: a squad leader can unlock paid joining for their squad
// (500 Cent one-time, non-refundable) and set a join price up to 300
// Cent. The platform keeps 10% of every join fee; the leader gets 90%,
// credited straight to their NaijaLearn balance. A monetized squad
// cannot also require manual approval — paying is instant membership,
// no pending/refund state to manage.
//
// Every RPC call here is security-definer and keys off auth.uid() —
// nothing here trusts a client-supplied user id, so scores/XP/roles/
// payments can't be spoofed from the app.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const int kSquadMonetizeUnlockCost = 500;
const int kSquadMaxJoinPrice = 300;

class SquadInfo {
  final int id;
  final String name;
  final String description;
  final String avatarEmoji;
  final int level;
  final int xp;
  final String inviteCode;
  final bool requireApproval;
  final String myRole;
  final int memberCount;
  final bool isMonetized;
  final int joinPriceCent;
  final bool isActive;

  SquadInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.avatarEmoji,
    required this.level,
    required this.xp,
    required this.inviteCode,
    required this.requireApproval,
    required this.myRole,
    required this.memberCount,
    required this.isMonetized,
    required this.joinPriceCent,
    required this.isActive,
  });

  factory SquadInfo.fromMap(Map<String, dynamic> m) => SquadInfo(
        id: (m['id'] as num).toInt(),
        name: m['name'] as String,
        description: m['description'] as String? ?? '',
        avatarEmoji: m['avatar_emoji'] as String? ?? '📚',
        level: (m['level'] as num?)?.toInt() ?? 1,
        xp: (m['xp'] as num?)?.toInt() ?? 0,
        inviteCode: m['invite_code'] as String,
        requireApproval: m['require_approval'] as bool? ?? false,
        myRole: m['my_role'] as String,
        memberCount: (m['member_count'] as num?)?.toInt() ?? 0,
        isMonetized: m['is_monetized'] as bool? ?? false,
        joinPriceCent: (m['join_price_cent'] as num?)?.toInt() ?? 0,
        isActive: m['is_active'] as bool? ?? false,
      );

  int get xpIntoLevel => xp % 1000;
  bool get isLeader => myRole == 'leader';
  bool get canManage => myRole == 'leader' || myRole == 'co_leader';
}

/// Result of any "try to join a squad" action — join-by-code or
/// join-by-discovery both funnel through this so the UI can handle
/// "joined immediately" vs "pending approval" vs "failed" uniformly.
class SquadJoinOutcome {
  final String? error;
  final String? status; // 'joined' | 'pending'
  final int? squadId;
  const SquadJoinOutcome({this.error, this.status, this.squadId});

  bool get success => error == null;
  bool get isPending => status == 'pending';
}

/// Cap on how many co-leaders ("admins") a squad can have.
const int kSquadMaxAdmins = 3;
const int kSquadAdminNudgeThreshold = 10;

class SquadService extends ChangeNotifier {
  SquadService._();
  static final SquadService instance = SquadService._();

  SupabaseClient get _client => Supabase.instance.client;

  List<SquadInfo> _mySquads = [];
  List<SquadInfo> get mySquads => _mySquads;
  bool _loaded = false;
  bool get loaded => _loaded;

  /// The squad currently earning study XP. Falls back to the first
  /// squad if none is explicitly marked active (shouldn't normally
  /// happen — squad_create/join set it automatically the first time).
  SquadInfo? get activeSquad {
    if (_mySquads.isEmpty) return null;
    return _mySquads.firstWhere((s) => s.isActive, orElse: () => _mySquads.first);
  }

  Future<void> loadMySquads() async {
    if (_client.auth.currentUser == null) return;
    try {
      final rows = await _client.rpc('squad_get_mine');
      if (rows is List) {
        _mySquads = rows.map((r) => SquadInfo.fromMap(Map<String, dynamic>.from(r as Map))).toList();
      } else {
        _mySquads = [];
      }
    } catch (_) {
      _mySquads = [];
    }
    _loaded = true;
    notifyListeners();
  }

  Future<String?> setActiveSquad(int squadId) async {
    try {
      await _client.rpc('squad_set_active', params: {'p_squad_id': squadId});
      await loadMySquads();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> createSquad({required String name, required String description, required String emoji}) async {
    try {
      await _client.rpc('squad_create', params: {'p_name': name, 'p_description': description, 'p_avatar_emoji': emoji});
      await loadMySquads();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Join by typed invite code. May join immediately (free, or paid —
  /// caller should confirm price with the user first for paid squads),
  /// or create a pending request if the squad requires approval.
  Future<SquadJoinOutcome> joinByCode(String code) async {
    try {
      final result = await _client.rpc('squad_join_by_code', params: {'p_code': code.trim()});
      final map = Map<String, dynamic>.from(result as Map);
      final status = map['status'] as String?;
      if (status == 'joined') await loadMySquads();
      return SquadJoinOutcome(status: status, squadId: (map['squad_id'] as num?)?.toInt());
    } on PostgrestException catch (e) {
      return SquadJoinOutcome(error: e.message);
    } catch (e) {
      return const SquadJoinOutcome(error: 'Something went wrong. Please try again.');
    }
  }

  /// Join a squad found via Discover / Top Squads (by id, not code).
  Future<SquadJoinOutcome> requestJoin(int squadId) async {
    try {
      final result = await _client.rpc('squad_request_join', params: {'p_squad_id': squadId});
      final map = Map<String, dynamic>.from(result as Map);
      final status = map['status'] as String?;
      if (status == 'joined') await loadMySquads();
      return SquadJoinOutcome(status: status, squadId: squadId);
    } on PostgrestException catch (e) {
      return SquadJoinOutcome(error: e.message);
    } catch (e) {
      return const SquadJoinOutcome(error: 'Something went wrong. Please try again.');
    }
  }

  Future<List<Map<String, dynamic>>> discoverSquads() async {
    final rows = await _client.rpc('squad_discover');
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<Map<String, dynamic>?> getMyPendingRequest() async {
    try {
      final result = await _client.rpc('squad_get_my_pending_request');
      if (result == null) return null;
      return Map<String, dynamic>.from(result as Map);
    } catch (_) {
      return null;
    }
  }

  Future<String?> cancelJoinRequest(int squadId) async {
    try {
      await _client.rpc('squad_cancel_join_request', params: {'p_squad_id': squadId});
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<void> leaveSquad(int squadId) async {
    await _client.rpc('squad_leave', params: {'p_squad_id': squadId});
    await loadMySquads();
  }

  Future<List<Map<String, dynamic>>> getMembers(int squadId) async {
    final rows = await _client.rpc('squad_get_members', params: {'p_squad_id': squadId});
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getPendingRequests(int squadId) async {
    final rows = await _client.rpc('squad_get_pending_requests', params: {'p_squad_id': squadId});
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<String?> approveRequest(int requestId) async {
    try {
      await _client.rpc('squad_approve_request', params: {'p_request_id': requestId});
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> rejectRequest(int requestId) async {
    try {
      await _client.rpc('squad_reject_request', params: {'p_request_id': requestId});
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> updateSettings({
    required int squadId,
    required String name,
    required String description,
    required String emoji,
    required bool requireApproval,
  }) async {
    try {
      await _client.rpc('squad_update_settings', params: {
        'p_squad_id': squadId,
        'p_name': name,
        'p_description': description,
        'p_avatar_emoji': emoji,
        'p_require_approval': requireApproval,
      });
      await loadMySquads();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Unlocks (or updates the price of) monetization for a squad the
  /// caller leads. Returns an error message on failure, null on success.
  Future<String?> toggleMonetization({required int squadId, required int joinPriceCent}) async {
    try {
      await _client.rpc('squad_toggle_monetization', params: {
        'p_squad_id': squadId,
        'p_join_price_cent': joinPriceCent,
      });
      await loadMySquads();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> disableMonetization(int squadId) async {
    try {
      await _client.rpc('squad_disable_monetization', params: {'p_squad_id': squadId});
      await loadMySquads();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<List<Map<String, dynamic>>> getFeed(int squadId) async {
    final rows = await _client.rpc('squad_get_feed', params: {'p_squad_id': squadId});
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<void> reactToFeed(int feedId, String reaction) async {
    await _client.rpc('squad_react_to_feed', params: {'p_feed_id': feedId, 'p_reaction': reaction});
  }

  Future<List<Map<String, dynamic>>> getMessages(int squadId) async {
    final rows = await _client.rpc('squad_get_messages', params: {'p_squad_id': squadId});
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<void> postMessage(String message) async {
    await _client.rpc('squad_post_message', params: {'p_message': message});
  }

  Future<List<Map<String, dynamic>>> getGoals(int squadId) async {
    final rows = await _client.rpc('squad_get_goals', params: {'p_squad_id': squadId});
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<String?> setGoal({required String goalType, required int target, required int rewardCp}) async {
    try {
      await _client.rpc('squad_set_goal', params: {'p_goal_type': goalType, 'p_target': target, 'p_reward_cp': rewardCp});
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<List<Map<String, dynamic>>> getAttendanceToday(int squadId) async {
    final rows = await _client.rpc('squad_get_attendance_today', params: {'p_squad_id': squadId});
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getLibrary(int squadId) async {
    final rows = await _client.rpc('squad_get_library', params: {'p_squad_id': squadId});
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<void> addLibraryNote({required String title, required String content}) async {
    await _client.rpc('squad_add_library_note', params: {'p_title': title, 'p_content': content});
  }

  Future<String?> startBattle({required String opponentCode, required int durationMinutes}) async {
    try {
      await _client.rpc('squad_start_battle', params: {'p_opponent_invite_code': opponentCode, 'p_duration_minutes': durationMinutes});
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<Map<String, dynamic>?> getActiveBattle() async {
    final result = await _client.rpc('squad_get_active_battle');
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> getRankings() async {
    final rows = await _client.rpc('squad_get_rankings');
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<String?> changeRole(String userId, String newRole) async {
    try {
      await _client.rpc('squad_change_role', params: {'p_target_user': userId, 'p_new_role': newRole});
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> removeMember(String userId) async {
    try {
      await _client.rpc('squad_remove_member', params: {'p_target_user': userId});
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> transferLeadership(String userId) async {
    try {
      await _client.rpc('squad_transfer_leadership', params: {'p_target_user': userId});
      await loadMySquads();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// The central hook — call this after any study activity. Awards XP
  /// to whichever squad the student has marked "active". Does nothing
  /// if they have no active squad.
  Future<void> recordActivity({required String activityType, required int amount, String? subject}) async {
    final squadId = activeSquad?.id;
    if (squadId == null) return;
    try {
      await _client.rpc('squad_record_activity', params: {
        'p_squad_id': squadId,
        'p_activity_type': activityType,
        'p_amount': amount,
        'p_subject': subject,
      });
    } catch (_) {}
  }

  Future<void> addBattleScore(int points) async {
    try {
      await _client.rpc('squad_add_battle_score', params: {'p_points': points});
    } catch (_) {}
  }
}

/// =========================================================================
/// ENTRY SCREEN — squad list (multi-squad) or the no-squad landing page
/// =========================================================================

class SquadEntryScreen extends StatefulWidget {
  const SquadEntryScreen({super.key});

  @override
  State<SquadEntryScreen> createState() => _SquadEntryScreenState();
}

class _SquadEntryScreenState extends State<SquadEntryScreen> {
  @override
  void initState() {
    super.initState();
    SquadService.instance.loadMySquads();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SquadService.instance,
      builder: (context, _) {
        if (!SquadService.instance.loaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (SquadService.instance.mySquads.isNotEmpty) {
          return const MySquadsListScreen();
        }
        return const _NoSquadScreen();
      },
    );
  }
}

/// Shown once a student has at least one squad — lists all of them,
/// shows which is active, and lets them add more.
class MySquadsListScreen extends StatefulWidget {
  const MySquadsListScreen({super.key});

  @override
  State<MySquadsListScreen> createState() => _MySquadsListScreenState();
}

class _MySquadsListScreenState extends State<MySquadsListScreen> {
  bool _switching = false;

  Future<void> _setActive(int squadId) async {
    setState(() => _switching = true);
    final err = await SquadService.instance.setActiveSquad(squadId);
    if (!mounted) return;
    setState(() => _switching = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: SquadService.instance,
      builder: (context, _) {
        final squads = SquadService.instance.mySquads;
        return Scaffold(
          appBar: AppBar(title: const Text('My Squads')),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add_rounded),
            label: const Text('Join Another'),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _NoSquadScreen(isAddingAnother: true)));
            },
          ),
          body: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: squads.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final s = squads[i];
              return Material(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SquadHomeScreen(squad: s))),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text(s.avatarEmoji, style: const TextStyle(fontSize: 30)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                  if (s.isActive) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(20)),
                                      child: const Text('Active', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                  if (s.isMonetized) ...[
                                    const SizedBox(width: 6),
                                    Icon(Icons.attach_money_rounded, size: 16, color: Colors.amber.shade700),
                                  ],
                                ],
                              ),
                              Text('Lv.${s.level} · ${s.memberCount}/20 members', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        if (!s.isActive)
                          TextButton(
                            onPressed: _switching ? null : () => _setActive(s.id),
                            child: const Text('Set Active', style: TextStyle(fontSize: 12)),
                          ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _NoSquadScreen extends StatefulWidget {
  final bool isAddingAnother;
  const _NoSquadScreen({this.isAddingAnother = false});

  @override
  State<_NoSquadScreen> createState() => _NoSquadScreenState();
}

class _NoSquadScreenState extends State<_NoSquadScreen> {
  bool _loadingPending = true;
  Map<String, dynamic>? _pendingRequest;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    final pending = await SquadService.instance.getMyPendingRequest();
    if (!mounted) return;
    setState(() {
      _pendingRequest = pending;
      _loadingPending = false;
    });
  }

  Future<void> _cancelPending() async {
    final req = _pendingRequest;
    if (req == null) return;
    setState(() => _cancelling = true);
    final err = await SquadService.instance.cancelJoinRequest((req['squad_id'] as num).toInt());
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      setState(() => _cancelling = false);
      return;
    }
    setState(() {
      _pendingRequest = null;
      _cancelling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loadingPending) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_pendingRequest != null) {
      final req = _pendingRequest!;
      return Scaffold(
        appBar: AppBar(title: const Text('Study Squads')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 64, color: Colors.amber),
              const SizedBox(height: 16),
              Text('Request sent to ${req['avatar_emoji'] ?? '📚'} ${req['squad_name'] ?? 'a squad'}',
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 8),
              Text('Waiting for an admin to approve your join request.',
                  textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: _cancelling ? null : _cancelPending,
                  child: _cancelling
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Cancel Request'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.isAddingAnother ? 'Join Another Squad' : 'Study Squads')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⭐', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text('Study together, motivate each other',
                textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                icon: const Icon(Icons.travel_explore_rounded),
                label: const Text('Discover Squads'),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SquadDiscoverScreen()));
                  if (mounted) Navigator.of(context).maybePop();
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create a Squad'),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateSquadScreen()));
                  if (mounted) Navigator.of(context).maybePop();
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.group_add_rounded),
                label: const Text('Join with a Code'),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JoinSquadScreen()));
                  if (mounted) Navigator.of(context).maybePop();
                },
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SquadRankingsScreen())),
              child: const Text('View Top Squads'),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// DISCOVER SQUADS — browse & tap to join, price shown up front if paid
/// =========================================================================

class SquadDiscoverScreen extends StatefulWidget {
  const SquadDiscoverScreen({super.key});

  @override
  State<SquadDiscoverScreen> createState() => _SquadDiscoverScreenState();
}

class _SquadDiscoverScreenState extends State<SquadDiscoverScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _squads = [];
  int? _joiningId;

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
      final squads = await SquadService.instance.discoverSquads();
      if (!mounted) return;
      setState(() {
        _squads = squads;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load squads. Please try again.';
        _loading = false;
      });
    }
  }

  Future<bool> _confirmPaidJoin(Map<String, dynamic> squad, int price) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paid Squad'),
        content: Text('${squad['name']} costs $price Cent to join. This will be deducted from your NaijaLearn balance immediately. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Pay $price Cent')),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _join(Map<String, dynamic> squad) async {
    final id = (squad['id'] as num).toInt();
    final isMonetized = squad['is_monetized'] as bool? ?? false;
    final price = (squad['join_price_cent'] as num?)?.toInt() ?? 0;

    if (isMonetized && price > 0) {
      final ok = await _confirmPaidJoin(squad, price);
      if (!ok) return;
    }

    setState(() => _joiningId = id);
    final outcome = await SquadService.instance.requestJoin(id);
    if (!mounted) return;
    setState(() => _joiningId = null);

    if (!outcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(outcome.error!)));
      return;
    }
    if (outcome.isPending) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request sent to ${squad['name']} — waiting for approval.')),
      );
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MySquadsListScreen()),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Discover Squads')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Try Again')),
                      ],
                    ),
                  ),
                )
              : _squads.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No open squads right now — you could start your own!',
                            textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _squads.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final s = _squads[i];
                          final id = (s['id'] as num).toInt();
                          final requiresApproval = s['require_approval'] as bool? ?? false;
                          final memberCount = (s['member_count'] as num?)?.toInt() ?? 0;
                          final isMonetized = s['is_monetized'] as bool? ?? false;
                          final price = (s['join_price_cent'] as num?)?.toInt() ?? 0;
                          final busy = _joiningId == id;
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                            child: Row(
                              children: [
                                Text(s['avatar_emoji'] as String? ?? '📚', style: const TextStyle(fontSize: 28)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(child: Text(s['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                          if (isMonetized && price > 0) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                              child: Text('$price Cent', style: TextStyle(fontSize: 11, color: Colors.amber.shade800, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      Text('$memberCount/20 members · Lv.${s['level'] ?? 1}',
                                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                                      if ((s['description'] as String?)?.isNotEmpty == true)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(s['description'] as String,
                                              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 92,
                                  child: FilledButton(
                                    onPressed: busy ? null : () => _join(s),
                                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                                    child: busy
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : Text(requiresApproval ? 'Request' : 'Join', style: const TextStyle(fontSize: 13)),
                                  ),
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

class CreateSquadScreen extends StatefulWidget {
  const CreateSquadScreen({super.key});

  @override
  State<CreateSquadScreen> createState() => _CreateSquadScreenState();
}

class _CreateSquadScreenState extends State<CreateSquadScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _emoji = '📚';
  bool _busy = false;
  String? _error;

  static const _emojiChoices = ['📚', '⭐', '🧠', '🚀', '🔥', '🏆', '🦉', '🎯', '💡', '🐝', '🌱', '⚡'];

  Future<void> _create() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Give your squad a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await SquadService.instance.createSquad(
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      emoji: _emoji,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Squad')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _emojiChoices.map((e) {
                final selected = _emoji == e;
                return GestureDetector(
                  onTap: () => setState(() => _emoji = e),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: selected ? Theme.of(context).colorScheme.primaryContainer : null,
                    child: Text(e, style: const TextStyle(fontSize: 22)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Squad Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              maxLines: 2,
              decoration: InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: _busy ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

class JoinSquadScreen extends StatefulWidget {
  const JoinSquadScreen({super.key});

  @override
  State<JoinSquadScreen> createState() => _JoinSquadScreenState();
}

class _JoinSquadScreenState extends State<JoinSquadScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await SquadService.instance.joinByCode(_codeController.text);
    if (!mounted) return;
    if (!outcome.success) {
      setState(() {
        _busy = false;
        _error = outcome.error;
      });
      return;
    }
    if (outcome.isPending) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent — waiting for approval.')),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Squad')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Enter the invite code your friend shared with you.'),
            const Text('If it\'s a paid squad, you\'ll be charged the join price immediately on success.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(hintText: 'JOIN-8X91P', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _join,
              child: _busy ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// SQUAD HOME — tabs: Feed / Chat / Goals / Members / Library
/// Now takes the squad explicitly (a user can be in several).
/// =========================================================================

class SquadHomeScreen extends StatefulWidget {
  final SquadInfo squad;
  const SquadHomeScreen({super.key, required this.squad});

  @override
  State<SquadHomeScreen> createState() => _SquadHomeScreenState();
}

class _SquadHomeScreenState extends State<SquadHomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-fetch the freshest copy from the loaded list (in case settings
    // changed since this screen was opened) — fall back to the widget's
    // squad if it's no longer in the list for some reason.
    final squad = SquadService.instance.mySquads.firstWhere(
      (s) => s.id == widget.squad.id,
      orElse: () => widget.squad,
    );
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('${squad.avatarEmoji} ${squad.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: 'Squad Perks',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SquadPerksScreen(squad: squad))),
          ),
          IconButton(
            icon: const Icon(Icons.emoji_events_rounded),
            tooltip: 'Battle',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SquadBattleScreen(squad: squad))),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SquadSettingsScreen(squad: squad))),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Feed'),
            Tab(text: 'Chat'),
            Tab(text: 'Goals'),
            Tab(text: 'Members'),
            Tab(text: 'Library'),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: scheme.surfaceContainerHighest,
            child: Column(
              children: [
                Row(
                  children: [
                    Text('Level ${squad.level}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (!squad.isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: scheme.outline.withOpacity(0.3), borderRadius: BorderRadius.circular(20)),
                        child: const Text('Not earning XP here', style: TextStyle(fontSize: 10)),
                      ),
                    ],
                    const Spacer(),
                    Text('${squad.memberCount}/20 members', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: squad.xpIntoLevel / 1000, minHeight: 8, backgroundColor: scheme.surface),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _SquadFeedTab(squad: squad),
                _SquadChatTab(squad: squad),
                _SquadGoalsTab(squad: squad),
                _SquadMembersTab(squad: squad),
                _SquadLibraryTab(squad: squad),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _TabErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try Again')),
          ],
        ),
      ),
    );
  }
}

class _SquadFeedTab extends StatefulWidget {
  final SquadInfo squad;
  const _SquadFeedTab({required this.squad});

  @override
  State<_SquadFeedTab> createState() => _SquadFeedTabState();
}

class _SquadFeedTabState extends State<_SquadFeedTab> {
  List<Map<String, dynamic>> _feed = [];
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
      final feed = await SquadService.instance.getFeed(widget.squad.id);
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the feed.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _TabErrorState(message: _error!, onRetry: _load);
    if (_feed.isEmpty) {
      return const Center(child: Text('No activity yet — start studying!'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _feed.length,
        itemBuilder: (context, i) {
          final item = _feed[i];
          final reactions = Map<String, dynamic>.from(item['reactions'] as Map? ?? {});
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['event_text'] as String? ?? ''),
                  const SizedBox(height: 8),
                  Row(
                    children: ['👍', '🔥', '👏'].map((r) {
                      final count = reactions[r] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                          onPressed: () async {
                            await SquadService.instance.reactToFeed((item['id'] as num).toInt(), r);
                            _load();
                          },
                          child: Text('$r ${count > 0 ? count : ''}'),
                        ),
                      );
                    }).toList(),
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

class _SquadChatTab extends StatefulWidget {
  final SquadInfo squad;
  const _SquadChatTab({required this.squad});

  @override
  State<_SquadChatTab> createState() => _SquadChatTabState();
}

class _SquadChatTabState extends State<_SquadChatTab> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
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
      final msgs = await SquadService.instance.getMessages(widget.squad.id);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load messages.';
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await SquadService.instance.postMessage(_controller.text.trim());
      _controller.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send — please try again.')),
        );
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _TabErrorState(message: _error!, onRetry: _load);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m['sender_username'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(m['message'] as String? ?? ''),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(hintText: 'Share a question, note, or motivation...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24))),
                  ),
                ),
                IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send_rounded)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SquadGoalsTab extends StatefulWidget {
  final SquadInfo squad;
  const _SquadGoalsTab({required this.squad});

  @override
  State<_SquadGoalsTab> createState() => _SquadGoalsTabState();
}

class _SquadGoalsTabState extends State<_SquadGoalsTab> {
  List<Map<String, dynamic>> _goals = [];
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
      final goals = await SquadService.instance.getGoals(widget.squad.id);
      if (!mounted) return;
      setState(() {
        _goals = goals;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load goals.';
        _loading = false;
      });
    }
  }

  Future<void> _createGoal(String type) async {
    final targetController = TextEditingController();
    final rewardController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('New ${type[0].toUpperCase()}${type.substring(1)} Goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: targetController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Target (questions)')),
            TextField(controller: rewardController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Reward CP')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Set')),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = await SquadService.instance.setGoal(
      goalType: type,
      target: int.tryParse(targetController.text) ?? 100,
      rewardCp: int.tryParse(rewardController.text) ?? 0,
    );
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _TabErrorState(message: _error!, onRetry: _load);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._goals.map((g) {
          final progress = (g['progress'] as num).toInt();
          final target = (g['target'] as num).toInt();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${(g['goal_type'] as String).toUpperCase()} · $progress / $target', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: (progress / target).clamp(0, 1), minHeight: 8),
                  ),
                  if (g['completed'] == true) const Padding(padding: EdgeInsets.only(top: 6), child: Text('✅ Completed!')),
                ],
              ),
            ),
          );
        }),
        if (widget.squad.canManage) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton(onPressed: () => _createGoal('daily'), child: const Text('+ Daily Goal')),
              OutlinedButton(onPressed: () => _createGoal('weekly'), child: const Text('+ Weekly Goal')),
              OutlinedButton(onPressed: () => _createGoal('monthly'), child: const Text('+ Monthly Goal')),
            ],
          ),
        ],
      ],
    );
  }
}

class _SquadMembersTab extends StatefulWidget {
  final SquadInfo squad;
  const _SquadMembersTab({required this.squad});

  @override
  State<_SquadMembersTab> createState() => _SquadMembersTabState();
}

class _SquadMembersTabState extends State<_SquadMembersTab> {
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _attendance = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _loading = true;
  String? _error;
  final Set<int> _busyRequestIds = {};

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
      final members = await SquadService.instance.getMembers(widget.squad.id);
      final attendance = await SquadService.instance.getAttendanceToday(widget.squad.id);
      final pending = widget.squad.canManage ? await SquadService.instance.getPendingRequests(widget.squad.id) : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _members = members;
        _attendance = attendance;
        _pendingRequests = pending;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load members.';
        _loading = false;
      });
    }
  }

  bool _studiedToday(String userId) {
    final match = _attendance.where((a) => a['user_id'] == userId);
    return match.isNotEmpty && match.first['studied_today'] == true;
  }

  int get _adminCount => _members.where((m) => m['role'] == 'co_leader').length;

  Future<void> _respondToRequest(int requestId, bool approve) async {
    setState(() => _busyRequestIds.add(requestId));
    final err = approve
        ? await SquadService.instance.approveRequest(requestId)
        : await SquadService.instance.rejectRequest(requestId);
    if (!mounted) return;
    setState(() => _busyRequestIds.remove(requestId));
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    _load();
  }

  Future<void> _changeRole(String userId, String newRole) async {
    final err = await SquadService.instance.changeRole(userId, newRole);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    _load();
  }

  Future<void> _removeMember(String userId) async {
    final err = await SquadService.instance.removeMember(userId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    _load();
  }

  Future<void> _transferLeadership(String userId) async {
    final err = await SquadService.instance.transferLeadership(userId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _TabErrorState(message: _error!, onRetry: _load);
    final scheme = Theme.of(context).colorScheme;
    final showAdminNudge = widget.squad.isLeader &&
        widget.squad.memberCount >= kSquadAdminNudgeThreshold &&
        _adminCount < kSquadMaxAdmins;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Icon(Icons.shield_rounded, size: 18),
                const SizedBox(width: 8),
                Text('Admins: $_adminCount/$kSquadMaxAdmins', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
          if (showAdminNudge)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  const Text('💡', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A squad this size runs smoother with $kSquadMaxAdmins admins to help moderate. Consider promoting ${kSquadMaxAdmins - _adminCount} more member${kSquadMaxAdmins - _adminCount == 1 ? '' : 's'}.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.squad.canManage && _pendingRequests.isNotEmpty) ...[
            Text('Pending Requests (${_pendingRequests.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._pendingRequests.map((r) {
              final requestId = (r['id'] as num).toInt();
              final busy = _busyRequestIds.contains(requestId);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: scheme.primaryContainer.withOpacity(0.3), borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Expanded(child: Text(r['username'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                    if (busy)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else ...[
                      IconButton(
                        icon: const Icon(Icons.check_circle_rounded, color: Colors.green),
                        tooltip: 'Approve',
                        onPressed: () => _respondToRequest(requestId, true),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                        tooltip: 'Reject',
                        onPressed: () => _respondToRequest(requestId, false),
                      ),
                    ],
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
          Text('Members (${_members.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._members.map((m) {
            final userId = m['user_id'] as String;
            final role = m['role'] as String;
            final atAdminCap = _adminCount >= kSquadMaxAdmins;
            return ListTile(
              leading: Text(_studiedToday(userId) ? '✅' : '❌', style: const TextStyle(fontSize: 18)),
              title: Text(m['username'] as String? ?? ''),
              subtitle: Text(role == 'leader' ? 'Leader' : role == 'co_leader' ? 'Co-Leader (Admin)' : 'Member'),
              trailing: widget.squad.isLeader && role != 'leader'
                  ? PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'promote') _changeRole(userId, 'co_leader');
                        if (value == 'demote') _changeRole(userId, 'member');
                        if (value == 'remove') _removeMember(userId);
                        if (value == 'transfer') _transferLeadership(userId);
                      },
                      itemBuilder: (context) => [
                        if (role == 'member')
                          PopupMenuItem(
                            value: 'promote',
                            enabled: !atAdminCap,
                            child: Text(atAdminCap ? 'Make Co-Leader (cap reached)' : 'Make Co-Leader'),
                          ),
                        if (role == 'co_leader') const PopupMenuItem(value: 'demote', child: Text('Remove Co-Leader')),
                        const PopupMenuItem(value: 'transfer', child: Text('Transfer Leadership')),
                        const PopupMenuItem(value: 'remove', child: Text('Remove from Squad')),
                      ],
                    )
                  : null,
            );
          }),
        ],
      ),
    );
  }
}

class _SquadLibraryTab extends StatefulWidget {
  final SquadInfo squad;
  const _SquadLibraryTab({required this.squad});

  @override
  State<_SquadLibraryTab> createState() => _SquadLibraryTabState();
}

class _SquadLibraryTabState extends State<_SquadLibraryTab> {
  List<Map<String, dynamic>> _notes = [];
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
      final notes = await SquadService.instance.getLibrary(widget.squad.id);
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the library.';
        _loading = false;
      });
    }
  }

  Future<void> _addNote() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: contentController, maxLines: 5, decoration: const InputDecoration(labelText: 'Content')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (confirmed != true || titleController.text.trim().isEmpty) return;
    await SquadService.instance.addLibraryNote(title: titleController.text.trim(), content: contentController.text.trim());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _TabErrorState(message: _error!, onRetry: _load);
    return Scaffold(
      body: _notes.isEmpty
          ? const Center(child: Text('No shared notes yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _notes.length,
              itemBuilder: (context, i) {
                final n = _notes[i];
                return Card(
                  child: ListTile(
                    title: Text(n['title'] as String? ?? ''),
                    subtitle: Text(n['content_text'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(n['title'] as String? ?? ''),
                        content: SingleChildScrollView(child: Text(n['content_text'] as String? ?? '')),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: _addNote, child: const Icon(Icons.add_rounded)),
    );
  }
}

/// =========================================================================
/// SETTINGS — squad details + monetization (leader-only) + leave
/// =========================================================================

class SquadSettingsScreen extends StatefulWidget {
  final SquadInfo squad;
  const SquadSettingsScreen({super.key, required this.squad});

  @override
  State<SquadSettingsScreen> createState() => _SquadSettingsScreenState();
}

class _SquadSettingsScreenState extends State<SquadSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _priceController;
  late String _emoji;
  late bool _requireApproval;
  bool _saving = false;
  bool _monetizing = false;
  String? _error;

  static const _emojiChoices = ['📚', '⭐', '🧠', '🚀', '🔥', '🏆', '🦉', '🎯', '💡', '🐝', '🌱', '⚡'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.squad.name);
    _descController = TextEditingController(text: widget.squad.description);
    _priceController = TextEditingController(text: widget.squad.joinPriceCent.toString());
    _emoji = widget.squad.avatarEmoji;
    _requireApproval = widget.squad.requireApproval;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Squad name can\'t be empty.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await SquadService.instance.updateSettings(
      squadId: widget.squad.id,
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      emoji: _emoji,
      // Monetized squads can't require approval — the toggle handles
      // this server-side too, but keep the UI honest either way.
      requireApproval: widget.squad.isMonetized ? false : _requireApproval,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Squad settings updated.')));
  }

  Future<void> _confirmAndMonetize() async {
    final price = int.tryParse(_priceController.text) ?? 0;
    if (price < 0 || price > kSquadMaxJoinPrice) {
      setState(() => _error = 'Join price must be between 0 and $kSquadMaxJoinPrice Cent.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlock Monetization?'),
        content: Text(
          'This costs $kSquadMonetizeUnlockCost Cent, deducted from your balance now, and is non-refundable. '
          'New members will pay $price Cent to join — you keep 90%, the platform keeps 10%. '
          'This will also turn off "require approval" for this squad.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Pay $kSquadMonetizeUnlockCost Cent')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _monetizing = true;
      _error = null;
    });
    final err = await SquadService.instance.toggleMonetization(squadId: widget.squad.id, joinPriceCent: price);
    if (!mounted) return;
    setState(() {
      _monetizing = false;
      if (err == null) _requireApproval = false;
    });
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monetization unlocked!')));
  }

  Future<void> _updatePriceOnly() async {
    final price = int.tryParse(_priceController.text) ?? 0;
    if (price < 0 || price > kSquadMaxJoinPrice) {
      setState(() => _error = 'Join price must be between 0 and $kSquadMaxJoinPrice Cent.');
      return;
    }
    setState(() {
      _monetizing = true;
      _error = null;
    });
    final err = await SquadService.instance.toggleMonetization(squadId: widget.squad.id, joinPriceCent: price);
    if (!mounted) return;
    setState(() => _monetizing = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Join price updated.')));
  }

  Future<void> _disableMonetization() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable Monetization?'),
        content: const Text('New members will be able to join for free again. The unlock fee already paid is not refunded.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disable')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _monetizing = true);
    final err = await SquadService.instance.disableMonetization(widget.squad.id);
    if (!mounted) return;
    setState(() => _monetizing = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _priceController.text = '0');
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monetization disabled.')));
  }

  @override
  Widget build(BuildContext context) {
    final isLeader = widget.squad.isLeader;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Squad Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                SelectableText(widget.squad.inviteCode, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const Text('Share this code to invite members'),
              ],
            ),
          ),
          const SizedBox(height: 28),
          if (isLeader) ...[
            Text('Squad Details', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _emojiChoices.map((e) {
                final selected = _emoji == e;
                return GestureDetector(
                  onTap: () => setState(() => _emoji = e),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: selected ? scheme.primaryContainer : null,
                    child: Text(e, style: const TextStyle(fontSize: 20)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Squad Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              maxLines: 2,
              decoration: InputDecoration(labelText: 'Description', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require approval to join'),
              subtitle: Text(
                widget.squad.isMonetized
                    ? 'Not available for paid squads — joining is instant on payment'
                    : 'New join requests need a leader/co-leader to approve them',
              ),
              value: widget.squad.isMonetized ? false : _requireApproval,
              onChanged: widget.squad.isMonetized ? null : (v) => setState(() => _requireApproval = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes'),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.08),
                border: Border.all(color: Colors.amber.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.attach_money_rounded, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Text('Monetize This Squad', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.squad.isMonetized
                        ? 'Monetization is active. New members pay to join — you keep 90% of every join fee.'
                        : 'Charge new members up to $kSquadMaxJoinPrice Cent to join. Unlocking costs a one-time $kSquadMonetizeUnlockCost Cent — you keep 90% of every join fee after that.',
                    style: const TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Join price (0-$kSquadMaxJoinPrice Cent)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.squad.isMonetized)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _monetizing ? null : _updatePriceOnly,
                            child: _monetizing
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Update Price'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _monetizing ? null : _disableMonetization,
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Disable'),
                          ),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _monetizing ? null : _confirmAndMonetize,
                        style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade800),
                        child: _monetizing
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text('Unlock for $kSquadMonetizeUnlockCost Cent'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          ListTile(
            leading: const Icon(Icons.exit_to_app_rounded, color: Colors.red),
            title: const Text('Leave Squad', style: TextStyle(color: Colors.red)),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Leave Squad?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
                  ],
                ),
              );
              if (confirmed == true) {
                await SquadService.instance.leaveSquad(widget.squad.id);
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// =========================================================================
/// SQUAD PERKS — informational level ladder (client-side, cosmetic only)
/// =========================================================================

class SquadPerkTier {
  final int level;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  const SquadPerkTier(this.level, this.title, this.description, this.icon, this.color);
}

const List<SquadPerkTier> kSquadPerkTiers = [
  SquadPerkTier(1, 'New Squad', 'Just getting started — every question answered by a member adds to the squad\'s XP.', Icons.emoji_flags_rounded, Colors.grey),
  SquadPerkTier(5, 'Rising Squad', 'Your squad shows up in Top Squads rankings once it\'s active enough.', Icons.trending_up_rounded, Color(0xFF4CAF50)),
  SquadPerkTier(10, 'Established Squad', 'Big enough to benefit from a full 3-admin team — see the Members tab.', Icons.groups_rounded, Color(0xFF2196F3)),
  SquadPerkTier(20, 'Elite Squad', 'A squad this active is a serious contender in Squad Battles.', Icons.bolt_rounded, Color(0xFFE91E63)),
  SquadPerkTier(35, 'Legendary Squad', 'Among the most consistent study communities on NaijaLearn.', Icons.military_tech_rounded, Color(0xFF9C27B0)),
  SquadPerkTier(50, 'Hall of Fame Squad', 'The top tier — a genuine study powerhouse.', Icons.emoji_events_rounded, Color(0xFFFFD700)),
];

class SquadPerksScreen extends StatelessWidget {
  final SquadInfo squad;
  const SquadPerksScreen({super.key, required this.squad});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentIndex = kSquadPerkTiers.lastIndexWhere((t) => squad.level >= t.level);
    final current = kSquadPerkTiers[currentIndex < 0 ? 0 : currentIndex];
    final next = currentIndex + 1 < kSquadPerkTiers.length ? kSquadPerkTiers[currentIndex + 1] : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Squad Perks')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: current.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: current.color, width: 1.4),
            ),
            child: Column(
              children: [
                Icon(current.icon, color: current.color, size: 40),
                const SizedBox(height: 8),
                Text(current.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: current.color)),
                const SizedBox(height: 4),
                Text('Squad Level ${squad.level}', style: TextStyle(color: scheme.onSurfaceVariant)),
                if (next != null) ...[
                  const SizedBox(height: 10),
                  Text('${next.level - squad.level} levels to ${next.title}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Level Roadmap', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...kSquadPerkTiers.map((t) {
            final reached = squad.level >= t.level;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.title == current.title ? t.color.withOpacity(0.15) : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: t.title == current.title ? Border.all(color: t.color, width: 1.4) : null,
              ),
              child: Row(
                children: [
                  Icon(t.icon, color: reached ? t.color : scheme.onSurfaceVariant.withOpacity(0.4)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title, style: TextStyle(fontWeight: FontWeight.w600, color: reached ? null : scheme.onSurfaceVariant.withOpacity(0.6))),
                        Text(t.description, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Text('Lv.${t.level}+', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class SquadBattleScreen extends StatefulWidget {
  final SquadInfo squad;
  const SquadBattleScreen({super.key, required this.squad});

  @override
  State<SquadBattleScreen> createState() => _SquadBattleScreenState();
}

class _SquadBattleScreenState extends State<SquadBattleScreen> {
  Map<String, dynamic>? _activeBattle;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final battle = await SquadService.instance.getActiveBattle();
    if (mounted) setState(() {
      _activeBattle = battle;
      _loading = false;
    });
  }

  Future<void> _challenge() async {
    final codeController = TextEditingController();
    int duration = 30;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Challenge a Squad'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: codeController, decoration: const InputDecoration(labelText: 'Their invite code')),
              const SizedBox(height: 12),
              DropdownButton<int>(
                value: duration,
                items: const [
                  DropdownMenuItem(value: 30, child: Text('30 minutes')),
                  DropdownMenuItem(value: 60, child: Text('1 hour')),
                  DropdownMenuItem(value: 1440, child: Text('24 hours')),
                ],
                onChanged: (v) => setState(() => duration = v ?? 30),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start Battle')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final err = await SquadService.instance.startBattle(opponentCode: codeController.text, durationMinutes: duration);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Squad Battle')),
      body: Center(
        child: _activeBattle == null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No active battle', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    if (widget.squad.canManage)
                      FilledButton(onPressed: _challenge, child: const Text('Challenge Another Squad')),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⚔️ Battle in Progress', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 20),
                    Text('Your score: ${_activeBattle!['challenger_score']} vs ${_activeBattle!['opponent_score']}'),
                  ],
                ),
              ),
      ),
    );
  }
}

class SquadRankingsScreen extends StatefulWidget {
  const SquadRankingsScreen({super.key});

  @override
  State<SquadRankingsScreen> createState() => _SquadRankingsScreenState();
}

class _SquadRankingsScreenState extends State<SquadRankingsScreen> {
  List<Map<String, dynamic>> _rankings = [];
  bool _loading = true;
  String? _error;
  int? _joiningId;

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
      final r = await SquadService.instance.getRankings();
      if (!mounted) return;
      setState(() {
        _rankings = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load rankings.';
        _loading = false;
      });
    }
  }

  Future<void> _join(Map<String, dynamic> squad) async {
    final id = (squad['id'] as num?)?.toInt();
    if (id == null) return;

    final isMonetized = squad['is_monetized'] as bool? ?? false;
    final price = (squad['join_price_cent'] as num?)?.toInt() ?? 0;
    final alreadyMember = SquadService.instance.mySquads.any((s) => s.id == id);
    if (alreadyMember) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are already in this squad.')));
      return;
    }

    if (isMonetized && price > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Paid Squad'),
          content: Text('This squad costs $price Cent to join, deducted from your balance immediately. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Pay $price Cent')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _joiningId = id);
    final outcome = await SquadService.instance.requestJoin(id);
    if (!mounted) return;
    setState(() => _joiningId = null);

    if (!outcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(outcome.error!)));
      return;
    }
    if (outcome.isPending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent — waiting for approval.')),
      );
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MySquadsListScreen()),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Top Squads — Nigeria')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _TabErrorState(message: _error!, onRetry: _load)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rankings.length,
                  itemBuilder: (context, i) {
                    final s = _rankings[i];
                    final id = (s['id'] as num?)?.toInt();
                    final busy = _joiningId == id;
                    final alreadyMember = id != null && SquadService.instance.mySquads.any((sq) => sq.id == id);
                    return ListTile(
                      leading: Text('#${s['rank']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      title: Text('${s['avatar_emoji']} ${s['name']}'),
                      subtitle: Text('Lv.${s['level']} · ${s['xp']} XP'),
                      trailing: (alreadyMember || id == null)
                          ? null
                          : SizedBox(
                              width: 76,
                              child: OutlinedButton(
                                onPressed: busy ? null : () => _join(s),
                                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                                child: busy
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Text('Join', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                    );
                  },
                ),
    );
  }
}
