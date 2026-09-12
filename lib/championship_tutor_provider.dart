// lib/championship_tutor_provider.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'championship_models.dart';
import 'championship_service.dart';

class TutorChampionshipProvider extends ChangeNotifier {
  final ChampionshipService _service = ChampionshipService.instance;

  bool loading = true;
  String? error;
  String? actionError;

  bool isApprovedTutor = false;
  ChampionshipSeason? season;
  List<Map<String, dynamic>> myClassrooms = [];
  num myCentBalance = 0;
  ChampionshipTeam? team;
  List<ChampionshipPlayer> roster = [];
  List<Map<String, dynamic>> eligibleStudents = []; // from the team's classroom
  Set<String> rosteredElsewhere = {};

  List<ChampionshipRound> rounds = [];
  ChampionshipRound? selectedRound;
  ChampionshipMatch? matchForSelectedRound;
  List<ChampionshipPlayer> currentSelections = [];

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      isApprovedTutor = await _service.isCurrentUserApprovedTutor();
      season = await _service.fetchActiveSeason();
      if (season == null) {
        loading = false;
        notifyListeners();
        return;
      }
      myClassrooms = await _service.fetchMyClassrooms();
      myCentBalance = await _service.fetchMyCentBalance();
      team = await _service.fetchMyTutorTeam(season!.id);
      if (team != null) {
        await _loadTeamDetail();
      }
    } catch (e) {
      error = 'Could not load championship data: $e';
      debugPrint('[TutorChampionship] load() failed: $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadTeamDetail() async {
    roster = await _service.fetchRoster(team!.id);
    eligibleStudents = await _service.fetchEligibleClassroomStudents(classroomId: team!.classroomId);
    rosteredElsewhere = await _service.fetchRosteredStudentIdsForSeason(season!.id);
    rounds = await _service.fetchRounds(season!.id);
    if (rounds.isNotEmpty) {
      selectedRound = rounds.cast<ChampionshipRound?>().firstWhere(
            (r) => r?.status == 'scheduled' || r?.status == 'open',
            orElse: () => rounds.first,
          );
      await _loadRoundDetail();
    }
  }

  Future<void> _loadRoundDetail() async {
    if (selectedRound == null || team == null) return;
    matchForSelectedRound = await _service.fetchTeamMatchForRound(roundId: selectedRound!.id, teamId: team!.id);
    if (matchForSelectedRound != null) {
      currentSelections = await _service.fetchSelectionsForMatch(
        matchId: matchForSelectedRound!.id,
        teamId: team!.id,
      );
    } else {
      currentSelections = [];
    }
  }

  Future<void> selectRound(ChampionshipRound round) async {
    selectedRound = round;
    notifyListeners();
    await _loadRoundDetail();
    notifyListeners();
  }

  Future<bool> registerTeam({
    required int classroomId,
    required String name,
    String? description,
    String? category,
  }) async {
    actionError = null;
    try {
      team = await _service.registerTeam(
        seasonId: season!.id,
        classroomId: classroomId,
        name: name,
        description: description,
        category: category,
      );
      await _loadTeamDetail();
      myCentBalance = await _service.fetchMyCentBalance();
      notifyListeners();
      return true;
    } catch (e) {
      final message = e is PostgrestException ? e.message : e.toString();
      actionError = 'Could not register team: $message';
      notifyListeners();
      return false;
    }
  }

  Future<bool> addToRoster(String studentId) async {
    actionError = null;
    if (roster.length >= season!.rosterLimit) {
      actionError = 'Roster is full (${season!.rosterLimit} players max).';
      notifyListeners();
      return false;
    }
    try {
      await _service.addPlayerToRoster(seasonId: season!.id, teamId: team!.id, studentId: studentId);
      roster = await _service.fetchRoster(team!.id);
      rosteredElsewhere = await _service.fetchRosteredStudentIdsForSeason(season!.id);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not add player — they may already be on a Championship team this season.';
      notifyListeners();
      return false;
    }
  }

  Future<void> removeFromRoster(String playerRowId) async {
    try {
      await _service.removePlayerFromRoster(playerRowId);
      roster = await _service.fetchRoster(team!.id);
    } catch (e) {
      actionError = 'Could not remove player: $e';
    }
    notifyListeners();
  }

  bool get canEditSelectionForCurrentRound => selectedRound?.status == 'scheduled';

  Future<bool> toggleSelection(String studentId) async {
    actionError = null;
    if (!canEditSelectionForCurrentRound || matchForSelectedRound == null) {
      actionError = 'Selections are locked once the round opens.';
      notifyListeners();
      return false;
    }
    final already = currentSelections.any((p) => p.studentId == studentId);
    try {
      if (already) {
        await _service.deselectPlayerForMatch(matchId: matchForSelectedRound!.id, studentId: studentId);
      } else {
        if (currentSelections.length >= season!.playersPerRound) {
          actionError = 'Only ${season!.playersPerRound} players can be selected per round.';
          notifyListeners();
          return false;
        }
        await _service.selectPlayerForMatch(
          matchId: matchForSelectedRound!.id,
          teamId: team!.id,
          studentId: studentId,
        );
      }
      currentSelections = await _service.fetchSelectionsForMatch(
        matchId: matchForSelectedRound!.id,
        teamId: team!.id,
      );
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not update selection: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> refresh() => load();
}
