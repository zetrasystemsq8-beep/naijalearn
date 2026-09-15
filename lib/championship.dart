// lib/championship.dart
//
// NaijaLearn Academic Championship — full Flutter implementation.
//
// Matches championship_final.sql exactly: bigint IDs throughout,
// server-side scoring/tie-breaking, correct_index NEVER sent to the
// client (student_get_match_questions withholds it, same pattern as
// get_battle_questions elsewhere in the app).
//
// DISPLAY RULE: amounts under 999 Cent show as "N Cent". At 999 Cent or
// above, they show as CP instead (999 Cent = 1 CP for display purposes
// only -- this is a UI convention, not a real currency exchange rate.
// The database always stores the precise integer Cent value; only the
// on-screen label changes).
//
// Tutors add players to their roster BY USERNAME -- there is no
// classroom system yet (confirmed empty). Swapping this for real
// classroom-sourced rosters later only touches the one "Add Player"
// dialog in TutorChampionshipScreen.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show Question, kSubjects, QuestionRepository;

/// =========================================================================
/// DISPLAY FORMATTING
/// =========================================================================

class CentFormat {
  CentFormat._();
  static const int _centsPerCP = 999;

  static String format(int cents) {
    if (cents < _centsPerCP) return '$cents Cent';
    final wholeCP = cents ~/ _centsPerCP;
    final remainder = cents % _centsPerCP;
    return remainder == 0 ? '$wholeCP CP' : '$wholeCP CP + $remainder Cent';
  }
}

/// =========================================================================
/// MODELS
/// =========================================================================

class ChampionshipSeason {
  final int id;
  final String name;
  final String? description;
  final String status;
  final DateTime? registrationStart;
  final DateTime? registrationEnd;
  final DateTime? startAt;
  final DateTime? endAt;
  final int? teamLimit;
  final int rosterLimit;
  final int playersPerRound;
  final int entryFeeCent;

  ChampionshipSeason({
    required this.id,
    required this.name,
    this.description,
    required this.status,
    this.registrationStart,
    this.registrationEnd,
    this.startAt,
    this.endAt,
    this.teamLimit,
    required this.rosterLimit,
    required this.playersPerRound,
    required this.entryFeeCent,
  });

  factory ChampionshipSeason.fromMap(Map<String, dynamic> m) => ChampionshipSeason(
        id: (m['id'] as num).toInt(),
        name: m['name'] as String,
        description: m['description'] as String?,
        status: m['status'] as String,
        registrationStart: m['registration_start'] != null ? DateTime.tryParse(m['registration_start']) : null,
        registrationEnd: m['registration_end'] != null ? DateTime.tryParse(m['registration_end']) : null,
        startAt: m['start_at'] != null ? DateTime.tryParse(m['start_at']) : null,
        endAt: m['end_at'] != null ? DateTime.tryParse(m['end_at']) : null,
        teamLimit: (m['team_limit'] as num?)?.toInt(),
        rosterLimit: (m['roster_limit'] as num?)?.toInt() ?? 10,
        playersPerRound: (m['players_per_round'] as num?)?.toInt() ?? 5,
        entryFeeCent: (m['entry_fee_cent'] as num?)?.toInt() ?? 0,
      );
}

class RosterPlayer {
  final String studentId;
  final String username;
  final String status;
  RosterPlayer({required this.studentId, required this.username, required this.status});

  factory RosterPlayer.fromMap(Map<String, dynamic> m) =>
      RosterPlayer(studentId: m['student_id'] as String, username: m['username'] as String, status: m['status'] as String);
}

class BracketRow {
  final int roundId;
  final int roundNumber;
  final String roundName;
  final String roundStatus;
  final int matchId;
  final int teamAId;
  final String teamAName;
  final int teamBId;
  final String teamBName;
  final double? teamAScore;
  final double? teamBScore;
  final int? winnerTeamId;
  final String matchStatus;

  BracketRow({
    required this.roundId, required this.roundNumber, required this.roundName, required this.roundStatus,
    required this.matchId, required this.teamAId, required this.teamAName, required this.teamBId, required this.teamBName,
    this.teamAScore, this.teamBScore, this.winnerTeamId, required this.matchStatus,
  });

