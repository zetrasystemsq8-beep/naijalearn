// lib/championship_admin_provider.dart

import 'package:flutter/foundation.dart';
import 'championship_models.dart';
import 'championship_service.dart';

class AdminChampionshipProvider extends ChangeNotifier {
  final ChampionshipService _service = ChampionshipService.instance;

  bool loading = true;
  bool isAdmin = false;
  String? error;
  String? actionError;

  List<ChampionshipSeason> seasons = [];
  ChampionshipSeason? selectedSeason;

  List<ChampionshipTeam> teams = [];
  List<ChampionshipRound> rounds = [];
  List<ChampionshipQuestionSet> questionSets = [];
  Map<String, List<ChampionshipMatch>> matchesByRound = {};
  Map<String, String> teamNames = {}; // teamId -> name, for match display
  List<ChampionshipPayout> payouts = [];
  num collectedEntryFees = 0;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      isAdmin = await _service.isCurrentUserAdmin();
      if (!isAdmin) {
        loading = false;
        notifyListeners();
        return;
      }
      seasons = await _service.fetchAllSeasons();
      if (seasons.isNotEmpty) {
        selectedSeason = seasons.first;
        await _loadSeasonDetail();
      }
    } catch (e) {
      error = 'Could not load admin data: $e';
      debugPrint('[AdminChampionship] load() failed: $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectSeason(ChampionshipSeason season) async {
    selectedSeason = season;
    notifyListeners();
    await _loadSeasonDetail();
    notifyListeners();
  }

  Future<void> _loadSeasonDetail() async {
    if (selectedSeason == null) return;
    final id = selectedSeason!.id;
    teams = await _service.fetchTeamsForSeason(id);
    rounds = await _service.fetchRounds(id);
    questionSets = await _service.fetchQuestionSetsForSeason(id);
    teamNames = await _service.fetchTeamNamesBySeason(id);
    matchesByRound = {};
    for (final r in rounds) {
      matchesByRound[r.id] = await _service.fetchRawMatchesForRound(r.id);
    }
    payouts = await _service.fetchPayoutsForSeason(id);
    collectedEntryFees = await _service.fetchCollectedEntryFees(id);
  }

  Future<bool> createSeason({
    required String name,
    String? description,
    required DateTime registrationStart,
    required DateTime registrationEnd,
    int teamLimit = 32,
    int rosterLimit = 10,
    int playersPerRound = 5,
    num entryFeeCent = 0,
  }) async {
    actionError = null;
    try {
      final s = await _service.createSeason(
        name: name,
        description: description,
        registrationStart: registrationStart,
        registrationEnd: registrationEnd,
        teamLimit: teamLimit,
        rosterLimit: rosterLimit,
        playersPerRound: playersPerRound,
        entryFeeCent: entryFeeCent,
      );
      seasons = await _service.fetchAllSeasons();
      selectedSeason = s;
      await _loadSeasonDetail();
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not create season: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> setSeasonStatus(String status) async {
    if (selectedSeason == null) return;
    try {
      await _service.updateSeasonStatus(selectedSeason!.id, status);
      seasons = await _service.fetchAllSeasons();
      selectedSeason = seasons.firstWhere((s) => s.id == selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not update season status: $e';
    }
    notifyListeners();
  }

  Future<void> setTeamStatus(String teamId, String status) async {
    try {
      await _service.updateTeamStatus(teamId, status);
      teams = await _service.fetchTeamsForSeason(selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not update team: $e';
    }
    notifyListeners();
  }

  Future<void> disqualifyTeam(String teamId, String reason) async {
    try {
      await _service.disqualifyTeam(teamId: teamId, reason: reason);
      teams = await _service.fetchTeamsForSeason(selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not disqualify team: $e';
    }
    notifyListeners();
  }

  Future<bool> refundTeam({required String teamId, required num amountCent, required String reason}) async {
    actionError = null;
    try {
      await _service.refundTeam(teamId: teamId, amountCent: amountCent, reason: reason);
      collectedEntryFees = await _service.fetchCollectedEntryFees(selectedSeason!.id);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not process refund: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetRound(String roundId) async {
    actionError = null;
    try {
      await _service.resetRound(roundId);
      rounds = await _service.fetchRounds(selectedSeason!.id);
      matchesByRound[roundId] = await _service.fetchRawMatchesForRound(roundId);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not reset round: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> createRound({
    required int roundNumber,
    required String name,
    required DateTime opensAt,
    required DateTime closesAt,
    String? questionSetId,
  }) async {
    actionError = null;
    try {
      await _service.createRound(
        seasonId: selectedSeason!.id,
        roundNumber: roundNumber,
        name: name,
        opensAt: opensAt,
        closesAt: closesAt,
        questionSetId: questionSetId,
      );
      rounds = await _service.fetchRounds(selectedSeason!.id);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not create round: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> setRoundStatus(String roundId, String status) async {
    actionError = null;
    try {
      if (status == 'closed') {
        // Actually scores every match in the round — not just a flag flip.
        await _service.closeRound(roundId);
      } else {
        await _service.updateRoundStatus(roundId, status);
      }
      rounds = await _service.fetchRounds(selectedSeason!.id);
      matchesByRound[roundId] = await _service.fetchRawMatchesForRound(roundId);
    } catch (e) {
      actionError = 'Could not update round: $e';
    }
    notifyListeners();
  }

  Future<bool> createMatch({
    required String roundId,
    required String teamAId,
    required String teamBId,
  }) async {
    actionError = null;
    try {
      await _service.createMatch(
        seasonId: selectedSeason!.id,
        roundId: roundId,
        teamAId: teamAId,
        teamBId: teamBId,
      );
      matchesByRound[roundId] = await _service.fetchRawMatchesForRound(roundId);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not create match: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> createQuestionSet({
    required String name,
    required String subject,
    required int durationSeconds,
    String? difficulty,
    required List<String> questionIds,
  }) async {
    actionError = null;
    try {
      await _service.createQuestionSet(
        seasonId: selectedSeason!.id,
        name: name,
        subject: subject,
        durationSeconds: durationSeconds,
        difficulty: difficulty,
        questionIds: questionIds,
      );
      questionSets = await _service.fetchQuestionSetsForSeason(selectedSeason!.id);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not create question set: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> refresh() => load();

  Future<void> resolveDisputedMatch({required String matchId, required String winnerTeamId, required String roundId}) async {
    actionError = null;
    try {
      await _service.setMatchWinner(matchId: matchId, winnerTeamId: winnerTeamId);
      matchesByRound[roundId] = await _service.fetchRawMatchesForRound(roundId);
      notifyListeners();
    } catch (e) {
      actionError = 'Could not resolve match: $e';
      notifyListeners();
    }
  }

  Future<bool> finalizePrize({
    required String winnerTeamId,
    required num tutorPct,
    required num playerPct,
    required num platformPct,
  }) async {
    actionError = null;
    try {
      await _service.finalizePrize(
        seasonId: selectedSeason!.id,
        winnerTeamId: winnerTeamId,
        tutorPct: tutorPct,
        playerPct: playerPct,
        platformPct: platformPct,
      );
      payouts = await _service.fetchPayoutsForSeason(selectedSeason!.id);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not finalize prize: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> processPayout(String payoutId) async {
    try {
      await _service.processPayout(payoutId);
      payouts = await _service.fetchPayoutsForSeason(selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not process payout: $e';
    }
    notifyListeners();
  }
}
