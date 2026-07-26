// lib/career_features.dart
//
// AI Study Coach, JAMB Score Predictor, Career Mode, Hall of Fame, Live
// Quiz Battles, Mistakes Vault, Bookmarks, Report Card, Streak Saver
// banner, and the exam Pace Meter.
//
// Weak-topic detection is SUBJECT-level, not sub-topic-level — the
// question data has no topic tags (see certification.dart's own comment
// on this), so "focus on Quadratic Equations" style output would be
// fabricated. This coach instead says "focus on Mathematics" honestly,
// based on real accuracy numbers.
//
// Score Predictor's "predicted marks" figures are explicitly heuristic
// estimates from practice accuracy — not official JAMB scoring — and are
// labelled as such in the UI.

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
        if (s != 'English') _selected.remove(s); // English is compulsory in real UTME
      } else if (_selected.length < maxSubjects) {
        _selected.add(s);
      }
    });
  }

  double _predictedFor(AppProvider provider, String subject) {
    final accuracy = provider.getSubjectScore(subject); // 0-100
    // Heuristic: guessing on 4-option MCQs nets ~25% by chance, so floor
    // there; scale remaining accuracy up toward 100. ESTIMATE ONLY.
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

// Thresholds intentionally match rankTitleForLevel/rankColor in
// app_enhancements.dart so "Rank" on Home/Profile and "Career Mode" never
// disagree with each other.
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
/// 5. LIVE QUIZ BATTLES (real-time, via Supabase)
/// =========================================================================

class BattleInfo {
  final String id;
  final String code;
  final String subject;
  final int questionCount;
  final String status;
  final List<String> questionIds;

  BattleInfo({
    required this.id,
    required this.code,
    required this.subject,
    required this.questionCount,
    required this.status,
    required this.questionIds,
  });

  factory BattleInfo.fromMap(Map<String, dynamic> m) => BattleInfo(
        id: m['id'] as String,
        code: m['code'] as String,
        subject: m['subject'] as String,
        questionCount: (m['question_count'] as num).toInt(),
        status: m['status'] as String,
        questionIds: List<String>.from((m['question_ids'] as List<dynamic>?) ?? []),
      );
}

class BattleParticipant {
  final String userId;
  final String username;
  final String? avatarEmoji;
  final int score;
  final int currentQuestion;
  final bool finished;

  BattleParticipant({
    required this.userId,
    required this.username,
    this.avatarEmoji,
    required this.score,
    required this.currentQuestion,
    required this.finished,
  });

  factory BattleParticipant.fromMap(Map<String, dynamic> m) => BattleParticipant(
        userId: m['user_id'] as String,
        username: m['username'] as String? ?? 'Player',
        avatarEmoji: m['avatar_emoji'] as String?,
        score: (m['score'] as num?)?.toInt() ?? 0,
        currentQuestion: (m['current_question'] as num?)?.toInt() ?? 0,
        finished: m['finished'] as bool? ?? false,
      );
}

class BattleService {
  BattleService._();
  static final BattleService instance = BattleService._();

  SupabaseClient get _client => Supabase.instance.client;

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<String> _currentUsername(String userId) async {
    try {
      final row = await _client.from('profiles').select('username').eq('id', userId).maybeSingle();
      return row?['username'] as String? ?? 'Player';
    } catch (_) {
      return 'Player';
    }
  }

  Future<BattleInfo> createBattle({required String subject, required int questionCount}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in.');

    final pool = QuestionRepository.getForSubject(subject);
    if (pool.length < questionCount) {
      throw StateError('Not enough questions in $subject for a $questionCount-question battle.');
    }
    final shuffled = List<Question>.from(pool)..shuffle();
    final ids = shuffled.take(questionCount).map((q) => q.id).toList();
    final code = _generateCode();

    final row = await _client.from('battles').insert({
      'code': code,
      'subject': subject,
      'question_count': questionCount,
      'status': 'waiting',
      'question_ids': ids,
      'created_by': user.id,
    }).select().single();

    final battle = BattleInfo.fromMap(row);
    final username = await _currentUsername(user.id);

    await _client.from('battle_participants').insert({
      'battle_id': battle.id,
      'user_id': user.id,
      'username': username,
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
    final username = await _currentUsername(user.id);

    await _client.from('battle_participants').upsert({
      'battle_id': battle.id,
      'user_id': user.id,
      'username': username,
    }, onConflict: 'battle_id,user_id');

    return battle;
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

  Future<void> updateProgress({
    required String battleId,
    required int score,
    required int currentQuestion,
    bool finished = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('battle_participants')
        .update({'score': score, 'current_question': currentQuestion, 'finished': finished})
        .eq('battle_id', battleId)
        .eq('user_id', user.id);
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

class BattleLobbyScreen extends StatefulWidget {
  const BattleLobbyScreen({super.key});
  @override
  State<BattleLobbyScreen> createState() => _BattleLobbyScreenState();
}

class _BattleLobbyScreenState extends State<BattleLobbyScreen> {
  String _subject = kSubjects.first.name;
  int _count = 10;
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final battle = await BattleService.instance.createBattle(subject: _subject, questionCount: _count);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => BattleRoomScreen(battleId: battle.id, isHost: true)));
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
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => BattleRoomScreen(battleId: battle.id, isHost: false)));
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
          Text('Create a Battle', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _subject,
                  items: kSubjects.map((s) => DropdownMenuItem(value: s.name, child: Text(s.name))).toList(),
                  onChanged: (v) => setState(() => _subject = v!),
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _count,
                  items: const [5, 10, 15, 20].map((c) => DropdownMenuItem(value: c, child: Text('$c questions'))).toList(),
                  onChanged: (v) => setState(() => _count = v!),
                  decoration: const InputDecoration(labelText: 'Question count'),
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

class BattleRoomScreen extends StatefulWidget {
  final String battleId;
  final bool isHost;
  const BattleRoomScreen({super.key, required this.battleId, required this.isHost});
  @override
  State<BattleRoomScreen> createState() => _BattleRoomScreenState();
}

class _BattleRoomScreenState extends State<BattleRoomScreen> {
  List<BattleParticipant> _participants = [];
  RealtimeChannel? _participantsChannel;
  RealtimeChannel? _battleChannel;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _participantsChannel = BattleService.instance.subscribeToParticipants(widget.battleId, _refresh);
    _battleChannel = BattleService.instance.subscribeToBattle(widget.battleId, _onBattleChanged);
  }

  Future<void> _refresh() async {
    final participants = await BattleService.instance.getParticipants(widget.battleId);
    if (!mounted) return;
    setState(() => _participants = participants);
  }

  Future<void> _onBattleChanged() async {
    final battle = await BattleService.instance.getBattle(widget.battleId);
    if (!mounted || battle == null) return;
    if (battle.status == 'active' && !_navigated) {
      _navigated = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => BattlePlayScreen(battleId: widget.battleId, questionIds: battle.questionIds, subject: battle.subject),
      ));
    }
  }

  @override
  void dispose() {
    _participantsChannel?.unsubscribe();
    _battleChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Battle Room')),
      body: FutureBuilder<BattleInfo?>(
        future: BattleService.instance.getBattle(widget.battleId),
        builder: (context, snapshot) {
          final code = snapshot.data?.code;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (code != null)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
                    child: Column(children: [
                      const Text('Share this code', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(code, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 6)),
                    ]),
                  ),
                const SizedBox(height: 20),
                Text('Players (${_participants.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ..._participants.map((p) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Text(p.avatarEmoji ?? '🙂', style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Text(p.username, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    )),
                const Spacer(),
                if (widget.isHost)
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _participants.length >= 2 ? () => BattleService.instance.startBattle(widget.battleId) : null,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(_participants.length >= 2 ? 'Start Battle' : 'Waiting for opponent…'),
                    ),
                  )
                else
                  const Text('Waiting for host to start…', textAlign: TextAlign.center),
              ],
            ),
          );
        },
      ),
    );
  }
}