  factory BracketRow.fromMap(Map<String, dynamic> m) => BracketRow(
        roundId: (m['round_id'] as num).toInt(),
        roundNumber: (m['round_number'] as num).toInt(),
        roundName: m['round_name'] as String,
        roundStatus: m['round_status'] as String,
        matchId: (m['match_id'] as num).toInt(),
        teamAId: (m['team_a_id'] as num).toInt(),
        teamAName: m['team_a_name'] as String,
        teamBId: (m['team_b_id'] as num).toInt(),
        teamBName: m['team_b_name'] as String,
        teamAScore: (m['team_a_score'] as num?)?.toDouble(),
        teamBScore: (m['team_b_score'] as num?)?.toDouble(),
        winnerTeamId: (m['winner_team_id'] as num?)?.toInt(),
        matchStatus: m['match_status'] as String,
      );
}

/// =========================================================================
/// SERVICE
/// =========================================================================

class ChampionshipService {
  ChampionshipService._();
  static final ChampionshipService instance = ChampionshipService._();
  SupabaseClient get _c => Supabase.instance.client;

  Future<int> adminCreateSeason({
    required String name, String? description, DateTime? regStart, DateTime? regEnd,
    DateTime? startAt, DateTime? endAt, int? teamLimit, int rosterLimit = 10, int playersPerRound = 5, int entryFeeCent = 0,
  }) async {
    final id = await _c.rpc('admin_create_championship_season', params: {
      'p_name': name, 'p_description': description,
      'p_registration_start': regStart?.toIso8601String(), 'p_registration_end': regEnd?.toIso8601String(),
      'p_start_at': startAt?.toIso8601String(), 'p_end_at': endAt?.toIso8601String(),
      'p_team_limit': teamLimit, 'p_roster_limit': rosterLimit, 'p_players_per_round': playersPerRound, 'p_entry_fee_cent': entryFeeCent,
    });
    return (id as num).toInt();
  }

  Future<void> adminUpdateSeasonStatus(int seasonId, String status) =>
      _c.rpc('admin_update_season_status', params: {'p_season_id': seasonId, 'p_status': status});

