// lib/connect_baba.dart
//
// Connect Baba — a 2-player CO-OP boss duel.
//
// Two students book a match (create + share a 6-char code, same UX
// pattern as Live Quiz Battle's lobby), then fight ONE shared-HP boss
// TOGETHER instead of competing against each other:
//   - Same question shown to both players at once.
//   - If EITHER player answers correctly, Baba takes damage.
//   - Only if BOTH players miss the same question does Baba counter —
//     damaging a shared Team HP bar instead.
//   - Baba defeated (HP 0) → both players win CP.
//   - Team HP hits 0, or the question set runs out first → Baba survives.
//
// All grading happens server-side (connect_baba_answer RPC) — the
// client never receives or claims a correct answer itself, same
// withholding pattern as get_battle_questions / submit_battle_answers
// already used by Live Quiz Battle.
//
// Lives in the Quiz/Battle section (BattleLobbyScreen in
// career_features.dart) as a third option alongside Live Battle and
// Practice vs Bot — neither of those was touched or removed.
//
// REQUIRES: connect_baba.sql (tables + RPCs) run in Supabase first.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show Question, kSubjects;
import 'app_enhancements.dart' show AppProvider;
import 'zetra_pay.dart';

/// =========================================================================
/// MODELS
/// =========================================================================

class ConnectBabaMatch {
  final int id;
  final String code;
  final String subject;
  final int questionCount;
  final List<String> questionIds;
  final String status; // 'waiting' | 'active' | 'finished'
  final int currentQuestionIndex;
  final int bossHp;
  final int teamHp;
  final String? outcome; // 'won' | 'lost'
  final int durationSeconds;
  final DateTime? startedAt;
  final String createdBy;

  ConnectBabaMatch({
    required this.id,
    required this.code,
    required this.subject,
    required this.questionCount,
    required this.questionIds,
    required this.status,
    required this.currentQuestionIndex,
    required this.bossHp,
    required this.teamHp,
    this.outcome,
    required this.durationSeconds,
    this.startedAt,
    required this.createdBy,
  });

  factory ConnectBabaMatch.fromMap(Map<String, dynamic> m) => ConnectBabaMatch(
        id: (m['id'] as num).toInt(),
        code: m['code'] as String,
        subject: m['subject'] as String,
        questionCount: (m['question_count'] as num?)?.toInt() ?? 15,
        questionIds: List<String>.from((m['question_ids'] as List<dynamic>?) ?? []),
        status: m['status'] as String? ?? 'waiting',
        currentQuestionIndex: (m['current_question_index'] as num?)?.toInt() ?? 0,
        bossHp: (m['boss_hp'] as num?)?.toInt() ?? 100,
        teamHp: (m['team_hp'] as num?)?.toInt() ?? 100,
        outcome: m['outcome'] as String?,
        durationSeconds: (m['duration_seconds'] as num?)?.toInt() ?? 300,
        startedAt: m['started_at'] != null ? DateTime.tryParse(m['started_at'] as String) : null,
        createdBy: m['created_by'] as String? ?? '',
      );
}

class ConnectBabaParticipant {
  final String userId;
  final String username;
  final bool ready;
  ConnectBabaParticipant({required this.userId, required this.username, required this.ready});

  factory ConnectBabaParticipant.fromMap(Map<String, dynamic> m) => ConnectBabaParticipant(
        userId: m['user_id'] as String,
        username: m['username'] as String? ?? 'Player',
        ready: m['ready'] as bool? ?? false,
      );
}

/// =========================================================================
/// SERVICE
/// =========================================================================

