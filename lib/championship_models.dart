// lib/championship_models.dart
//
// REPLACES the earlier version entirely — matches the clean-rebuild SQL
// (bigint IDs throughout championship_*, Cent not kobo, no classroom
// link on teams). Not additive with the old models; this is the schema now.

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

  factory ChampionshipSeason.fromMap(Map<String, dynamic> map) => ChampionshipSeason(
        id: map['id'] as int,
        name: map['name'] as String,
        description: map['description'] as String?,
        status: map['status'] as String,
        registrationStart: map['registration_start'] == null ? null : DateTime.parse(map['registration_start'] as String),
        registrationEnd: map['registration_end'] == null ? null : DateTime.parse(map['registration_end'] as String),
        startAt: map['start_at'] == null ? null : DateTime.parse(map['start_at'] as String),
        endAt: map['end_at'] == null ? null : DateTime.parse(map['end_at'] as String),
        teamLimit: map['team_limit'] as int?,
        rosterLimit: map['roster_limit'] as int,
        playersPerRound: map['players_per_round'] as int,
        entryFeeCent: map['entry_fee_cent'] as int,
      );
}

class ChampionshipTeam {
  final int id;
  final int seasonId;
  final int tutorId; // tutor_profiles.id, NOT the tutor's auth uid
  final int? classroomId;
  final String name;
  final String? logoUrl;
  final String? description;
  final String? category;
  final String status; // pending | approved | rejected | disqualified
  final bool rosterLocked;
  final String? disqualifiedReason;

  ChampionshipTeam({
    required this.id,
    required this.seasonId,
    required this.tutorId,
    this.classroomId,
    required this.name,
    this.logoUrl,
    this.description,
    this.category,
    required this.status,
    required this.rosterLocked,
    this.disqualifiedReason,
  });

  factory ChampionshipTeam.fromMap(Map<String, dynamic> map) => ChampionshipTeam(
        id: map['id'] as int,
        seasonId: map['season_id'] as int,
        tutorId: map['tutor_id'] as int,
        classroomId: map['classroom_id'] as int?,
        name: map['name'] as String,
        logoUrl: map['logo_url'] as String?,
        description: map['description'] as String?,
        category: map['category'] as String?,
        status: map['status'] as String,
        rosterLocked: map['roster_locked'] as bool? ?? false,
        disqualifiedReason: map['disqualified_reason'] as String?,
      );
}

class ChampionshipPlayer {
  final String studentId; // uuid
  final String username;
  final String status; // active | removed

  ChampionshipPlayer({required this.studentId, required this.username, required this.status});

  factory ChampionshipPlayer.fromMap(Map<String, dynamic> map) => ChampionshipPlayer(
        studentId: map['student_id'] as String,
        username: map['username'] as String,
        status: map['status'] as String,
      );
}

class ChampionshipQuestionSet {
  final int id;
  final int seasonId;
  final String name;
  final String subject;
  final int durationSeconds;
  final int questionCount;

  ChampionshipQuestionSet({
    required this.id,
    required this.seasonId,
    required this.name,
    required this.subject,
    required this.durationSeconds,
    required this.questionCount,
  });

  factory ChampionshipQuestionSet.fromMap(Map<String, dynamic> map) => ChampionshipQuestionSet(
        id: map['id'] as int,
        seasonId: map['season_id'] as int,
        name: map['name'] as String,
        subject: map['subject'] as String,
        durationSeconds: map['duration_seconds'] as int,
        questionCount: map['question_count'] as int,
      );
}

class ChampionshipRound {
  final int id;
  final int seasonId;
  final int roundNumber;
  final String name;
  final String status; // scheduled | open | closed (informational — actual gating is time-based, see opensAt/closesAt)
  final DateTime opensAt;
  final DateTime closesAt;
  final int? questionSetId;

  ChampionshipRound({
    required this.id,
    required this.seasonId,
    required this.roundNumber,
    required this.name,
    required this.status,
    required this.opensAt,
    required this.closesAt,
    this.questionSetId,
  });

  factory ChampionshipRound.fromMap(Map<String, dynamic> map) => ChampionshipRound(
        id: map['id'] as int,
        seasonId: map['season_id'] as int,
        roundNumber: map['round_number'] as int,
        name: map['name'] as String,
        status: map['status'] as String,
        opensAt: DateTime.parse(map['opens_at'] as String),
        closesAt: DateTime.parse(map['closes_at'] as String),
        questionSetId: map['question_set_id'] as int?,
      );

  bool get isWithinWindow {
    final now = DateTime.now().toUtc();
    return now.isAfter(opensAt.toUtc()) && now.isBefore(closesAt.toUtc());
  }

  bool get hasOpened => DateTime.now().toUtc().isAfter(opensAt.toUtc());
}

