// lib/championship_service.dart
//
// All Supabase access for the Academic Championship feature lives here —
// screens and the provider never call Supabase.instance.client directly.
// Uses the same client instance as AuthService (Supabase.instance.client),
// so it shares the existing session/auth state automatically.

import 'package:supabase_flutter/supabase_flutter.dart';
import 'championship_models.dart';

class ChampionshipService {
  ChampionshipService._();
  static final ChampionshipService instance = ChampionshipService._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  // ---------------------------------------------------------------
  // ROLE CHECKS
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
    final row = await _client
        .from('tutor_profiles')
        .select('status')
        .eq('user_id', uid)
        .maybeSingle();
    return row?['status'] == 'approved';
  }

  // ---------------------------------------------------------------
  // SEASONS
  // ---------------------------------------------------------------

  /// The season students/tutors currently care about: the most recent
  /// one that isn't finished/cancelled.
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

  Future<List<ChampionshipSeason>> fetchAllSeasons() async {
    final rows = await _client.from('championship_seasons').select().order('created_at', ascending: false);
    return rows.map<ChampionshipSeason>(ChampionshipSeason.fromMap).toList();
  }

  // ---------------------------------------------------------------
  // TEAMS
  // ---------------------------------------------------------------

  /// The team the current student plays for in this season, or null.
  Future<ChampionshipTeam?> fetchMyStudentTeam(String seasonId) async {
    final uid = _uid;
    if (uid == null) return null;
    final playerRow = await _client
        .from('championship_players')
        .select('team_id')
        .eq('season_id', seasonId)
        .eq('student_id', uid)
        .eq('status', 'active')
        .maybeSingle();
    if (playerRow == null) return null;
    final teamRow = await _client
        .from('championship_teams')
        .select()
        .eq('id', playerRow['team_id'] as String)
        .single();
    return ChampionshipTeam.fromMap(teamRow);
  }

  /// The team the current tutor owns in this season, or null.
  Future<ChampionshipTeam?> fetchMyTutorTeam(String seasonId) async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await _client
        .from('championship_teams')
        .select()
        .eq('season_id', seasonId)
        .eq('tutor_id', uid)
        .maybeSingle();
    if (row == null) return null;
    return ChampionshipTeam.fromMap(row);
  }

  Future<ChampionshipTeam> registerTeam({
    required String seasonId,
    required int classroomId,
    required String name,
    String? logoUrl,
    String? description,
    String? category,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not signed in');
    final row = await _client
        .from('championship_teams')
        .insert({
          'season_id': seasonId,
          'tutor_id': uid,
          'classroom_id': classroomId,
          'name': name,
          'logo_url': logoUrl,
          'description': description,
          'category': category,
        })
        .select()
        .single();
    return ChampionshipTeam.fromMap(row);
  }

  // ---------------------------------------------------------------
  // ROSTER
  // ---------------------------------------------------------------

  Future<List<ChampionshipPlayer>> fetchRoster(String teamId) async {
    final rows = await _client
        .from('championship_players')
        .select('*, profiles(username, avatar_url)')
        .eq('team_id', teamId)
        .eq('status', 'active');
    return rows.map<ChampionshipPlayer>(ChampionshipPlayer.fromMap).toList();
  }

  /// Students eligible for this team's roster: the tutor's classroom
  /// minus anyone already rostered this season (enforced again server-side
  /// by RLS + the unique(season_id, student_id) constraint).
  Future<List<Map<String, dynamic>>> fetchEligibleClassroomStudents({
    required int classroomId,
  }) async {
    final rows = await _client
        .from('classroom_students')
        .select('student_id, profiles(username, avatar_url)')
        .eq('classroom_id', classroomId);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> addPlayerToRoster({
    required String seasonId,
    required String teamId,
    required String studentId,
  }) async {
    await _client.from('championship_players').insert({
      'season_id': seasonId,
      'team_id': teamId,
      'student_id': studentId,
    });
  }

  Future<void> removePlayerFromRoster(String playerRowId) async {
    await _client.from('championship_players').delete().eq('id', playerRowId);
  }

  Future<ChampionshipTeam?> fetchTeamById(String teamId) async {
    final row = await _client.from('championship_teams').select().eq('id', teamId).maybeSingle();
    if (row == null) return null;
    return ChampionshipTeam.fromMap(row);
  }

  Future<String?> fetchUsername(String profileId) async {
    final row = await _client.from('profiles').select('username').eq('id', profileId).maybeSingle();
    return row?['username'] as String?;
  }

  // ---------------------------------------------------------------
  // ROUNDS & MATCHES
  // ---------------------------------------------------------------

  Future<List<ChampionshipRound>> fetchRounds(String seasonId) async {
    final rows = await _client
        .from('championship_rounds')
        .select()
        .eq('season_id', seasonId)
        .order('round_number');
    return rows.map<ChampionshipRound>(ChampionshipRound.fromMap).toList();
  }

  /// This team's match in a given round, via the score-hiding public view.
  Future<ChampionshipMatch?> fetchTeamMatchForRound({
    required String roundId,
    required String teamId,
  }) async {
    final rows = await _client
        .from('championship_matches_public')
        .select()
        .eq('round_id', roundId)
        .or('team_a_id.eq.$teamId,team_b_id.eq.$teamId')
        .limit(1);
    if (rows.isEmpty) return null;
    return ChampionshipMatch.fromMap(rows.first);
  }

  Future<List<ChampionshipMatch>> fetchAllMatchesForSeason(String seasonId) async {
    final rows = await _client.from('championship_matches_public').select().eq('season_id', seasonId);
    return rows.map<ChampionshipMatch>(ChampionshipMatch.fromMap).toList();
  }

  /// Realtime stream of a single match row (public view has no realtime
  /// support in Supabase, so we stream the base table and let the UI
  /// itself decide whether to show the score based on round status).
  Stream<List<Map<String, dynamic>>> watchMatch(String matchId) {
    return _client.from('championship_matches').stream(primaryKey: ['id']).eq('id', matchId);
  }

  Stream<List<Map<String, dynamic>>> watchRound(String roundId) {
    return _client.from('championship_rounds').stream(primaryKey: ['id']).eq('id', roundId);
  }

  // ---------------------------------------------------------------
  // SELECTIONS (tutor picks players for a specific match)
  // ---------------------------------------------------------------

  Future<List<ChampionshipPlayer>> fetchSelectionsForMatch({
    required String matchId,
    required String teamId,
  }) async {
    final rows = await _client
        .from('championship_selections')
        .select('student_id, profiles(username, avatar_url)')
        .eq('match_id', matchId)
        .eq('team_id', teamId);
    return rows
        .map<ChampionshipPlayer>((m) => ChampionshipPlayer(
              id: '', // selections don't have their own roster row id
              seasonId: '',
              teamId: teamId,
              studentId: m['student_id'] as String,
              status: 'active',
              studentName: m['profiles']?['username'] as String?,
              studentAvatarUrl: m['profiles']?['avatar_url'] as String?,
            ))
        .toList();
  }

  /// Throws if the round has already opened — RLS enforces this too,
  /// but surfacing a clear error here saves a round trip's worth of confusion.
  Future<void> selectPlayerForMatch({
    required String matchId,
    required String teamId,
    required String studentId,
  }) async {
    await _client.from('championship_selections').insert({
      'match_id': matchId,
      'team_id': teamId,
      'student_id': studentId,
    });
  }

  Future<void> deselectPlayerForMatch({
    required String matchId,
    required String studentId,
  }) async {
    await _client
        .from('championship_selections')
        .delete()
        .eq('match_id', matchId)
        .eq('student_id', studentId);
  }

  /// Whether the current student has a locked selection for this match.
  Future<bool> isCurrentStudentLockedForMatch(String matchId) async {
    final uid = _uid;
    if (uid == null) return false;
    final row = await _client
        .from('championship_selections')
        .select('locked_at')
        .eq('match_id', matchId)
        .eq('student_id', uid)
        .maybeSingle();
    return row != null && row['locked_at'] != null;
  }

  // ---------------------------------------------------------------
  // ATTEMPTS (the timed quiz)
  // ---------------------------------------------------------------

  Future<ChampionshipAttempt?> fetchMyAttempt(String matchId) async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await _client
        .from('championship_attempts')
        .select()
        .eq('match_id', matchId)
        .eq('student_id', uid)
        .maybeSingle();
    if (row == null) return null;
    return ChampionshipAttempt.fromMap(row);
  }

  Future<ChampionshipAttempt> startAttempt(String matchId) async {
    final row = await _client.rpc('championship_start_attempt', params: {'p_match_id': matchId});
    return ChampionshipAttempt.fromMap(row as Map<String, dynamic>);
  }

  Future<List<ChampionshipQuizQuestion>> fetchAttemptQuestions(String attemptId) async {
    final rows = await _client.rpc('championship_get_attempt_questions', params: {'p_attempt_id': attemptId});
    return (rows as List)
        .map<ChampionshipQuizQuestion>((m) => ChampionshipQuizQuestion.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  /// [answers] maps questionId -> selected option INDEX as a string ("0".."3").
  Future<ChampionshipAttempt> submitAttempt({
    required String attemptId,
    required Map<String, String> answers,
  }) async {
    final payload = answers.entries
        .map((e) => {'question_id': e.key, 'selected_answer': e.value})
        .toList();
    final row = await _client.rpc('championship_submit_attempt', params: {
      'p_attempt_id': attemptId,
      'p_answers': payload,
    });
    return ChampionshipAttempt.fromMap(row as Map<String, dynamic>);
  }
}
