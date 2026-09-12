// lib/championship_provider.dart
//
// ChangeNotifier for the STUDENT side of the championship (team status,
// current round/match, live updates). Matches the existing app's
// Provider-based pattern (see AppProvider / CoinService in main.dart) —
// wrap this locally in the screen that needs it:
//
//   ChangeNotifierProvider(
//     create: (_) => StudentChampionshipProvider()..load(),
//     child: const StudentChampionshipScreen(),
//   )
//
// No changes to main.dart's MultiProvider are required.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'championship_models.dart';
import 'championship_service.dart';

class StudentChampionshipProvider extends ChangeNotifier {
  final ChampionshipService _service = ChampionshipService.instance;

  bool loading = true;
  String? error;

  ChampionshipSeason? season;
  ChampionshipTeam? team;
  List<ChampionshipPlayer> roster = [];
  List<ChampionshipRound> rounds = [];
  ChampionshipRound? currentRound;
  ChampionshipMatch? currentMatch;
  ChampionshipTeam? opponentTeam;
  String? coachName;
  bool isSelectedForCurrentMatch = false;
  ChampionshipAttempt? myAttempt;

  StreamSubscription? _matchSub;
  StreamSubscription? _roundSub;

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

      team = await _service.fetchMyStudentTeam(season!.id);
      if (team == null) {
        loading = false;
        notifyListeners();
        return;
      }

      roster = await _service.fetchRoster(team!.id);
      rounds = await _service.fetchRounds(season!.id);
      coachName = await _service.fetchUsername(team!.tutorId);

      // "Current round" = the first one that's open, else the first
      // still-scheduled one, else the most recently closed one.
      currentRound = rounds.cast<ChampionshipRound?>().firstWhere(
            (r) => r?.status == 'open',
            orElse: () => rounds.cast<ChampionshipRound?>().firstWhere(
                  (r) => r?.status == 'scheduled',
                  orElse: () => rounds.isNotEmpty ? rounds.last : null,
                ),
          );

      if (currentRound != null) {
        currentMatch = await _service.fetchTeamMatchForRound(
          roundId: currentRound!.id,
          teamId: team!.id,
        );
        if (currentMatch != null) {
          isSelectedForCurrentMatch =
              await _service.isCurrentStudentLockedForMatch(currentMatch!.id);
          myAttempt = await _service.fetchMyAttempt(currentMatch!.id);
          final opponentId =
              currentMatch!.teamAId == team!.id ? currentMatch!.teamBId : currentMatch!.teamAId;
          opponentTeam = await _service.fetchTeamById(opponentId);
          _subscribeToLiveUpdates();
        }
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
    if (currentMatch == null || currentRound == null) return;

    _matchSub = _service.watchMatch(currentMatch!.id).listen((rows) {
      if (rows.isEmpty) return;
      // Only reveal scores once the round is closed — mirrors the RLS view.
      final closed = currentRound?.status == 'closed';
      currentMatch = ChampionshipMatch(
        id: rows.first['id'] as String,
        seasonId: rows.first['season_id'] as String,
        roundId: rows.first['round_id'] as String,
        teamAId: rows.first['team_a_id'] as String,
        teamBId: rows.first['team_b_id'] as String,
        teamAScore: closed ? rows.first['team_a_score'] as num? : null,
        teamBScore: closed ? rows.first['team_b_score'] as num? : null,
        winnerTeamId: closed ? rows.first['winner_team_id'] as String? : null,
        status: rows.first['status'] as String,
      );
      notifyListeners();
    });

    _roundSub = _service.watchRound(currentRound!.id).listen((rows) {
      if (rows.isEmpty) return;
      currentRound = ChampionshipRound.fromMap(rows.first);
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
