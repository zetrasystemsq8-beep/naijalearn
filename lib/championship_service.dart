// lib/championship_service.dart
//
// REPLACES the earlier version entirely. Every write in this schema goes
// through a SECURITY DEFINER RPC — there are no client-writable INSERT/
// UPDATE RLS policies on any championship_* table, by design (see the
// clean-rebuild SQL: only `for select` policies exist). So unlike the
// previous version of this file, there is no direct .insert()/.update()
// anywhere below — only .select() for reads the RLS allows, and .rpc()
// for everything else.

import 'package:supabase_flutter/supabase_flutter.dart';
import 'championship_models.dart';

class ChampionshipService {
  ChampionshipService._();
  static final ChampionshipService instance = ChampionshipService._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  // ---------------------------------------------------------------
  // ROLE CHECKS — untouched by the championship migration, same as
  // before: profiles.is_admin and tutor_profiles.status='approved'.
  // ---------------------------------------------------------------

  Future<bool> isCurrentUserAdmin() async {
    final uid = _uid;
    if (uid == null) return false;
    final row = await _client.from('profiles').select('is_admin').eq('id', uid).maybeSingle();
    return row?['is_admin'] == true;
  }

  Future<bool> isCurrentUserApprovedTutor() async {
    final uid = _uid;
    if (uid == null) return false;
    final row = await _client.from('tutor_profiles').select('status').eq('user_id', uid).maybeSingle();
    return row?['status'] == 'approved';
  }

  Future<List<Map<String, dynamic>>> fetchMyClassrooms() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _client.from('classrooms').select('id, name').eq('tutor_id', uid);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<num> fetchMyCentBalance() async {
    final uid = _uid;
    if (uid == null) return 0;
    final row = await _client.from('app_currency_balances').select('balance').eq('user_id', uid).eq('app_id', 'naijalearn').maybeSingle();
    return (row?['balance'] as num?) ?? 0;
  }

  // ---------------------------------------------------------------
  // SEASONS — plain reads (cs_select allows any authenticated user);
  // writes go through admin_* RPCs.
  // ---------------------------------------------------------------

  Future<List<ChampionshipSeason>> fetchAllSeasons() async {
    final rows = await _client.from('championship_seasons').select().order('created_at', ascending: false);
    return rows.map<ChampionshipSeason>(ChampionshipSeason.fromMap).toList();
  }

  Future<ChampionshipSeason?> fetchActiveSeason() async {
    final rows = await _client
        .from('championship_seasons')
        .select()
        .not('status', 'in', '(completed,cancelled)')
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return ChampionshipSeason.fromMap(rows.first);
  }

  Future<int> adminCreateSeason({
    required String name,
    String? description,
    DateTime? registrationStart,
    DateTime? registrationEnd,
    DateTime? startAt,
    DateTime? endAt,
    int? teamLimit,
    int rosterLimit = 10,
    int playersPerRound = 5,
    int entryFeeCent = 0,
  }) async {
    final id = await _client.rpc('admin_create_championship_season', params: {
      'p_name': name,
      'p_description': description,
      'p_registration_start': registrationStart?.toIso8601String(),
      'p_registration_end': registrationEnd?.toIso8601String(),
      'p_start_at': startAt?.toIso8601String(),
      'p_end_at': endAt?.toIso8601String(),
      'p_team_limit': teamLimit,
      'p_roster_limit': rosterLimit,
      'p_players_per_round': playersPerRound,
      'p_entry_fee_cent': entryFeeCent,
    });
    return id as int;
  }

  Future<void> adminUpdateSeasonStatus(int seasonId, String status) async {
    await _client.rpc('admin_update_season_status', params: {'p_season_id': seasonId, 'p_status': status});
  }

  // ---------------------------------------------------------------
  // TEAMS
  // ---------------------------------------------------------------

  Future<List<ChampionshipTeam>> fetchTeamsForSeason(int seasonId) async {
    final rows = await _client.from('championship_teams').select().eq('season_id', seasonId);
    return rows.map<ChampionshipTeam>(ChampionshipTeam.fromMap).toList();
  }

  Future<ChampionshipTeam?> fetchTeamById(int teamId) async {
    final row = await _client.from('championship_teams').select().eq('id', teamId).maybeSingle();
    if (row == null) return null;
    return ChampionshipTeam.fromMap(row);
  }

