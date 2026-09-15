// lib/championship_provider.dart
//
// REPLACES the earlier version. This schema has no single "give me my
// current round/match" RPC — get_championship_bracket returns the whole
// season's bracket in one call, so "current match" is derived client-side
// by filtering rows that involve my team and picking the most relevant one.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'championship_models.dart';
import 'championship_service.dart';

class StudentChampionshipProvider extends ChangeNotifier {
  final ChampionshipService _service = ChampionshipService.instance;

  bool loading = true;
  String? error;

  ChampionshipSeason? season;
  bool onTeam = false;
  int? teamId;
  String? teamName;
  String? coachName;
  ChampionshipTeam? myTeam;
  List<ChampionshipPlayer> roster = [];

  List<ChampionshipBracketRow> myMatches = [];
  ChampionshipBracketRow? currentMatch;
  bool isSelectedForCurrentMatch = false;
  Map<String, dynamic>? myAttempt; // raw row: status, score, correct_count, server_deadline...

  StreamSubscription? _matchSub;
  StreamSubscription? _roundSub;
  String? _currentRoundStatus;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      season = await _service.fetchActiveSeason();
      if (season == null) {
        loading = false;
        notifyListeners();
        return;
      }

      final status = await _service.studentGetMyStatus(season!.id);
      onTeam = status['on_team'] == true;
      if (!onTeam) {
        loading = false;
        notifyListeners();
        return;
      }
      teamId = status['team_id'] as int;
      teamName = status['team_name'] as String?;
      coachName = status['coach_name'] as String?;
      myTeam = await _service.fetchTeamById(teamId!);
      roster = await _service.fetchRoster(teamId!);

      final bracket = await _service.fetchBracket(season!.id);
      myMatches = bracket.where((r) => r.involvesTeam(teamId!)).toList()
        ..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));

      currentMatch = myMatches.cast<ChampionshipBracketRow?>().firstWhere(
            (m) => m?.roundStatus == 'open',
            orElse: () => myMatches.cast<ChampionshipBracketRow?>().firstWhere(
                  (m) => m?.roundStatus == 'scheduled',
                  orElse: () => myMatches.isNotEmpty ? myMatches.last : null,
                ),
          );

      if (currentMatch != null) {
        _currentRoundStatus = currentMatch!.roundStatus;
        isSelectedForCurrentMatch = await _service.isCurrentStudentSelected(currentMatch!.matchId);
        myAttempt = await _service.fetchMyAttempt(currentMatch!.matchId);
        _subscribeToLiveUpdates();
      }
    } catch (e) {
      error = 'Could not load championship data. Please try again.';
      debugPrint('[Championship] load() failed: $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _subscribeToLiveUpdates() {
    _matchSub?.cancel();
    _roundSub?.cancel();
    if (currentMatch == null) return;

    _matchSub = _service.watchMatch(currentMatch!.matchId).listen((rows) {
      if (rows.isEmpty) return;
      final row = rows.first;
      final closed = row['status'] == 'completed';
      currentMatch = ChampionshipBracketRow(
        roundId: currentMatch!.roundId,
        roundNumber: currentMatch!.roundNumber,
        roundName: currentMatch!.roundName,
        roundStatus: _currentRoundStatus ?? currentMatch!.roundStatus,
        matchId: row['id'] as int,
        teamAId: row['team_a_id'] as int,
        teamAName: currentMatch!.teamAName,
        teamBId: row['team_b_id'] as int,
        teamBName: currentMatch!.teamBName,
        teamAScore: closed ? row['team_a_score'] as num? : null,
        teamBScore: closed ? row['team_b_score'] as num? : null,
        winnerTeamId: closed ? row['winner_team_id'] as int? : null,
        matchStatus: row['status'] as String,
      );
      notifyListeners();
    });

    _roundSub = _service.watchRound(currentMatch!.roundId).listen((rows) {
      if (rows.isEmpty) return;
      _currentRoundStatus = rows.first['status'] as String;
      notifyListeners();
    });
  }

  Future<void> refresh() => load();

  @override
  void dispose() {
    _matchSub?.cancel();
    _roundSub?.cancel();
    super.dispose();
  }
}