class ConnectBabaService {
  ConnectBabaService._();
  static final ConnectBabaService instance = ConnectBabaService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<Map<String, dynamic>> createMatch({
    required String subject,
    required int questionCount,
    required int durationSeconds,
  }) async {
    final result = await _client.rpc('connect_baba_create', params: {
      'p_subject': subject,
      'p_question_count': questionCount,
      'p_duration_seconds': durationSeconds,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> joinMatch(String code) async {
    final result = await _client.rpc('connect_baba_join', params: {'p_code': code.trim()});
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> setReady({required int matchId, required bool ready}) async {
    await _client.rpc('connect_baba_set_ready', params: {'p_match_id': matchId, 'p_ready': ready});
  }

  Future<void> startMatch(int matchId) async {
    await _client.rpc('connect_baba_start', params: {'p_match_id': matchId});
  }

  Future<ConnectBabaMatch?> getMatch(int matchId) async {
    final row = await _client.rpc('connect_baba_get_match', params: {'p_match_id': matchId});
    if (row == null) return null;
    return ConnectBabaMatch.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<List<ConnectBabaParticipant>> getParticipants(int matchId) async {
    final rows = await _client.rpc('connect_baba_get_participants', params: {'p_match_id': matchId});
    return (rows as List).map((r) => ConnectBabaParticipant.fromMap(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Answer key withheld — correctIndex is always -1 on the client, same
  /// pattern as BattleService.getBattleQuestions.
  Future<List<Question>> getQuestions(int matchId) async {
    final rows = await _client.rpc('connect_baba_get_questions', params: {'p_match_id': matchId});
    return (rows as List).map((r) {
      final row = r as Map<String, dynamic>;
      return Question(
        id: row['id'] as String,
        subject: row['subject'] as String,
        year: 0,
        questionText: row['question_text'] as String,
        options: List<String>.from(row['options'] as List),
        correctIndex: -1,
      );
    }).toList();
  }

  /// The only way a round resolves. Server grades the selection, and —
  /// only once BOTH players have answered this question index — applies
  /// damage and returns the outcome. Returns {'status': 'waiting_partner'}
  /// if the other player hasn't answered yet.
  Future<Map<String, dynamic>> answer({
    required int matchId,
    required int questionIndex,
    required int selectedIndex,
  }) async {
    final result = await _client.rpc('connect_baba_answer', params: {
      'p_match_id': matchId,
      'p_question_index': questionIndex,
      'p_selected_index': selectedIndex,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  /// Returns true only the first time THIS player claims the reward for
  /// a won match — call once on the results screen before crediting CP.
  Future<bool> claimReward(int matchId) async {
    final result = await _client.rpc('connect_baba_claim_reward', params: {'p_match_id': matchId});
    return result == true;
  }

  RealtimeChannel subscribeToMatch(int matchId, void Function() onChange) {
    final channel = _client.channel('connect_baba_match_$matchId').onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'connect_baba_matches',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: matchId),
          callback: (payload) => onChange(),
        );
    channel.subscribe();
    return channel;
  }

  RealtimeChannel subscribeToParticipants(int matchId, void Function() onChange) {
    final channel = _client.channel('connect_baba_participants_$matchId').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'connect_baba_participants',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'match_id', value: matchId),
          callback: (payload) => onChange(),
        );
    channel.subscribe();
    return channel;
  }
}

/// =========================================================================
/// LOBBY — create or join a duel
/// =========================================================================

class ConnectBabaLobbyScreen extends StatefulWidget {
  const ConnectBabaLobbyScreen({super.key});

  @override
  State<ConnectBabaLobbyScreen> createState() => _ConnectBabaLobbyScreenState();
}

class _ConnectBabaLobbyScreenState extends State<ConnectBabaLobbyScreen> {
  String _subject = kSubjects.first.name;
  int _questionCount = 15;
  int _durationSeconds = 300;
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  static const List<int> _durationOptions = [180, 240, 300, 360, 480];

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    return '$m min';
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ConnectBabaService.instance.createMatch(
        subject: _subject,
        questionCount: _questionCount,
        durationSeconds: _durationSeconds,
      );
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConnectBabaReadyScreen(matchId: result['match_id'] as int, isHost: true),
      ));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    if (_codeController.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ConnectBabaService.instance.joinMatch(_codeController.text);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConnectBabaReadyScreen(matchId: result['match_id'] as int, isHost: false),
      ));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('🧟 Connect Baba')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFF2D1B4E)]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(children: [
              Text('🧟', style: TextStyle(fontSize: 30)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Team up with a friend on another phone. You share ONE boss HP bar — "
                  "Baba only strikes back if you BOTH miss the same question.",
                  style: TextStyle(color: Colors.white, fontSize: 12.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Text('Start a Duel', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _subject,
                  items: kSubjects.map((s) => DropdownMenuItem(value: s.name, child: Text(s.name))).toList(),
                  onChanged: (v) => setState(() => _subject = v!),
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: _questionCount,
                  items: const [10, 15, 20, 25].map((c) => DropdownMenuItem(value: c, child: Text('$c questions'))).toList(),
                  onChanged: (v) => setState(() => _questionCount = v!),
                  decoration: const InputDecoration(labelText: 'Question count'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: _durationSeconds,
                  items: _durationOptions.map((c) => DropdownMenuItem(value: c, child: Text(_formatDuration(c)))).toList(),
                  onChanged: (v) => setState(() => _durationSeconds = v!),
                  decoration: const InputDecoration(labelText: 'Time limit'),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Create Duel'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Join a Duel', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
            child: Column(
              children: [
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Enter 6-character code'),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _join,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Join Duel'),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: TextStyle(color: scheme.error))),
        ],
      ),
    );
  }
}

/// =========================================================================
/// READY CHECK
/// =========================================================================

class ConnectBabaReadyScreen extends StatefulWidget {
  final int matchId;
  final bool isHost;
  const ConnectBabaReadyScreen({super.key, required this.matchId, required this.isHost});

  @override
  State<ConnectBabaReadyScreen> createState() => _ConnectBabaReadyScreenState();
}

class _ConnectBabaReadyScreenState extends State<ConnectBabaReadyScreen> {
  ConnectBabaMatch? _match;
  List<ConnectBabaParticipant> _participants = [];
  RealtimeChannel? _matchChannel;
  RealtimeChannel? _participantsChannel;
  Timer? _pollTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _matchChannel = ConnectBabaService.instance.subscribeToMatch(widget.matchId, _onChanged);
    _participantsChannel = ConnectBabaService.instance.subscribeToParticipants(widget.matchId, _onChanged);
    // Fallback poll — same lesson learned from Live Battle's Ready
    // screen: never rely on realtime alone, or a dropped websocket can
    // strand a player here indefinitely.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshAll());
  }

  Future<void> _onChanged() async => _refreshAll();

  Future<void> _refreshAll() async {
    final match = await ConnectBabaService.instance.getMatch(widget.matchId);
    final participants = await ConnectBabaService.instance.getParticipants(widget.matchId);
    if (!mounted) return;
    setState(() {
      _match = match;
      _participants = participants;
    });
    if (match != null && match.status == 'active' && !_navigated) {
      _navigated = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ConnectBabaDuelScreen(matchId: widget.matchId),
      ));
    }
  }

