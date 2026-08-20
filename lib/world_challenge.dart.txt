import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show Question;

class WorldChallengeEntry {
  final String userId;
  final int score;
  final bool finished;

  WorldChallengeEntry({required this.userId, required this.score, required this.finished});

  factory WorldChallengeEntry.fromMap(Map<String, dynamic> m) => WorldChallengeEntry(
        userId: m['user_id'] as String,
        score: (m['score'] as num?)?.toInt() ?? 0,
        finished: m['finished'] as bool? ?? false,
      );
}

class WorldChallengeService {
  WorldChallengeService._();
  static final WorldChallengeService instance = WorldChallengeService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<String?> join() async {
    try {
      final result = await _client.rpc('join_world_challenge');
      if (result is Map && result['success'] == true) return null;
      return 'Could not join';
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return 'Something went wrong. Please try again.';
    }
  }

  Future<String> getOrCreateChallengeId() async {
    final result = await _client.rpc('get_or_create_world_challenge');
    return result as String;
  }

  Future<List<Question>> getQuestions(String challengeId) async {
    final rows = await _client.rpc('get_world_challenge_questions', params: {
      'p_challenge_id': challengeId,
    });
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

  /// Submits the user's answers. Deliberately returns nothing — the
  /// server withholds the score entirely until the challenge concludes,
  /// so there is no way for the client to know the result early.
  Future<void> submitAnswers(String challengeId, Map<String, int> answers) async {
    await _client.rpc('submit_world_challenge_answers', params: {
      'p_challenge_id': challengeId,
      'p_answers': answers,
    });
  }

  /// The most recent challenge this user has joined — works even after
  /// the week has rolled over, so results stay reachable afterward.
  Future<String?> getMyLastChallengeId() async {
    final result = await _client.rpc('get_my_last_world_challenge');
    return result as String?;
  }

  /// Returns one of:
  ///   { concluded: false }
  ///   { concluded: true, joined: false }
  ///   { concluded: true, joined: true, won: true, rank, percentage, prize_cent }
  ///   { concluded: true, joined: true, won: false, percentage }
  /// Percentage only — raw score is never sent to the client.
  Future<Map<String, dynamic>> getResult(String challengeId) async {
    final result = await _client.rpc('get_world_challenge_result', params: {'p_challenge_id': challengeId});
    return Map<String, dynamic>.from(result as Map);
  }
}

/// =========================================================================
/// HOME / JOIN SCREEN
/// =========================================================================
///
/// WINNER VISIBILITY FIX: previously, winning (or simply finishing) a
/// concluded challenge was invisible unless the user remembered to tap
/// "View My Last Result" — nothing on this screen ever indicated a
/// decided outcome existed. On open, this screen now also silently loads
/// the user's last challenge result and, if it has concluded, shows a
/// prominent banner right at the top (🏆 win, or a plain "scored X%"
/// completion note) — so a decided winner is surfaced automatically
/// instead of staying hidden behind an extra tap.
class WorldChallengeScreen extends StatefulWidget {
  const WorldChallengeScreen({super.key});
  @override
  State<WorldChallengeScreen> createState() => _WorldChallengeScreenState();
}

class _WorldChallengeScreenState extends State<WorldChallengeScreen> {
  bool _busy = false;
  String? _error;

  bool _loadingLastResult = true;
  Map<String, dynamic>? _lastResult;

  @override
  void initState() {
    super.initState();
    _loadLastResult();
  }

  Future<void> _loadLastResult() async {
    try {
      final challengeId = await WorldChallengeService.instance.getMyLastChallengeId();
      if (challengeId == null) {
        if (!mounted) return;
        setState(() => _loadingLastResult = false);
        return;
      }
      final result = await WorldChallengeService.instance.getResult(challengeId);
      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _loadingLastResult = false;
      });
    } catch (e) {
      // Non-fatal — the banner just doesn't show if this fails. The user
      // can still reach the full result screen via the button below.
      if (!mounted) return;
      setState(() => _loadingLastResult = false);
    }
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final joinError = await WorldChallengeService.instance.join();
    if (joinError != null) {
      setState(() {
        _busy = false;
        _error = joinError;
      });
      return;
    }

