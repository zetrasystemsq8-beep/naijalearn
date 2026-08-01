// lib/study_squads.dart
//
// Study Squads — small (2-20 member) study communities. Members study
// together, chat, see each other's activity in a feed, chase shared
// goals, battle other squads, and share notes.
//
// Every RPC call here is security-definer and keys off auth.uid() —
// nothing here trusts a client-supplied user id, so scores/XP/roles
// can't be spoofed from the app.
//
// NOT built yet (flagged honestly, not silently skipped):
//   - QR code image rendering for invites (the code itself works fully,
//     just shown as text — add a QR package later if you want the image)
//   - Automated NAI insight posts into the feed ("only 4 studied today")
//     — the feed fully supports any message being posted into it, but
//     no scheduled job generates these yet.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      );

  int get xpIntoLevel => xp % 1000;
  bool get isLeader => myRole == 'leader';
  bool get canManage => myRole == 'leader' || myRole == 'co_leader';
}

class SquadService extends ChangeNotifier {
  SquadService._();
  static final SquadService instance = SquadService._();

  SupabaseClient get _client => Supabase.instance.client;

  SquadInfo? _mySquad;
  SquadInfo? get mySquad => _mySquad;
  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> loadMySquad() async {
    if (_client.auth.currentUser == null) return;
    try {
      final rows = await _client.rpc('squad_get_mine');
      if (rows is List && rows.isNotEmpty) {
        _mySquad = SquadInfo.fromMap(Map<String, dynamic>.from(rows.first as Map));
      } else {
        _mySquad = null;
      }
    } catch (_) {
      _mySquad = null;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<String?> createSquad({required String name, required String description, required String emoji}) async {
    try {
      await _client.rpc('squad_create', params: {'p_name': name, 'p_description': description, 'p_avatar_emoji': emoji});
      await loadMySquad();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> joinByCode(String code) async {
    try {
      await _client.rpc('squad_join_by_code', params: {'p_code': code.trim()});
      await loadMySquad();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<void> leaveSquad() async {
    await _client.rpc('squad_leave');
    _mySquad = null;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getMembers(int squadId) async {
    final rows = await _client.rpc('squad_get_members', params: {'p_squad_id': squadId});
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
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

  Future<void> changeRole(String userId, String newRole) async {
    await _client.rpc('squad_change_role', params: {'p_target_user': userId, 'p_new_role': newRole});
  }

  Future<void> removeMember(String userId) async {
    await _client.rpc('squad_remove_member', params: {'p_target_user': userId});
  }

  Future<void> transferLeadership(String userId) async {
    await _client.rpc('squad_transfer_leadership', params: {'p_target_user': userId});
    await loadMySquad();
  }

  /// The central hook — call this after any study activity. Silently
  /// does nothing if the user isn't in a squad. Also feeds an active
  /// battle's score when p_activityType is 'question' and correct.
  Future<void> recordActivity({required String activityType, required int amount, String? subject}) async {
    try {
      await _client.rpc('squad_record_activity', params: {
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
/// ENTRY SCREEN — routes to CreateSquad / JoinSquad / SquadHome
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
    SquadService.instance.loadMySquad();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SquadService.instance,
      builder: (context, _) {
        if (!SquadService.instance.loaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (SquadService.instance.mySquad != null) {
          return const SquadHomeScreen();
        }
        return const _NoSquadScreen();
      },
    );
  }
}

class _NoSquadScreen extends StatelessWidget {
  const _NoSquadScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Study Squads')),
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
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create a Squad'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateSquadScreen())),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.group_add_rounded),
                label: const Text('Join with a Code'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JoinSquadScreen())),
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

  static const _emojiChoices = ['📚', '⭐', '🧠', '🚀', '🔥', '🏆', '🦉', '🎯'];

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
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const SquadHomeScreen()));
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
    final err = await SquadService.instance.joinByCode(_codeController.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const SquadHomeScreen()));
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
/// =========================================================================

class SquadHomeScreen extends StatefulWidget {
  const SquadHomeScreen({super.key});

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
    final squad = SquadService.instance.mySquad;
    if (squad == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('${squad.avatarEmoji} ${squad.name}'),
        actions: [
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

class _SquadFeedTab extends StatefulWidget {
  final SquadInfo squad;
  const _SquadFeedTab({required this.squad});

  @override
  State<_SquadFeedTab> createState() => _SquadFeedTabState();
}

class _SquadFeedTabState extends State<_SquadFeedTab> {
  List<Map<String, dynamic>> _feed = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final feed = await SquadService.instance.getFeed(widget.squad.id);
    if (mounted) setState(() {
      _feed = feed;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final msgs = await SquadService.instance.getMessages(widget.squad.id);
    if (mounted) setState(() {
      _messages = msgs;
      _loading = false;
    });
  }

  Future<void> _send() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() => _sending = true);
    await SquadService.instance.postMessage(_controller.text.trim());
    _controller.clear();
    await _load();
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final goals = await SquadService.instance.getGoals(widget.squad.id);
    if (mounted) setState(() {
      _goals = goals;
      _loading = false;
    });
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
    await SquadService.instance.setGoal(
      goalType: type,
      target: int.tryParse(targetController.text) ?? 100,
      rewardCp: int.tryParse(rewardController.text) ?? 0,
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final members = await SquadService.instance.getMembers(widget.squad.id);
    final attendance = await SquadService.instance.getAttendanceToday(widget.squad.id);
    if (mounted) setState(() {
      _members = members;
      _attendance = attendance;
      _loading = false;
    });
  }

  bool _studiedToday(String userId) {
    final match = _attendance.where((a) => a['user_id'] == userId);
    return match.isNotEmpty && match.first['studied_today'] == true;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _members.length,
      itemBuilder: (context, i) {
        final m = _members[i];
        final userId = m['user_id'] as String;
        final role = m['role'] as String;
        return ListTile(
          leading: Text(_studiedToday(userId) ? '✅' : '❌', style: const TextStyle(fontSize: 18)),
          title: Text(m['username'] as String? ?? ''),
          subtitle: Text(role == 'leader' ? 'Leader' : role == 'co_leader' ? 'Co-Leader' : 'Member'),
          trailing: widget.squad.isLeader && role != 'leader'
              ? PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'promote') await SquadService.instance.changeRole(userId, 'co_leader');
                    if (value == 'demote') await SquadService.instance.changeRole(userId, 'member');
                    if (value == 'remove') await SquadService.instance.removeMember(userId);
                    if (value == 'transfer') await SquadService.instance.transferLeadership(userId);
                    _load();
                  },
                  itemBuilder: (context) => [
                    if (role == 'member') const PopupMenuItem(value: 'promote', child: Text('Make Co-Leader')),
                    if (role == 'co_leader') const PopupMenuItem(value: 'demote', child: Text('Remove Co-Leader')),
                    const PopupMenuItem(value: 'transfer', child: Text('Transfer Leadership')),
                    const PopupMenuItem(value: 'remove', child: Text('Remove from Squad')),
                  ],
                )
              : null,
        );
      },
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await SquadService.instance.getLibrary(widget.squad.id);
    if (mounted) setState(() {
      _notes = notes;
      _loading = false;
    });
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

class SquadSettingsScreen extends StatelessWidget {
  final SquadInfo squad;
  const SquadSettingsScreen({super.key, required this.squad});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Squad Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                SelectableText(squad.inviteCode, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const Text('Share this code to invite members'),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
                await SquadService.instance.leaveSquad();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
          ),
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

  @override
  void initState() {
    super.initState();
    SquadService.instance.getRankings().then((r) {
      if (mounted) setState(() {
        _rankings = r;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Top Squads — Nigeria')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _rankings.length,
              itemBuilder: (context, i) {
                final s = _rankings[i];
                return ListTile(
                  leading: Text('#${s['rank']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  title: Text('${s['avatar_emoji']} ${s['name']}'),
                  trailing: Text('Lv.${s['level']} · ${s['xp']} XP'),
                );
              },
            ),
    );
  }
}