  Future<List<Map<String, dynamic>>> adminListSeasons() async {
    final rows = await _c.from('championship_seasons').select().order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> adminListTeams(int seasonId) async {
    final rows = await _c.from('championship_teams').select().eq('season_id', seasonId).order('created_at');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> adminApproveTeam(int teamId) => _c.rpc('admin_approve_team', params: {'p_team_id': teamId});
  Future<void> adminRejectTeam(int teamId, String reason) => _c.rpc('admin_reject_team', params: {'p_team_id': teamId, 'p_reason': reason});
  Future<void> adminDisqualifyTeam(int teamId, String reason) => _c.rpc('admin_disqualify_team', params: {'p_team_id': teamId, 'p_reason': reason});

  Future<int> adminCreateQuestionSet({required int seasonId, required String name, required String subject, required int durationSeconds, required List<String> questionIds}) async {
    final id = await _c.rpc('admin_create_question_set', params: {
      'p_season_id': seasonId, 'p_name': name, 'p_subject': subject, 'p_duration_seconds': durationSeconds, 'p_question_ids': questionIds,
    });
    return (id as num).toInt();
  }

  Future<List<Map<String, dynamic>>> adminListQuestionSets(int seasonId) async {
    final rows = await _c.from('championship_question_sets').select().eq('season_id', seasonId).order('created_at');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<int> adminCreateRound({required int seasonId, required int roundNumber, required String name, required DateTime opensAt, required DateTime closesAt, required int questionSetId}) async {
    final id = await _c.rpc('admin_create_round', params: {
      'p_season_id': seasonId, 'p_round_number': roundNumber, 'p_name': name,
      'p_opens_at': opensAt.toIso8601String(), 'p_closes_at': closesAt.toIso8601String(), 'p_question_set_id': questionSetId,
    });
    return (id as num).toInt();
  }

  Future<List<Map<String, dynamic>>> adminListRounds(int seasonId) async {
    final rows = await _c.from('championship_rounds').select().eq('season_id', seasonId).order('round_number');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> adminSetRoundStatus(int roundId, String status) => _c.rpc('admin_set_round_status', params: {'p_round_id': roundId, 'p_status': status});

  Future<int> adminCreateMatch({required int roundId, required int teamAId, required int teamBId}) async {
    final id = await _c.rpc('admin_create_match', params: {'p_round_id': roundId, 'p_team_a_id': teamAId, 'p_team_b_id': teamBId});
    return (id as num).toInt();
  }

  Future<List<Map<String, dynamic>>> adminListMatches(int roundId) async {
    final rows = await _c.from('championship_matches').select().eq('round_id', roundId).order('created_at');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, dynamic>> adminComputeMatchResult(int matchId) async {
    final result = await _c.rpc('admin_compute_match_result', params: {'p_match_id': matchId});
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> adminSetMatchWinner(int matchId, int winnerTeamId) =>
      _c.rpc('admin_set_match_winner', params: {'p_match_id': matchId, 'p_winner_team_id': winnerTeamId});

  Future<int> adminFinalizePrize({required int seasonId, required int winnerTeamId, required int prizePoolCent, required double platformPct, required double tutorPct, required double studentPct}) async {
    final id = await _c.rpc('admin_finalize_prize', params: {
      'p_season_id': seasonId, 'p_winner_team_id': winnerTeamId, 'p_prize_pool_cent': prizePoolCent,
      'p_platform_pct': platformPct, 'p_tutor_pct': tutorPct, 'p_student_pct': studentPct,
    });
    return (id as num).toInt();
  }

  Future<void> adminCreatePayoutsForPrize(int prizeId) => _c.rpc('admin_create_payouts_for_prize', params: {'p_prize_id': prizeId});
  Future<void> adminSetPayoutStatus(int payoutId, String status) => _c.rpc('admin_set_payout_status', params: {'p_payout_id': payoutId, 'p_status': status});

  Future<int> tutorRegisterTeam({required int seasonId, required String name, String? logoUrl, String? description, String? category}) async {
    final id = await _c.rpc('tutor_register_team', params: {
      'p_season_id': seasonId, 'p_name': name, 'p_logo_url': logoUrl, 'p_description': description, 'p_category': category,
    });
    return (id as num).toInt();
  }

  Future<Map<String, dynamic>?> tutorGetMyTeam(int seasonId) async {
    final result = await _c.rpc('tutor_get_my_team', params: {'p_season_id': seasonId});
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<RosterPlayer>> tutorGetMyRoster(int teamId) async {
    final rows = await _c.rpc('tutor_get_my_roster', params: {'p_team_id': teamId});
    return (rows as List).map((r) => RosterPlayer.fromMap(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<void> tutorAddPlayer(int teamId, String username) => _c.rpc('tutor_add_player_to_roster', params: {'p_team_id': teamId, 'p_username': username});
  Future<void> tutorRemovePlayer(int teamId, String studentId) => _c.rpc('tutor_remove_player_from_roster', params: {'p_team_id': teamId, 'p_student_id': studentId});
  Future<void> tutorLockRoster(int teamId) => _c.rpc('tutor_lock_roster', params: {'p_team_id': teamId});
  Future<void> tutorSelectRoundPlayers(int matchId, List<String> studentIds) =>
      _c.rpc('tutor_select_round_players', params: {'p_match_id': matchId, 'p_student_ids': studentIds});

  Future<Map<String, dynamic>> studentGetStatus(int seasonId) async {
    final result = await _c.rpc('student_get_my_championship_status', params: {'p_season_id': seasonId});
    return Map<String, dynamic>.from(result as Map);
  }

  Future<bool> studentIsSelected(int matchId) async {
    final result = await _c.rpc('student_get_my_selection', params: {'p_match_id': matchId});
    return result == true;
  }

  Future<List<Question>> studentGetMatchQuestions(int matchId) async {
    final rows = await _c.rpc('student_get_match_questions', params: {'p_match_id': matchId});
    return (rows as List).map((r) {
      final row = r as Map<String, dynamic>;
      return Question(
        id: row['id'] as String, subject: row['subject'] as String, year: 0,
        questionText: row['question_text'] as String, options: List<String>.from(row['options'] as List), correctIndex: -1,
      );
    }).toList();
  }

  Future<Map<String, dynamic>> studentStartAttempt(int matchId) async {
    final result = await _c.rpc('student_start_attempt', params: {'p_match_id': matchId});
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> studentSubmitAttempt(int matchId, Map<String, int> answers) async {
    final result = await _c.rpc('student_submit_attempt', params: {'p_match_id': matchId, 'p_answers': answers});
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<BracketRow>> getBracket(int seasonId) async {
    final rows = await _c.rpc('get_championship_bracket', params: {'p_season_id': seasonId});
    return (rows as List).map((r) => BracketRow.fromMap(Map<String, dynamic>.from(r as Map))).toList();
  }
}

/// =========================================================================
/// SEASON PICKER
/// =========================================================================

class ChampionshipHomeScreen extends StatefulWidget {
  const ChampionshipHomeScreen({super.key});
  @override
  State<ChampionshipHomeScreen> createState() => _ChampionshipHomeScreenState();
}

class _ChampionshipHomeScreenState extends State<ChampionshipHomeScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = ChampionshipService.instance.adminListSeasons();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Academic Championship')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final seasons = snapshot.data ?? [];
          if (seasons.isEmpty) {
            return Center(child: Text('No Championship seasons yet.', style: TextStyle(color: scheme.onSurfaceVariant)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: seasons.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final s = ChampionshipSeason.fromMap(seasons[i]);
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                        child: Text(s.status, style: const TextStyle(fontSize: 11)),
                      ),
                    ]),
                    if (s.description != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.description!)),
                    if (s.entryFeeCent > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Entry: ' + CentFormat.format(s.entryFeeCent), style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold, fontSize: 12))),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentChampionshipScreen(season: s))), child: const Text('Student View')),
                      OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TutorChampionshipScreen(season: s))), child: const Text('Tutor View')),
                      OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChampionshipBracketScreen(season: s))), child: const Text('Bracket')),
                      OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminChampionshipScreen(season: s))), child: const Text('Admin')),
                    ]),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminCreateSeasonScreen()));
          setState(() => _future = ChampionshipService.instance.adminListSeasons());
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Season'),
      ),
    );
  }
}

