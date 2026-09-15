// lib/championship_tutor_provider.dart
// REPLACES the earlier version. Roster is username-based now (no
// classroom-student picker list — tutor types a username, server
// validates classroom membership). Round selection is a whole-list
// replace via tutor_select_round_players, not per-checkbox toggles.

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

  List<ChampionshipBracketRow> myMatches = [];
  List<ChampionshipRound> rounds = [];
  ChampionshipBracketRow? selectedMatch;
  List<String> currentSelectionStudentIds = [];

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
    rounds = await _service.fetchRounds(season!.id);
    final bracket = await _service.fetchBracket(season!.id);
    myMatches = bracket.where((r) => r.involvesTeam(team!.id)).toList()
      ..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
    if (myMatches.isNotEmpty) {
      selectedMatch = myMatches.firstWhere((m) => m.roundStatus != 'closed', orElse: () => myMatches.last);
      await _loadSelection();
    }
  }

  ChampionshipRound? get selectedRound {
    if (selectedMatch == null) return null;
    try {
      return rounds.firstWhere((r) => r.id == selectedMatch!.roundId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadSelection() async {
    if (selectedMatch == null || team == null) return;
    currentSelectionStudentIds = await _service.fetchSelectionForMatch(matchId: selectedMatch!.matchId, teamId: team!.id);
  }

  Future<void> selectMatch(ChampionshipBracketRow match) async {
    selectedMatch = match;
    notifyListeners();
    await _loadSelection();
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
      final id = await _service.registerTeam(
        seasonId: season!.id,
        classroomId: classroomId,
        name: name,
        description: description,
        category: category,
      );
      team = await _service.fetchTeamById(id);
      myCentBalance = await _service.fetchMyCentBalance();
      await _loadTeamDetail();
      notifyListeners();
      return true;
    } catch (e) {
      final message = e is PostgrestException ? e.message : e.toString();
      actionError = 'Could not register team: $message';
      notifyListeners();
      return false;
    }
  }

  Future<bool> addToRoster(String username) async {
    actionError = null;
    try {
      await _service.addPlayerToRoster(teamId: team!.id, username: username);
      roster = await _service.fetchRoster(team!.id);
      notifyListeners();
      return true;
    } catch (e) {
      final message = e is PostgrestException ? e.message : e.toString();
      actionError = message;
      notifyListeners();
      return false;
    }
  }

  Future<void> removeFromRoster(String studentId) async {
    try {
      await _service.removePlayerFromRoster(teamId: team!.id, studentId: studentId);
      roster = await _service.fetchRoster(team!.id);
    } catch (e) {
      actionError = 'Could not remove player: $e';
    }
    notifyListeners();
  }

  Future<bool> lockRoster() async {
    actionError = null;
    try {
      await _service.lockRoster(team!.id);
      team = await _service.fetchTeamById(team!.id);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not lock roster: $e';
      notifyListeners();
      return false;
    }
  }

  bool get canEditSelection {
    final round = selectedRound;
    if (round == null) return false;
    return !round.hasOpened;
  }

  Future<bool> saveSelection(List<String> studentIds) async {
    actionError = null;
    if (studentIds.length > season!.playersPerRound) {
      actionError = 'Only ${season!.playersPerRound} players can be selected per round.';
      notifyListeners();
      return false;
    }
    try {
      await _service.selectRoundPlayers(matchId: selectedMatch!.matchId, studentIds: studentIds);
      currentSelectionStudentIds = studentIds;
      notifyListeners();
      return true;
    } catch (e) {
      final message = e is PostgrestException ? e.message : e.toString();
      actionError = 'Could not save selection: $message';
      notifyListeners();
      return false;
    }
  }

  Future<void> refresh() => load();
}