/// One row of get_championship_bracket() — the single source of truth
/// for round+match+team-name+score data across student/tutor/admin/bracket
/// views, since this schema has no separate score-hiding view; the RPC
/// itself nulls team_a_score/team_b_score unless match_status = 'completed'.
class ChampionshipBracketRow {
  final int roundId;
  final int roundNumber;
  final String roundName;
  final String roundStatus;
  final int matchId;
  final int teamAId;
  final String teamAName;
  final int teamBId;
  final String teamBName;
  final num? teamAScore;
  final num? teamBScore;
  final int? winnerTeamId;
  final String matchStatus; // scheduled | active | completed | disputed

  ChampionshipBracketRow({
    required this.roundId,
    required this.roundNumber,
    required this.roundName,
    required this.roundStatus,
    required this.matchId,
    required this.teamAId,
    required this.teamAName,
    required this.teamBId,
    required this.teamBName,
    this.teamAScore,
    this.teamBScore,
    this.winnerTeamId,
    required this.matchStatus,
  });

  factory ChampionshipBracketRow.fromMap(Map<String, dynamic> map) => ChampionshipBracketRow(
        roundId: map['round_id'] as int,
        roundNumber: map['round_number'] as int,
        roundName: map['round_name'] as String,
        roundStatus: map['round_status'] as String,
        matchId: map['match_id'] as int,
        teamAId: map['team_a_id'] as int,
        teamAName: map['team_a_name'] as String,
        teamBId: map['team_b_id'] as int,
        teamBName: map['team_b_name'] as String,
        teamAScore: map['team_a_score'] as num?,
        teamBScore: map['team_b_score'] as num?,
        winnerTeamId: map['winner_team_id'] as int?,
        matchStatus: map['match_status'] as String,
      );

  bool involvesTeam(int teamId) => teamAId == teamId || teamBId == teamId;
  bool get scoresVisible => teamAScore != null && teamBScore != null;
}

class ChampionshipPrize {
  final int id;
  final int seasonId;
  final int winnerTeamId;
  final int prizePoolCent;
  final int platformAmountCent;
  final int tutorAmountCent;
  final int studentAmountCent;
  final String status;

  ChampionshipPrize({
    required this.id,
    required this.seasonId,
    required this.winnerTeamId,
    required this.prizePoolCent,
    required this.platformAmountCent,
    required this.tutorAmountCent,
    required this.studentAmountCent,
    required this.status,
  });

  factory ChampionshipPrize.fromMap(Map<String, dynamic> map) => ChampionshipPrize(
        id: map['id'] as int,
        seasonId: map['season_id'] as int,
        winnerTeamId: map['winner_team_id'] as int,
        prizePoolCent: map['prize_pool_cent'] as int,
        platformAmountCent: map['platform_amount_cent'] as int,
        tutorAmountCent: map['tutor_amount_cent'] as int,
        studentAmountCent: map['student_amount_cent'] as int,
        status: map['status'] as String,
      );
}

class ChampionshipPayout {
  final int id;
  final int seasonId;
  final String recipientUserId; // uuid
  final String recipientType; // tutor | student | platform
  final int amountCent;
  final String status;
  final String? recipientName; // populated via a separate profiles lookup if needed

  ChampionshipPayout({
    required this.id,
    required this.seasonId,
    required this.recipientUserId,
    required this.recipientType,
    required this.amountCent,
    required this.status,
    this.recipientName,
  });

  factory ChampionshipPayout.fromMap(Map<String, dynamic> map) => ChampionshipPayout(
        id: map['id'] as int,
        seasonId: map['season_id'] as int,
        recipientUserId: map['recipient_user_id'] as String,
        recipientType: map['recipient_type'] as String,
        amountCent: map['amount_cent'] as int,
        status: map['status'] as String,
        recipientName: map['profiles']?['username'] as String?,
      );
}

/// Client-side representation of an attempt in progress. student_start_attempt
/// only returns started_at/duration_seconds/server_deadline (not a full row),
/// so this is built from that response, not fetched from the table directly
/// (RLS on championship_attempts only allows a student to see their own row
/// anyway, which this matches).
class ChampionshipAttemptState {
  final DateTime startedAt;
  final int durationSeconds;
  final DateTime serverDeadline;

  ChampionshipAttemptState({
    required this.startedAt,
    required this.durationSeconds,
    required this.serverDeadline,
  });

  factory ChampionshipAttemptState.fromMap(Map<String, dynamic> map) => ChampionshipAttemptState(
        startedAt: DateTime.parse(map['started_at'] as String),
        durationSeconds: map['duration_seconds'] as int,
        serverDeadline: DateTime.parse(map['server_deadline'] as String),
      );
}

/// A single tournament question as delivered by student_get_match_questions
/// — never includes correct_index.
class ChampionshipQuizQuestion {
  final String id; // questions.id is text
  final String subject;
  final String questionText;
  final List<String> options;
  final int order;

  ChampionshipQuizQuestion({
    required this.id,
    required this.subject,
    required this.questionText,
    required this.options,
    required this.order,
  });

  factory ChampionshipQuizQuestion.fromMap(Map<String, dynamic> map) => ChampionshipQuizQuestion(
        id: map['id'] as String,
        subject: map['subject'] as String,
        questionText: map['question_text'] as String,
        options: List<String>.from(map['options'] as List),
        order: map['question_order'] as int,
      );
}