    try {
      final challengeId = await WorldChallengeService.instance.getOrCreateChallengeId();
      final questions = await WorldChallengeService.instance.getQuestions(challengeId);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _WorldChallengeQuizScreen(challengeId: challengeId, questions: questions),
      ));
      // Refresh the banner in case this session's submission changed
      // what "last result" means (e.g. re-checking after a resubmit flow).
      if (mounted) _loadLastResult();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget? _buildLastResultBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = _lastResult;
    if (_loadingLastResult || result == null) return null;
    if (result['joined'] == false) return null;
    if (result['concluded'] != true) return null;

    final won = result['won'] == true;
    final percentage = (result['percentage'] as num?)?.toDouble() ?? 0;

    if (won) {
      final rank = (result['rank'] as num?)?.toInt() ?? 1;
      final prize = (result['prize_cent'] as num?)?.toDouble() ?? 0;
      final rankLabel = rank == 1 ? '🥇 1st Place' : rank == 2 ? '🥈 2nd Place' : '🥉 3rd Place';
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorldChallengeResultScreen())),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA000)]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Last week: $rankLabel!', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 15)),
                      Text(
                        prize > 0
                            ? 'Scored ${percentage.toStringAsFixed(0)}% — +${prize.toStringAsFixed(0)} Cent prize'
                            : 'Scored ${percentage.toStringAsFixed(0)}%',
                        style: const TextStyle(color: Colors.black87, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.black87),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorldChallengeResultScreen())),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Last week\'s challenge: Complete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('You scored ${percentage.toStringAsFixed(0)}% — didn\'t place in the top 3',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final banner = _buildLastResultBanner(context);
    return Scaffold(
      appBar: AppBar(title: const Text('🌍 World Challenge')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (banner != null) banner,
            const Icon(Icons.emoji_events_rounded, size: 64, color: Colors.amber),
            const SizedBox(height: 16),
            Text('Weekly World Challenge', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Entry: 500 Cent. Top 3 scorers share the prize pool.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _join,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Join This Week\'s Challenge'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorldChallengeResultScreen())),
              child: const Text('View My Last Result'),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// QUIZ SCREEN
/// =========================================================================
///
/// Two safe additions here, both motivated by this being a paid (500
/// Cent) entry with an irreversible submit:
///  1. A confirmation dialog before the final submit (mirrors the
///     pattern already used by the regular exam screen), showing how
///     many questions were actually answered so a stray tap can't lock
///     in an incomplete attempt.
///  2. Real error handling around submitAnswers() — previously a failed
///     submit (network drop, RPC error) left the button spinning forever
///     with no feedback and no way to retry. It now shows an error and
///     lets the user try again without losing their answers.
///  3. A back-button guard: leaving mid-challenge (back button/gesture)
///     now asks for confirmation, since the entry fee is already paid
///     and backing out silently could look like a lost attempt.
class _WorldChallengeQuizScreen extends StatefulWidget {
  final String challengeId;
  final List<Question> questions;
  const _WorldChallengeQuizScreen({required this.challengeId, required this.questions});

  @override
  State<_WorldChallengeQuizScreen> createState() => _WorldChallengeQuizScreenState();
}

class _WorldChallengeQuizScreenState extends State<_WorldChallengeQuizScreen> {
  late List<int?> _answers;
  int _index = 0;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _answers = List<int?>.filled(widget.questions.length, null);
  }

  Future<void> _confirmAndFinish() async {
    final answeredCount = _answers.where((a) => a != null).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Answers?'),
        content: Text(
          'You have answered $answeredCount of ${widget.questions.length} questions. '
          'This is your one entry for this week\'s challenge — once submitted, answers cannot be changed. Submit now?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed == true) _finish();
  }

  Future<void> _finish() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final answersMap = <String, int>{
      for (var i = 0; i < widget.questions.length; i++)
        if (_answers[i] != null) widget.questions[i].id: _answers[i]!,
    };

    try {
      await WorldChallengeService.instance.submitAnswers(widget.challengeId, answersMap);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = 'Could not submit your answers — please check your connection and try again.';
      });
      return;
    }
    if (!mounted) return;

    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Submitted'), automaticallyImplyLeading: false),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.hourglass_top_rounded, color: Colors.amber, size: 64),
                const SizedBox(height: 16),
                const Text('Your answers are locked in.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text('Winners are announced at the end of the week. Check back then to see how you did.', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  Future<bool> _confirmLeave() async {
    if (_submitting) return false;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Challenge?'),
        content: const Text(
          'You\'ve already paid your entry for this week. Leaving now means your answers won\'t be submitted — '
          'you can come back and finish before the week ends.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = widget.questions[_index];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await _confirmLeave();
        if (shouldLeave && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Question ${_index + 1}/${widget.questions.length}')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                child: Text(q.questionText, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 18),
              ...List.generate(q.options.length, (i) {
                final selected = _answers[_index] == i;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: selected ? scheme.primaryContainer : null,
                      padding: const EdgeInsets.all(16),
                    ),
                    onPressed: () => setState(() => _answers[_index] = i),
                    child: Align(alignment: Alignment.centerLeft, child: Text(q.options[i])),
                  ),
                );
              }),
              if (_submitError != null) ...[
                const SizedBox(height: 8),
                Text(_submitError!, style: TextStyle(color: scheme.error, fontSize: 13)),
              ],
              const Spacer(),
              Row(
                children: [
                  if (_index > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : () => setState(() => _index--),
                        child: const Text('Previous'),
                      ),
                    ),
                  if (_index > 0) const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting
                          ? null
                          : () {
                              if (_index < widget.questions.length - 1) {
                                setState(() => _index++);
                              } else {
                                _confirmAndFinish();
                              }
                            },
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_index < widget.questions.length - 1 ? 'Next' : 'Submit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// RESULTS SCREEN
/// =========================================================================
///
/// Winners (top 3): shown their position AND their score, as a percentage.
/// Everyone else: shown ONLY their score, as a percentage — no rank, no
/// hint of how close they came. The server itself withholds rank/prize
/// data from non-winners, so this isn't just a UI choice to hide it —
/// the app genuinely never receives it for a loss.

class WorldChallengeResultScreen extends StatefulWidget {
  const WorldChallengeResultScreen({super.key});

  @override
  State<WorldChallengeResultScreen> createState() => _WorldChallengeResultScreenState();
}

class _WorldChallengeResultScreenState extends State<WorldChallengeResultScreen> {
  bool _loading = true;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final challengeId = await WorldChallengeService.instance.getMyLastChallengeId();
      if (challengeId == null) {
        setState(() {
          _loading = false;
          _result = {'concluded': true, 'joined': false};
        });
        return;
      }
      final result = await WorldChallengeService.instance.getResult(challengeId);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your result. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Result')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Center(child: Text(_error!, style: TextStyle(color: scheme.error)))
            else
              _buildResultContent(context),
          ],
        ),
      ),
    );
  }

  Widget _buildResultContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = _result!;

    if (result['joined'] == false) {
      return Column(
        children: [
          const Text('🌍', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text("You haven't joined a World Challenge yet.", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      );
    }

    if (result['concluded'] == false) {
      return Column(
        children: [
          const Icon(Icons.hourglass_top_rounded, size: 64, color: Colors.amber),
          const SizedBox(height: 16),
          const Text('Not decided yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          const Text('Winners are announced once the week ends. Check back then.', textAlign: TextAlign.center),
        ],
      );
    }

    final percentage = (result['percentage'] as num?)?.toDouble() ?? 0;
    final won = result['won'] == true;

    if (won) {
      final rank = (result['rank'] as num).toInt();
      final prize = (result['prize_cent'] as num?)?.toDouble() ?? 0;
      final rankLabel = rank == 1 ? '🥇 1st Place' : rank == 2 ? '🥈 2nd Place' : '🥉 3rd Place';

      return Column(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 72)),
          const SizedBox(height: 16),
          Text(rankLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
            child: Text('${percentage.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ),
          if (prize > 0) ...[
            const SizedBox(height: 16),
            Text('+${prize.toStringAsFixed(0)} Cent prize', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
          ],
        ],
      );
    }

    return Column(
      children: [
        const Icon(Icons.check_circle_outline_rounded, size: 64),
        const SizedBox(height: 16),
        const Text('Challenge Complete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
          child: Text('${percentage.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        ),
        const SizedBox(height: 12),
        Text('You didn\'t place in the top 3 this week — try again next week!', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