  /// The current tutor's team for a season, or null if they haven't
  /// registered one. Uses tutor_get_my_team to discover the ID (it
  /// resolves the caller's tutor_profiles.id internally), then a plain
  /// select for the FULL row — the RPC's own jsonb omits description/category.
  Future<ChampionshipTeam?> fetchMyTutorTeam(int seasonId) async {
    final result = await _client.rpc('tutor_get_my_team', params: {'p_season_id': seasonId});
    if (result == null) return null;
    final id = (result as Map<String, dynamic>)['id'] as int;
    return fetchTeamById(id);
  }

  /// Atomic paid registration: verifies approved tutor + classroom
  /// ownership, spends the entry fee, creates the team — all inside
  /// tutor_register_team. Throws with the server's message on failure.
  Future<int> registerTeam({
    required int seasonId,
    required int classroomId,
    required String name,
    String? logoUrl,
    String? description,
    String? category,
  }) async {
    final id = await _client.rpc('tutor_register_team', params: {
      'p_season_id': seasonId,
      'p_classroom_id': classroomId,
      'p_name': name,
      'p_logo_url': logoUrl,
      'p_description': description,
      'p_category': category,
    });
    return id as int;
  }

  Future<void> adminApproveTeam(int teamId) async {
    await _client.rpc('admin_approve_team', params: {'p_team_id': teamId});
  }

  Future<void> adminRejectTeam(int teamId, String reason) async {
    await _client.rpc('admin_reject_team', params: {'p_team_id': teamId, 'p_reason': reason});
  }

  Future<void> adminDisqualifyTeam(int teamId, String reason) async {
    await _client.rpc('admin_disqualify_team', params: {'p_team_id': teamId, 'p_reason': reason});
  }

  Future<void> adminRefundTeam({required int teamId, required int amountCent, required String reason}) async {
    await _client.rpc('admin_refund_team', params: {
      'p_team_id': teamId,
      'p_amount_cent': amountCent,
      'p_reason': reason,
    });
  }

  // ---------------------------------------------------------------
  // ROSTER
  // ---------------------------------------------------------------

  /// Direct select, not the tutor_get_my_roster RPC — that RPC checks
  /// the caller IS the team's tutor internally and returns nothing
  /// otherwise, but championship_players has an open select policy
  /// (any authenticated user), so students/admin can read it directly.
  Future<List<ChampionshipPlayer>> fetchRoster(int teamId) async {
    final rows = await _client.from('championship_players').select().eq('team_id', teamId).eq('status', 'active');
    return rows.map<ChampionshipPlayer>(ChampionshipPlayer.fromMap).toList();
  }

  /// Throws with a clear message if the username doesn't exist, isn't
  /// in the team's classroom, is already on another team this season,
  /// or the roster is full/locked — all enforced server-side.
  Future<void> addPlayerToRoster({required int teamId, required String username}) async {
    await _client.rpc('tutor_add_player_to_roster', params: {'p_team_id': teamId, 'p_username': username});
  }

  Future<void> removePlayerFromRoster({required int teamId, required String studentId}) async {
    await _client.rpc('tutor_remove_player_from_roster', params: {'p_team_id': teamId, 'p_student_id': studentId});
  }

  Future<void> lockRoster(int teamId) async {
    await _client.rpc('tutor_lock_roster', params: {'p_team_id': teamId});
  }

  Future<void> adminUnlockRoster(int teamId) async {
    await _client.rpc('admin_unlock_roster', params: {'p_team_id': teamId});
  }

  // ---------------------------------------------------------------
  // QUESTION SETS
  // ---------------------------------------------------------------

  Future<int> adminCreateQuestionSet({
    required int seasonId,
    required String name,
    required String subject,
    required int durationSeconds,
    required List<String> questionIds,
  }) async {
    final id = await _client.rpc('admin_create_question_set', params: {
      'p_season_id': seasonId,
      'p_name': name,
      'p_subject': subject,
      'p_duration_seconds': durationSeconds,
      'p_question_ids': questionIds,
    });
    return id as int;
  }

