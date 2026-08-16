// lib/career_features.dart
//
// AI Study Coach, JAMB Score Predictor, Career Mode, Hall of Fame, Live
// Quiz Battles, Mistakes Vault, Bookmarks, Report Card, Streak Saver
// banner, and the exam Pace Meter.
//
// LIVE QUIZ BATTLES (multiplayer + connecting overlay):
// - Battles now support 2–6 players (host picks max players).
// - Every participant has their own "ready" state (not just host/joiner).
// - Any non-host player can raise a 👏 Request Edit; host can then adjust
//   subjects, which resets everyone's ready state.
// - Host can either wait for auto-start (all joined + all ready +
//   scheduled time reached) or manually "Start Now" once >=2 are ready.
// - The moment a start is triggered (locally predicted or confirmed via
//   realtime), a full-screen "connecting" overlay appears with a spinner
//   and rotating status messages ("Creating battle server...", "Ensuring
//   service space...", etc.) for a minimum of ~2.2s so it never feels
//   like a dead tap — then both players drop into the battle together.
// - Randomized countdown timer per battle; no manual submit — the timer
//   auto-submits for everyone when it hits zero.
// - Results now show a full ranked leaderboard (not just 1v1), and the
//   last-5 match history strip (e.g. "LLLWWL") is tracked per user.
//
// SECURITY UPDATE: question bank + correct answers now live in Postgres
// (`questions` table), never in the client binary. BattlePlayScreen fetches
// questions via the get_battle_questions RPC (answer key withheld) and
// submits raw answer choices via submit_battle_answers, which recomputes
// the score server-side against the real answer key. battle_participants'
// score/finished columns can no longer be set directly by any client.
//
// SYNC FIX: battle progress and the countdown timer are now driven by the
// shared `started_at` timestamp on the battle row instead of each device's
// own local clock, and _goTo() now actually pushes progress to the server
// so opponents' progress bars move in real time.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show Question, QuestionRepository, SubjectInfo, kSubjects, ExamInstructionsScreen;
import 'app_enhancements.dart' show AppProvider, rankTitleForLevel, QuizScreen;

/// =========================================================================
/// SHARED HELPER — daily goal status text (fixes the "40 / 10" bug)
/// =========================================================================

String dailyGoalStatusText(AppProvider provider) {
  final done = provider.questionsToday;
  final goal = provider.dailyGoalQuestions;
  if (goal <= 0) return '$done questions today';
  if (done >= goal) {
    final extra = done - goal;
    return extra > 0 ? '$goal / $goal completed (+$extra extra)' : '$goal / $goal completed';
  }
  return '$done / $goal questions today';
}

/// =========================================================================
/// 1. AI STUDY COACH
/// =========================================================================

class StudyCoachScreen extends StatelessWidget {
  const StudyCoachScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final stats = provider.stats;
    final scheme = Theme.of(context).colorScheme;

    final subjectStats = <String, double>{};
    for (final subject in provider.getAvailableSubjects()) {
      final attempts = stats.subjectAttempts[subject] ?? 0;
      if (attempts >= 5) {
        subjectStats[subject] = provider.getSubjectScore(subject);
      }
    }

    final sorted = subjectStats.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final weakest = sorted.take(3).toList();
    final hasEnoughData = subjectStats.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('🧠 AI Study Coach')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [scheme.primary, scheme.primary.withOpacity(0.75)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              const Icon(Icons.psychology_alt_rounded, color: Colors.white, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  hasEnoughData
                      ? 'Hi ${provider.userName}, here\'s where to focus next.'
                      : 'Practice at least 5 questions in a few subjects and I\'ll build your plan.',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          if (hasEnoughData) ...[
            Text('Focus Subjects', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Based on subject-level accuracy — the question bank isn\'t tagged by topic, so this reflects whole subjects, not sub-topics.',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            ...weakest.map((e) {
              final gapToTarget = (75 - e.value).clamp(0, 100).toDouble();
              final predictedGain = (gapToTarget * 0.25).clamp(1, 20).round();
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      Text('${e.value.toStringAsFixed(0)}%',
                          style: TextStyle(fontWeight: FontWeight.bold, color: e.value < 50 ? Colors.red : Colors.orange)),
                    ]),
                    const SizedBox(height: 6),
                    Text('Estimated JAMB gain if you improve this: +$predictedGain marks',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Practice this subject'),
                        onPressed: () {
                          final subjectInfo = kSubjects.firstWhere((s) => s.name == e.key);
                          final set = QuestionRepository.getForSubject(e.key)..shuffle();
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ExamInstructionsScreen(subject: subjectInfo, questions: set.take(20).toList()),
                          ));
                        },
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),
            Text('Suggested Daily Plan', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: weakest.map((e) {
                  final perDay = (provider.dailyGoalQuestions / weakest.length).ceil().clamp(5, 30);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text('$perDay questions/day in ${e.key}'),
                    ]),
                  );
                }).toList(),
              ),
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
              child: const Text('Not enough practice data yet. Try a few subject practice sessions first, then come back here.'),
            ),
        ],
      ),
    );
  }
}

/// =========================================================================
/// 2. JAMB SCORE PREDICTOR
/// =========================================================================

class ScorePredictorScreen extends StatefulWidget {
  const ScorePredictorScreen({super.key});
  @override
  State<ScorePredictorScreen> createState() => _ScorePredictorScreenState();
}

class _ScorePredictorScreenState extends State<ScorePredictorScreen> {
  final List<String> _selected = ['English'];
  static const int maxSubjects = 4;

  void _toggle(String s) {
    setState(() {
      if (_selected.contains(s)) {
        if (s != 'English') _selected.remove(s);
      } else if (_selected.length < maxSubjects) {
        _selected.add(s);
      }
    });
  }

  double _predictedFor(AppProvider provider, String subject) {
    final accuracy = provider.getSubjectScore(subject);
    final predicted = 25 + (accuracy * 0.75);
    return predicted.clamp(0, 100);
  }