class BattlePlayScreen extends StatefulWidget {
  final String battleId;
  final List<String> questionIds;
  final String subject;
  const BattlePlayScreen({super.key, required this.battleId, required this.questionIds, required this.subject});
  @override
  State<BattlePlayScreen> createState() => _BattlePlayScreenState();
}

class _BattlePlayScreenState extends State<BattlePlayScreen> {
  late List<Question> _questions;
  int _index = 0;
  int _score = 0;
  int? _selected;
  List<BattleParticipant> _participants = [];
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    final all = {for (final q in QuestionRepository.getAll()) q.id: q};
    _questions = widget.questionIds.map((id) => all[id]).whereType<Question>().toList();
    _channel = BattleService.instance.subscribeToParticipants(widget.battleId, _refreshOpponents);
    _refreshOpponents();
  }

  Future<void> _refreshOpponents() async {
    final p = await BattleService.instance.getParticipants(widget.battleId);
    if (!mounted) return;
    setState(() => _participants = p);
  }

  void _selectOption(int i) => setState(() => _selected = i);

  Future<void> _next() async {
    if (_selected == null) return;
    final q = _questions[_index];
    if (_selected == q.correctIndex) _score++;
    final isLast = _index == _questions.length - 1;

    await BattleService.instance.updateProgress(
      battleId: widget.battleId,
      score: _score,
      currentQuestion: _index + 1,
      finished: isLast,
    );

    if (isLast) {
      final provider = context.read<AppProvider>();
      await Future.delayed(const Duration(seconds: 2)); // give the opponent a moment to also finish
      final finalParticipants = await BattleService.instance.getParticipants(widget.battleId);
      final me = Supabase.instance.client.auth.currentUser?.id;
      final myEntry = finalParticipants.firstWhere(
        (p) => p.userId == me,
        orElse: () => BattleParticipant(userId: '', username: '', score: _score, currentQuestion: _questions.length, finished: true),
      );
      final opponents = finalParticipants.where((p) => p.userId != me).toList();
      final opponentScore = opponents.isNotEmpty ? opponents.first.score : 0;
      final won = myEntry.score > opponentScore;
      final tied = myEntry.score == opponentScore;

      await provider.recordBattleResult(won: won && !tied);
      await provider.addXP(won && !tied ? 50 : (tied ? 25 : 10));

      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => BattleResultScreen(
          myScore: myEntry.score,
          opponentScore: opponentScore,
          opponentName: opponents.isNotEmpty ? opponents.first.username : 'Opponent',
          total: _questions.length,
        ),
      ));
    } else {
      setState(() {
        _index++;
        _selected = null;
      });
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_questions.isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text('Battle')), body: const Center(child: Text('Could not load battle questions.')));
    }
    final me = Supabase.instance.client.auth.currentUser?.id;
    final opponents = _participants.where((p) => p.userId != me).toList();
    final opponentProgress = opponents.isNotEmpty ? opponents.first.currentQuestion / _questions.length : 0.0;
    final q = _questions[_index];

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: Text('⚔️ Battle — ${widget.subject}'), automaticallyImplyLeading: false),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  Row(children: [
                    Expanded(child: Text('You: Q${_index + 1}/${_questions.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                    if (opponents.isNotEmpty)
                      Text('${opponents.first.username}: Q${opponents.first.currentQuestion}/${_questions.length}',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: _index / _questions.length, minHeight: 6, backgroundColor: scheme.surfaceContainerHighest)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: opponentProgress, minHeight: 4, backgroundColor: scheme.surfaceContainerHighest, valueColor: AlwaysStoppedAnimation(scheme.secondary)),
                  ),
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
                      child: Text(q.questionText, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 18),
                    ...List.generate(q.options.length, (i) {
                      final isSelected = _selected == i;
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
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(onPressed: _selected == null ? null : _next, child: Text(_index == _questions.length - 1 ? 'Finish' : 'Next')),
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
  final int myScore;
  final int opponentScore;
  final String opponentName;
  final int total;
  const BattleResultScreen({super.key, required this.myScore, required this.opponentScore, required this.opponentName, required this.total});

  @override
  Widget build(BuildContext context) {
    final won = myScore > opponentScore;
    final tied = myScore == opponentScore;
    final scheme = Theme.of(context).colorScheme;
    final color = tied ? Colors.amber : (won ? Colors.green : scheme.error);

    return Scaffold(
      appBar: AppBar(title: const Text('Battle Result'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(tied ? Icons.handshake_rounded : (won ? Icons.emoji_events_rounded : Icons.sentiment_dissatisfied_rounded), size: 72, color: color),
            const SizedBox(height: 16),
            Text(tied ? "It's a Tie!" : (won ? 'You Won! 🏆' : 'You Lost'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _ScoreChip(label: 'You', score: myScore, total: total, color: scheme.primary),
              const SizedBox(width: 16),
              const Text('vs', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              _ScoreChip(label: opponentName, score: opponentScore, total: total, color: scheme.secondary),
            ]),
            const SizedBox(height: 24),
            if (won && !tied)
              const Text('+50 XP • Ranking increased', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
            else if (tied)
              const Text('+25 XP', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))
            else
              const Text('+10 XP for showing up', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            SizedBox(width: double.infinity, height: 52, child: FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('Back to Home'))),
          ],
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  final String label;
  final int score;
  final int total;
  final Color color;
  const _ScoreChip({required this.label, required this.score, required this.total, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
        CircleAvatar(radius: 28, backgroundColor: color.withOpacity(0.15), child: Text('$score', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18))),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('/ $total', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);
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

class ReportCardScreen extends StatelessWidget {
  const ReportCardScreen({super.key});

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
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                  child: Text(text, style: const TextStyle(height: 1.6, fontSize: 14)),
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
