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

  Future<List<Map<String, dynamic>>> fetchMyClassrooms() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _client.from('classrooms').select('id, name').eq('tutor_id', uid);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Every student already on a roster somewhere this season, so the
  /// tutor's picker can gray them out before hitting the RLS error.
  Future<Set<String>> fetchRosteredStudentIdsForSeason(String seasonId) async {
    final rows = await _client.from('championship_players').select('student_id').eq('season_id', seasonId);
    return rows.map<String>((r) => r['student_id'] as String).toSet();
  }

  // ---------------------------------------------------------------
  // ADMIN — seasons / teams / rounds / matches / question sets
  // ---------------------------------------------------------------

  Future<ChampionshipSeason> createSeason({
    required String name,
    String? description,
    required DateTime registrationStart,
    required DateTime registrationEnd,
    DateTime? startAt,
    DateTime? endAt,
    int teamLimit = 32,
    int rosterLimit = 10,
    int playersPerRound = 5,
    int entryFeeKobo = 0,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not signed in');
    final row = await _client
        .from('championship_seasons')
        .insert({
          'name': name,
          'description': description,
          'status': 'draft',
          'registration_start': registrationStart.toIso8601String(),
          'registration_end': registrationEnd.toIso8601String(),
          'start_at': startAt?.toIso8601String(),
          'end_at': endAt?.toIso8601String(),
          'team_limit': teamLimit,
          'roster_limit': rosterLimit,
          'players_per_round': playersPerRound,
          'entry_fee_kobo': entryFeeKobo,
          'created_by': uid,
        })
        .select()
        .single();
    return ChampionshipSeason.fromMap(row);
  }

  Future<void> updateSeasonStatus(String seasonId, String status) async {
    await _client.from('championship_seasons').update({'status': status}).eq('id', seasonId);
  }

  Future<List<ChampionshipTeam>> fetchTeamsForSeason(String seasonId) async {
    final rows = await _client.from('championship_teams').select().eq('season_id', seasonId);
    return rows.map<ChampionshipTeam>(ChampionshipTeam.fromMap).toList();
  }

  Future<void> updateTeamStatus(String teamId, String status) async {
    await _client.from('championship_teams').update({'status': status}).eq('id', teamId);
  }

  Future<void> disqualifyTeam({required String teamId, required String reason}) async {
    final uid = _uid;
    await _client.from('championship_teams').update({
      'status': 'disqualified',
      'disqualified_reason': reason,
      'disqualified_by': uid,
      'disqualified_at': DateTime.now().toIso8601String(),
    }).eq('id', teamId);
  }

  Future<ChampionshipRound> createRound({
    required String seasonId,
    required int roundNumber,
    required String name,
    required DateTime opensAt,
    required DateTime closesAt,
    String? questionSetId,
  }) async {
    final row = await _client
        .from('championship_rounds')
        .insert({
          'season_id': seasonId,
          'round_number': roundNumber,
          'name': name,
          'opens_at': opensAt.toIso8601String(),
          'closes_at': closesAt.toIso8601String(),
          'question_set_id': questionSetId,
        })
        .select()
        .single();
    return ChampionshipRound.fromMap(row);
  }

  Future<void> updateRoundStatus(String roundId, String status) async {
    await _client.from('championship_rounds').update({'status': status}).eq('id', roundId);
  }

  Future<ChampionshipMatch> createMatch({
    required String seasonId,
    required String roundId,
    required String teamAId,
    required String teamBId,
  }) async {
    final row = await _client
        .from('championship_matches')
        .insert({
          'season_id': seasonId,
          'round_id': roundId,
          'team_a_id': teamAId,
          'team_b_id': teamBId,
        })
        .select()
        .single();
    return ChampionshipMatch.fromMap(row);
  }

  /// Admin-only: raw table (real scores, no hiding) rather than the
  /// public score-hiding view.
  Future<List<ChampionshipMatch>> fetchRawMatchesForRound(String roundId) async {
    final rows = await _client.from('championship_matches').select().eq('round_id', roundId);
    return rows.map<ChampionshipMatch>((m) => ChampionshipMatch(
          id: m['id'] as String,
          seasonId: m['season_id'] as String,
          roundId: m['round_id'] as String,
          teamAId: m['team_a_id'] as String,
          teamBId: m['team_b_id'] as String,
          teamAScore: m['team_a_score'] as num?,
          teamBScore: m['team_b_score'] as num?,
          winnerTeamId: m['winner_team_id'] as String?,
          status: m['status'] as String,
        )).toList();
  }

  Future<ChampionshipQuestionSet> createQuestionSet({
    required String seasonId,
    required String name,
    required String subject,
    required int durationSeconds,
    String? difficulty,
    required List<String> questionIds,
  }) async {
    final setRow = await _client
        .from('championship_question_sets')
        .insert({
          'season_id': seasonId,
          'name': name,
          'subject': subject,
          'duration_seconds': durationSeconds,
          'question_count': questionIds.length,
          'difficulty': difficulty,
        })
        .select()
        .single();
    final setId = setRow['id'] as String;

    final items = List.generate(
      questionIds.length,
      (i) => {'question_set_id': setId, 'question_id': questionIds[i], 'question_order': i + 1, 'marks': 1},
    );
    if (items.isNotEmpty) {
      await _client.from('championship_question_set_items').insert(items);
    }
    return ChampionshipQuestionSet.fromMap(setRow);
  }

  Future<List<ChampionshipQuestionSet>> fetchQuestionSetsForSeason(String seasonId) async {
    final rows = await _client.from('championship_question_sets').select().eq('season_id', seasonId);
    return rows.map<ChampionshipQuestionSet>(ChampionshipQuestionSet.fromMap).toList();
  }

  /// For the admin's question-picker when building a question set.
  Future<List<Map<String, dynamic>>> fetchQuestionsBySubject(String subject, {int limit = 100}) async {
    final rows = await _client.from('questions').select('id, question_text').eq('subject', subject).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<String>> fetchDistinctSubjects() async {
    final rows = await _client.from('questions').select('subject');
    return rows.map<String>((r) => r['subject'] as String).toSet().toList()..sort();
  }

  // ---------------------------------------------------------------
  // TEAM NAME LOOKUP (used by the bracket + tutor dashboards)
  // ---------------------------------------------------------------

  Future<Map<String, String>> fetchTeamNamesBySeason(String seasonId) async {
    final rows = await _client.from('championship_teams').select('id, name').eq('season_id', seasonId);
    return {for (final r in rows) r['id'] as String: r['name'] as String};
  }
}