/// =========================================================================
/// ADMIN -- create season
/// =========================================================================

class AdminCreateSeasonScreen extends StatefulWidget {
  const AdminCreateSeasonScreen({super.key});
  @override
  State<AdminCreateSeasonScreen> createState() => _AdminCreateSeasonScreenState();
}

class _AdminCreateSeasonScreenState extends State<AdminCreateSeasonScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _rosterCtrl = TextEditingController(text: '10');
  final _perRoundCtrl = TextEditingController(text: '5');
  final _entryFeeCtrl = TextEditingController(text: '0');
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter a season name.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ChampionshipService.instance.adminCreateSeason(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        rosterLimit: int.tryParse(_rosterCtrl.text) ?? 10,
        playersPerRound: int.tryParse(_perRoundCtrl.text) ?? 5,
        entryFeeCent: int.tryParse(_entryFeeCtrl.text) ?? 0,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Championship Season')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Season name')),
          const SizedBox(height: 12),
          TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
          const SizedBox(height: 12),
          TextField(controller: _rosterCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Roster limit per team')),
          const SizedBox(height: 12),
          TextField(controller: _perRoundCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Players per round')),
          const SizedBox(height: 12),
          TextField(controller: _entryFeeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Entry fee (Cent)')),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _create, child: _busy ? const CircularProgressIndicator() : const Text('Create Season')),
        ],
      ),
    );
  }
}

/// =========================================================================
/// ADMIN DASHBOARD
/// =========================================================================

class AdminChampionshipScreen extends StatefulWidget {
  final ChampionshipSeason season;
  const AdminChampionshipScreen({super.key, required this.season});
  @override
  State<AdminChampionshipScreen> createState() => _AdminChampionshipScreenState();
}

class _AdminChampionshipScreenState extends State<AdminChampionshipScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late Future<List<Map<String, dynamic>>> _teamsFuture;
  late Future<List<Map<String, dynamic>>> _roundsFuture;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _reload();
  }

  void _reload() {
    _teamsFuture = ChampionshipService.instance.adminListTeams(widget.season.id);
    _roundsFuture = ChampionshipService.instance.adminListRounds(widget.season.id);
  }

  Future<void> _approve(int teamId) async {
    await ChampionshipService.instance.adminApproveTeam(teamId);
    setState(_reload);
  }

  Future<void> _reject(int teamId) async {
    await ChampionshipService.instance.adminRejectTeam(teamId, 'Rejected by admin');
    setState(_reload);
  }

  Future<void> _disqualify(int teamId) async {
    await ChampionshipService.instance.adminDisqualifyTeam(teamId, 'Disqualified by admin');
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Admin -- ' + widget.season.name),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Teams'), Tab(text: 'Rounds'), Tab(text: 'Prizes')]),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _teamsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final teams = snapshot.data ?? [];
              if (teams.isEmpty) return const Center(child: Text('No teams registered yet.'));
              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: teams.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final t = teams[i];
                  final status = t['status'] as String;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(status, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      ])),
                      if (status == 'pending') ...[
                        IconButton(icon: const Icon(Icons.check_circle_rounded, color: Colors.green), onPressed: () => _approve((t['id'] as num).toInt())),
                        IconButton(icon: const Icon(Icons.cancel_rounded, color: Colors.red), onPressed: () => _reject((t['id'] as num).toInt())),
                      ] else if (status == 'approved')
                        IconButton(icon: const Icon(Icons.block_rounded, color: Colors.orange), tooltip: 'Disqualify', onPressed: () => _disqualify((t['id'] as num).toInt())),
                    ]),
                  );
                },
              );
            },
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _roundsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final rounds = snapshot.data ?? [];
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  ...rounds.map((r) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text((r['name'] as String) + ' (Round ' + r['round_number'].toString() + ')', style: const TextStyle(fontWeight: FontWeight.bold))),
                            Text(r['status'] as String, style: TextStyle(fontSize: 12, color: scheme.primary)),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, children: [
                            OutlinedButton(
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminMatchesScreen(roundId: (r['id'] as num).toInt(), season: widget.season))),
                              child: const Text('Matches'),
                            ),
                            OutlinedButton(onPressed: () async { await ChampionshipService.instance.adminSetRoundStatus((r['id'] as num).toInt(), 'open'); setState(_reload); }, child: const Text('Open')),
                            OutlinedButton(onPressed: () async { await ChampionshipService.instance.adminSetRoundStatus((r['id'] as num).toInt(), 'closed'); setState(_reload); }, child: const Text('Close')),
                          ]),
                        ]),
                      )),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminCreateRoundScreen(season: widget.season)));
                      setState(_reload);
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New Round'),
                  ),
                ],
              );
            },
          ),
          AdminPrizeTab(season: widget.season),
        ],
      ),
    );
  }
}

