import 'dart:async';
import 'package:flutter/material.dart';
import 'uni_controller.dart';
import 'uni_models.dart';

/// Runs a practice set OR a quiz. The server (repository) issues the questions
/// without answers and does all scoring; this screen only collects choices.
class UniTestScreen extends StatefulWidget {
  const UniTestScreen({super.key, required this.ctrl, required this.title, required this.start});
  final UniversityController ctrl;
  final String title;
  final Future<UniSession> Function() start;
  @override
  State<UniTestScreen> createState() => _UniTestScreenState();
}

class _UniTestScreenState extends State<UniTestScreen> {
  UniSession? _s;
  String? _error;
  UniAttemptResult? _result;
  final Map<String, int> _answers = {};
  int _i = 0, _left = 0;
  Timer? _timer;
  bool _submitting = false;

  @override
  void initState() { super.initState(); _begin(); }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _begin() async {
    try {
      final s = await widget.start();
      if (!mounted) return;
      setState(() { _s = s; _left = s.seconds; });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        if (_left <= 1) { t.cancel(); setState(() => _left = 0); _submit(); }
        else { setState(() => _left--); }
      });
    } on UniException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start. Check your connection and try again.');
    }
  }

  Future<void> _submit() async {
    if (_submitting || _result != null || _s == null) return;
    _submitting = true;
    _timer?.cancel();
    try {
      final r = await widget.ctrl.repo.submitSession(_s!.id, _answers);
      if (mounted) setState(() => _result = r);
    } on UniException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not submit. Check your connection.');
    } finally {
      _submitting = false;
    }
  }

  Future<void> _confirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit?'),
        content: Text('You answered ${_answers.length} of ${_s!.questions.length} questions.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (ok == true) _submit();
  }

  String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return Scaffold(appBar: AppBar(title: Text(widget.title)),
          body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center))));
    }
    if (_s == null) {
      return Scaffold(appBar: AppBar(title: Text(widget.title)), body: const Center(child: CircularProgressIndicator()));
    }
    if (_result != null) return _resultView(_result!);

    final q = _s!.questions[_i];
    final last = _i == _s!.questions.length - 1;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        Center(child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Text(_fmt(_left), style: TextStyle(fontWeight: FontWeight.bold, color: _left <= 60 ? scheme.error : null)),
        )),
      ]),
      body: Column(children: [
        LinearProgressIndicator(value: (_i + 1) / _s!.questions.length),
        Expanded(child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Question ${_i + 1} of ${_s!.questions.length}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(q.text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 16),
          for (var k = 0; k < q.options.length; k++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: _answers[q.id] == k ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _answers[q.id] = k),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      CircleAvatar(radius: 13, child: Text(String.fromCharCode(65 + k), style: const TextStyle(fontSize: 12))),
                      const SizedBox(width: 12),
                      Expanded(child: Text(q.options[k])),
                    ]),
                  ),
                ),
              ),
            ),
        ])),
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: _i > 0 ? () => setState(() => _i--) : null, child: const Text('Previous'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(
              onPressed: last ? _confirm : () => setState(() => _i++),
              child: Text(last ? 'Submit' : 'Next'),
            )),
          ]),
        )),
      ]),
    );
  }

  Widget _resultView(UniAttemptResult r) {
    final scheme = Theme.of(context).colorScheme;
    final pct = r.total == 0 ? 0 : (r.correct * 100 / r.total).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Results'), automaticallyImplyLeading: false),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: Text('$pct%', style: Theme.of(context).textTheme.displayMedium)),
        Center(child: Text('${r.correct} of ${r.total} correct • ${_fmt(r.seconds)} spent')),
        if (r.weakTopics.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Areas to improve', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [for (final t in r.weakTopics) Chip(label: Text(t))]),
        ],
        const SizedBox(height: 4),
        const Text('Practice result, not your official university grade.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 16),
        for (var n = 0; n < r.review.length; n++) _reviewCard(n, r.review[n], scheme),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ]),
    );
  }

  Widget _reviewCard(int n, UniReviewItem it, ColorScheme scheme) {
    final q = it.question;
    return Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Q${n + 1}. ${q.text}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (var k = 0; k < q.options.length; k++)
          Row(children: [
            Icon(k == it.correctIndex ? Icons.check_circle : (k == it.selected ? Icons.cancel : Icons.circle_outlined),
                size: 18, color: k == it.correctIndex ? Colors.green : (k == it.selected ? Colors.red : scheme.outline)),
            const SizedBox(width: 8),
            Expanded(child: Text(q.options[k])),
          ]),
        if (it.selected == null) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Not answered', style: TextStyle(color: Colors.orange))),
        if (it.explanation.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(it.explanation, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12.5))),
      ]),
    ));
  }
}
