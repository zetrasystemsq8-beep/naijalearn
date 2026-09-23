// lib/classroom_ask.dart
//
// "Ask the Classroom" — unlike chat, questions persist and stay
// searchable/browsable. A tutor (or Zetra AI, if enabled) pins the
// correct answer so future students hit the answer instead of
// re-asking the same question.
//
// AI-authored answers have responder_id = null and is_ai_response =
// true (see patch 10) — they're written directly by the classroom-ai
// Edge Function using the service role key, not through this screen.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'classroom_shared.dart' show loadUsernames;

class ClassroomAskWidget extends StatefulWidget {
  final int classroomId;
  final bool isTutor;
  const ClassroomAskWidget({super.key, required this.classroomId, required this.isTutor});

  @override
  State<ClassroomAskWidget> createState() => _ClassroomAskWidgetState();
}

class _ClassroomAskWidgetState extends State<ClassroomAskWidget> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _questions = [];
  Map<String, String> _usernames = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _client
          .from('classroom_questions')
          .select()
          .eq('classroom_id', widget.classroomId)
          .order('created_at', ascending: false);
      final questions = List<Map<String, dynamic>>.from(rows);
      final usernames = await loadUsernames(questions.map((q) => q['student_id'] as String).toList());
      setState(() {
        _questions = questions;
        _usernames = usernames;
      });
    } catch (_) {
      // Non-fatal.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _askQuestion() async {
    final controller = TextEditingController();
    final question = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ask the Classroom'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'What are you stuck on?', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Ask')),
        ],
      ),
    );
    if (question == null || question.isEmpty) return;

    try {
      await _client.from('classroom_questions').insert({
        'classroom_id': widget.classroomId,
        'student_id': _client.auth.currentUser!.id,
        'question': question,
      });
      _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post your question.')));
    }
  }

  void _openThread(Map<String, dynamic> question) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _QuestionThreadScreen(
          question: question,
          askerName: _usernames[question['student_id']] ?? 'Student',
          isTutor: widget.isTutor,
          onChanged: _load,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _askQuestion, icon: const Icon(Icons.add), label: const Text('Ask')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum_outlined, size: 40, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        const Text('No questions yet', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text('Questions asked here stay answered for everyone later — unlike chat.', textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: _questions.length,
                    itemBuilder: (context, index) {
                      final q = _questions[index];
                      final asker = _usernames[q['student_id']] ?? 'Student';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(q['question'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text('Asked by $asker · ${DateFormat('MMM d').format(DateTime.parse(q['created_at']))}'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _openThread(q),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _QuestionThreadScreen extends StatefulWidget {
  final Map<String, dynamic> question;
  final String askerName;
  final bool isTutor;
  final VoidCallback onChanged;

  const _QuestionThreadScreen({
    required this.question,
    required this.askerName,
    required this.isTutor,
    required this.onChanged,
  });

  @override
  State<_QuestionThreadScreen> createState() => _QuestionThreadScreenState();
}

class _QuestionThreadScreenState extends State<_QuestionThreadScreen> {
  final _client = Supabase.instance.client;
  final _answerController = TextEditingController();
  List<Map<String, dynamic>> _answers = [];
  Map<String, String> _usernames = {};
  bool _loading = true;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _client
          .from('classroom_question_answers')
          .select()
          .eq('question_id', widget.question['id'])
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: true);
      final answers = List<Map<String, dynamic>>.from(rows);
      // AI answers have responder_id = null — only look up real users.
      final humanResponderIds = answers.where((a) => a['is_ai_response'] != true).map((a) => a['responder_id'] as String).toList();
      final usernames = await loadUsernames(humanResponderIds);
      setState(() {
        _answers = answers;
        _usernames = usernames;
      });
    } catch (_) {
      // Non-fatal.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _postAnswer() async {
    final text = _answerController.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    try {
      await _client.from('classroom_question_answers').insert({
        'question_id': widget.question['id'],
        'responder_id': _client.auth.currentUser!.id,
        'answer': text,
      });
      _answerController.clear();
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post your answer.')));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _togglePin(int answerId, bool currentlyPinned) async {
    try {
      // Unpin any other pinned answer first — only one pinned answer at a time.
      if (!currentlyPinned) {
        await _client.from('classroom_question_answers').update({'is_pinned': false}).eq('question_id', widget.question['id']);
      }
      await _client.from('classroom_question_answers').update({'is_pinned': !currentlyPinned}).eq('id', answerId);
      await _load();
      widget.onChanged();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update pin.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Question')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.question['question'] as String, style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('Asked by ${widget.askerName}', style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12)),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _answers.isEmpty
                    ? const Center(child: Text('No answers yet — be the first.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _answers.length,
                        itemBuilder: (context, index) {
                          final a = _answers[index];
                          final isPinned = a['is_pinned'] as bool;
                          final isAi = a['is_ai_response'] == true;
                          final name = isAi ? 'Zetra AI' : (_usernames[a['responder_id']] ?? 'Student');
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isPinned ? Colors.green.withOpacity(0.08) : (isAi ? scheme.primaryContainer.withOpacity(0.3) : scheme.surfaceContainerLowest),
                              borderRadius: BorderRadius.circular(12),
                              border: isPinned ? Border.all(color: Colors.green.withOpacity(0.4)) : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (isAi) ...[
                                      Icon(Icons.auto_awesome_rounded, size: 14, color: scheme.primary),
                                      const SizedBox(width: 4),
                                    ],
                                    if (isPinned) ...[
                                      const Icon(Icons.push_pin_rounded, size: 14, color: Colors.green),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: isAi ? scheme.primary : null)),
                                    if (isPinned) ...[
                                      const SizedBox(width: 6),
                                      const Text('Best answer', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                    const Spacer(),
                                    if (widget.isTutor)
                                      GestureDetector(
                                        onTap: () => _togglePin(a['id'] as int, isPinned),
                                        child: Icon(isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, size: 16, color: scheme.onSurfaceVariant),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(a['answer'] as String),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _answerController,
                      decoration: InputDecoration(hintText: 'Write an answer...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _posting ? null : _postAnswer,
                    icon: _posting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