  /// Requires the RLS patch (cqs_select for admin) — without it this
  /// silently returns an empty list rather than erroring.
  Future<List<ChampionshipQuestionSet>> fetchQuestionSetsForSeason(int seasonId) async {
    final rows = await _client.from('championship_question_sets').select().eq('season_id', seasonId);
    return rows.map<ChampionshipQuestionSet>(ChampionshipQuestionSet.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> fetchQuestionsBySubject(String subject, {int limit = 100}) async {
    final rows = await _client.from('questions').select('id, question_text').eq('subject', subject).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<String>> fetchDistinctSubjects() async {
    final rows = await _client.from('questions').select('subject');
    return rows.map<String>((r) => r['subject'] as String).toSet().toList()..sort();
  }

  // ---------------------------------------------------------------
  // ROUNDS
  // ---------------------------------------------------------------

  Future<List<ChampionshipRound>> fetchRounds(int seasonId) async {
    final rows = await _client.from('championship_rounds').select().eq('season_id', seasonId).order('round_number');
    return rows.map<ChampionshipRound>(ChampionshipRound.fromMap).toList();
  }

  Future<int> adminCreateRound({
    required int seasonId,
    required int roundNumber,
    required String name,
    required DateTime opensAt,
    required DateTime closesAt,
    required int questionSetId,
  }) async {
    final id = await _client.rpc('admin_create_round', params: {
      'p_season_id': seasonId,
      'p_round_number': roundNumber,
      'p_name': name,
      'p_opens_at': opensAt.toIso8601String(),
      'p_closes_at': closesAt.toIso8601String(),
      'p_question_set_id': questionSetId,
    });
    return id as int;
  }

  Future<void> adminSetRoundStatus(int roundId, String status) async {
    await _client.rpc('admin_set_round_status', params: {'p_round_id': roundId, 'p_status': status});
  }

  /// Scores every match in the round and closes it — use this, not
  /// adminSetRoundStatus(roundId, 'closed'), or nothing gets scored.
  Future<void> adminCloseRound(int roundId) async {
    await _client.rpc('admin_close_round', params: {'p_round_id': roundId});
  }

  /// The only way to change a round's question set after any attempt
  /// exists — wipes attempts/answers and resets to scheduled.
  Future<void> adminResetRound(int roundId) async {
    await _client.rpc('admin_reset_round', params: {'p_round_id': roundId});
  }

  // ---------------------------------------------------------------
  // MATCHES / BRACKET
  // ---------------------------------------------------------------

  Future<int> adminCreateMatch({required int roundId, required int teamAId, required int teamBId}) async {
    final id = await _client.rpc('admin_create_match', params: {
      'p_round_id': roundId,
      'p_team_a_id': teamAId,
      'p_team_b_id': teamBId,
    });
    return id as int;
  }

  /// The single source of truth for round+match+team-name+score display
  /// across every screen — scores are null unless match_status='completed',
  /// computed server-side in the RPC itself.
  Future<List<ChampionshipBracketRow>> fetchBracket(int seasonId) async {
    final rows = await _client.rpc('get_championship_bracket', params: {'p_season_id': seasonId});
    return (rows as List).map<ChampionshipBracketRow>((m) => ChampionshipBracketRow.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> adminComputeMatchResult(int matchId) async {
    final result = await _client.rpc('admin_compute_match_result', params: {'p_match_id': matchId});
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> adminSetMatchWinner({required int matchId, required int winnerTeamId}) async {
    await _client.rpc('admin_set_match_winner', params: {'p_match_id': matchId, 'p_winner_team_id': winnerTeamId});
  }

  // ---------------------------------------------------------------
  // SELECTIONS
  // ---------------------------------------------------------------

  /// Whole-list replace, not per-player toggle — the server deletes the
  /// team's existing selection for this match and inserts exactly this set.
  Future<void> selectRoundPlayers({required int matchId, required List<String> studentIds}) async {
    await _client.rpc('tutor_select_round_players', params: {'p_match_id': matchId, 'p_student_ids': studentIds});
  }

  Future<List<String>> fetchSelectionForMatch({required int matchId, required int teamId}) async {
    final rows = await _client
        .from('championship_selections')
        .select('student_id')
        .eq('match_id', matchId)
        .eq('team_id', teamId);
    return rows.map<String>((r) => r['student_id'] as String).toList();
  }

  Future<bool> isCurrentStudentSelected(int matchId) async {
    final result = await _client.rpc('student_get_my_selection', params: {'p_match_id': matchId});
    return result as bool;
  }

  // ---------------------------------------------------------------
  // STUDENT STATUS / ATTEMPTS
  // ---------------------------------------------------------------

  Future<Map<String, dynamic>> studentGetMyStatus(int seasonId) async {
    final result = await _client.rpc('student_get_my_championship_status', params: {'p_season_id': seasonId});
    return Map<String, dynamic>.from(result as Map);
  }

  /// Direct select, not an RPC — ca_select's RLS already scopes this to
  /// the caller's own row (student_id = auth.uid()), so no function is
  /// needed just to read it back.
  Future<Map<String, dynamic>?> fetchMyAttempt(int matchId) async {
    final uid = _uid;
    if (uid == null) return null;
    return await _client.from('championship_attempts').select().eq('match_id', matchId).eq('student_id', uid).maybeSingle();
  }

  Stream<List<Map<String, dynamic>>> watchMatch(int matchId) {
    return _client.from('championship_matches').stream(primaryKey: ['id']).eq('id', matchId);
  }

  Stream<List<Map<String, dynamic>>> watchRound(int roundId) {
    return _client.from('championship_rounds').stream(primaryKey: ['id']).eq('id', roundId);
  }

  Future<List<ChampionshipQuizQuestion>> fetchMatchQuestions(int matchId) async {
    final rows = await _client.rpc('student_get_match_questions', params: {'p_match_id': matchId});
    return (rows as List).map<ChampionshipQuizQuestion>((m) => ChampionshipQuizQuestion.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<ChampionshipAttemptState> startAttempt(int matchId) async {
    final result = await _client.rpc('student_start_attempt', params: {'p_match_id': matchId});
    return ChampionshipAttemptState.fromMap(Map<String, dynamic>.from(result as Map));
  }

  /// [answers] maps questionId -> selected option INDEX. Returns
  /// {score, correct_count, expired} — expired=true means the server
  /// rejected the timing and zeroed the score instead of grading.
  Future<Map<String, dynamic>> submitAttempt({required int matchId, required Map<String, int> answers}) async {
    final result = await _client.rpc('student_submit_attempt', params: {
      'p_match_id': matchId,
      'p_answers': answers,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  // ---------------------------------------------------------------
  // PRIZES & PAYOUTS
  // ---------------------------------------------------------------

  Future<int> adminFinalizePrize({
    required int seasonId,
    required int winnerTeamId,
    required int prizePoolCent,
    required num platformPct,
    required num tutorPct,
    required num studentPct,
  }) async {
    final id = await _client.rpc('admin_finalize_prize', params: {
      'p_season_id': seasonId,
      'p_winner_team_id': winnerTeamId,
      'p_prize_pool_cent': prizePoolCent,
      'p_platform_pct': platformPct,
      'p_tutor_pct': tutorPct,
      'p_student_pct': studentPct,
    });
    return id as int;
  }

  Future<void> adminCreatePayoutsForPrize(int prizeId) async {
    await _client.rpc('admin_create_payouts_for_prize', params: {'p_prize_id': prizeId});
  }

  Future<List<ChampionshipPrize>> fetchPrizesForSeason(int seasonId) async {
    final rows = await _client.from('championship_prizes').select().eq('season_id', seasonId);
    return rows.map<ChampionshipPrize>(ChampionshipPrize.fromMap).toList();
  }

  Future<List<ChampionshipPayout>> fetchPayoutsForSeason(int seasonId) async {
    final rows = await _client.from('championship_payouts').select().eq('season_id', seasonId).order('created_at');
    return rows.map<ChampionshipPayout>(ChampionshipPayout.fromMap).toList();
  }

  /// Non-'paid' transitions only (approved/cancelled/etc) — the server
  /// itself refuses 'paid' through this path, see adminProcessPayout.
  Future<void> adminSetPayoutStatus(int payoutId, String status) async {
    await _client.rpc('admin_set_payout_status', params: {'p_payout_id': payoutId, 'p_status': status});
  }

  /// Does the real Cent credit — the only function allowed to mark a
  /// payout 'paid'.
  Future<void> adminProcessPayout(int payoutId) async {
    await _client.rpc('admin_process_payout', params: {'p_payout_id': payoutId});
  }
}
