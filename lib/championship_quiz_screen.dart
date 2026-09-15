// lib/championship_quiz_screen.dart
//
// REPLACES the earlier version. This schema's student_submit_attempt
// has NO server-side deadline check in the original SQL — the patch
// file adds one (server_deadline column + a check in submit). If you
// haven't run championship_v2_patch.sql, submissions are graded no
// matter how late — the countdown here would be purely decorative.
// With the patch applied, past server_deadline the server returns
// {expired: true, score: 0} instead of grading.
//
// No pausing: back navigation is blocked while an attempt is in progress.

import 'dart:async';
import 'package:flutter/material.dart';
import 'championship_service.dart';
import 'championship_models.dart';

class ChampionshipQuizScreen extends StatefulWidget {
  final int matchId;
  const ChampionshipQuizScreen({super.key, required this.matchId});

  /// Starts the attempt (idempotent server-side) and pushes the quiz
  /// screen. Returns true if the user completed or the attempt expired
  /// (so the caller knows to refresh), false if starting failed.
  static Future<bool> startAndOpen(BuildContext context, int matchId) async {
    ChampionshipAttemptState state;
    try {
      state = await ChampionshipService.instance.startAttempt(matchId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start attempt: $e')));
      }
      return false;
    }
    if (!context.mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChampionshipQuizScreen(matchId: matchId),
        fullscreenDialog: true,
      ),
    );
    return true;
  }

  @override
  State<ChampionshipQuizScreen> createState() => _ChampionshipQuizScreenState();
}

class _ChampionshipQuizScreenState extends State<ChampionshipQuizScreen> {
  final _service = ChampionshipService.instance;

  bool _loading = true;
  String? _error;
  DateTime? _serverDeadline;
  List<ChampionshipQuizQuestion> _questions = [];
  final Map<String, int> _answers = {}; // questionId -> selected index
  int _currentIndex = 0;
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _submitting = false;
  Map<String, dynamic>? _result; // {score, correct_count, expired}

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      // Re-call start (idempotent) to get the deadline for this session,
      // and the existing attempt row (via a direct select) to check if
      // it's already been submitted from a previous session.
      final state = await _service.startAttempt(widget.matchId);
      final existing = await _service.fetchMyAttempt(widget.matchId);
      if (existing != null && existing['status'] == 'submitted') {
        setState(() {
          _result = {'score': existing['score'], 'correct_count': existing['correct_count'], 'expired': false};
          _loading = false;
        });
        return;
      }
      if (existing != null && existing['status'] == 'expired') {
        setState(() {
          _result = {'score': 0, 'correct_count': 0, 'expired': true};
          _loading = false;
        });
        return;
      }

      final questions = await _service.fetchMatchQuestions(widget.matchId);
      setState(() {
        _serverDeadline = state.serverDeadline;
        _questions = questions;
        _loading = false;
      });
      _startTicker();
    } catch (e) {
      setState(() {
        _error = 'Could not load your attempt: $e';
        _loading = false;
      });
    }
  }

  void _startTicker() {
    _updateRemaining();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
      if (_remaining <= Duration.zero) {
        _ticker?.cancel();
        _submit(auto: true);
      }
    });
  }

  void _updateRemaining() {
    final deadline = _serverDeadline;
    if (deadline == null) return;
    setState(() {
      _remaining = deadline.difference(DateTime.now());
      if (_remaining.isNegative) _remaining = Duration.zero;
    });
  }

  Future<void> _submit({bool auto = false}) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await _service.submitAttempt(matchId: widget.matchId, answers: _answers);
      setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(auto ? 'Time up — submission failed: $e' : 'Submit failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _result != null,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Championship Round'),
          automaticallyImplyLeading: _result != null,
          actions: [
            if (_result == null && _serverDeadline != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: Text(_formatDuration(_remaining), style: const TextStyle(fontWeight: FontWeight.bold))),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    if (_result != null) return _buildResultView();
    if (_questions.isEmpty) return const Center(child: Text('No questions found for this round.'));

    final q = _questions[_currentIndex];
    final selected = _answers[q.id];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: (_currentIndex + 1) / _questions.length),
            const SizedBox(height: 8),
            Text('Question ${_currentIndex + 1} of ${_questions.length}', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(q.questionText, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 20),
                    ...List.generate(q.options.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            backgroundColor: selected == i ? Theme.of(context).colorScheme.primaryContainer : null,
                          ),
                          onPressed: () => setState(() => _answers[q.id] = i),
                          child: Text(q.options[i]),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                if (_currentIndex > 0)
                  TextButton(onPressed: () => setState(() => _currentIndex--), child: const Text('Back')),
                const Spacer(),
                if (_currentIndex < _questions.length - 1)
                  FilledButton(onPressed: () => setState(() => _currentIndex++), child: const Text('Next'))
                else
                  FilledButton(
                    onPressed: _submitting ? null : () => _confirmSubmit(),
                    child: _submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Submit'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSubmit() async {
    final unanswered = _questions.length - _answers.length;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Submit attempt?'),
        content: Text(
          unanswered > 0
              ? 'You have $unanswered unanswered question(s). This cannot be undone once submitted.'
              : 'This cannot be undone once submitted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep working')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
        ],
      ),
    );
    if (proceed == true) _submit();
  }

  Widget _buildResultView() {
    final scheme = Theme.of(context).colorScheme;
    final expired = _result!['expired'] == true;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              expired ? Icons.timer_off_rounded : Icons.check_circle_rounded,
              size: 64,
              color: expired ? scheme.error : scheme.primary,
            ),
            const SizedBox(height: 16),
            Text(expired ? 'Time expired' : 'Attempt submitted', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              expired
                  ? 'You ran out of time before submitting, so this attempt scored 0.'
                  : 'Your score will be revealed to both teams once the round closes.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