class AdminCreateRoundScreen extends StatefulWidget {
  final ChampionshipSeason season;
  const AdminCreateRoundScreen({super.key, required this.season});
  @override
  State<AdminCreateRoundScreen> createState() => _AdminCreateRoundScreenState();
}

class _AdminCreateRoundScreenState extends State<AdminCreateRoundScreen> {
  final _nameCtrl = TextEditingController();
  final _roundNumberCtrl = TextEditingController(text: '1');
  final _durationCtrl = TextEditingController(text: '1800');
  String _subject = kSubjects.first.name;
  int _questionCount = 20;
  DateTime _opensAt = DateTime.now().add(const Duration(hours: 1));
  DateTime _closesAt = DateTime.now().add(const Duration(hours: 25));
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    setState(() { _busy = true; _error = null; });
    try {
      final pool = List<Question>.from(QuestionRepository.getForSubject(_subject))..shuffle();
      final ids = pool.take(_questionCount).map((q) => q.id).toList();
      if (ids.isEmpty) throw Exception('No questions available for ' + _subject + '.');

      final qsetId = await ChampionshipService.instance.adminCreateQuestionSet(
        seasonId: widget.season.id, name: _nameCtrl.text.trim() + ' -- ' + _subject,
        subject: _subject, durationSeconds: int.tryParse(_durationCtrl.text) ?? 1800, questionIds: ids,
      );

      await ChampionshipService.instance.adminCreateRound(
        seasonId: widget.season.id, roundNumber: int.tryParse(_roundNumberCtrl.text) ?? 1,
        name: _nameCtrl.text.trim(), opensAt: _opensAt, closesAt: _closesAt, questionSetId: qsetId,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate(bool isOpen) async {
    final base = isOpen ? _opensAt : _closesAt;
    final date = await showDatePicker(context: context, initialDate: base, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (time == null) return;
    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => isOpen ? _opensAt = combined : _closesAt = combined);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Round')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Round name (e.g. Quarter Final)')),
          const SizedBox(height: 12),
          TextField(controller: _roundNumberCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Round number')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _subject,
            items: kSubjects.map((s) => DropdownMenuItem(value: s.name, child: Text(s.name))).toList(),
            onChanged: (v) => setState(() => _subject = v!),
            decoration: const InputDecoration(labelText: 'Subject'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _questionCount,
            items: const [10, 15, 20, 25, 30].map((c) => DropdownMenuItem(value: c, child: Text(c.toString() + ' questions'))).toList(),
            onChanged: (v) => setState(() => _questionCount = v!),
            decoration: const InputDecoration(labelText: 'Question count'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _durationCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duration (seconds)')),
          const SizedBox(height: 16),
          ListTile(title: const Text('Opens at'), subtitle: Text(_opensAt.toString()), trailing: const Icon(Icons.edit_calendar_rounded), onTap: () => _pickDate(true)),
          ListTile(title: const Text('Closes at'), subtitle: Text(_closesAt.toString()), trailing: const Icon(Icons.edit_calendar_rounded), onTap: () => _pickDate(false)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _create, child: _busy ? const CircularProgressIndicator() : const Text('Create Round')),
        ],
      ),
    );
  }
}