  bool get _allReady => _participants.length == 2 && _participants.every((p) => p.ready);

  Future<void> _toggleReady() async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final mine = _participants.where((p) => p.userId == me).toList();
    final currentlyReady = mine.isNotEmpty && mine.first.ready;
    await ConnectBabaService.instance.setReady(matchId: widget.matchId, ready: !currentlyReady);
    _refreshAll();
  }

  Future<void> _hostStart() async {
    try {
      await ConnectBabaService.instance.startMatch(widget.matchId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  void dispose() {
    _matchChannel?.unsubscribe();
    _participantsChannel?.unsubscribe();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final match = _match;
    final me = Supabase.instance.client.auth.currentUser?.id;
    final myEntry = _participants.where((p) => p.userId == me).toList();
    final myReady = myEntry.isNotEmpty && myEntry.first.ready;

    if (match == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ready Check')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                const Text('Share this code', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(match.code, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 6)),
                const SizedBox(height: 4),
                Text('${match.subject} · ${match.questionCount} questions', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(height: 20),
            Text('Players (${_participants.length}/2)', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ..._participants.map((p) {
              final isMe = p.userId == me;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Expanded(child: Text(isMe ? '${p.username} (You)' : p.username, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Icon(p.ready ? Icons.check_circle_rounded : Icons.hourglass_bottom_rounded, color: p.ready ? Colors.green : Colors.orange, size: 20),
                ]),
              );
            }),
            if (_participants.length < 2)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Waiting for your teammate to join with the code above...', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
            const Spacer(),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _participants.length < 2 ? null : _toggleReady,
                icon: Icon(myReady ? Icons.close_rounded : Icons.check_circle_outline_rounded),
                label: Text(myReady ? 'Not Ready' : "I'm Ready"),
              ),
            ),
            if (widget.isHost) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _allReady ? _hostStart : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start Duel'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// THE DUEL — shared boss HP, co-op question resolution
/// =========================================================================

class ConnectBabaDuelScreen extends StatefulWidget {
  final int matchId;
  const ConnectBabaDuelScreen({super.key, required this.matchId});

  @override
  State<ConnectBabaDuelScreen> createState() => _ConnectBabaDuelScreenState();
}

class _ConnectBabaDuelScreenState extends State<ConnectBabaDuelScreen> {
  ConnectBabaMatch? _match;
  List<Question> _questions = [];
  bool _loadingQuestions = true;
  String? _loadError;

  int? _selectedOption;
  bool _waitingPartner = false;
  String? _roundFlash; // brief message shown after a round resolves

  RealtimeChannel? _matchChannel;
  Timer? _pollTimer;
  Timer? _flashTimer;
  bool _navigatedToResults = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _matchChannel = ConnectBabaService.instance.subscribeToMatch(widget.matchId, _onMatchPing);
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _onMatchPing());
  }

  Future<void> _loadInitial() async {
    try {
      final match = await ConnectBabaService.instance.getMatch(widget.matchId);
      final questions = await ConnectBabaService.instance.getQuestions(widget.matchId);
      if (!mounted) return;
      setState(() {
        _match = match;
        _questions = questions;
        _loadingQuestions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loadingQuestions = false;
      });
    }
  }

  Future<void> _onMatchPing() async {
    final newMatch = await ConnectBabaService.instance.getMatch(widget.matchId);
    if (!mounted || newMatch == null) return;
    _syncFromMatch(newMatch);
  }

  /// Single source of truth: the displayed question index, HP bars, and
  /// waiting state are always driven from the server's match row — never
  /// from local optimistic guesses — so it doesn't matter whether a
  /// round resolved because of MY answer or because my teammate's
  /// answer arrived after me. Whoever finds out first just reflects it.
  void _syncFromMatch(ConnectBabaMatch newMatch) {
    final old = _match;
    final hpChanged = old != null && (newMatch.bossHp != old.bossHp || newMatch.teamHp != old.teamHp);
    final indexAdvanced = old != null && newMatch.currentQuestionIndex > old.currentQuestionIndex;

    setState(() {
      _match = newMatch;
      if (indexAdvanced) {
        _selectedOption = null;
        _waitingPartner = false;
      }
    });

    if (hpChanged) {
      final bossHit = newMatch.bossHp < (old?.bossHp ?? newMatch.bossHp);
      _showRoundFlash(bossHit ? '💥 Baba took a hit!' : '⚠️ Baba strikes back — Team HP down!');
    }

    if (newMatch.status == 'finished' && !_navigatedToResults) {
      _navigatedToResults = true;
      _goToResults(newMatch);
    }
  }

  void _showRoundFlash(String message) {
    _flashTimer?.cancel();
    setState(() => _roundFlash = message);
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _roundFlash = null);
    });
  }

  Future<void> _selectAndAnswer(int optionIndex) async {
    final match = _match;
    if (match == null || _selectedOption != null || _waitingPartner) return;

    setState(() {
      _selectedOption = optionIndex;
      _waitingPartner = true;
    });

    try {
      final result = await ConnectBabaService.instance.answer(
        matchId: widget.matchId,
        questionIndex: match.currentQuestionIndex,
        selectedIndex: optionIndex,
      );
      // Whether the round resolved from my own answer (status ==
      // 'resolved') or my teammate hadn't answered yet ('waiting_partner'),
      // pull the freshest match row immediately rather than waiting for
      // realtime/poll latency — _syncFromMatch handles both cases safely.
      if (result['status'] == 'resolved') {
        final fresh = await ConnectBabaService.instance.getMatch(widget.matchId);
        if (fresh != null && mounted) _syncFromMatch(fresh);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedOption = null;
          _waitingPartner = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit — please try again. (${e.toString()})')),
        );
      }
    }
  }

  void _goToResults(ConnectBabaMatch match) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ConnectBabaResultScreen(matchId: match.id, subject: match.subject, outcome: match.outcome ?? 'lost'),
    ));
  }

  @override
  void dispose() {
    _matchChannel?.unsubscribe();
    _pollTimer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final match = _match;

    if (_loadingQuestions || match == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null || _questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Connect Baba')),
        body: Center(child: Text(_loadError ?? 'Could not load questions.', textAlign: TextAlign.center)),
      );
    }

    final index = match.currentQuestionIndex;
    if (index >= _questions.length) {
      // Server already marked this finished; UI will navigate via
      // _syncFromMatch shortly — show a brief spinner instead of a crash.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final q = _questions[index];

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: Text('🧟 ${match.subject} vs Baba'), automaticallyImplyLeading: false),
        body: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    children: [
                      Row(children: [
                        const Text('🧟', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Baba HP: ${match.bossHp}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: match.bossHp / 100,
                                  minHeight: 10,
                                  backgroundColor: scheme.surfaceContainerHighest,
                                  valueColor: const AlwaysStoppedAnimation(Colors.deepPurple),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Text('🛡️', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Team HP: ${match.teamHp}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: match.teamHp / 100,
                                  minHeight: 10,
                                  backgroundColor: scheme.surfaceContainerHighest,
                                  valueColor: AlwaysStoppedAnimation(match.teamHp > 40 ? Colors.green : Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text('Question ${index + 1} of ${match.questionCount}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                          child: Text(q.questionText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4)),
                        ),
                        const SizedBox(height: 18),
                        ...List.generate(q.options.length, (i) {
                          final isSelected = _selectedOption == i;
                          final letter = String.fromCharCode(65 + i);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: isSelected ? scheme.primaryContainer : scheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: (_selectedOption == null && !_waitingPartner) ? () => _selectAndAnswer(i) : null,
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: isSelected ? scheme.primary : scheme.outlineVariant, width: isSelected ? 2 : 1),
                                  ),
                                  child: Row(children: [
                                    CircleAvatar(radius: 14, backgroundColor: isSelected ? scheme.primary : scheme.surfaceContainerHighest, child: Text(letter)),
                                    const SizedBox(width: 14),
                                    Expanded(child: Text(q.options[i])),
                                  ]),
                                ),
                              ),
                            ),
                          );
                        }),
                        if (_waitingPartner)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(children: [
                              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 10),
                              Text('Waiting for your teammate to answer...', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_roundFlash != null)
              Positioned(
                top: 100,
                left: 20,
                right: 20,
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(_roundFlash!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// RESULTS
/// =========================================================================

class ConnectBabaResultScreen extends StatefulWidget {
  final int matchId;
  final String subject;
  final String outcome; // 'won' | 'lost'
  const ConnectBabaResultScreen({super.key, required this.matchId, required this.subject, required this.outcome});

  @override
  State<ConnectBabaResultScreen> createState() => _ConnectBabaResultScreenState();
}

class _ConnectBabaResultScreenState extends State<ConnectBabaResultScreen> {
  bool _claiming = true;
  bool _rewardCredited = false;

  @override
  void initState() {
    super.initState();
    if (widget.outcome == 'won') {
      _claimReward();
    } else {
      _claiming = false;
    }
  }

  Future<void> _claimReward() async {
    try {
      final firstClaim = await ConnectBabaService.instance.claimReward(widget.matchId);
      if (firstClaim) {
        // 5 CP for defeating Baba together — same reward size as a solo
        // Boss Battle win, since this took two people's correct answers.
        await ZetraPay.creditAppCurrency(appId: ZetraPay.naijaLearnAppId, unitAmount: 5);
        if (mounted) setState(() => _rewardCredited = true);
      }
    } catch (_) {
      // Non-fatal — the win itself still shows; CP can be a background retry later.
    }
    if (mounted) setState(() => _claiming = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final won = widget.outcome == 'won';

    return Scaffold(
      appBar: AppBar(title: const Text('Duel Result'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(won ? '🏆' : '😤', style: const TextStyle(fontSize: 72)),
            const SizedBox(height: 16),
            Text(
              won ? 'Baba Defeated!' : 'Baba Got Away...',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: won ? Colors.green : scheme.error),
            ),
            const SizedBox(height: 8),
            Text('${widget.subject} Co-op Duel', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            if (won)
              _claiming
                  ? const CircularProgressIndicator()
                  : Text(_rewardCredited ? '+5 CP earned' : 'Great teamwork!', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
            else
              const Text('Team up again and try a different strategy!', textAlign: TextAlign.center),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Back to Home'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