  double _confidenceFor(AppProvider provider, String subject) {
    final attempts = provider.stats.subjectAttempts[subject] ?? 0;
    return (attempts / 50 * 100).clamp(5, 95);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final scheme = Theme.of(context).colorScheme;
    final subjects = provider.getAvailableSubjects();

    final predictions = {for (final s in _selected) s: _predictedFor(provider, s)};
    final total = predictions.values.fold<double>(0, (a, b) => a + b);
    final avgConfidence = _selected.isEmpty
        ? 0.0
        : _selected.map((s) => _confidenceFor(provider, s)).reduce((a, b) => a + b) / _selected.length;
    final weakest = predictions.entries.isEmpty
        ? null
        : (predictions.entries.toList()..sort((a, b) => a.value.compareTo(b.value))).first;

    return Scaffold(
      appBar: AppBar(title: const Text('🔮 JAMB Score Predictor')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Pick your 4 UTME subjects (English is compulsory)', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: subjects.map((s) {
              final isSelected = _selected.contains(s);
              final locked = s == 'English';
              final disabled = !isSelected && _selected.length >= maxSubjects;
              return FilterChip(
                label: Text(locked ? '$s 🔒' : s),
                selected: isSelected,
                onSelected: disabled ? null : (_) => _toggle(s),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [scheme.primary, scheme.primary.withOpacity(0.75)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              const Text('Predicted UTME Total', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('${total.round()} / 400', style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Confidence: ${avgConfidence.round()}%', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 20),
          ...predictions.entries.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(e.value.round().toString(), style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary, fontSize: 16)),
                ]),
              )),
          if (weakest != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
              child: Text('To raise your total, focus on ${weakest.key} — it\'s currently your lowest predicted subject.',
                  style: const TextStyle(fontSize: 13)),
            ),
          ],
          const SizedBox(height: 16),
          Text('This is an estimate from your practice accuracy — not an official JAMB score.',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// =========================================================================
/// 3. CAREER MODE
/// =========================================================================

class CareerTier {
  final String title;
  final int minLevel;
  final Color color;
  final IconData icon;
  final List<String> avatars;
  const CareerTier(this.title, this.minLevel, this.color, this.icon, this.avatars);
}

const List<CareerTier> kCareerTiers = [
  CareerTier('Rookie', 1, Colors.grey, Icons.backpack_rounded, ['🙂', '📘']),
  CareerTier('Scholar', 5, Color(0xFF4CAF50), Icons.menu_book_rounded, ['🎓', '📗']),
  CareerTier('Ace', 10, Color(0xFF2196F3), Icons.bolt_rounded, ['⚡', '🎯']),
  CareerTier('Master', 15, Color(0xFFE91E63), Icons.workspace_premium_rounded, ['🥋', '🏅']),
  CareerTier('Grandmaster', 25, Color(0xFF9C27B0), Icons.military_tech_rounded, ['👑', '🔥']),
  CareerTier('Legend', 50, Color(0xFFFFD700), Icons.emoji_events_rounded, ['🏆', '🐐']),
];

class CareerModeScreen extends StatelessWidget {
  const CareerModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final level = provider.stats.level;
    final scheme = Theme.of(context).colorScheme;

    final currentTierIndex = kCareerTiers.lastIndexWhere((t) => level >= t.minLevel);
    final currentTier = kCareerTiers[currentTierIndex < 0 ? 0 : currentTierIndex];
    final nextTier = currentTierIndex + 1 < kCareerTiers.length ? kCareerTiers[currentTierIndex + 1] : null;
    final unlockedAvatars = kCareerTiers.take(currentTierIndex + 1).expand((t) => t.avatars).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('🎮 Career Mode')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: currentTier.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: currentTier.color, width: 1.4),
            ),
            child: Column(children: [
              Icon(currentTier.icon, color: currentTier.color, size: 40),
              const SizedBox(height: 8),
              Text(currentTier.title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: currentTier.color)),
              Text('Level $level', style: TextStyle(color: scheme.onSurfaceVariant)),
              if (nextTier != null) ...[
                const SizedBox(height: 10),
                Text('${nextTier.minLevel - level} levels to ${nextTier.title}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ]),
          ),
          const SizedBox(height: 24),
          Text('Career Ladder', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...kCareerTiers.map((t) {
            final reached = level >= t.minLevel;
            final isCurrent = t.title == currentTier.title;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isCurrent ? t.color.withOpacity(0.15) : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: isCurrent ? Border.all(color: t.color, width: 1.4) : null,
              ),
              child: Row(children: [
                Icon(t.icon, color: reached ? t.color : scheme.onSurfaceVariant.withOpacity(0.4)),
                const SizedBox(width: 12),
                Expanded(child: Text(t.title, style: TextStyle(fontWeight: FontWeight.w600, color: reached ? null : scheme.onSurfaceVariant.withOpacity(0.6)))),
                Text('Lv. ${t.minLevel}+', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 8),
                Icon(reached ? Icons.lock_open_rounded : Icons.lock_outline_rounded, size: 16, color: reached ? Colors.green : scheme.onSurfaceVariant),
              ]),
            );
          }),
          const SizedBox(height: 24),
          Text('Your Avatar', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Unlocked as you rank up', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: unlockedAvatars.map((emoji) {
              final isSelected = provider.avatarEmoji == emoji;
              return GestureDetector(
                onTap: () => provider.setAvatarEmoji(emoji),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: isSelected ? Border.all(color: scheme.primary, width: 2) : null,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 28)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// =========================================================================
/// 4. HALL OF FAME
/// =========================================================================

class HallOfFameScreen extends StatefulWidget {
  const HallOfFameScreen({super.key});
  @override
  State<HallOfFameScreen> createState() => _HallOfFameScreenState();
}

class _HallOfFameScreenState extends State<HallOfFameScreen> {
  String _subject = kSubjects.first.name;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('subject_leaderboard')
          .select()
          .eq('subject', _subject)
          .order('best_score', ascending: false)
          .limit(20);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('[HallOfFame] load failed: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('🎓 Hall of Fame')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _subject,
              items: kSubjects.map((s) => DropdownMenuItem(value: s.name, child: Text(s.name))).toList(),
              onChanged: (v) => setState(() {
                _subject = v!;
                _future = _load();
              }),
              decoration: const InputDecoration(labelText: 'Subject'),
            ),
            const SizedBox(height: 4),
            Text('All-time top students (min. 5 practice attempts)', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = snapshot.data ?? [];
                  if (rows.isEmpty) {
                    return Center(child: Text('No entries yet for $_subject.', style: TextStyle(color: scheme.onSurfaceVariant)));
                  }
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final isTop3 = i < 3;
                      final medalColors = [Colors.amber, Colors.grey, Colors.brown];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          border: isTop3 ? Border.all(color: medalColors[i], width: 1.6) : null,
                        ),
                        child: Row(children: [
                          CircleAvatar(
                            backgroundColor: isTop3 ? medalColors[i] : scheme.primaryContainer,
                            child: Text('${i + 1}', style: TextStyle(color: isTop3 ? Colors.white : scheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          Text((r['avatar_emoji'] as String?) ?? '🙂', style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(r['username'] as String? ?? 'Student', style: const TextStyle(fontWeight: FontWeight.w600))),
                          Text('${((r['best_score'] as num?) ?? 0).toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary)),
                        ]),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// 5. LIVE QUIZ BATTLES — multiplayer + connecting overlay
/// =========================================================================

class BattleInfo {
  final String id;
  final String code;
  final List<String> subjects;
  final int perSubjectCount;
  final String status;
  final List<String> questionIds;
  final int durationSeconds;
  final DateTime? scheduledAt;
  final int maxPlayers;
  final String? editRequestedBy;
  final String createdBy;
  final DateTime? startedAt;

  BattleInfo({
    required this.id,
    required this.code,
    required this.subjects,
    required this.perSubjectCount,
    required this.status,
    required this.questionIds,
    required this.durationSeconds,
    this.scheduledAt,
    required this.maxPlayers,
    this.editRequestedBy,
    required this.createdBy,
    this.startedAt,
  });

  factory BattleInfo.fromMap(Map<String, dynamic> m) => BattleInfo(
        id: m['id'] as String,
        code: m['code'] as String,
        subjects: List<String>.from((m['subjects'] as List<dynamic>?) ?? [m['subject']]),
        perSubjectCount: (m['per_subject_count'] as num?)?.toInt() ?? (m['question_count'] as num?)?.toInt() ?? 10,
        status: m['status'] as String,
        questionIds: List<String>.from((m['question_ids'] as List<dynamic>?) ?? []),
        durationSeconds: (m['duration_seconds'] as num?)?.toInt() ?? 240,
        scheduledAt: m['scheduled_at'] != null ? DateTime.tryParse(m['scheduled_at'] as String) : null,
        maxPlayers: (m['max_players'] as num?)?.toInt() ?? 2,
        editRequestedBy: m['edit_requested_by'] as String?,
        createdBy: m['created_by'] as String? ?? '',
        startedAt: m['started_at'] != null ? DateTime.tryParse(m['started_at'] as String) : null,
      );

  String get subjectsLabel => subjects.join(' + ');
}

class BattleParticipant {
  final String userId;
  final String username;
  final String? avatarEmoji;
  final int score;
  final int currentQuestion;
  final bool finished;
  final bool ready;

  BattleParticipant({
    required this.userId,
    required this.username,
    this.avatarEmoji,
    required this.score,
    required this.currentQuestion,
    required this.finished,
    required this.ready,
  });

  factory BattleParticipant.fromMap(Map<String, dynamic> m) => BattleParticipant(
        userId: m['user_id'] as String,
        username: m['username'] as String? ?? 'Player',
        avatarEmoji: m['avatar_emoji'] as String?,
        score: (m['score'] as num?)?.toInt() ?? 0,
        currentQuestion: (m['current_question'] as num?)?.toInt() ?? 0,
        finished: m['finished'] as bool? ?? false,
        ready: m['ready'] as bool? ?? false,
      );
}

class BattleService {
  BattleService._();
  static final BattleService instance = BattleService._();

  SupabaseClient get _client => Supabase.instance.client;
  final Random _rng = Random();

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  /// Randomized every battle — 3 to 8 minutes, 30-second increments — so
  /// the duration can never be memorized or gamed.
  int _randomDurationSeconds() {
    final options = [180, 210, 240, 270, 300, 330, 360, 390, 420, 450, 480];
    return options[_rng.nextInt(options.length)];
  }

  Future<String> _currentUsername(String userId) async {
    try {
      final row = await _client.from('profiles').select('username').eq('id', userId).maybeSingle();
      return row?['username'] as String? ?? 'Player';
    } catch (_) {
      return 'Player';
    }
  }

  List<String> _buildQuestionIds(List<String> subjects, int perSubjectCount) {
    final ids = <String>[];
    for (final subject in subjects) {
      final pool = List<Question>.from(QuestionRepository.getForSubject(subject))..shuffle();
      ids.addAll(pool.take(perSubjectCount).map((q) => q.id));
    }
    ids.shuffle();
    return ids;
  }

  Future<BattleInfo> createBattle({
    required List<String> subjects,
    required int perSubjectCount,
    required int maxPlayers,
    DateTime? scheduledAt,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    if (subjects.isEmpty) throw StateError('Pick at least one subject.');

    final ids = _buildQuestionIds(subjects, perSubjectCount);
    if (ids.isEmpty) throw StateError('Not enough questions available for that selection.');

    final code = _generateCode();

    final row = await _client.from('battles').insert({
      'code': code,
      'subjects': subjects,
      'per_subject_count': perSubjectCount,
      'status': 'waiting',
      'question_ids': ids,
      'duration_seconds': _randomDurationSeconds(),
      'scheduled_at': scheduledAt?.toIso8601String(),
      'max_players': maxPlayers,
      'created_by': user.id,
    }).select().single();

    final battle = BattleInfo.fromMap(row);
    final username = await _currentUsername(user.id);

    await _client.from('battle_participants').insert({
      'battle_id': battle.id,
      'user_id': user.id,
      'username': username,
      'ready': false,
    });

    return battle;
  }

  Future<BattleInfo> joinBattle(String code) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    final normalized = code.trim().toUpperCase();

    final row = await _client.from('battles').select().eq('code', normalized).eq('status', 'waiting').maybeSingle();
    if (row == null) throw StateError('No open battle found with that code.');
    final battle = BattleInfo.fromMap(row);

    final existing = await getParticipants(battle.id);
    final alreadyIn = existing.any((p) => p.userId == user.id);
    if (!alreadyIn && existing.length >= battle.maxPlayers) {
      throw StateError('This battle room is full (${battle.maxPlayers} players).');
    }

    final username = await _currentUsername(user.id);
    await _client.from('battle_participants').upsert({
      'battle_id': battle.id,
      'user_id': user.id,
      'username': username,
      'ready': false,
    }, onConflict: 'battle_id,user_id');

    return battle;
  }

  Future<void> setReady({required String battleId, required bool ready}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('battle_participants').update({'ready': ready}).eq('battle_id', battleId).eq('user_id', user.id);
  }

  Future<void> resetAllReady(String battleId) async {
    await _client.from('battle_participants').update({'ready': false}).eq('battle_id', battleId);
  }

  /// Any non-host player's 👏 — flags the host, and drops everyone's ready
  /// state so no one accidentally starts mid-negotiation.
  Future<void> requestEdit(String battleId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('battles').update({'edit_requested_by': user.id}).eq('id', battleId);
    await resetAllReady(battleId);
  }

  Future<void> updateSubjects({
    required String battleId,
    required List<String> subjects,
    required int perSubjectCount,
  }) async {
    final ids = _buildQuestionIds(subjects, perSubjectCount);
    await _client.from('battles').update({
      'subjects': subjects,
      'per_subject_count': perSubjectCount,
      'question_ids': ids,
      'edit_requested_by': null,
    }).eq('id', battleId);
    await resetAllReady(battleId);
  }

  Future<void> startBattle(String battleId) async {
    await _client.from('battles').update({
      'status': 'active',
      'started_at': DateTime.now().toIso8601String(),
    }).eq('id', battleId);
  }

  Future<List<BattleParticipant>> getParticipants(String battleId) async {
    final rows = await _client.from('battle_participants').select().eq('battle_id', battleId).order('joined_at');
    return (rows as List<dynamic>).map((r) => BattleParticipant.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<BattleInfo?> getBattle(String battleId) async {
    final row = await _client.from('battles').select().eq('id', battleId).maybeSingle();
    if (row == null) return null;
    return BattleInfo.fromMap(row);
  }

  /// Live progress ping (which question a player is currently on) —
  /// current_question is still directly client-writable. Score and
  /// "finished" are no longer settable this way; see submitAnswers below.
  Future<void> updateProgress({
    required String battleId,
    required int currentQuestion,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('battle_participants')
        .update({'current_question': currentQuestion})
        .eq('battle_id', battleId)
        .eq('user_id', user.id);
  }

  /// Fetches the real question bank from Postgres for this battle — the
  /// correct answer is deliberately never included in the response.
  Future<List<Question>> getBattleQuestions(List<String> questionIds) async {
  final rows = await _client.rpc('get_battle_questions', params: {
    'p_question_ids': questionIds,
  });
  return (rows as List).map((r) {
    final row = r as Map<String, dynamic>;
    return Question(
      id: row['id'] as String,
      subject: row['subject'] as String,
      // Battle questions don't carry a meaningful exam year — this field
      // isn't shown or used anywhere in the battle UI.
      year: 0,
      questionText: row['question_text'] as String,
      options: List<String>.from(row['options'] as List),
      correctIndex: -1,
    );
  }).toList();
}

  /// The ONLY way a battle result becomes final. Sends the player's raw
  /// answer choices; the server recomputes the score against the real
  /// answer key and writes score/finished itself. Returns the verified
  /// score and total question count.
  Future<Map<String, dynamic>> submitAnswers({
    required String battleId,
    required Map<String, int> answers,
  }) async {
    final result = await _client.rpc('submit_battle_answers', params: {
      'p_battle_id': battleId,
      'p_answers': answers,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> recordMatchResult(String result) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('battle_history').insert({
        'user_id': user.id,
        'result': result,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[BattleHistory] record failed: $e');
    }
  }

  Future<List<String>> getRecentResults({int limit = 5}) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    try {
      final rows = await _client
          .from('battle_history')
          .select('result')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List<dynamic>).map((r) => (r as Map<String, dynamic>)['result'] as String).toList();
    } catch (e) {
      debugPrint('[BattleHistory] load failed: $e');
      return [];
    }
  }

  RealtimeChannel subscribeToParticipants(String battleId, void Function() onChange) {
    final channel = _client.channel('battle_participants_$battleId').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'battle_participants',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'battle_id', value: battleId),
          callback: (payload) => onChange(),
        );
    channel.subscribe();
    return channel;
  }

  RealtimeChannel subscribeToBattle(String battleId, void Function() onChange) {
    final channel = _client.channel('battle_status_$battleId').onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'battles',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: battleId),
          callback: (payload) => onChange(),
        );
    channel.subscribe();
    return channel;
  }
}

/// Compact "LLLWWL"-style streak strip, reusable anywhere.
class MatchHistoryStrip extends StatelessWidget {
  final List<String> results;
  const MatchHistoryStrip({super.key, required this.results});

  Color _colorFor(String r) {
    switch (r) {
      case 'W':
        return Colors.green;
      case 'L':
        return Colors.red;
      default:
        return Colors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (results.isEmpty) {
      return Text('No battles played yet', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: results
          .map((r) => Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: _colorFor(r), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(r, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ))
          .toList(),
    );
  }
}

/// Full-screen "connecting" overlay with rotating status messages — shown
/// from the moment a start is predicted/confirmed until the player lands
/// inside the battle, so the transition never feels like a dead tap.
class _BattleConnectingOverlay extends StatefulWidget {
  const _BattleConnectingOverlay();
  @override
  State<_BattleConnectingOverlay> createState() => _BattleConnectingOverlayState();
}

class _BattleConnectingOverlayState extends State<_BattleConnectingOverlay> {
  static const List<String> _messages = [
    'Creating battle server...',
    'Ensuring service space...',
    'Syncing all players...',
    'Loading question bank...',
    'Shuffling questions fairly...',
    'Locking in the timer...',
    'Warming up the arena...',
    'Almost ready...',
  ];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.78),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(strokeWidth: 4, color: Colors.white),
            ),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _messages[_index],
                key: ValueKey(_index),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 10),
            Text('⚔️ Entering the battle arena', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class BattleLobbyScreen extends StatefulWidget {
  const BattleLobbyScreen({super.key});
  @override
  State<BattleLobbyScreen> createState() => _BattleLobbyScreenState();
}

class _BattleLobbyScreenState extends State<BattleLobbyScreen> {
  final List<String> _subjects = [kSubjects.first.name];
  int _perSubjectCount = 10;
  int _maxPlayers = 2;
  bool _playNow = true;
  DateTime? _scheduledAt;
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;
  late Future<List<String>> _historyFuture;

  static const int _maxSubjects = 4;

  @override
  void initState() {
    super.initState();
    _historyFuture = BattleService.instance.getRecentResults();
  }

  void _toggleSubject(String s) {
    setState(() {
      if (_subjects.contains(s)) {
        if (_subjects.length > 1) _subjects.remove(s);
      } else if (_subjects.length < _maxSubjects) {
        _subjects.add(s);
      }
    });
  }

  Future<void> _pickScheduleTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;
    setState(() {
      _scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _playNow = false;
    });
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final battle = await BattleService.instance.createBattle(
        subjects: _subjects,
        perSubjectCount: _perSubjectCount,
        maxPlayers: _maxPlayers,
        scheduledAt: _playNow ? null : _scheduledAt,
      );
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => BattleReadyScreen(battleId: battle.id, isHost: true)));
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
      final battle = await BattleService.instance.joinBattle(_codeController.text);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => BattleReadyScreen(battleId: battle.id, isHost: false)));
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
      appBar: AppBar(title: const Text('⚔️ Quiz Battle')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                const Icon(Icons.history_rounded),
                const SizedBox(width: 10),
                const Text('Last 5', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                FutureBuilder<List<String>>(
                  future: _historyFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    return MatchHistoryStrip(results: snapshot.data ?? []);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.primaryContainer.withOpacity(0.35), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Text('🤖', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('No one online?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('Battle a bot instead — same rules, instant start.', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BotBattleSetupScreen())),
                child: const Text('Practice'),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Text('Create a Battle', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Subjects (${_subjects.length}/$_maxSubjects) — pick one or more',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kSubjects.map((s) {
                    final isSelected = _subjects.contains(s.name);
                    final disabled = !isSelected && _subjects.length >= _maxSubjects;
                    return FilterChip(
                      label: Text(s.name),
                      selected: isSelected,
                      onSelected: disabled ? null : (_) => _toggleSubject(s.name),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: _perSubjectCount,
                  items: const [5, 10, 15, 20].map((c) => DropdownMenuItem(value: c, child: Text('$c questions per subject'))).toList(),
                  onChanged: (v) => setState(() => _perSubjectCount = v!),
                  decoration: const InputDecoration(labelText: 'Questions per subject'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: _maxPlayers,
                  items: const [2, 3, 4, 5, 6].map((c) => DropdownMenuItem(value: c, child: Text('$c players'))).toList(),
                  onChanged: (v) => setState(() => _maxPlayers = v!),
                  decoration: const InputDecoration(labelText: 'Number of players'),
                ),
                const SizedBox(height: 14),
                const Text('When do you want to compete?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Play Now'),
                        selected: _playNow,
                        onSelected: (_) => setState(() {
                          _playNow = true;
                          _scheduledAt = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ChoiceChip(
                        label: Text(_scheduledAt == null
                            ? 'Schedule…'
                            : '${_scheduledAt!.day}/${_scheduledAt!.month} ${_scheduledAt!.hour.toString().padLeft(2, '0')}:${_scheduledAt!.minute.toString().padLeft(2, '0')}'),
                        selected: !_playNow,
                        onSelected: (_) => _pickScheduleTime(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Create Battle'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Join a Battle', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
                    label: const Text('Join Battle'),
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

class BattleReadyScreen extends StatefulWidget {
  final String battleId;
  final bool isHost;
  const BattleReadyScreen({super.key, required this.battleId, required this.isHost});
  @override
  State<BattleReadyScreen> createState() => _BattleReadyScreenState();
}

class _BattleReadyScreenState extends State<BattleReadyScreen> {
  BattleInfo? _battle;
  List<BattleParticipant> _participants = [];
  RealtimeChannel? _participantsChannel;
  RealtimeChannel? _battleChannel;
  bool _navigated = false;
  Timer? _scheduleTicker;

  bool _connecting = false;
  DateTime? _connectingSince;

  @override
  void initState() {
    super.initState();
    _refreshBattle();
    _refreshParticipants();
    _participantsChannel = BattleService.instance.subscribeToParticipants(widget.battleId, _onParticipantsChanged);
    _battleChannel = BattleService.instance.subscribeToBattle(widget.battleId, _onBattleChanged);
    _scheduleTicker = Timer.periodic(const Duration(seconds: 5), (_) => _maybeAutoStart());
  }

  Future<void> _onParticipantsChanged() async {
    await _refreshParticipants();
    _syncConnectingState();
    _maybeAutoStart();
  }

  Future<void> _refreshParticipants() async {
    final participants = await BattleService.instance.getParticipants(widget.battleId);
    if (!mounted) return;
    setState(() => _participants = participants);
  }

  Future<void> _refreshBattle() async {
    final battle = await BattleService.instance.getBattle(widget.battleId);
    if (!mounted || battle == null) return;
    setState(() => _battle = battle);
  }

  Future<void> _onBattleChanged() async {
    await _refreshBattle();
    if (!mounted || _battle == null) return;
    _syncConnectingState();
    if (_battle!.status == 'active' && !_navigated) {
      _navigated = true;
      final since = _connectingSince ?? DateTime.now();
      final elapsed = DateTime.now().difference(since);
      const minDuration = Duration(milliseconds: 2200);
      final wait = elapsed >= minDuration ? Duration.zero : minDuration - elapsed;
      final battleSnapshot = _battle!;
      Timer(wait, () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => BattlePlayScreen(
            battleId: widget.battleId,
            questionIds: battleSnapshot.questionIds,
            subjectsLabel: battleSnapshot.subjectsLabel,
            durationSeconds: battleSnapshot.durationSeconds,
            startedAt: battleSnapshot.startedAt ?? DateTime.now(),
          ),
        ));
      });
      return;
    }
    _maybeAutoStart();
  }

  bool get _scheduleReached {
    final scheduled = _battle?.scheduledAt;
    if (scheduled == null) return true;
    return DateTime.now().isAfter(scheduled);
  }

  bool get _allReady => _participants.isNotEmpty && _participants.every((p) => p.ready);

  void _syncConnectingState() {
    final b = _battle;
    if (b == null) return;
    final aboutToStart = b.status == 'waiting' && _participants.length >= 2 && _allReady && _scheduleReached;
    final starting = b.status == 'active';
    final shouldShow = aboutToStart || starting;
    if (shouldShow && !_connecting) {
      setState(() {
        _connecting = true;
        _connectingSince = DateTime.now();
      });
    } else if (!shouldShow && _connecting && b.status != 'active') {
      setState(() => _connecting = false);
    }
  }

  Future<void> _maybeAutoStart() async {
    final b = _battle;
    if (b == null || !widget.isHost || _navigated) return;
    if (_participants.length == b.maxPlayers && _allReady && _scheduleReached) {
      await BattleService.instance.startBattle(widget.battleId);
    }
  }

  Future<void> _hostStartNow() async {
    setState(() {
      _connecting = true;
      _connectingSince = DateTime.now();
    });
    await BattleService.instance.startBattle(widget.battleId);
  }

  Future<void> _toggleReady() async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final myEntry = _participants.where((p) => p.userId == me).toList();
    final currentlyReady = myEntry.isNotEmpty && myEntry.first.ready;
    await BattleService.instance.setReady(battleId: widget.battleId, ready: !currentlyReady);
    await _refreshParticipants();
    _syncConnectingState();
    _maybeAutoStart();
  }

  Future<void> _requestEdit() async {
    await BattleService.instance.requestEdit(widget.battleId);
    if (!mounted) return;
    setState(() => _connecting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('👏 Edit request sent to the host')),
    );
  }

  Future<void> _editSubjects() async {
    final battle = _battle;
    if (battle == null) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SubjectEditSheet(initialSubjects: battle.subjects, initialCount: battle.perSubjectCount),
    );
    if (result == null) return;
    await BattleService.instance.updateSubjects(
      battleId: widget.battleId,
      subjects: List<String>.from(result['subjects'] as List),
      perSubjectCount: result['count'] as int,
    );
    _refreshBattle();
  }

  @override
  void dispose() {
    _participantsChannel?.unsubscribe();
    _battleChannel?.unsubscribe();
    _scheduleTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final battle = _battle;
    final me = Supabase.instance.client.auth.currentUser?.id;
    final myEntryList = _participants.where((p) => p.userId == me).toList();
    final myReady = myEntryList.isNotEmpty && myEntryList.first.ready;
    final editRequested = battle?.editRequestedBy != null && battle!.editRequestedBy != me;
    final notReadyNames = _participants.where((p) => !p.ready).map((p) => p.userId == me ? 'You' : p.username).toList();
    final canManualStart = battle != null &&
        widget.isHost &&
        _participants.length >= 2 &&
        _allReady &&
        _scheduleReached &&
        battle.status == 'waiting';

    return Scaffold(
      appBar: AppBar(title: const Text('Ready Check')),
      body: battle == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Padding(
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
                          Text(battle.code, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 6)),
                          const SizedBox(height: 4),
                          Text('Up to ${battle.maxPlayers} players', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        ]),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.menu_book_rounded, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(battle.subjectsLabel, style: const TextStyle(fontWeight: FontWeight.bold))),
                              Text('${battle.perSubjectCount}/subject', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                            ]),
                            if (battle.scheduledAt != null) ...[
                              const SizedBox(height: 8),
                              Row(children: [
                                const Icon(Icons.schedule_rounded, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  _scheduleReached
                                      ? 'Scheduled time reached'
                                      : 'Starts at ${battle.scheduledAt!.hour.toString().padLeft(2, '0')}:${battle.scheduledAt!.minute.toString().padLeft(2, '0')} on ${battle.scheduledAt!.day}/${battle.scheduledAt!.month}',
                                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                                ),
                              ]),
                            ],
                          ],
                        ),
                      ),
                      if (editRequested && widget.isHost) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                          child: Row(children: [
                            const Text('👏', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('A player asked to change the subjects.')),
                            TextButton(onPressed: _editSubjects, child: const Text('Edit')),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text('Players (${_participants.length}/${battle.maxPlayers})', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView(
                          children: _participants.map((p) {
                            final isMe = p.userId == me;
                            final isHostPlayer = p.userId == battle.createdBy;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                              child: Row(children: [
                                Text(p.avatarEmoji ?? '🙂', style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Row(children: [
                                    Flexible(child: Text(p.username, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                    if (isMe) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8)),
                                        child: const Text('You', style: TextStyle(fontSize: 10, color: Colors.white)),
                                      ),
                                    ],
                                    if (isHostPlayer) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(8)),
                                        child: const Text('Host', style: TextStyle(fontSize: 10, color: Colors.white)),
                                      ),
                                    ],
                                  ]),
                                ),
                                Icon(p.ready ? Icons.check_circle_rounded : Icons.hourglass_bottom_rounded,
                                    color: p.ready ? Colors.green : Colors.orange, size: 20),
                              ]),
                            );
                          }).toList(),
                        ),
                      ),
                      if (notReadyNames.isNotEmpty && _participants.length >= 2) ...[
                        Text('Waiting on: ${notReadyNames.join(', ')}',
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 8),
                      ],
                      if (!widget.isHost)
                        SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: myReady ? null : _requestEdit,
                            icon: const Text('👏'),
                            label: const Text('Request Subject Change'),
                          ),
                        ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: battle.status == 'waiting' ? _toggleReady : null,
                          icon: Icon(myReady ? Icons.close_rounded : Icons.check_circle_outline_rounded),
                          label: Text(myReady ? 'Not Ready' : 'I\'m Ready'),
                        ),
                      ),
                      if (canManualStart) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _hostStartNow,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text('Start Now (${_participants.length}/${battle.maxPlayers} joined)'),
                          ),
                        ),
                      ],
                      if (!_scheduleReached) ...[
                        const SizedBox(height: 8),
                        Text('Battle will auto-start once the scheduled time arrives.',
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
                      ],
                    ],
                  ),
                ),
                if (_connecting) const Positioned.fill(child: _BattleConnectingOverlay()),
              ],
            ),
    );
  }
}