class AdminMatchesScreen extends StatefulWidget {
  final int roundId;
  final ChampionshipSeason season;
  const AdminMatchesScreen({super.key, required this.roundId, required this.season});
  @override
  State<AdminMatchesScreen> createState() => _AdminMatchesScreenState();
}

class _AdminMatchesScreenState extends State<AdminMatchesScreen> {
  late Future<List<Map<String, dynamic>>> _matchesFuture;
  late Future<List<Map<String, dynamic>>> _teamsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _matchesFuture = ChampionshipService.instance.adminListMatches(widget.roundId);
    _teamsFuture = ChampionshipService.instance.adminListTeams(widget.season.id);
  }

  Future<void> _createMatch() async {
    final teams = await _teamsFuture;
    final approved = teams.where((t) => t['status'] == 'approved').toList();
    if (approved.length < 2 || !mounted) return;

    int? teamA, teamB;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('New Match'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              items: approved.map((t) => DropdownMenuItem(value: (t['id'] as num).toInt(), child: Text(t['name'] as String))).toList(),
              onChanged: (v) => setDlgState(() => teamA = v),
              decoration: const InputDecoration(labelText: 'Team A'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              items: approved.map((t) => DropdownMenuItem(value: (t['id'] as num).toInt(), child: Text(t['name'] as String))).toList(),
              onChanged: (v) => setDlgState(() => teamB = v),
              decoration: const InputDecoration(labelText: 'Team B'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: (teamA != null && teamB != null && teamA != teamB)
                  ? () async {
                      await ChampionshipService.instance.adminCreateMatch(roundId: widget.roundId, teamAId: teamA!, teamBId: teamB!);
                      if (context.mounted) Navigator.pop(context);
                      setState(_reload);
                    }
                  : null,
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Matches')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _matchesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final matches = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ...matches.map((m) {
                final status = m['status'] as String;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Match #' + m['id'].toString() + ' -- ' + status, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(m['team_a_score'].toString() + ' vs ' + m['team_b_score'].toString(), style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    if (status != 'completed')
                      OutlinedButton(
                        onPressed: () async {
                          final result = await ChampionshipService.instance.adminComputeMatchResult((m['id'] as num).toInt());
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Result: ' + result['status'].toString())));
                          }
                          setState(_reload);
                        },
                        child: const Text('Compute Result'),
                      ),
                  ]),
                );
              }),
              const SizedBox(height: 10),
              FilledButton.icon(onPressed: _createMatch, icon: const Icon(Icons.add_rounded), label: const Text('New Match')),
            ],
          );
        },
      ),
    );
  }
}

class AdminPrizeTab extends StatefulWidget {
  final ChampionshipSeason season;
  const AdminPrizeTab({super.key, required this.season});
  @override
  State<AdminPrizeTab> createState() => _AdminPrizeTabState();
}

class _AdminPrizeTabState extends State<AdminPrizeTab> {
  final _winnerTeamIdCtrl = TextEditingController();
  final _poolCtrl = TextEditingController(text: '0');
  final _platformPctCtrl = TextEditingController(text: '20');
  final _tutorPctCtrl = TextEditingController(text: '30');
  final _studentPctCtrl = TextEditingController(text: '50');
  bool _busy = false;
  String? _error;
  int? _lastPrizeId;

  Future<void> _finalize() async {
    setState(() { _busy = true; _error = null; });
    try {
      final id = await ChampionshipService.instance.adminFinalizePrize(
        seasonId: widget.season.id,
        winnerTeamId: int.parse(_winnerTeamIdCtrl.text),
        prizePoolCent: int.parse(_poolCtrl.text),
        platformPct: double.parse(_platformPctCtrl.text),
        tutorPct: double.parse(_tutorPctCtrl.text),
        studentPct: double.parse(_studentPctCtrl.text),
      );
      setState(() => _lastPrizeId = id);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Finalize Prize', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        TextField(controller: _winnerTeamIdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Winner Team ID')),
        const SizedBox(height: 10),
        TextField(controller: _poolCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Prize pool (Cent)')),
        const SizedBox(height: 10),
        TextField(controller: _platformPctCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Platform %')),
        const SizedBox(height: 10),
        TextField(controller: _tutorPctCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tutor %')),
        const SizedBox(height: 10),
        TextField(controller: _studentPctCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Student %')),
        const Text('Percentages must total 100.', style: TextStyle(fontSize: 11, color: Colors.grey)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _finalize, child: _busy ? const CircularProgressIndicator() : const Text('Finalize Prize')),
        if (_lastPrizeId != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () async {
              await ChampionshipService.instance.adminCreatePayoutsForPrize(_lastPrizeId!);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payouts created.')));
            },
            child: const Text('Create Payouts for This Prize'),
          ),
        ],
      ],
    );
  }
}

