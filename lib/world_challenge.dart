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

  Future<int> submitAnswers(String challengeId, Map<String, int> answers) async {
    final result = await _client.rpc('submit_world_challenge_answers', params: {
      'p_challenge_id': challengeId,
      'p_answers': answers,
    });
    return (result as Map)['score'] as int;
  }
}

class WorldChallengeScreen extends StatefulWidget {
  const WorldChallengeScreen({super.key});
  @override
  State<WorldChallengeScreen> createState() => _WorldChallengeScreenState();
}

class _WorldChallengeScreenState extends State<WorldChallengeScreen> {
  bool _busy = false;
  String? _error;

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
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _WorldChallengeQuizScreen(challengeId: challengeId, questions: questions),
      ));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('🌍 World Challenge')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events_rounded, size: 64, color: Colors.amber),
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
          ],
        ),
      ),
    );
  }
}

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

  @override
  void initState() {
    super.initState();
    _answers = List<int?>.filled(widget.questions.length, null);
  }

  Future<void> _finish() async {
    setState(() => _submitting = true);
    final answersMap = <String, int>{
      for (var i = 0; i < widget.questions.length; i++)
        if (_answers[i] != null) widget.questions[i].id: _answers[i]!,
    };

    final score = await WorldChallengeService.instance.submitAnswers(widget.challengeId, answersMap);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Submitted'), automaticallyImplyLeading: false),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              Text('You scored $score/${widget.questions.length}'),
              const SizedBox(height: 8),
              const Text('Winners are announced at the end of the week.'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = widget.questions[_index];

    return Scaffold(
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
            const Spacer(),
            Row(
              children: [
                if (_index > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _index--),
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
                              _finish();
                            }
                          },
                    child: Text(_index < widget.questions.length - 1 ? 'Next' : 'Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