class _SubjectEditSheet extends StatefulWidget {
  final List<String> initialSubjects;
  final int initialCount;
  const _SubjectEditSheet({required this.initialSubjects, required this.initialCount});

  @override
  State<_SubjectEditSheet> createState() => _SubjectEditSheetState();
}

class _SubjectEditSheetState extends State<_SubjectEditSheet> {
  late List<String> _subjects;
  late int _count;
  static const int _maxSubjects = 4;

  @override
  void initState() {
    super.initState();
    _subjects = List<String>.from(widget.initialSubjects);
    _count = widget.initialCount;
  }

  void _toggle(String s) {
    setState(() {
      if (_subjects.contains(s)) {
        if (_subjects.length > 1) _subjects.remove(s);
      } else if (_subjects.length < _maxSubjects) {
        _subjects.add(s);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit Subjects', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kSubjects.map((s) {
              final isSelected = _subjects.contains(s.name);
              final disabled = !isSelected && _subjects.length >= _maxSubjects;
              return FilterChip(
                label: Text(s.name),
                selected: isSelected,
                onSelected: disabled ? null : (_) => _toggle(s.name),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: _count,
            items: const [5, 10, 15, 20].map((c) => DropdownMenuItem(value: c, child: Text('$c questions per subject'))).toList(),
            onChanged: (v) => setState(() => _count = v!),
            decoration: const InputDecoration(labelText: 'Questions per subject'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, {'subjects': _subjects, 'count': _count}),
              child: const Text('Save Changes'),
            ),
          ),
        ],
      ),
    );
  }
}