/// =========================================================================
/// TUTOR SCREEN
/// =========================================================================

class TutorChampionshipScreen extends StatefulWidget {
  final ChampionshipSeason season;
  const TutorChampionshipScreen({super.key, required this.season});
  @override
  State<TutorChampionshipScreen> createState() => _TutorChampionshipScreenState();
}

class _TutorChampionshipScreenState extends State<TutorChampionshipScreen> {
  Map<String, dynamic>? _team;
  List<RosterPlayer> _roster = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final team = await ChampionshipService.instance.tutorGetMyTeam(widget.season.id);
      List<RosterPlayer> roster = [];
      if (team != null) roster = await ChampionshipService.instance.tutorGetMyRoster((team['id'] as num).toInt());
      if (!mounted) return;
      setState(() { _team = team; _roster = roster; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _registerTeam() async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Register Your Team'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Team name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                await ChampionshipService.instance.tutorRegisterTeam(seasonId: widget.season.id, name: nameCtrl.text.trim());
                if (context.mounted) Navigator.pop(context);
                _load();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }

  Future<void> _addPlayer() async {
    if (_team == null) return;
    final usernameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Player by Username'),
        content: TextField(controller: usernameCtrl, decoration: const InputDecoration(labelText: 'Student username')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                await ChampionshipService.instance.tutorAddPlayer((_team!['id'] as num).toInt(), usernameCtrl.text.trim());
                if (context.mounted) Navigator.pop(context);
                _load();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Tutor -- ' + widget.season.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _team == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text("You haven't registered a team for this season."),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: _registerTeam, child: const Text('Register Team')),
                        ]),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_team!['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            Text('Status: ' + _team!['status'].toString(), style: TextStyle(color: scheme.onSurfaceVariant)),
                            Text('Roster locked: ' + _team!['roster_locked'].toString(), style: TextStyle(color: scheme.onSurfaceVariant)),
                          ]),
                        ),
                        const SizedBox(height: 20),
                        Row(children: [
                          const Text('Roster', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const Spacer(),
                          if (_team!['roster_locked'] != true) TextButton(onPressed: _addPlayer, child: const Text('+ Add Player')),
                        ]),
                        const SizedBox(height: 8),
                        ..._roster.map((p) => ListTile(
                              title: Text(p.username),
                              trailing: (_team!['roster_locked'] != true)
                                  ? IconButton(
                                      icon: const Icon(Icons.remove_circle_outline_rounded),
                                      onPressed: () async {
                                        await ChampionshipService.instance.tutorRemovePlayer((_team!['id'] as num).toInt(), p.studentId);
                                        _load();
                                      },
                                    )
                                  : null,
                            )),
                        if (_team!['roster_locked'] != true && _roster.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: () async {
                              await ChampionshipService.instance.tutorLockRoster((_team!['id'] as num).toInt());
                              _load();
                            },
                            child: const Text('Lock Roster'),
                          ),
                        ],
                      ],
                    ),
    );
  }
}

/// =========================================================================
/// STUDENT SCREEN
/// =========================================================================

class StudentChampionshipScreen extends StatefulWidget {
  final ChampionshipSeason season;
  const StudentChampionshipScreen({super.key, required this.season});
  @override
  State<StudentChampionshipScreen> createState() => _StudentChampionshipScreenState();
}

