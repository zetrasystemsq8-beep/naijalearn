// lib/championship_quiz_screen.dart
//
// The timed attempt itself (spec sections 12, 14, 24). The on-screen
// countdown is a convenience only — championship_submit_attempt on the
// server independently checks server_deadline and forfeits late
// submissions regardless of what the client's clock says.
//
// No pausing: back navigation is blocked while an attempt is in
// progress (RULE: players cannot pause and return later).

import 'dart:async';
import 'package:flutter/material.dart';
import 'championship_service.dart';
import 'championship_models.dart';

class ChampionshipQuizScreen extends StatefulWidget {
  final String matchId;
  const ChampionshipQuizScreen({super.key, required this.matchId});

  /// Starts the attempt (idempotent server-side) and pushes the quiz
  /// screen. Returns true if the user completed or forfeited an attempt
  /// (so the caller knows to refresh), false if starting failed.
  static Future<bool> startAndOpen(BuildContext context, String matchId) async {
    try {
      await ChampionshipService.instance.startAttempt(matchId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start attempt: ${e.toString()}')),
        );
      }
      return false;
    }
    if (!context.mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChampionshipQuizScreen(matchId: matchId), fullscreenDialog: true),
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
  ChampionshipAttempt? _attempt;
  List<ChampionshipQuizQuestion> _questions = [];
  final Map<String, String> _answers = {}; // questionId -> selected index as string
  int _currentIndex = 0;
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _submitting = false;
  ChampionshipAttempt? _result;

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
      final attempt = await _service.fetchMyAttempt(widget.matchId);
      if (attempt == null || attempt.serverDeadline == null) {
        throw Exception('Attempt could not be found.');
      }
      final questions = await _service.fetchAttemptQuestions(attempt.id);
      setState(() {
        _attempt = attempt;
        _questions = questions;
        _loading = false;
      });
      if (attempt.status == 'in_progress') {
        _startTicker();
      }
    } catch (e) {
      setState(() {
        _error = 'Could not load your attempt: ${e.toString()}';
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
    final deadline = _attempt?.serverDeadline;
    if (deadline == null) return;
    setState(() {
      _remaining = deadline.difference(DateTime.now());
      if (_remaining.isNegative) _remaining = Duration.zero;
    });
  }

  Future<void> _submit({bool auto = false}) async {
    if (_submitting || _attempt == null) return;
    setState(() => _submitting = true);
    try {
      final result = await _service.submitAttempt(attemptId: _attempt!.id, answers: _answers);
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
      canPop: _result != null, // block back navigation mid-attempt — no pausing
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Championship Round'),
          automaticallyImplyLeading: _result != null,
          actions: [
            if (_attempt?.status == 'in_progress' && _result == null)
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
                      final idx = i.toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            backgroundColor: selected == idx
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                          ),
                          onPressed: () => setState(() => _answers[q.id] = idx),
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
                  TextButton(
                    onPressed: () => setState(() => _currentIndex--),
                    child: const Text('Back'),
                  ),
                const Spacer(),
                if (_currentIndex < _questions.length - 1)
                  FilledButton(
                    onPressed: () => setState(() => _currentIndex++),
                    child: const Text('Next'),
                  )
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
    final forfeited = _result!.status == 'forfeited';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              forfeited ? Icons.timer_off_rounded : Icons.check_circle_rounded,
              size: 64,
              color: forfeited ? scheme.error : scheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              forfeited ? 'Time expired' : 'Attempt submitted',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              forfeited
                  ? 'You ran out of time before submitting, so this attempt scored 0.'
                  : 'Your score will be revealed to both teams once the round closes.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
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
