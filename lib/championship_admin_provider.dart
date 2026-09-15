// lib/championship_admin_provider.dart
// REPLACES the earlier version — every write goes through an admin_*
// RPC now, none are direct table writes (RLS doesn't allow any).

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
  List<ChampionshipBracketRow> bracket = [];
  List<ChampionshipPrize> prizes = [];
  List<ChampionshipPayout> payouts = [];

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
    bracket = await _service.fetchBracket(id);
    prizes = await _service.fetchPrizesForSeason(id);
    payouts = await _service.fetchPayoutsForSeason(id);
  }

  // ---------------- Seasons ----------------

  Future<bool> createSeason({
    required String name,
    String? description,
    DateTime? registrationStart,
    DateTime? registrationEnd,
    int? teamLimit,
    int rosterLimit = 10,
    int playersPerRound = 5,
    int entryFeeCent = 0,
  }) async {
    actionError = null;
    try {
      final id = await _service.adminCreateSeason(
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
      selectedSeason = seasons.firstWhere((s) => s.id == id);
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
      await _service.adminUpdateSeasonStatus(selectedSeason!.id, status);
      seasons = await _service.fetchAllSeasons();
      selectedSeason = seasons.firstWhere((s) => s.id == selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not update season status: $e';
    }
    notifyListeners();
  }

  // ---------------- Teams ----------------

  Future<void> approveTeam(int teamId) async {
    try {
      await _service.adminApproveTeam(teamId);
      teams = await _service.fetchTeamsForSeason(selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not approve team: $e';
    }
    notifyListeners();
  }

  Future<void> rejectTeam(int teamId, String reason) async {
    try {
      await _service.adminRejectTeam(teamId, reason);
      teams = await _service.fetchTeamsForSeason(selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not reject team: $e';
    }
    notifyListeners();
  }

  Future<void> disqualifyTeam(int teamId, String reason) async {
    try {
      await _service.adminDisqualifyTeam(teamId, reason);
      teams = await _service.fetchTeamsForSeason(selectedSeason!.id);
      bracket = await _service.fetchBracket(selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not disqualify team: $e';
    }
    notifyListeners();
  }

  Future<bool> refundTeam({required int teamId, required int amountCent, required String reason}) async {
    actionError = null;
    try {
      await _service.adminRefundTeam(teamId: teamId, amountCent: amountCent, reason: reason);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not process refund: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> unlockRoster(int teamId) async {
    try {
      await _service.adminUnlockRoster(teamId);
      teams = await _service.fetchTeamsForSeason(selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not unlock roster: $e';
    }
    notifyListeners();
  }

  // ---------------- Question sets ----------------

  Future<bool> createQuestionSet({
    required String name,
    required String subject,
    required int durationSeconds,
    required List<String> questionIds,
  }) async {
    actionError = null;
    try {
      await _service.adminCreateQuestionSet(
        seasonId: selectedSeason!.id,
        name: name,
        subject: subject,
        durationSeconds: durationSeconds,
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

  // ---------------- Rounds ----------------

  Future<bool> createRound({
    required int roundNumber,
    required String name,
    required DateTime opensAt,
    required DateTime closesAt,
    required int questionSetId,
  }) async {
    actionError = null;
    try {
      await _service.adminCreateRound(
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

  Future<void> setRoundStatus(int roundId, String status) async {
    actionError = null;
    try {
      await _service.adminSetRoundStatus(roundId, status);
      rounds = await _service.fetchRounds(selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not update round: $e';
    }
    notifyListeners();
  }

  /// Scores every match in the round and closes it.
  Future<bool> closeRound(int roundId) async {
    actionError = null;
    try {
      await _service.adminCloseRound(roundId);
      rounds = await _service.fetchRounds(selectedSeason!.id);
      bracket = await _service.fetchBracket(selectedSeason!.id);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not close round: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetRound(int roundId) async {
    actionError = null;
    try {
      await _service.adminResetRound(roundId);
      rounds = await _service.fetchRounds(selectedSeason!.id);
      bracket = await _service.fetchBracket(selectedSeason!.id);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not reset round: $e';
      notifyListeners();
      return false;
    }
  }

  // ---------------- Matches ----------------

  Future<bool> createMatch({required int roundId, required int teamAId, required int teamBId}) async {
    actionError = null;
    try {
      await _service.adminCreateMatch(roundId: roundId, teamAId: teamAId, teamBId: teamBId);
      bracket = await _service.fetchBracket(selectedSeason!.id);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not create match: $e';
      notifyListeners();
      return false;
    }
  }

  /// Per-match manual score compute — adminCloseRound already does this
  /// for every match in a round; this is for recomputing a single one
  /// without closing the whole round again.
  Future<void> computeMatchResult(int matchId) async {
    try {
      await _service.adminComputeMatchResult(matchId);
      bracket = await _service.fetchBracket(selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not compute result: $e';
    }
    notifyListeners();
  }

  Future<void> resolveDisputedMatch({required int matchId, required int winnerTeamId}) async {
    try {
      await _service.adminSetMatchWinner(matchId: matchId, winnerTeamId: winnerTeamId);
      bracket = await _service.fetchBracket(selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not resolve match: $e';
    }
    notifyListeners();
  }

  // ---------------- Prizes & payouts ----------------

  Future<bool> finalizePrize({
    required int winnerTeamId,
    required int prizePoolCent,
    required num platformPct,
    required num tutorPct,
    required num studentPct,
  }) async {
    actionError = null;
    try {
      final id = await _service.adminFinalizePrize(
        seasonId: selectedSeason!.id,
        winnerTeamId: winnerTeamId,
        prizePoolCent: prizePoolCent,
        platformPct: platformPct,
        tutorPct: tutorPct,
        studentPct: studentPct,
      );
      await _service.adminCreatePayoutsForPrize(id);
      prizes = await _service.fetchPrizesForSeason(selectedSeason!.id);
      payouts = await _service.fetchPayoutsForSeason(selectedSeason!.id);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not finalize prize: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> processPayout(int payoutId) async {
    try {
      await _service.adminProcessPayout(payoutId);
      payouts = await _service.fetchPayoutsForSeason(selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not process payout: $e';
    }
    notifyListeners();
  }

  Future<void> setPayoutStatus(int payoutId, String status) async {
    try {
      await _service.adminSetPayoutStatus(payoutId, status);
      payouts = await _service.fetchPayoutsForSeason(selectedSeason!.id);
    } catch (e) {
      actionError = 'Could not update payout: $e';
    }
    notifyListeners();
  }

  Future<void> refresh() => load();
}
