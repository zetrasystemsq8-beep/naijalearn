// lib/championship_models.dart
//
// Plain data models for the NaijaLearn Academic Championship, mirroring
// the championship_* tables. Follows the same fromMap/toJson pattern as
// ZetraProfile in main.dart.

class ChampionshipSeason {
  final String id;
  final String name;
  final String? description;
  final String status; // draft | registration_open | registration_closed | in_progress | completed | cancelled
  final DateTime registrationStart;
  final DateTime registrationEnd;
  final DateTime? startAt;
  final DateTime? endAt;
  final int teamLimit;
  final int rosterLimit;
  final int playersPerRound;
  final int entryFeeKobo;

  ChampionshipSeason({
    required this.id,
    required this.name,
    this.description,
    required this.status,
    required this.registrationStart,
    required this.registrationEnd,
    this.startAt,
    this.endAt,
    required this.teamLimit,
    required this.rosterLimit,
    required this.playersPerRound,
    required this.entryFeeKobo,
  });

  factory ChampionshipSeason.fromMap(Map<String, dynamic> map) => ChampionshipSeason(
        id: map['id'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
        status: map['status'] as String,
        registrationStart: DateTime.parse(map['registration_start'] as String),
        registrationEnd: DateTime.parse(map['registration_end'] as String),
        startAt: map['start_at'] == null ? null : DateTime.parse(map['start_at'] as String),
        endAt: map['end_at'] == null ? null : DateTime.parse(map['end_at'] as String),
        teamLimit: map['team_limit'] as int,
        rosterLimit: map['roster_limit'] as int,
        playersPerRound: map['players_per_round'] as int,
        entryFeeKobo: map['entry_fee_kobo'] as int,
      );
}

class ChampionshipTeam {
  final String id;
  final String seasonId;
  final String tutorId;
  final int classroomId;
  final String name;
  final String? logoUrl;
  final String? description;
  final String? category;
  final String status; // pending | approved | rejected | disqualified | withdrawn
  final String? disqualifiedReason;

  ChampionshipTeam({
    required this.id,
    required this.seasonId,
    required this.tutorId,
    required this.classroomId,
    required this.name,
    this.logoUrl,
    this.description,
    this.category,
    required this.status,
    this.disqualifiedReason,
  });

  factory ChampionshipTeam.fromMap(Map<String, dynamic> map) => ChampionshipTeam(
        id: map['id'] as String,
        seasonId: map['season_id'] as String,
        tutorId: map['tutor_id'] as String,
        classroomId: map['classroom_id'] as int,
        name: map['name'] as String,
        logoUrl: map['logo_url'] as String?,
        description: map['description'] as String?,
        category: map['category'] as String?,
        status: map['status'] as String,
        disqualifiedReason: map['disqualified_reason'] as String?,
      );
}

class ChampionshipPlayer {
  final String id;
  final String seasonId;
  final String teamId;
  final String studentId;
  final String status; // active | removed | disqualified
  // Populated via a joined `profiles` select in the service layer, not a raw column.
  final String? studentName;
  final String? studentAvatarUrl;

  ChampionshipPlayer({
    required this.id,
    required this.seasonId,
    required this.teamId,
    required this.studentId,
    required this.status,
    this.studentName,
    this.studentAvatarUrl,
  });

  factory ChampionshipPlayer.fromMap(Map<String, dynamic> map) => ChampionshipPlayer(
        id: map['id'] as String,
        seasonId: map['season_id'] as String,
        teamId: map['team_id'] as String,
        studentId: map['student_id'] as String,
        status: map['status'] as String,
        studentName: map['profiles']?['username'] as String?,
        studentAvatarUrl: map['profiles']?['avatar_url'] as String?,
      );
}

class ChampionshipRound {
  final String id;
  final String seasonId;
  final int roundNumber;
  final String name;
  final String status; // scheduled | open | closed | cancelled
  final DateTime opensAt;
  final DateTime closesAt;
  final String? questionSetId;

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
        id: map['id'] as String,
        seasonId: map['season_id'] as String,
        roundNumber: map['round_number'] as int,
        name: map['name'] as String,
        status: map['status'] as String,
        opensAt: DateTime.parse(map['opens_at'] as String),
        closesAt: DateTime.parse(map['closes_at'] as String),
        questionSetId: map['question_set_id'] as String?,
      );
}

class ChampionshipMatch {
  final String id;
  final String seasonId;
  final String roundId;
  final String teamAId;
  final String teamBId;
  final num? teamAScore; // null while round is still open (hidden by the public view)
  final num? teamBScore;
  final String? winnerTeamId;
  final String status; // scheduled | in_progress | completed | disputed | cancelled

  ChampionshipMatch({
    required this.id,
    required this.seasonId,
    required this.roundId,
    required this.teamAId,
    required this.teamBId,
    this.teamAScore,
    this.teamBScore,
    this.winnerTeamId,
    required this.status,
  });

  factory ChampionshipMatch.fromMap(Map<String, dynamic> map) => ChampionshipMatch(
        id: map['id'] as String,
        seasonId: map['season_id'] as String,
        roundId: map['round_id'] as String,
        teamAId: map['team_a_id'] as String,
        teamBId: map['team_b_id'] as String,
        teamAScore: map['team_a_score'] as num?,
        teamBScore: map['team_b_score'] as num?,
        winnerTeamId: map['winner_team_id'] as String?,
        status: map['status'] as String,
      );

  bool get scoresVisible => teamAScore != null && teamBScore != null;
}

class ChampionshipAttempt {
  final String id;
  final String matchId;
  final String teamId;
  final String studentId;
  final String questionSetId;
  final DateTime? startedAt;
  final DateTime? submittedAt;
  final num score;
  final int correctCount;
  final String status; // not_started | in_progress | submitted | forfeited | flagged
  final DateTime? serverDeadline;

  ChampionshipAttempt({
    required this.id,
    required this.matchId,
    required this.teamId,
    required this.studentId,
    required this.questionSetId,
    this.startedAt,
    this.submittedAt,
    required this.score,
    required this.correctCount,
    required this.status,
    this.serverDeadline,
  });

  factory ChampionshipAttempt.fromMap(Map<String, dynamic> map) => ChampionshipAttempt(
        id: map['id'] as String,
        matchId: map['match_id'] as String,
        teamId: map['team_id'] as String,
        studentId: map['student_id'] as String,
        questionSetId: map['question_set_id'] as String,
        startedAt: map['started_at'] == null ? null : DateTime.parse(map['started_at'] as String),
        submittedAt: map['submitted_at'] == null ? null : DateTime.parse(map['submitted_at'] as String),
        score: map['score'] as num,
        correctCount: map['correct_count'] as int,
        status: map['status'] as String,
        serverDeadline: map['server_deadline'] == null ? null : DateTime.parse(map['server_deadline'] as String),
      );
}

/// A single tournament question, shaped for the quiz UI. Only ever
/// fetched via ChampionshipService.fetchAttemptQuestions(), which goes
/// through the server-side path — never a direct `questions` table
/// select, since RLS deliberately blocks that for championship items.
class ChampionshipQuizQuestion {
  final String id;
  final String questionText;
  final List<String> options;
  final int order;

  ChampionshipQuizQuestion({
    required this.id,
    required this.questionText,
    required this.options,
    required this.order,
  });

  factory ChampionshipQuizQuestion.fromMap(Map<String, dynamic> map) => ChampionshipQuizQuestion(
        id: map['id'] as String,
        questionText: map['question_text'] as String,
        options: List<String>.from(map['options'] as List),
        order: map['question_order'] as int,
      );
}