class BattlePlayScreen extends StatefulWidget {
  final String battleId;
  final List<String> questionIds;
  final String subjectsLabel;
  final int durationSeconds;
  final DateTime startedAt;
  const BattlePlayScreen({
    super.key,
    required this.battleId,
    required this.questionIds,
    required this.subjectsLabel,
    required this.durationSeconds,
    required this.startedAt,
  });
  @override
  State<BattlePlayScreen> createState() => _BattlePlayScreenState();
}

class _BattlePlayScreenState extends State<BattlePlayScreen> {
  List<Question> _questions = [];
  List<int?> _selectedAnswers = [];
  int _index = 0;
  List<BattleParticipant> _participants = [];
  RealtimeChannel? _channel;
  Timer? _timer;
  late int _remainingSeconds;
  bool _submitting = false;
  bool _loadingQuestions = true;
  String? _loadError;
  bool _manuallySubmitted = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = _computeRemainingSeconds();
    _channel = BattleService.instance.subscribeToParticipants(widget.battleId, _refreshOpponents);
    _refreshOpponents();
    _loadQuestions();
  }

  /// Remaining time is always derived from the shared `started_at`
  /// timestamp (same value for every player), not a per-device
  /// countdown — this is what keeps everyone's timer in sync instead
  /// of each phone silently running its own independent clock.
  int _computeRemainingSeconds() {
    final elapsed = DateTime.now().difference(widget.startedAt).inSeconds;
    final remaining = widget.durationSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  /// Fetches the real question bank from Postgres (answer key withheld).
  /// The countdown timer only starts once questions have actually loaded,
  /// so a slow connection never eats into a player's answering time.
  Future<void> _loadQuestions() async {
    try {
      final questions = await BattleService.instance.getBattleQuestions(widget.questionIds);
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _selectedAnswers = List<int?>.filled(_questions.length, null);
        _loadingQuestions = false;
      });
      if (_questions.isNotEmpty) {
        BattleService.instance.updateProgress(battleId: widget.battleId, currentQuestion: 0);
        _startTimer();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loadingQuestions = false;
      });
    }
  }

  void _startTimer() {
    // If a slow connection meant this player's questions loaded after
    // the shared clock had already run out, submit right away instead
    // of showing a frozen/negative timer.
    if (_remainingSeconds <= 0) {
      _autoSubmit();
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = _computeRemainingSeconds();
      if (remaining <= 0) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
        _autoSubmit();
      } else {
        setState(() => _remainingSeconds = remaining);
      }
    });
  }

  Future<void> _refreshOpponents() async {
    final p = await BattleService.instance.getParticipants(widget.battleId);
    if (!mounted) return;
    setState(() => _participants = p);
  }

  void _selectOption(int i) => setState(() => _selectedAnswers[_index] = i);

  void _goTo(int index) {
    if (index < 0 || index >= _questions.length) return;
    setState(() => _index = index);
    // Push progress to the server so the opponent's progress bar
    // actually moves — previously this only updated local state.
    BattleService.instance.updateProgress(battleId: widget.battleId, currentQuestion: index);
  }

  /// Fires only when the shared countdown hits zero — no manual submit
  /// button exists, so both/all players lock in at the same instant.
  /// Sends raw answer choices to the server; the server recomputes the
  /// real score against the answer key. The client never claims a score.
  Future<void> _autoSubmit() async {
    if (_submitting) return;
    _submitting = true;

    final answersMap = <String, int>{
      for (var i = 0; i < _questions.length; i++)
        if (_selectedAnswers[i] != null) _questions[i].id: _selectedAnswers[i]!,
    };

    try {
      await BattleService.instance.submitAnswers(battleId: widget.battleId, answers: answersMap);
    } catch (e) {
      debugPrint('[Battle] submitAnswers failed: $e');
    }

    final provider = context.read<AppProvider>();
    await Future.delayed(const Duration(seconds: 2));
    final finalParticipants = await BattleService.instance.getParticipants(widget.battleId);
    final me = Supabase.instance.client.auth.currentUser?.id;

    final ranked = List<BattleParticipant>.from(finalParticipants)..sort((a, b) => b.score.compareTo(a.score));
    final topScore = ranked.isNotEmpty ? ranked.first.score : 0;
    final topScorers = ranked.where((p) => p.score == topScore).toList();
    final iAmTop = topScorers.any((p) => p.userId == me);
    final tied = iAmTop && topScorers.length > 1;
    final won = iAmTop && !tied;

    await provider.recordBattleResult(won: won);
    await provider.addXP(won ? 50 : (tied ? 25 : 10));
    await BattleService.instance.recordMatchResult(won ? 'W' : (tied ? 'T' : 'L'));

    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => BattleResultScreen(participants: finalParticipants, total: _questions.length),
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  String get _formattedTime {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loadingQuestions) {
      return Scaffold(
        appBar: AppBar(title: Text('⚔️ ${widget.subjectsLabel}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null || _questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Battle')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              _loadError != null ? 'Could not load battle questions: $_loadError' : 'Could not load battle questions.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final me = Supabase.instance.client.auth.currentUser?.id;
    final opponents = _participants.where((p) => p.userId != me).toList();
    final q = _questions[_index];
    final answeredCount = _selectedAnswers.where((a) => a != null).length;
    final isLowTime = _remainingSeconds <= 30;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('⚔️ ${widget.subjectsLabel}'),
          automaticallyImplyLeading: false,
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isLowTime ? scheme.errorContainer : scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Icon(Icons.timer_rounded, size: 18, color: isLowTime ? scheme.onErrorContainer : scheme.onPrimaryContainer),
                const SizedBox(width: 6),
                Text(_formattedTime,
                    style: TextStyle(fontWeight: FontWeight.bold, color: isLowTime ? scheme.onErrorContainer : scheme.onPrimaryContainer)),
              ]),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  Row(children: [
                    Expanded(child: Text('You: $answeredCount/${_questions.length} answered', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: answeredCount / _questions.length, minHeight: 6, backgroundColor: scheme.surfaceContainerHighest),
                  ),
                  if (opponents.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...opponents.map((o) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            SizedBox(width: 90, child: Text(o.username, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: o.currentQuestion / _questions.length,
                                  minHeight: 4,
                                  backgroundColor: scheme.surfaceContainerHighest,
                                  valueColor: AlwaysStoppedAnimation(scheme.secondary),
                                ),
                              ),
                            ),
                          ]),
                        )),
                  ],
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: const Text(
                'Answers lock in automatically when the timer hits 0 — no early submit.',
                style: TextStyle(fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey(_index),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                      child: Text('Q${_index + 1}. ${q.questionText}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 18),
                    ...List.generate(q.options.length, (i) {
                      final isSelected = _selectedAnswers[_index] == i;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: isSelected ? scheme.primaryContainer : scheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _selectOption(i),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: isSelected ? scheme.primary : scheme.outlineVariant, width: isSelected ? 2 : 1)),
                              child: Row(children: [
                                CircleAvatar(radius: 14, backgroundColor: isSelected ? scheme.primary : scheme.surfaceContainerHighest, child: Text(String.fromCharCode(65 + i))),
                                const SizedBox(width: 14),
                                Expanded(child: Text(q.options[i])),
                              ]),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  children: [
                    // Manual Submit Button
                    if (!_manuallySubmitted)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: FilledButton.icon(
                          onPressed: _submitting
                              ? null
                              : () {
                                  setState(() => _manuallySubmitted = true);
                                  _autoSubmit();
                                },
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('Submit Now'),
                        ),
                      ),
                    // Navigation buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                            icon: const Icon(Icons.chevron_left_rounded),
                            label: const Text('Previous'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _index < _questions.length - 1 ? () => _goTo(_index + 1) : null,
                            icon: const Icon(Icons.chevron_right_rounded),
                            label: const Text('Next'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BattleResultScreen extends StatelessWidget {
  final List<BattleParticipant> participants;
  final int total;
  const BattleResultScreen({super.key, required this.participants, required this.total});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = Supabase.instance.client.auth.currentUser?.id;
    final ranked = List<BattleParticipant>.from(participants)..sort((a, b) => b.score.compareTo(a.score));
    final topScore = ranked.isNotEmpty ? ranked.first.score : 0;
    final topScorers = ranked.where((p) => p.score == topScore).toList();
    final myEntry = ranked.where((p) => p.userId == me).toList();
    final iAmTop = myEntry.isNotEmpty && topScorers.any((p) => p.userId == me);
    final tied = iAmTop && topScorers.length > 1;
    final won = iAmTop && !tied;
    final color = tied ? Colors.amber : (won ? Colors.green : scheme.error);

    return Scaffold(
      appBar: AppBar(title: const Text('Battle Result'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(tied ? Icons.handshake_rounded : (won ? Icons.emoji_events_rounded : Icons.sentiment_dissatisfied_rounded), size: 64, color: color),
            const SizedBox(height: 12),
            Text(tied ? "It's a Tie!" : (won ? 'You Won! 🏆' : 'Battle Over'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: ranked.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final p = ranked[i];
                  final isMe = p.userId == me;
                  final isTop = p.score == topScore;
                  final medalColors = [Colors.amber, Colors.grey, Colors.brown];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isMe ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: isTop ? Border.all(color: Colors.amber, width: 1.6) : null,
                    ),
                    child: Row(children: [
                      CircleAvatar(
                        backgroundColor: i < 3 ? medalColors[i] : scheme.primaryContainer,
                        child: Text('${i + 1}', style: TextStyle(color: i < 3 ? Colors.white : scheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Text(p.avatarEmoji ?? '🙂', style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(children: [
                          Flexible(child: Text(p.username, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8)),
                              child: const Text('You', style: TextStyle(fontSize: 10, color: Colors.white)),
                            ),
                          ],
                        ]),
                      ),
                      Text('${p.score}/$total', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary)),
                    ]),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (won)
              const Text('+50 XP • Ranking increased', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
            else if (tied)
              const Text('+25 XP', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))
            else
              const Text('+10 XP for showing up', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            FutureBuilder<List<String>>(
              future: BattleService.instance.getRecentResults(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                return Column(children: [
                  Text('Your Last 5', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  MatchHistoryStrip(results: snapshot.data!),
                ]);
              },
            ),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 52, child: FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('Back to Home'))),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// 5b. PRACTICE VS BOT — solo battle simulation, no human opponent required.
/// Fully client-side: reuses the same local QuestionRepository already used
/// by AI Study Coach / exam practice, so no new Supabase tables, RLS, or
/// bot "user" accounts are needed. The bot's score is simulated locally
/// (accuracy roll per question, randomized pace by difficulty) and never
/// touches battle_participants/submit_battle_answers, so it can't be used
/// to spoof a real PvP result. XP is awarded but bot matches are kept out
/// of the real Battle Record (Last 5 / streak) shown elsewhere.
/// =========================================================================

enum BotDifficulty { rookie, scholar, ace, master }

class BotProfile {
  final String label;
  final double accuracy;
  final double minSecondsPerQuestion;
  final double maxSecondsPerQuestion;
  const BotProfile({
    required this.label,
    required this.accuracy,
    required this.minSecondsPerQuestion,
    required this.maxSecondsPerQuestion,
  });
}

const Map<BotDifficulty, BotProfile> kBotProfiles = {
  BotDifficulty.rookie: BotProfile(label: 'Rookie', accuracy: 0.40, minSecondsPerQuestion: 9, maxSecondsPerQuestion: 20),
  BotDifficulty.scholar: BotProfile(label: 'Scholar', accuracy: 0.60, minSecondsPerQuestion: 7, maxSecondsPerQuestion: 16),
  BotDifficulty.ace: BotProfile(label: 'Ace', accuracy: 0.78, minSecondsPerQuestion: 5, maxSecondsPerQuestion: 12),
  BotDifficulty.master: BotProfile(label: 'Master', accuracy: 0.92, minSecondsPerQuestion: 4, maxSecondsPerQuestion: 9),
};

const List<String> _kBotNames = ['Chidi Bot', 'Ngozi Bot', 'Tunde Bot', 'Amaka Bot', 'Kelechi Bot', 'Fatima Bot', 'Emeka Bot', 'Zainab Bot'];

class BotBattleSetupScreen extends StatefulWidget {
  const BotBattleSetupScreen({super.key});
  @override
  State<BotBattleSetupScreen> createState() => _BotBattleSetupScreenState();
}

class _BotBattleSetupScreenState extends State<BotBattleSetupScreen> {
  final List<String> _subjects = [kSubjects.first.name];
  int _perSubjectCount = 10;
  int _durationSeconds = 240;
  BotDifficulty _difficulty = BotDifficulty.scholar;
  static const int _maxSubjects = 4;
  static const List<int> _durationOptions = [120, 180, 240, 300, 360, 420, 480];

  void _toggleSubject(String s) {
    setState(() {
      if (_subjects.contains(s)) {
        if (_subjects.length > 1) _subjects.remove(s);
      } else if (_subjects.length < _maxSubjects) {
        _subjects.add(s);
      }
    });
  }

  void _start() {
    final questions = <Question>[];
    for (final subject in _subjects) {
      final pool = List<Question>.from(QuestionRepository.getForSubject(subject))..shuffle();
      questions.addAll(pool.take(_perSubjectCount));
    }
    questions.shuffle();
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough questions available for that selection.')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BotBattlePlayScreen(
        questions: questions,
        subjectsLabel: _subjects.join(' + '),
        durationSeconds: _durationSeconds,
        difficulty: _difficulty,
      ),
    ));
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '$m min' : '$m:${s.toString().padLeft(2, '0')} min';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('🤖 Practice vs Bot')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Text('🤖', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No one to battle right now? Practice against a bot — same timer, same pressure, instant match.',
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text('Subjects (${_subjects.length}/$_maxSubjects)', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kSubjects.map((s) {
              final isSelected = _subjects.contains(s.name);
              final disabled = !isSelected && _subjects.length >= _maxSubjects;
              return FilterChip(
                label: Text(s.name),
                selected: isSelected,
                onSelected: disabled ? null : (_) => _toggleSubject(s.name),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<int>(
            initialValue: _perSubjectCount,
            items: const [5, 10, 15, 20].map((c) => DropdownMenuItem(value: c, child: Text('$c questions per subject'))).toList(),
            onChanged: (v) => setState(() => _perSubjectCount = v!),
            decoration: const InputDecoration(labelText: 'Questions per subject'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: _durationSeconds,
            items: _durationOptions.map((c) => DropdownMenuItem(value: c, child: Text(_formatDuration(c)))).toList(),
            onChanged: (v) => setState(() => _durationSeconds = v!),
            decoration: const InputDecoration(labelText: 'Battle duration'),
          ),
          const SizedBox(height: 20),
          Text('Bot Difficulty', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: BotDifficulty.values.map((d) {
              final profile = kBotProfiles[d]!;
              final isSelected = _difficulty == d;
              return ChoiceChip(
                label: Text('${profile.label} (~${(profile.accuracy * 100).round()}%)'),
                selected: isSelected,
                onSelected: (_) => setState(() => _difficulty = d),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.smart_toy_rounded),
              label: const Text('Start Bot Battle'),
            ),
          ),
        ],
      ),
    );
  }
}

class BotBattlePlayScreen extends StatefulWidget {
  final List<Question> questions;
  final String subjectsLabel;
  final int durationSeconds;
  final BotDifficulty difficulty;
  const BotBattlePlayScreen({
    super.key,
    required this.questions,
    required this.subjectsLabel,
    required this.durationSeconds,
    required this.difficulty,
  });
  @override
  State<BotBattlePlayScreen> createState() => _BotBattlePlayScreenState();
}

class _BotBattlePlayScreenState extends State<BotBattlePlayScreen> {
  late List<int?> _selectedAnswers;
  int _index = 0;
  Timer? _countdownTimer;
  Timer? _botTimer;
  late int _remainingSeconds;
  bool _submitting = false;
  late final Random _rng;
  late final String _botName;

  int _botCurrentQuestion = 0;
  int _botScore = 0;
  bool _botFinished = false;

  BotProfile get _profile => kBotProfiles[widget.difficulty]!;
  int get _total => widget.questions.length;

  @override
  void initState() {
    super.initState();
    _rng = Random();
    _botName = _kBotNames[_rng.nextInt(_kBotNames.length)];
    _selectedAnswers = List<int?>.filled(_total, null);
    _remainingSeconds = widget.durationSeconds;
    _startCountdown();
    _scheduleNextBotAnswer();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
        _finishBattle();
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  /// Bot "answers" one question at a randomized interval derived from its
  /// difficulty profile, rolling its configured accuracy each time — this
  /// keeps the bot's progress bar and final score feeling organic instead
  /// of a flat, predictable ramp. Stops scheduling once it has gone
  /// through every question, same as a human finishing early.
  void _scheduleNextBotAnswer() {
    if (_botCurrentQuestion >= _total) {
      _botFinished = true;
      return;
    }
    final delaySeconds = _profile.minSecondsPerQuestion +
        _rng.nextDouble() * (_profile.maxSecondsPerQuestion - _profile.minSecondsPerQuestion);
    _botTimer = Timer(Duration(milliseconds: (delaySeconds * 1000).round()), () {
      if (!mounted || _submitting) return;
      final gotItRight = _rng.nextDouble() < _profile.accuracy;
      setState(() {
        _botCurrentQuestion++;
        if (gotItRight) _botScore++;
      });
      _scheduleNextBotAnswer();
    });
  }

  void _selectOption(int i) => setState(() => _selectedAnswers[_index] = i);

  void _goTo(int index) {
    if (index < 0 || index >= _total) return;
    setState(() => _index = index);
  }

  int get _humanScore {
    var score = 0;
    for (var i = 0; i < _total; i++) {
      if (_selectedAnswers[i] != null && _selectedAnswers[i] == widget.questions[i].correctIndex) {
        score++;
      }
    }
    return score;
  }

  /// Fires when the timer hits zero — mirrors the human-vs-human battle's
  /// no-manual-submit rule. The bot's final score is whatever it had
  /// racked up by this point (or its full simulated score if it already
  /// finished all questions before time ran out).
  Future<void> _finishBattle() async {
    if (_submitting) return;
    _submitting = true;
    _botTimer?.cancel();

    final provider = context.read<AppProvider>();
    final humanScore = _humanScore;
    final won = humanScore > _botScore;
    final tied = humanScore == _botScore;

    await provider.addXP(won ? 30 : (tied ? 15 : 5));

    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => BotBattleResultScreen(
        humanScore: humanScore,
        botScore: _botScore,
        total: _total,
        botName: _botName,
        difficultyLabel: _profile.label,
      ),
    ));
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _botTimer?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = widget.questions[_index];
    final answeredCount = _selectedAnswers.where((a) => a != null).length;
    final isLowTime = _remainingSeconds <= 30;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('🤖 ${widget.subjectsLabel}'),
          automaticallyImplyLeading: false,
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isLowTime ? scheme.errorContainer : scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Icon(Icons.timer_rounded, size: 18, color: isLowTime ? scheme.onErrorContainer : scheme.onPrimaryContainer),
                const SizedBox(width: 6),
                Text(_formattedTime,
                    style: TextStyle(fontWeight: FontWeight.bold, color: isLowTime ? scheme.onErrorContainer : scheme.onPrimaryContainer)),
              ]),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  Row(children: [
                    Expanded(child: Text('You: $answeredCount/$_total answered', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: answeredCount / _total, minHeight: 6, backgroundColor: scheme.surfaceContainerHighest),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    SizedBox(width: 90, child: Text(_botName, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _botCurrentQuestion / _total,
                          minHeight: 4,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(scheme.secondary),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: const Text(
                'Answers lock in automatically when the timer hits 0 — no early submit.',
                style: TextStyle(fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey(_index),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                      child: Text('Q${_index + 1}. ${q.questionText}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 18),
                    ...List.generate(q.options.length, (i) {
                      final isSelected = _selectedAnswers[_index] == i;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: isSelected ? scheme.primaryContainer : scheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _selectOption(i),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: isSelected ? scheme.primary : scheme.outlineVariant, width: isSelected ? 2 : 1)),
                              child: Row(children: [
                                CircleAvatar(radius: 14, backgroundColor: isSelected ? scheme.primary : scheme.surfaceContainerHighest, child: Text(String.fromCharCode(65 + i))),
                                const SizedBox(width: 14),
                                Expanded(child: Text(q.options[i])),
                              ]),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('Previous'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _index < _total - 1 ? () => _goTo(_index + 1) : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                        label: const Text('Next'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BotBattleResultScreen extends StatelessWidget {
  final int humanScore;
  final int botScore;
  final int total;
  final String botName;
  final String difficultyLabel;
  const BotBattleResultScreen({
    super.key,
    required this.humanScore,
    required this.botScore,
    required this.total,
    required this.botName,
    required this.difficultyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final won = humanScore > botScore;
    final tied = humanScore == botScore;
    final color = tied ? Colors.amber : (won ? Colors.green : scheme.error);

    return Scaffold(
      appBar: AppBar(title: const Text('Bot Battle Result'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(tied ? Icons.handshake_rounded : (won ? Icons.emoji_events_rounded : Icons.smart_toy_rounded), size: 64, color: color),
            const SizedBox(height: 12),
            Text(tied ? "It's a Tie!" : (won ? 'You Won! 🏆' : 'Bot Wins This One'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 6),
            Text('vs $botName ($difficultyLabel)', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    const CircleAvatar(child: Icon(Icons.person_rounded)),
                    const SizedBox(width: 10),
                    const Text('You', style: TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  Text('$humanScore/$total', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary, fontSize: 16)),
                ]),
                const Divider(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    const CircleAvatar(child: Text('🤖')),
                    const SizedBox(width: 10),
                    Text(botName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  Text('$botScore/$total', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary, fontSize: 16)),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            if (won)
              const Text('+30 XP', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
            else if (tied)
              const Text('+15 XP', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))
            else
              const Text('+5 XP for the practice', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Practice battles don\'t count toward your Live Battle record.',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
            const Spacer(),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Rematch'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Back to Home'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// 6. MISTAKES VAULT
/// =========================================================================

class MistakeVaultService {
  MistakeVaultService._();
  static final MistakeVaultService instance = MistakeVaultService._();
  SupabaseClient get _client => Supabase.instance.client;

  Future<void> recordWrongAnswers({required String subject, required List<String> questionIds}) async {
    final user = _client.auth.currentUser;
    if (user == null || questionIds.isEmpty) return;
    for (final qid in questionIds) {
      try {
        final existing = await _client.from('mistake_bank').select().eq('user_id', user.id).eq('question_id', qid).maybeSingle();
        if (existing == null) {
          await _client.from('mistake_bank').insert({
            'user_id': user.id,
            'question_id': qid,
            'subject': subject,
            'times_wrong': 1,
            'last_wrong_at': DateTime.now().toIso8601String(),
          });
        } else {
          await _client.from('mistake_bank').update({
            'times_wrong': ((existing['times_wrong'] as num?)?.toInt() ?? 0) + 1,
            'last_wrong_at': DateTime.now().toIso8601String(),
          }).eq('user_id', user.id).eq('question_id', qid);
        }
      } catch (e) {
        debugPrint('[MistakeVault] record failed for $qid: $e');
      }
    }
  }

  Future<void> clearMistake(String questionId) async {
    final user = _client.auth.currentUser;
    if (user == null || questionId.isEmpty) return;
    try {
      await _client.from('mistake_bank').delete().eq('user_id', user.id).eq('question_id', questionId);
    } catch (e) {
      debugPrint('[MistakeVault] clear failed: $e');
    }
  }

  Future<List<Map<String, dynamic>>> loadAll() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    try {
      final rows = await _client.from('mistake_bank').select().eq('user_id', user.id).order('times_wrong', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('[MistakeVault] load failed: $e');
      return [];
    }
  }
}

class MistakesVaultScreen extends StatefulWidget {
  const MistakesVaultScreen({super.key});
  @override
  State<MistakesVaultScreen> createState() => _MistakesVaultScreenState();
}

class _MistakesVaultScreenState extends State<MistakesVaultScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = MistakeVaultService.instance.loadAll();
  }

  void _refresh() => setState(() => _future = MistakeVaultService.instance.loadAll());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('🗂️ Mistakes Vault')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No mistakes tracked yet — nice! Wrong answers from your practice sessions will show up here for targeted review.',
                    textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            );
          }

          final bySubject = <String, List<Map<String, dynamic>>>{};
          for (final r in rows) {
            final subject = r['subject'] as String? ?? 'Unknown';
            bySubject.putIfAbsent(subject, () => []).add(r);
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: bySubject.entries.map((entry) {
              final subject = entry.key;
              final items = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(subject, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      Text('${items.length} question${items.length == 1 ? '' : 's'}', style: TextStyle(color: scheme.onSurfaceVariant)),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry These'),
                        onPressed: () async {
                          final ids = items.map((r) => r['question_id'] as String).toSet();
                          final all = {for (final q in QuestionRepository.getAll()) q.id: q};
                          final questions = ids.map((id) => all[id]).whereType<Question>().map((q) => q.toJson()).toList();
                          if (questions.isEmpty || !context.mounted) return;
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => QuizScreen(
                              questions: questions,
                              title: '$subject — Mistakes Review',
                              onComplete: (_) => Navigator.pop(context),
                              onCompleteDetailed: (graded) async {
                                for (final g in graded) {
                                  if (g['__correct'] == true) {
                                    await MistakeVaultService.instance.clearMistake(g['id'] as String? ?? '');
                                  }
                                }
                                if (context.mounted) Navigator.pop(context);
                              },
                            ),
                          ));
                          _refresh();
                        },
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

/// =========================================================================
/// 7. BOOKMARKS
/// =========================================================================

class BookmarkService {
  BookmarkService._();
  static final BookmarkService instance = BookmarkService._();
  SupabaseClient get _client => Supabase.instance.client;

  Future<void> toggleBookmark({required String questionId, required String subject}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      final existing = await _client.from('bookmarked_questions').select().eq('user_id', user.id).eq('question_id', questionId).maybeSingle();
      if (existing == null) {
        await _client.from('bookmarked_questions').insert({'user_id': user.id, 'question_id': questionId, 'subject': subject});
      } else {
        await _client.from('bookmarked_questions').delete().eq('user_id', user.id).eq('question_id', questionId);
      }
    } catch (e) {
      debugPrint('[Bookmark] toggle failed: $e');
    }
  }

  Future<List<Map<String, dynamic>>> loadAll() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    try {
      final rows = await _client.from('bookmarked_questions').select().eq('user_id', user.id).order('bookmarked_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('[Bookmark] load failed: $e');
      return [];
    }
  }
}

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});
  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = BookmarkService.instance.loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('⭐ Bookmarks')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No bookmarks yet. Star any question in the Review screen to save it here.',
                    textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            );
          }
          final ids = rows.map((r) => r['question_id'] as String).toSet();
          final all = {for (final q in QuestionRepository.getAll()) q.id: q};
          final questions = ids.map((id) => all[id]).whereType<Question>().toList();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text('Practice All ${questions.length} Bookmarked'),
                  onPressed: questions.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => QuizScreen(
                              questions: questions.map((q) => q.toJson()).toList(),
                              title: 'Bookmarked Questions',
                              onComplete: (_) => Navigator.pop(context),
                            ),
                          ));
                        },
                ),
              ),
              const SizedBox(height: 16),
              ...questions.map((q) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      Expanded(child: Text(q.questionText, maxLines: 2, overflow: TextOverflow.ellipsis)),
                      IconButton(
                        icon: const Icon(Icons.star_rounded, color: Colors.amber),
                        onPressed: () async {
                          await BookmarkService.instance.toggleBookmark(questionId: q.id, subject: q.subject);
                          setState(() => _future = BookmarkService.instance.loadAll());
                        },
                      ),
                    ]),
                  )),
            ],
          );
        },
      ),
    );
  }
}

/// =========================================================================
/// 8. SHAREABLE REPORT CARD
/// =========================================================================

class ReportCardScreen extends StatefulWidget {
  const ReportCardScreen({super.key});
  @override
  State<ReportCardScreen> createState() => _ReportCardScreenState();
}

class _ReportCardScreenState extends State<ReportCardScreen> {
  late Future<List<String>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = BattleService.instance.getRecentResults();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final stats = provider.stats;
    final scheme = Theme.of(context).colorScheme;

    String? bestSubject;
    double bestScore = -1;
    for (final s in provider.getAvailableSubjects()) {
      final attempts = stats.subjectAttempts[s] ?? 0;
      if (attempts < 5) continue;
      final score = provider.getSubjectScore(s);
      if (score > bestScore) {
        bestScore = score;
        bestSubject = s;
      }
    }

    final text = '''
📊 NaijaLearn Report Card — ${provider.userName}
Rank: ${rankTitleForLevel(stats.level)} (Lv. ${stats.level})
XP: ${stats.xp}
Streak: ${stats.streak} days
This week: ${provider.weeklyXpTotal} XP
Best subject: ${bestSubject != null ? '$bestSubject (${bestScore.toStringAsFixed(0)}%)' : 'Not enough data yet'}
Quizzes completed: ${stats.quizzesCompleted}
Badges earned: ${stats.badges.length}

Practice. Prepare. Pass. — NaijaLearn
''';

    return Scaffold(
      appBar: AppBar(title: const Text('📋 Report Card')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                      child: Text(text, style: const TextStyle(height: 1.6, fontSize: 14)),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('⚔️ Battle Record (Last 5)', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          FutureBuilder<List<String>>(
                            future: _historyFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const SizedBox(height: 26, child: CircularProgressIndicator(strokeWidth: 2));
                              }
                              return MatchHistoryStrip(results: snapshot.data ?? []);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy to Clipboard'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report card copied!')));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// 9. STREAK SAVER BANNER
/// =========================================================================

class StreakSaverBanner extends StatelessWidget {
  const StreakSaverBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final stats = provider.stats;
    final atRisk = stats.streak > 0 && provider.questionsToday == 0;
    if (!atRisk) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.local_fire_department_rounded, color: Colors.red),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Your ${stats.streak}-day streak is at risk! Answer a few questions today to keep it alive.',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

/// =========================================================================
/// 10. LIVE PACE METER
/// =========================================================================

class PaceMeter extends StatelessWidget {
  final int answeredCount;
  final int totalQuestions;
  final int remainingSeconds;
  final int totalSeconds;
  const PaceMeter({
    super.key,
    required this.answeredCount,
    required this.totalQuestions,
    required this.remainingSeconds,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    if (totalQuestions == 0 || totalSeconds == 0) return const SizedBox.shrink();
    final timeUsedFraction = 1 - (remainingSeconds / totalSeconds);
    final answeredFraction = answeredCount / totalQuestions;
    final diff = answeredFraction - timeUsedFraction;
    final isAhead = diff >= -0.05;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: (isAhead ? Colors.green : Colors.orange).withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(
        isAhead ? '⏱️ On pace' : '⏱️ Behind pace — pick it up',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isAhead ? Colors.green : Colors.orange),
      ),
    );
  }
}