class _StudentChampionshipScreenState extends State<StudentChampionshipScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ChampionshipService.instance.studentGetStatus(widget.season.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Student -- ' + widget.season.name)),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final status = snapshot.data ?? {};
          if (status['on_team'] != true) {
            return Center(child: Text("You're not on a Championship team this season.", style: TextStyle(color: scheme.onSurfaceVariant)));
          }
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: scheme.primaryContainer.withOpacity(0.4), borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(status['team_name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                Text('Coach: ' + status['coach_name'].toString(), style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                const Text('Check the Bracket screen for your upcoming match, then come back here when your tutor selects you.'),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// =========================================================================
/// MATCH ATTEMPT
/// =========================================================================

class ChampionshipAttemptScreen extends StatefulWidget {
  final int matchId;
  const ChampionshipAttemptScreen({super.key, required this.matchId});
  @override
  State<ChampionshipAttemptScreen> createState() => _ChampionshipAttemptScreenState();
}

class _ChampionshipAttemptScreenState extends State<ChampionshipAttemptScreen> {
  List<Question> _questions = [];
  late List<int?> _answers;
  int _index = 0;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  DateTime? _startedAt;
  int _durationSeconds = 0;
  int _remaining = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final start = await ChampionshipService.instance.studentStartAttempt(widget.matchId);
      _startedAt = DateTime.tryParse(start['started_at'].toString()) ?? DateTime.now();
      _durationSeconds = (start['duration_seconds'] as num).toInt();

      final questions = await ChampionshipService.instance.studentGetMatchQuestions(widget.matchId);
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _answers = List<int?>.filled(questions.length, null);
        _loading = false;
      });
      _startTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _startTimer() {
    void tick() {
      final elapsed = DateTime.now().difference(_startedAt!).inSeconds;
      final remaining = _durationSeconds - elapsed;
      if (!mounted) return;
      setState(() => _remaining = remaining > 0 ? remaining : 0);
      if (remaining <= 0) {
        _timer?.cancel();
        _submit();
      }
    }
    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    _timer?.cancel();
    final answersMap = <String, int>{
      for (var i = 0; i < _questions.length; i++)
        if (_answers[i] != null) _questions[i].id: _answers[i]!,
    };
    try {
      final result = await ChampionshipService.instance.studentSubmitAttempt(widget.matchId, answersMap);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Submitted'), automaticallyImplyLeading: false),
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              Text('Score: ' + result['score'].toString() + ' (' + result['correct_count'].toString() + ' correct)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 20),
              FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('Back to Home')),
            ]),
          ),
        ),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(body: Center(child: Text(_error!)));
    if (_questions.isEmpty) return const Scaffold(body: Center(child: Text('No questions available.')));

    final scheme = Theme.of(context).colorScheme;
    final q = _questions[_index];
    final m = _remaining ~/ 60;
    final s = _remaining % 60;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Championship Round'),
          automaticallyImplyLeading: false,
          actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: Text(m.toString() + ':' + s.toString().padLeft(2, '0'), style: const TextStyle(fontWeight: FontWeight.bold))))],
        ),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Text('Question ' + (_index + 1).toString() + ' of ' + _questions.length.toString())),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                  child: Text(q.questionText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 16),
                ...List.generate(q.options.length, (i) {
                  final isSelected = _answers[_index] == i;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(backgroundColor: isSelected ? scheme.primaryContainer : null, padding: const EdgeInsets.all(14)),
                      onPressed: () => setState(() => _answers[_index] = i),
                      child: Align(alignment: Alignment.centerLeft, child: Text(q.options[i])),
                    ),
                  );
                }),
              ]),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                if (_index > 0) Expanded(child: OutlinedButton(onPressed: () => setState(() => _index--), child: const Text('Previous'))),
                if (_index > 0) const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _submitting ? null : () => _index < _questions.length - 1 ? setState(() => _index++) : _submit(),
                    child: _submitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_index < _questions.length - 1 ? 'Next' : 'Submit'),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// =========================================================================
/// BRACKET
/// =========================================================================

class ChampionshipBracketScreen extends StatefulWidget {
  final ChampionshipSeason season;
  const ChampionshipBracketScreen({super.key, required this.season});
  @override
  State<ChampionshipBracketScreen> createState() => _ChampionshipBracketScreenState();
}

class _ChampionshipBracketScreenState extends State<ChampionshipBracketScreen> {
  late Future<List<BracketRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = ChampionshipService.instance.getBracket(widget.season.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Bracket -- ' + widget.season.name)),
      body: FutureBuilder<List<BracketRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) return const Center(child: Text('No matches scheduled yet.'));

          final byRound = <int, List<BracketRow>>{};
          for (final r in rows) byRound.putIfAbsent(r.roundNumber, () => []).add(r);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: byRound.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Round ' + entry.key.toString() + ' -- ' + entry.value.first.roundName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...entry.value.map((m) {
                    final aWon = m.winnerTeamId == m.teamAId;
                    final bWon = m.winnerTeamId == m.teamBId;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                      child: Column(children: [
                        Row(children: [
                          Expanded(child: Text(m.teamAName, style: TextStyle(fontWeight: aWon ? FontWeight.bold : FontWeight.normal))),
                          Text(m.teamAScore?.toStringAsFixed(0) ?? '-'),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(child: Text(m.teamBName, style: TextStyle(fontWeight: bWon ? FontWeight.bold : FontWeight.normal))),
                          Text(m.teamBScore?.toStringAsFixed(0) ?? '-'),
                        ]),
                        const SizedBox(height: 6),
                        Text(m.matchStatus, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ]),
                    );
                  }),
                ]),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
