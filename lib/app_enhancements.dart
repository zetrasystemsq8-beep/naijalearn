// lib/app_enhancements.dart
//
// ⚡ REDESIGNED VERSION — visuals only. Every service, model, and
// AppProvider method below is 100% unchanged from your original file —
// copy this in as a straight replacement, nothing breaks.
//
// New design system used across every screen in this file (also reuse
// these constants/helpers when you redesign other files, so the whole
// app matches):
//   AppTheme.heroGradient(context)   — violet gradient for headers/primary buttons
//   kGoldAccent     — XP / streak / rewards
//   kTealAccent     — progress / study / positive
//   kCoralAccent    — urgency / warnings
//   ShinyCard       — soft-shadow rounded card (replaces flat grey fills)
//   GradientButton  — pill button with gradient + shadow
//   GradientHeader  — reusable gradient app-bar-style header

import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import 'app_theme.dart' show AppTheme;
import 'questions_english.dart';
import 'main.dart' show QuestionNavigatorSheet, QuestionStatus;
import 'questions_mathematics.dart';
import 'questions_physics.dart';
import 'questions_biology.dart';
import 'questions_chemistry.dart';
import 'questions_economics.dart';
import 'questions_government.dart';
import 'questions_literature.dart';
import 'questions_crs.dart';
import 'questions_accounting.dart';
import 'questions_commerce.dart';
import 'questions_geography.dart';
import 'questions_irs.dart';
import 'questions_arabic.dart';
import 'career_features.dart' show dailyGoalStatusText;
import 'features5.dart' show CoinService;

// =============================================================================
// 🎨 DESIGN SYSTEM — shared across every screen in this file.
// Colors are derived from Theme.of(context).colorScheme / AppTheme, NEVER
// hardcoded — that's what makes this correct in both light AND dark mode,
// and what stops the brand gradient from clashing with the rest of the
// theme (previous version hardcoded an unrelated purple).
// =============================================================================

const Color kGoldAccent = Color(0xFFD97706); // matches AppColors.xp
const Color kTealAccent = Color(0xFF16A34A); // matches AppColors.success
const Color kCoralAccent = Color(0xFFDC2626); // matches AppColors.error

/// Soft-shadow rounded card — replaces flat `surfaceContainerHighest`
/// fills everywhere in this file. Theme-aware: no shadow in dark mode
/// (shadows read as pale halos on dark backgrounds), full contrast tint
/// in both modes.
class ShinyCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  const ShinyCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.tint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint != null ? tint.withOpacity(isDark ? 0.16 : 0.08) : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 8))],
        border: tint != null ? Border.all(color: tint.withOpacity(isDark ? 0.35 : 0.22)) : null,
      ),
      child: DefaultTextStyle.merge(style: TextStyle(color: scheme.onSurface), child: child),
    );
  }
}

/// Gradient pill button with a colored drop shadow. Defaults to the
/// theme's own hero gradient (derived from colorScheme.primary) — pass a
/// different `gradient` only for a deliberately different accent (e.g.
/// destructive actions in coral/red).
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Gradient? gradient;
  final double height;
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.gradient,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final resolvedGradient = gradient ?? AppTheme.heroGradient(context);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: disabled ? null : resolvedGradient,
          color: disabled ? Theme.of(context).colorScheme.onSurface.withOpacity(0.12) : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: disabled
              ? null
              : [BoxShadow(color: (resolvedGradient.colors.first).withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, color: Colors.white, size: 19), const SizedBox(width: 8)],
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable gradient header block — used at the top of every redesigned
/// screen instead of a flat AppBar. ALWAYS includes a back button unless
/// explicitly told not to (root/tab screens pass showBackButton: false).
class GradientHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showBackButton;
  const GradientHeader({super.key, required this.title, this.subtitle, this.trailing, this.showBackButton = true});

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 50, 20, 26),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient(context),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      child: Row(
        children: [
          if (showBackButton && canPop)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Glassy stat pill used inside GradientHeader areas — white-on-gradient
/// is correct in both modes since the gradient background doesn't change.
class GlassPill extends StatelessWidget {
  final IconData icon;
  final String value;
  const GlassPill({super.key, required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// =========================================================================
/// DATA MODELS  (unchanged — logic only)
/// =========================================================================

class UserStats {
  final int xp;
  final int streak;
  final int level;
  final Map<String, int> subjectScores;
  final Map<String, int> subjectAttempts;
  final List<String> badges;
  final DateTime lastActive;

  final int dailyGoalQuestions;
  final int questionsToday;
  final String lastProgressDate;
  final int studySecondsToday;
  final int totalStudySeconds;
  final String lastStudyDate;
  final int goalsMetCount;
  final String lastGoalMetDate;
  final int quizzesCompleted;
  final Map<String, int> dailyXp;
  final Map<String, List<int>> dailyAccuracy;
  final int battlesWon;
  final String lastPracticedSubject;

  UserStats({
    this.xp = 0,
    this.streak = 0,
    this.level = 1,
    this.subjectScores = const {},
    this.subjectAttempts = const {},
    this.badges = const [],
    DateTime? lastActive,
    this.dailyGoalQuestions = 10,
    this.questionsToday = 0,
    this.lastProgressDate = '',
    this.studySecondsToday = 0,
    this.totalStudySeconds = 0,
    this.lastStudyDate = '',
    this.goalsMetCount = 0,
    this.lastGoalMetDate = '',
    this.quizzesCompleted = 0,
    this.dailyXp = const {},
    this.dailyAccuracy = const {},
    this.battlesWon = 0,
    this.lastPracticedSubject = '',
  }) : lastActive = lastActive ?? DateTime.now();

  UserStats copyWith({
    int? xp,
    int? streak,
    int? level,
    Map<String, int>? subjectScores,
    Map<String, int>? subjectAttempts,
    List<String>? badges,
    DateTime? lastActive,
    int? dailyGoalQuestions,
    int? questionsToday,
    String? lastProgressDate,
    int? studySecondsToday,
    int? totalStudySeconds,
    String? lastStudyDate,
    int? goalsMetCount,
    String? lastGoalMetDate,
    int? quizzesCompleted,
    Map<String, int>? dailyXp,
    Map<String, List<int>>? dailyAccuracy,
    int? battlesWon,
    String? lastPracticedSubject,
  }) {
    return UserStats(
      xp: xp ?? this.xp,
      streak: streak ?? this.streak,
      level: level ?? this.level,
      subjectScores: subjectScores ?? this.subjectScores,
      subjectAttempts: subjectAttempts ?? this.subjectAttempts,
      badges: badges ?? this.badges,
      lastActive: lastActive ?? this.lastActive,
      dailyGoalQuestions: dailyGoalQuestions ?? this.dailyGoalQuestions,
      questionsToday: questionsToday ?? this.questionsToday,
      lastProgressDate: lastProgressDate ?? this.lastProgressDate,
      studySecondsToday: studySecondsToday ?? this.studySecondsToday,
      totalStudySeconds: totalStudySeconds ?? this.totalStudySeconds,
      lastStudyDate: lastStudyDate ?? this.lastStudyDate,
      goalsMetCount: goalsMetCount ?? this.goalsMetCount,
      lastGoalMetDate: lastGoalMetDate ?? this.lastGoalMetDate,
      quizzesCompleted: quizzesCompleted ?? this.quizzesCompleted,
      dailyXp: dailyXp ?? this.dailyXp,
      dailyAccuracy: dailyAccuracy ?? this.dailyAccuracy,
      battlesWon: battlesWon ?? this.battlesWon,
      lastPracticedSubject: lastPracticedSubject ?? this.lastPracticedSubject,
    );
  }

  Map<String, dynamic> toJson() => {
        'xp': xp,
        'streak': streak,
        'level': level,
        'subjectScores': subjectScores,
        'subjectAttempts': subjectAttempts,
        'badges': badges,
        'lastActive': lastActive.toIso8601String(),
        'dailyGoalQuestions': dailyGoalQuestions,
        'questionsToday': questionsToday,
        'lastProgressDate': lastProgressDate,
        'studySecondsToday': studySecondsToday,
        'totalStudySeconds': totalStudySeconds,
        'lastStudyDate': lastStudyDate,
        'goalsMetCount': goalsMetCount,
        'lastGoalMetDate': lastGoalMetDate,
        'quizzesCompleted': quizzesCompleted,
        'dailyXp': dailyXp,
        'dailyAccuracy': dailyAccuracy,
        'battlesWon': battlesWon,
        'lastPracticedSubject': lastPracticedSubject,
      };

  factory UserStats.fromJson(Map<String, dynamic> json) => UserStats(
        xp: json['xp'] ?? 0,
        streak: json['streak'] ?? 0,
        level: json['level'] ?? 1,
        subjectScores: Map<String, int>.from(json['subjectScores'] ?? {}),
        subjectAttempts: Map<String, int>.from(json['subjectAttempts'] ?? {}),
        badges: List<String>.from(json['badges'] ?? []),
        lastActive: DateTime.tryParse(json['lastActive'] ?? '') ?? DateTime.now(),
        dailyGoalQuestions: json['dailyGoalQuestions'] ?? 10,
        questionsToday: json['questionsToday'] ?? 0,
        lastProgressDate: json['lastProgressDate'] ?? '',
        studySecondsToday: json['studySecondsToday'] ?? 0,
        totalStudySeconds: json['totalStudySeconds'] ?? 0,
        lastStudyDate: json['lastStudyDate'] ?? '',
        goalsMetCount: json['goalsMetCount'] ?? 0,
        lastGoalMetDate: json['lastGoalMetDate'] ?? '',
        quizzesCompleted: json['quizzesCompleted'] ?? 0,
        dailyXp: Map<String, int>.from(json['dailyXp'] ?? {}),
        dailyAccuracy: (json['dailyAccuracy'] as Map<String, dynamic>?)?.map(
              (key, value) => MapEntry(key, List<int>.from(value as List)),
            ) ??
            {},
        battlesWon: json['battlesWon'] ?? 0,
        lastPracticedSubject: json['lastPracticedSubject'] ?? '',
      );
}

class LeaderboardEntry {
  final String userId;
  final String name;
  final int xp;
  final int level;
  final int streak;
  final String? avatarEmoji;

  LeaderboardEntry({
    required this.userId,
    required this.name,
    required this.xp,
    required this.level,
    required this.streak,
    this.avatarEmoji,
  });

  factory LeaderboardEntry.fromMap(Map<String, dynamic> map) => LeaderboardEntry(
        userId: map['user_id'] as String? ?? '',
        name: map['username'] as String? ?? 'Anonymous',
        xp: (map['xp'] as num?)?.toInt() ?? 0,
        level: (map['level'] as num?)?.toInt() ?? 1,
        streak: (map['streak'] as num?)?.toInt() ?? 0,
        avatarEmoji: map['avatar_emoji'] as String?,
      );
}

class DailyChallenge {
  final List<Map<String, dynamic>> questions;
  final DateTime date;
  int score;
  bool completed;

  DailyChallenge({
    required this.questions,
    required this.date,
    this.score = 0,
    this.completed = false,
  });

  Map<String, dynamic> toJson() => {
        'questions': questions,
        'date': date.toIso8601String(),
        'score': score,
        'completed': completed,
      };

  factory DailyChallenge.fromJson(Map<String, dynamic> json) => DailyChallenge(
        questions: List<Map<String, dynamic>>.from(
          (json['questions'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        ),
        date: DateTime.parse(json['date']),
        score: json['score'] ?? 0,
        completed: json['completed'] ?? false,
      );
}

enum MasteryTier { none, bronze, silver, gold }

MasteryTier masteryTierFor(double percentScore, int attempts) {
  if (attempts < 10) return MasteryTier.none;
  if (percentScore >= 90) return MasteryTier.gold;
  if (percentScore >= 70) return MasteryTier.silver;
  if (percentScore >= 50) return MasteryTier.bronze;
  return MasteryTier.none;
}

String masteryLabel(MasteryTier tier) {
  switch (tier) {
    case MasteryTier.gold:
      return 'Gold';
    case MasteryTier.silver:
      return 'Silver';
    case MasteryTier.bronze:
      return 'Bronze';
    case MasteryTier.none:
      return 'Unranked';
  }
}

Color masteryColor(MasteryTier tier) {
  switch (tier) {
    case MasteryTier.gold:
      return const Color(0xFFFFD700);
    case MasteryTier.silver:
      return const Color(0xFFC0C0C0);
    case MasteryTier.bronze:
      return const Color(0xFFCD7F32);
    case MasteryTier.none:
      return Colors.grey;
  }
}

String rankTitleForLevel(int level) {
  if (level >= 50) return 'Legend';
  if (level >= 25) return 'Grandmaster';
  if (level >= 15) return 'Master';
  if (level >= 10) return 'Ace';
  if (level >= 5) return 'Scholar';
  return 'Rookie';
}

Color rankColor(int level) {
  if (level >= 50) return const Color(0xFFFFD700);
  if (level >= 25) return const Color(0xFF9C27B0);
  if (level >= 15) return const Color(0xFFE91E63);
  if (level >= 10) return const Color(0xFF2196F3);
  if (level >= 5) return const Color(0xFF4CAF50);
  return Colors.grey;
}

/// =========================================================================
/// SERVICES  (unchanged — logic only)
/// =========================================================================

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> saveUserStats(UserStats stats) async {
    await _prefs.setString('userStats', jsonEncode(stats.toJson()));
  }

  UserStats loadUserStats() {
    final data = _prefs.getString('userStats');
    if (data != null) {
      try {
        return UserStats.fromJson(jsonDecode(data));
      } catch (_) {}
    }
    return UserStats();
  }

  Future<void> saveDailyChallenge(DailyChallenge challenge) async {
    await _prefs.setString('dailyChallenge', jsonEncode(challenge.toJson()));
  }

  DailyChallenge? loadDailyChallengeFromDisk() {
    final data = _prefs.getString('dailyChallenge');
    if (data != null) {
      try {
        return DailyChallenge.fromJson(jsonDecode(data));
      } catch (_) {}
    }
    return null;
  }

  Future<void> saveDarkMode(bool dark) async {
    await _prefs.setBool('darkMode', dark);
  }

  bool loadDarkMode() {
    return _prefs.getBool('darkMode') ?? false;
  }

  Future<void> saveAvatarEmoji(String emoji) async {
    await _prefs.setString('avatarEmoji', emoji);
  }

  String loadAvatarEmoji() {
    return _prefs.getString('avatarEmoji') ?? '🙂';
  }

  Future<void> saveLastUserId(String? id) async {
    if (id == null) {
      await _prefs.remove('lastUserId');
    } else {
      await _prefs.setString('lastUserId', id);
    }
  }

  String? loadLastUserId() => _prefs.getString('lastUserId');
}

class StreakService {
  Future<UserStats> checkStreak(UserStats stats) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = DateTime(stats.lastActive.year, stats.lastActive.month, stats.lastActive.day);

    if (today == last) {
      return stats;
    } else if (today.difference(last).inDays == 1) {
      return stats.copyWith(streak: stats.streak + 1, lastActive: now);
    } else {
      final freezeUsed = CoinService.instance.consumeStreakFreeze();
      if (freezeUsed) {
        return stats.copyWith(lastActive: now);
      }
      return stats.copyWith(streak: 0, lastActive: now);
    }
  }

  UserStats addXP(UserStats stats, int amount) {
    final newXP = stats.xp + amount;
    final newLevel = (newXP / 100).floor() + 1;
    return stats.copyWith(xp: newXP, level: newLevel);
  }

  List<String> checkBadges(UserStats stats) {
    final badges = <String>[...stats.badges];

    if (stats.xp >= 1000 && !badges.contains('Scholar')) badges.add('Scholar');
    if (stats.xp >= 5000 && !badges.contains('Sage')) badges.add('Sage');
    if (stats.streak >= 3 && !badges.contains('Getting Started')) badges.add('Getting Started');
    if (stats.streak >= 7 && !badges.contains('Streak Master')) badges.add('Streak Master');
    if (stats.streak >= 30 && !badges.contains('Unstoppable')) badges.add('Unstoppable');
    if (stats.level >= 5 && !badges.contains('Rising Star')) badges.add('Rising Star');
    if (stats.level >= 10 && !badges.contains('Grandmaster')) badges.add('Grandmaster');
    if (stats.level >= 25 && !badges.contains('Legend')) badges.add('Legend');

    final goldSubjects = stats.subjectScores.keys.where((s) {
      final attempts = stats.subjectAttempts[s] ?? 0;
      final correct = stats.subjectScores[s] ?? 0;
      if (attempts < 10) return false;
      return (correct / attempts * 100) >= 90;
    }).length;
    if (goldSubjects >= 1 && !badges.contains('Subject Expert')) badges.add('Subject Expert');
    if (goldSubjects >= 5 && !badges.contains('Subject Master')) badges.add('Subject Master');
    if (goldSubjects >= 10 && !badges.contains('Polymath')) badges.add('Polymath');

    final totalAttempts = stats.subjectAttempts.values.fold(0, (a, b) => a + b);
    if (totalAttempts >= 100 && !badges.contains('Century Club')) badges.add('Century Club');
    if (totalAttempts >= 500 && !badges.contains('Marathoner')) badges.add('Marathoner');
    if (totalAttempts >= 2000 && !badges.contains('Iron Will')) badges.add('Iron Will');

    if (stats.subjectAttempts.keys.length >= 14 && !badges.contains('Well Rounded')) {
      badges.add('Well Rounded');
    }

    if (stats.goalsMetCount >= 7 && !badges.contains('Goal Getter')) badges.add('Goal Getter');
    if (stats.goalsMetCount >= 30 && !badges.contains('Goal Crusher')) badges.add('Goal Crusher');

    final studyMinutes = stats.totalStudySeconds ~/ 60;
    if (studyMinutes >= 60 && !badges.contains('Study Buddy')) badges.add('Study Buddy');
    if (studyMinutes >= 500 && !badges.contains('Study Master')) badges.add('Study Master');

    if (stats.quizzesCompleted >= 10 && !badges.contains('Quiz Regular')) badges.add('Quiz Regular');
    if (stats.quizzesCompleted >= 50 && !badges.contains('Quiz Champion')) badges.add('Quiz Champion');

    final perfectSubjects = stats.subjectScores.keys.where((s) {
      final attempts = stats.subjectAttempts[s] ?? 0;
      final correct = stats.subjectScores[s] ?? 0;
      if (attempts < 10) return false;
      return correct == attempts;
    }).length;
    if (perfectSubjects >= 1 && !badges.contains('Perfectionist')) badges.add('Perfectionist');

    if (stats.battlesWon >= 1 && !badges.contains('Battle Winner')) badges.add('Battle Winner');
    if (stats.battlesWon >= 10 && !badges.contains('Battle Champion')) badges.add('Battle Champion');

    return badges;
  }
}

class QuoteService {
  static const List<String> _quotes = [
    'Small steps every day lead to big results.',
    'Discipline today, success tomorrow.',
    'Your future is built by what you do now, not tomorrow.',
    'Every question you practice is a step closer to your goal.',
    'Consistency beats intensity — show up daily.',
    'Champions are made in practice, not just on exam day.',
    'You don\'t have to be perfect, just persistent.',
    'Hard work beats talent when talent doesn\'t work hard.',
    'The best time to study was yesterday. The next best time is now.',
    'Progress, not perfection.',
    'Believe you can, and you\'re halfway there.',
    'Focus on being productive instead of busy.',
    'A little progress each day adds up to big results.',
    'Success is the sum of small efforts repeated daily.',
    'Study while others sleep; win while others hope.',
  ];

  static String getRandomQuote() {
    final r = Random();
    return _quotes[r.nextInt(_quotes.length)];
  }
}

class LeaderboardService {
  SupabaseClient get _client => Supabase.instance.client;

  static const int topEntriesLimit = 7;

  Future<List<LeaderboardEntry>> getTopEntries({int limit = topEntriesLimit}) async {
    try {
      final rows = await _client
          .from('leaderboard_entries')
          .select()
          .order('xp', ascending: false)
          .limit(limit);
      return (rows as List<dynamic>)
          .map((r) => LeaderboardEntry.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Leaderboard] getTopEntries failed: $e');
      return [];
    }
  }

  Future<MapEntry<int, LeaderboardEntry>?> getMyRank() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final mine = await _client.from('leaderboard_entries').select().eq('user_id', user.id).maybeSingle();
      if (mine == null) return null;
      final myEntry = LeaderboardEntry.fromMap(mine);

      final higherRows = await _client.from('leaderboard_entries').select('user_id').gt('xp', myEntry.xp);
      final rank = (higherRows as List).length + 1;

      return MapEntry(rank, myEntry);
    } catch (e) {
      debugPrint('[Leaderboard] getMyRank failed: $e');
      return null;
    }
  }

  Future<int> getTotalPlayers() async {
    try {
      final rows = await _client.from('leaderboard_entries').select('user_id');
      return (rows as List).length;
    } catch (e) {
      debugPrint('[Leaderboard] getTotalPlayers failed: $e');
      return 0;
    }
  }

  Future<void> upsertEntry({required String name, required UserStats stats, String? avatarEmoji}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('leaderboard_entries').upsert({
        'user_id': user.id,
        'username': name,
        'xp': stats.xp,
        'level': stats.level,
        'streak': stats.streak,
        'avatar_emoji': avatarEmoji,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[Leaderboard] upsertEntry failed: $e');
    }
  }
}

class UserStatsSyncService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<Map<String, dynamic>?> fetchRemote() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await _client.from('user_stats').select().eq('user_id', user.id).maybeSingle();
      return row;
    } catch (e) {
      debugPrint('[UserStatsSync] fetchRemote failed: $e');
      return null;
    }
  }

  Future<void> pushRemote({
    required UserStats stats,
    required bool darkMode,
    required String avatarEmoji,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('user_stats').upsert({
        'user_id': user.id,
        'data': stats.toJson(),
        'dark_mode': darkMode,
        'avatar_emoji': avatarEmoji,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[UserStatsSync] pushRemote failed: $e');
    }
  }
}

/// =========================================================================
/// APP PROVIDER  (unchanged — logic only)
/// =========================================================================

class AppProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final StreakService _streak = StreakService();
  final LeaderboardService _leaderboard = LeaderboardService();
  final UserStatsSyncService _statsSync = UserStatsSyncService();

  UserStats _stats = UserStats();
  bool _darkMode = false;
  String _userName = 'Student';
  String _avatarEmoji = '🙂';
  DailyChallenge? _dailyChallenge;
  String? _pendingBadgeAnnouncement;

  UserStats get stats => _stats;
  bool get darkMode => _darkMode;
  String get userName => _userName;
  String get avatarEmoji => _avatarEmoji;
  String get lastPracticedSubject => _stats.lastPracticedSubject;
  DailyChallenge? get dailyChallenge => _dailyChallenge;
  String? get pendingBadgeAnnouncement => _pendingBadgeAnnouncement;

  AppProvider() {
    _init();
  }

  Future<void> _init() async {
    await _storage.init();
    _stats = _storage.loadUserStats();
    _darkMode = _storage.loadDarkMode();
    _avatarEmoji = _storage.loadAvatarEmoji();

    await _discardStatsIfDifferentUser();

    _stats = await _streak.checkStreak(_stats);

    if (_stats.streak > 0 && _stats.questionsToday == 0 && DateTime.now().hour >= 17) {
      NotificationService.instance.showStreakAtRisk(_stats.streak);
    }

    _stats = _rolloverDailyIfNeeded(_stats);
    await _storage.saveUserStats(_stats);

    await _pullFromSupabase();

    _loadOrGenerateDailyChallenge();
    notifyListeners();
  }

  Future<void> _discardStatsIfDifferentUser() async {
    final currentUid = Supabase.instance.client.auth.currentUser?.id;
    if (currentUid == null) return;
    final lastUid = _storage.loadLastUserId();
    if (lastUid == currentUid) return;

    _stats = UserStats();
    _dailyChallenge = null;
    await _storage.saveUserStats(_stats);
    await _storage.saveLastUserId(currentUid);
  }

  Future<void> reconcileForCurrentUser() async {
    final currentUid = Supabase.instance.client.auth.currentUser?.id;
    if (currentUid == null) return;
    final lastUid = _storage.loadLastUserId();
    if (lastUid == currentUid) return;

    await _discardStatsIfDifferentUser();
    await _pullFromSupabase();
    _loadOrGenerateDailyChallenge();
    notifyListeners();
  }

  Future<void> _pullFromSupabase() async {
    final remote = await _statsSync.fetchRemote();
    final remoteData = remote?['data'];
    if (remote != null && remoteData != null) {
      try {
        _stats = UserStats.fromJson(Map<String, dynamic>.from(remoteData as Map));
        _darkMode = remote['dark_mode'] as bool? ?? _darkMode;
        _avatarEmoji = remote['avatar_emoji'] as String? ?? _avatarEmoji;
        await _storage.saveUserStats(_stats);
        await _storage.saveDarkMode(_darkMode);
        await _storage.saveAvatarEmoji(_avatarEmoji);
      } catch (e) {
        debugPrint('[AppProvider] Failed to parse remote stats, keeping local: $e');
      }
    } else {
      await _pushToSupabase();
    }
  }

  Future<void> _pushToSupabase() async {
    await _statsSync.pushRemote(stats: _stats, darkMode: _darkMode, avatarEmoji: _avatarEmoji);
  }

  void _applyBadgeCheck() {
    final before = _stats.badges;
    final after = _streak.checkBadges(_stats);
    if (after.length > before.length) {
      final newOnes = after.where((b) => !before.contains(b)).toList();
      _pendingBadgeAnnouncement = newOnes.first;
    }
    _stats = _stats.copyWith(badges: after);
  }

  void clearBadgeAnnouncement() {
    _pendingBadgeAnnouncement = null;
  }

  void toggleDarkMode() {
    _darkMode = !_darkMode;
    _storage.saveDarkMode(_darkMode);
    notifyListeners();
    _pushToSupabase();
  }

  void setUserName(String name) {
    if (name.trim().isEmpty) return;
    _userName = name.trim();
    notifyListeners();
    _syncLeaderboard();
  }

  Future<void> _syncLeaderboard() async {
    await _leaderboard.upsertEntry(name: _userName, stats: _stats, avatarEmoji: _avatarEmoji);
  }

  Future<void> syncLeaderboardNow() => _syncLeaderboard();

  Future<void> setAvatarEmoji(String emoji) async {
    _avatarEmoji = emoji;
    await _storage.saveAvatarEmoji(emoji);
    notifyListeners();
    _syncLeaderboard();
    _pushToSupabase();
  }

  Future<void> _syncSubjectLeaderboard(String subject) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final attempts = _stats.subjectAttempts[subject] ?? 0;
    if (attempts < 5) return;
    try {
      await Supabase.instance.client.from('subject_leaderboard').upsert({
        'user_id': user.id,
        'subject': subject,
        'username': _userName,
        'best_score': getSubjectScore(subject),
        'attempts': attempts,
        'avatar_emoji': _avatarEmoji,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[SubjectLeaderboard] sync failed: $e');
    }
  }

  Future<void> recordBattleResult({required bool won}) async {
    if (won) {
      _stats = _stats.copyWith(battlesWon: _stats.battlesWon + 1);
      _applyBadgeCheck();
      await _storage.saveUserStats(_stats);
      notifyListeners();
      _pushToSupabase();
    }
  }

  Future<void> addXP(int amount) async {
    _stats = _streak.addXP(_stats, amount);
    final key = todayKey();
    final xpMap = Map<String, int>.from(_stats.dailyXp);
    xpMap[key] = (xpMap[key] ?? 0) + amount;
    _pruneOldDailyKeys(xpMap);
    _stats = _stats.copyWith(dailyXp: xpMap);
    _applyBadgeCheck();
    await _storage.saveUserStats(_stats);
    notifyListeners();
    _syncLeaderboard();
    _pushToSupabase();
  }

  Future<void> recordAnswer(String subject, int score, int total) async {
    if (total <= 0) return;
    final newScore = (stats.subjectScores[subject] ?? 0) + score;
    final newAttempts = (stats.subjectAttempts[subject] ?? 0) + total;
    _stats = _stats.copyWith(
      subjectScores: Map.from(_stats.subjectScores)..[subject] = newScore,
      subjectAttempts: Map.from(_stats.subjectAttempts)..[subject] = newAttempts,
      lastPracticedSubject: subject,
    );
    _stats = await _streak.checkStreak(_stats);
    _stats = _trackDailyProgress(correct: score, total: total);
    _applyBadgeCheck();
    await _storage.saveUserStats(_stats);
    notifyListeners();
    _syncLeaderboard();
    _syncSubjectLeaderboard(subject);
    _pushToSupabase();
  }

  double getSubjectScore(String subject) {
    final attempted = stats.subjectAttempts[subject] ?? 0;
    if (attempted == 0) return 0;
    final correct = stats.subjectScores[subject] ?? 0;
    return correct / attempted * 100;
  }

  MasteryTier getSubjectMastery(String subject) {
    final attempted = stats.subjectAttempts[subject] ?? 0;
    return masteryTierFor(getSubjectScore(subject), attempted);
  }

  void _loadOrGenerateDailyChallenge() {
    final loaded = _storage.loadDailyChallengeFromDisk();
    if (loaded != null && loaded.date.day == DateTime.now().day && loaded.date.month == DateTime.now().month) {
      _dailyChallenge = loaded;
    } else {
      _generateDailyChallenge();
    }
  }

  void _generateDailyChallenge() {
    final allQuestions = [
      ...englishQuestions,
      ...mathematicsQuestions,
      ...physicsQuestions,
      ...biologyQuestions,
      ...chemistryQuestions,
      ...economicsQuestions,
      ...governmentQuestions,
      ...literatureQuestions,
      ...crsQuestions,
      ...accountingQuestions,
      ...commerceQuestions,
      ...geographyQuestions,
      ...irsQuestions,
      ...arabicQuestions,
    ];
    final shuffled = List<Map<String, dynamic>>.from(allQuestions)..shuffle();
    final selected = shuffled.take(10).toList();
    _dailyChallenge = DailyChallenge(questions: selected, date: DateTime.now());
    _storage.saveDailyChallenge(_dailyChallenge!);
  }

  void refreshDailyChallengeIfNeeded() {
    final d = _dailyChallenge;
    if (d == null || d.date.day != DateTime.now().day) {
      _generateDailyChallenge();
      notifyListeners();
    }
  }

  Future<void> submitDailyChallenge(int score) async {
    if (_dailyChallenge != null && !_dailyChallenge!.completed) {
      _dailyChallenge!.score = score;
      _dailyChallenge!.completed = true;
      await _storage.saveDailyChallenge(_dailyChallenge!);
      _stats = _trackDailyProgress(correct: score, total: _dailyChallenge!.questions.length);
      await _storage.saveUserStats(_stats);
      await addXP(score * 2);
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> generateMockExam(String subject, int count) {
    final allQuestions = _getQuestionsForSubject(subject);
    final shuffled = List<Map<String, dynamic>>.from(allQuestions)..shuffle();
    return shuffled.take(count).toList();
  }

  List<Map<String, dynamic>> generateMockExamMulti(List<String> subjects, int perSubject) {
    final combined = <Map<String, dynamic>>[];
    for (final subject in subjects) {
      final pool = _getQuestionsForSubject(subject);
      final shuffled = List<Map<String, dynamic>>.from(pool)..shuffle();
      final picked = shuffled.take(perSubject).map((q) => <String, dynamic>{
            ...q,
            'subject': subject,
          });
      combined.addAll(picked);
    }
    combined.shuffle();
    return combined;
  }

  List<Map<String, dynamic>> _getQuestionsForSubject(String subject) {
    switch (subject) {
      case 'English':
        return englishQuestions;
      case 'Mathematics':
        return mathematicsQuestions;
      case 'Physics':
        return physicsQuestions;
      case 'Biology':
        return biologyQuestions;
      case 'Chemistry':
        return chemistryQuestions;
      case 'Economics':
        return economicsQuestions;
      case 'Government':
        return governmentQuestions;
      case 'Literature':
        return literatureQuestions;
      case 'CRS':
        return crsQuestions;
      case 'Accounting':
        return accountingQuestions;
      case 'Commerce':
        return commerceQuestions;
      case 'Geography':
        return geographyQuestions;
      case 'IRS':
        return irsQuestions;
      case 'Arabic':
        return arabicQuestions;
      default:
        return [];
    }
  }

  List<String> getAvailableSubjects() => const [
        'English', 'Mathematics', 'Physics', 'Biology', 'Chemistry',
        'Economics', 'Government', 'Literature', 'CRS', 'Accounting',
        'Commerce', 'Geography', 'IRS', 'Arabic',
      ];

  String todayKey() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _keyForOffset(int daysAgo) {
    final d = DateTime.now().subtract(Duration(days: daysAgo));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _pruneOldDailyKeys(Map<String, int> map) {
    if (map.length <= 30) return;
    final validKeys = List.generate(30, (i) => _keyForOffset(i)).toSet();
    map.removeWhere((k, _) => !validKeys.contains(k));
  }

  UserStats _rolloverDailyIfNeeded(UserStats s) {
    final key = todayKey();
    var result = s;
    if (s.lastProgressDate != key) {
      result = result.copyWith(questionsToday: 0, lastProgressDate: key);
    }
    if (s.lastStudyDate != key) {
      result = result.copyWith(studySecondsToday: 0, lastStudyDate: key);
    }
    return result;
  }

  UserStats _trackDailyProgress({required int correct, required int total}) {
    var s = _rolloverDailyIfNeeded(_stats);
    final key = todayKey();

    final newQuestionsToday = s.questionsToday + total;

    final accMap = Map<String, List<int>>.from(s.dailyAccuracy);
    final existing = accMap[key] ?? [0, 0];
    accMap[key] = [existing[0] + correct, existing[1] + total];
    _pruneOldAccuracyKeys(accMap);

    var newGoalsMet = s.goalsMetCount;
    var newLastGoalMetDate = s.lastGoalMetDate;
    if (newQuestionsToday >= s.dailyGoalQuestions && s.lastGoalMetDate != key) {
      newGoalsMet += 1;
      newLastGoalMetDate = key;
    }

    return s.copyWith(
      questionsToday: newQuestionsToday,
      lastProgressDate: key,
      dailyAccuracy: accMap,
      goalsMetCount: newGoalsMet,
      lastGoalMetDate: newLastGoalMetDate,
      quizzesCompleted: s.quizzesCompleted + 1,
    );
  }

  void _pruneOldAccuracyKeys(Map<String, List<int>> map) {
    if (map.length <= 30) return;
    final validKeys = List.generate(30, (i) => _keyForOffset(i)).toSet();
    map.removeWhere((k, _) => !validKeys.contains(k));
  }

  Future<void> setDailyGoal(int questions) async {
    _stats = _rolloverDailyIfNeeded(_stats).copyWith(dailyGoalQuestions: questions);
    await _storage.saveUserStats(_stats);
    notifyListeners();
    _pushToSupabase();
  }

  int get dailyGoalQuestions => _stats.dailyGoalQuestions;

  int get questionsToday {
    final s = _rolloverDailyIfNeeded(_stats);
    return s.questionsToday;
  }

  double get dailyGoalProgress {
    if (_stats.dailyGoalQuestions <= 0) return 0;
    final progress = questionsToday / _stats.dailyGoalQuestions;
    return progress.clamp(0.0, 1.0);
  }

  bool get dailyGoalMet => questionsToday >= _stats.dailyGoalQuestions;

  Future<void> addStudySeconds(int seconds) async {
    if (seconds <= 0) return;
    var s = _rolloverDailyIfNeeded(_stats);
    s = s.copyWith(
      studySecondsToday: s.studySecondsToday + seconds,
      totalStudySeconds: s.totalStudySeconds + seconds,
      lastStudyDate: todayKey(),
    );
    _stats = s;
    _applyBadgeCheck();
    await _storage.saveUserStats(_stats);
    notifyListeners();
    _pushToSupabase();
  }

  int get studyMinutesToday {
    final s = _rolloverDailyIfNeeded(_stats);
    return s.studySecondsToday ~/ 60;
  }

  int get totalStudyMinutes => _stats.totalStudySeconds ~/ 60;

  List<MapEntry<String, int>> getWeeklyXp() {
    const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final entries = <MapEntry<String, int>>[];
    for (int i = 6; i >= 0; i--) {
      final date = DateTime.now().subtract(Duration(days: i));
      final key = _keyForOffset(i);
      final label = weekdayLabels[date.weekday - 1];
      entries.add(MapEntry(label, _stats.dailyXp[key] ?? 0));
    }
    return entries;
  }

  List<MapEntry<String, double>> getWeeklyAccuracy() {
    const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final entries = <MapEntry<String, double>>[];
    for (int i = 6; i >= 0; i--) {
      final date = DateTime.now().subtract(Duration(days: i));
      final key = _keyForOffset(i);
      final label = weekdayLabels[date.weekday - 1];
      final pair = _stats.dailyAccuracy[key];
      final pct = (pair != null && pair[1] > 0) ? (pair[0] / pair[1] * 100) : 0.0;
      entries.add(MapEntry(label, pct));
    }
    return entries;
  }

  int get weeklyXpTotal => getWeeklyXp().fold(0, (a, e) => a + e.value);
}

/// =========================================================================
/// 🎨 BADGE ANNOUNCEMENT  — redesigned
/// =========================================================================

void showBadgeAnnouncementIfAny(BuildContext context, AppProvider provider) {
  final badge = provider.pendingBadgeAnnouncement;
  if (badge == null) return;
  provider.clearBadgeAnnouncement();
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFB020), Color(0xFFFF8A00)]),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: kGoldAccent.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 12))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), shape: BoxShape.circle),
              child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            const Text('Badge Earned!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 6),
            Text('"$badge" 🎉', style: const TextStyle(color: Colors.white, fontSize: 15), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kGoldAccent),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Nice!', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// =========================================================================
/// 🎉 CELEBRATION DIALOG — redesigned
/// =========================================================================

Future<void> showCelebrationDialog(
  BuildContext context, {
  required int score,
  required int total,
  required int xpEarned,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CelebrationDialog(score: score, total: total, xpEarned: xpEarned),
  );
}

class _CelebrationDialog extends StatefulWidget {
  final int score;
  final int total;
  final int xpEarned;
  const _CelebrationDialog({required this.score, required this.total, required this.xpEarned});

  @override
  State<_CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<_CelebrationDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _headline {
    if (widget.total == 0) return 'Great effort!';
    final pct = widget.score / widget.total * 100;
    if (pct >= 90) return 'Outstanding! 🌟';
    if (pct >= 70) return 'Great job! 🎉';
    if (pct >= 50) return 'Well done! 👍';
    return 'Keep practising! 💪';
  }

  int get _stars {
    if (widget.total == 0) return 1;
    final pct = widget.score / widget.total * 100;
    if (pct >= 90) return 3;
    if (pct >= 60) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.25), blurRadius: 30, offset: const Offset(0, 14))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final filled = i < _stars;
                  return Icon(Icons.star_rounded, size: 44, color: filled ? kGoldAccent : Colors.grey.shade200);
                }),
              ),
              const SizedBox(height: 16),
              Text(_headline, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('You scored ${widget.score} out of ${widget.total}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFFB020), Color(0xFFFF8A00)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('+${widget.xpEarned} XP', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 18),
              Text('"${QuoteService.getRandomQuote()}"',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
              const SizedBox(height: 22),
              GradientButton(label: 'Continue', onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// 🏆 LEADERBOARD SCREEN — redesigned
/// =========================================================================

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late Future<List<LeaderboardEntry>> _topFuture;
  late Future<MapEntry<int, LeaderboardEntry>?> _myRankFuture;
  late Future<int> _totalPlayersFuture;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _loadAll() {
    _topFuture = LeaderboardService().getTopEntries();
    _myRankFuture = LeaderboardService().getMyRank();
    _totalPlayersFuture = LeaderboardService().getTotalPlayers();
  }

  Future<void> _refresh() async {
    setState(_loadAll);
    await Future.wait([_topFuture, _myRankFuture, _totalPlayersFuture]);
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: GradientHeader(
                title: '🏆 Leaderboard',
                subtitle: 'Top students, ranked by XP',
                trailing: FutureBuilder<int>(
                  future: _totalPlayersFuture,
                  builder: (context, s) => s.data == null ? const SizedBox.shrink() : GlassPill(icon: Icons.groups_rounded, value: '${s.data}'),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: FutureBuilder<MapEntry<int, LeaderboardEntry>?>(
                future: _myRankFuture,
                builder: (context, myRankSnapshot) {
                  final data = myRankSnapshot.data;
                  if (data == null) return const SizedBox.shrink();
                  final myRank = data.key;
                  final myEntry = data.value;
                  final inTop = myRank <= LeaderboardService.topEntriesLimit;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: ShinyCard(
                      tint: Theme.of(context).colorScheme.primary,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(gradient: AppTheme.heroGradient(context), shape: BoxShape.circle),
                            child: const Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Your Rank', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                                Text('#$myRank', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              ],
                            ),
                          ),
                          if (inTop)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: kTealAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                              child: Text('In Top 7', style: TextStyle(color: kTealAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                          const SizedBox(width: 10),
                          Text('${myEntry.xp} XP', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Text('Top ${LeaderboardService.topEntriesLimit}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ),
            FutureBuilder<List<LeaderboardEntry>>(
              future: _topFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));
                }
                final entries = snapshot.data ?? [];
                if (entries.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: Center(child: Text('No entries yet. Be the first!', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                    ),
                  );
                }
                final medalColors = [const Color(0xFFFFD700), const Color(0xFFC0C0C0), const Color(0xFFCD7F32)];
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final e = entries[i];
                        final isTop3 = i < 3;
                        final isMe = e.userId == myUserId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ShinyCard(
                            padding: const EdgeInsets.all(14),
                            tint: isMe ? Theme.of(context).colorScheme.primary : (isTop3 ? medalColors[i] : null),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: isTop3 ? medalColors[i] : Theme.of(context).colorScheme.primary.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text('${i + 1}',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: isTop3 ? Colors.white : Theme.of(context).colorScheme.primary)),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(e.avatarEmoji ?? '🙂', style: const TextStyle(fontSize: 14)),
                                          const SizedBox(width: 6),
                                          Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                          if (isMe) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(gradient: AppTheme.heroGradient(context), borderRadius: BorderRadius.circular(8)),
                                              child: const Text('You', style: TextStyle(fontSize: 10, color: Colors.white)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      Text('${rankTitleForLevel(e.level)} (Lv. ${e.level}) • 🔥${e.streak}d',
                                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                                Text('${e.xp} XP', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: entries.length,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// 📝 MOCK EXAM SCREEN — redesigned
/// =========================================================================

class MockExamScreen extends StatefulWidget {
  const MockExamScreen({super.key});

  @override
  State<MockExamScreen> createState() => _MockExamScreenState();
}

class _MockExamScreenState extends State<MockExamScreen> {
  final List<String> selectedSubjects = [];
  int perSubjectCount = 20;
  bool started = false;

  static const int maxSubjects = 4;

  void _toggleSubject(String subject) {
    setState(() {
      if (selectedSubjects.contains(subject)) {
        selectedSubjects.remove(subject);
      } else if (selectedSubjects.length < maxSubjects) {
        selectedSubjects.add(subject);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final subjects = provider.getAvailableSubjects();

    if (started) return _buildExam(context, provider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: GradientHeader(title: '📝 Mock Exam', subtitle: 'Simulate the real thing')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Choose up to $maxSubjects subjects (${selectedSubjects.length}/$maxSubjects)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('Great for practising subject combinations together.',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: subjects.map((s) {
                      final isSelected = selectedSubjects.contains(s);
                      final disabled = !isSelected && selectedSubjects.length >= maxSubjects;
                      return _SelectChip(label: s, selected: isSelected, disabled: disabled, onTap: () => _toggleSubject(s));
                    }).toList(),
                  ),
                  const SizedBox(height: 22),
                  ShinyCard(
                    child: DropdownButtonFormField<int>(
                      initialValue: perSubjectCount,
                      items: const [
                        DropdownMenuItem(value: 10, child: Text('10 questions per subject')),
                        DropdownMenuItem(value: 15, child: Text('15 questions per subject')),
                        DropdownMenuItem(value: 20, child: Text('20 questions per subject')),
                        DropdownMenuItem(value: 25, child: Text('25 questions per subject')),
                      ],
                      onChanged: (val) => setState(() => perSubjectCount = val!),
                      decoration: const InputDecoration(labelText: 'Questions per subject', border: InputBorder.none),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (selectedSubjects.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('Total: ${selectedSubjects.length * perSubjectCount} questions',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                    ),
                  GradientButton(
                    label: 'Start Mock Exam',
                    icon: Icons.play_arrow_rounded,
                    onPressed: selectedSubjects.isEmpty ? null : () => setState(() => started = true),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExam(BuildContext context, AppProvider provider) {
    final questions = provider.generateMockExamMulti(selectedSubjects, perSubjectCount);
    final subjectsLabel = selectedSubjects.join(' + ');
    return QuizScreen(
      questions: questions,
      title: 'Mock Exam — $subjectsLabel',
      onComplete: (score) {
        Navigator.pop(context);
      },
      onCompleteDetailed: (gradedQuestions) {
        final Map<String, int> correctBySubject = {};
        final Map<String, int> totalBySubject = {};
        int overallScore = 0;

        for (final gq in gradedQuestions) {
          final subject = gq['subject'] as String? ?? 'Unknown';
          final wasCorrect = gq['__correct'] as bool? ?? false;
          totalBySubject[subject] = (totalBySubject[subject] ?? 0) + 1;
          if (wasCorrect) {
            correctBySubject[subject] = (correctBySubject[subject] ?? 0) + 1;
            overallScore++;
          }
        }

        for (final subject in selectedSubjects) {
          provider.recordAnswer(subject, correctBySubject[subject] ?? 0, totalBySubject[subject] ?? 0);
        }
        provider.addXP(overallScore * 2);

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('You scored $overallScore out of ${gradedQuestions.length}'),
          backgroundColor: overallScore >= (gradedQuestions.length * 0.6) ? kTealAccent : kCoralAccent,
        ));
      },
    );
  }
}

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  const _SelectChip({required this.label, required this.selected, required this.disabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: disabled ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? AppTheme.heroGradient(context) : null,
            color: selected ? null : (disabled ? scheme.surfaceContainerHighest.withOpacity(0.5) : scheme.surfaceContainerHighest),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? Colors.transparent : scheme.outlineVariant),
            boxShadow: selected ? [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))] : null,
          ),
          child: Text(label,
              style: TextStyle(
                color: selected ? Colors.white : (disabled ? scheme.onSurfaceVariant.withOpacity(0.5) : scheme.onSurface),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              )),
        ),
      ),
    );
  }
}

/// =========================================================================
/// ❓ QUIZ SCREEN — redesigned (reusable for daily challenge and mock exams)
/// =========================================================================
class QuizScreen extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  final String title;
  final void Function(int score) onComplete;
  final void Function(List<Map<String, dynamic>> gradedQuestions)? onCompleteDetailed;
  final bool showCalculator;
  final bool showNavigator;

  const QuizScreen({
    super.key,
    required this.questions,
    required this.title,
    required this.onComplete,
    this.onCompleteDetailed,
    this.showCalculator = false,
    this.showNavigator = false,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late List<Map<String, dynamic>> shuffledQuestions;
  late List<int?> _selectedAnswers;
  int _currentIndex = 0;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    shuffledQuestions = List<Map<String, dynamic>>.from(widget.questions)..shuffle();
    _selectedAnswers = List<int?>.filled(shuffledQuestions.length, null);
  }

  void _selectOption(int i) {
    setState(() => _selectedAnswers[_currentIndex] = i);
  }

  void _goTo(int index) {
    if (index < 0 || index >= shuffledQuestions.length) return;
    setState(() => _currentIndex = index);
  }

  void _openNavigator() {
    final statuses = _selectedAnswers
        .map((a) => a != null ? QuestionStatus.answered : QuestionStatus.unanswered)
        .toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuestionNavigatorSheet(
        totalQuestions: shuffledQuestions.length,
        statuses: statuses,
        currentIndex: _currentIndex,
        onSelect: (index) {
          Navigator.pop(context);
          _goTo(index);
        },
      ),
    );
  }

  void _openCalculator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _JambCalculatorSheet(),
    );
  }

  Future<void> _confirmEarlySubmit() async {
    final answered = _selectedAnswers.where((a) => a != null).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Submit Exam?'),
        content: Text('You have answered $answered of ${shuffledQuestions.length} questions. Submit now?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed == true) _finish();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    int score = 0;
    final graded = <Map<String, dynamic>>[];
    for (int i = 0; i < shuffledQuestions.length; i++) {
      final q = shuffledQuestions[i];
      final isCorrect = _selectedAnswers[i] != null && _selectedAnswers[i] == q['correctIndex'];
      if (isCorrect) score++;
      graded.add({...q, '__correct': isCorrect});
    }

    await showCelebrationDialog(context, score: score, total: shuffledQuestions.length, xpEarned: score * 2);
    if (!mounted) return;

    if (widget.onCompleteDetailed != null) {
      widget.onCompleteDetailed!(graded);
    } else {
      widget.onComplete(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (shuffledQuestions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: Text('No questions available for this selection.')),
      );
    }

    final q = shuffledQuestions[_currentIndex];
    final options = List<String>.from(q['options']);
    final answeredCount = _selectedAnswers.where((a) => a != null).length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Compact gradient progress header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              decoration: BoxDecoration(gradient: AppTheme.heroGradient(context)),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(widget.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (widget.showCalculator)
                        IconButton(onPressed: _openCalculator, icon: const Icon(Icons.calculate_outlined, color: Colors.white)),
                      if (widget.showNavigator)
                        IconButton(onPressed: _openNavigator, icon: const Icon(Icons.grid_view_rounded, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: answeredCount / shuffledQuestions.length,
                      minHeight: 8,
                      backgroundColor: Colors.white.withOpacity(0.25),
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Question ${_currentIndex + 1} of ${shuffledQuestions.length}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      if (q['subject'] != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                          child: Text(q['subject'] as String, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: SingleChildScrollView(
                  key: ValueKey(_currentIndex),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShinyCard(
                        child: Text(q['question'] as String, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
                      ),
                      const SizedBox(height: 18),
                      ...List.generate(options.length, (i) {
                        final isSelected = _selectedAnswers[_currentIndex] == i;
                        final letter = String.fromCharCode(65 + i);
                        final scheme = Theme.of(context).colorScheme;
                        final isDark = Theme.of(context).brightness == Brightness.dark;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => _selectOption(i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  gradient: isSelected ? AppTheme.heroGradient(context) : null,
                                  color: isSelected ? null : scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: isDark
                                      ? null
                                      : [
                                          BoxShadow(
                                            color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.35) : Colors.black.withOpacity(0.05),
                                            blurRadius: isSelected ? 16 : 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: isSelected ? Colors.white.withOpacity(0.25) : scheme.surface,
                                      child: Text(letter,
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : scheme.onSurfaceVariant)),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(options[i],
                                          style: TextStyle(fontSize: 15, color: isSelected ? Colors.white : scheme.onSurface)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _currentIndex > 0 ? () => _goTo(_currentIndex - 1) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: const Text('Previous'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _currentIndex == shuffledQuestions.length - 1
                        ? GradientButton(label: 'Finish', icon: Icons.check_rounded, onPressed: _finishing ? null : _finish, height: 48)
                        : GradientButton(label: 'Next', icon: Icons.chevron_right_rounded, onPressed: () => _goTo(_currentIndex + 1), height: 48),
                  ),
                ],
              ),
            ),
            if (widget.showNavigator && _currentIndex != shuffledQuestions.length - 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(onPressed: _finishing ? null : _confirmEarlySubmit, child: const Text('Submit Now')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _JambCalculatorSheet extends StatefulWidget {
  const _JambCalculatorSheet();

  @override
  State<_JambCalculatorSheet> createState() => _JambCalculatorSheetState();
}

class _JambCalculatorSheetState extends State<_JambCalculatorSheet> {
  String _display = '0';
  double? _stored;
  String? _pendingOp;
  bool _shouldResetDisplay = false;

  void _inputDigit(String digit) {
    setState(() {
      if (_display == '0' || _shouldResetDisplay) {
        _display = digit;
        _shouldResetDisplay = false;
      } else {
        _display += digit;
      }
    });
  }

  void _inputDecimal() {
    setState(() {
      if (_shouldResetDisplay) {
        _display = '0.';
        _shouldResetDisplay = false;
        return;
      }
      if (!_display.contains('.')) _display += '.';
    });
  }

  void _clear() {
    setState(() {
      _display = '0';
      _stored = null;
      _pendingOp = null;
      _shouldResetDisplay = false;
    });
  }

  void _setOperator(String op) {
    setState(() {
      _stored = double.tryParse(_display) ?? 0;
      _pendingOp = op;
      _shouldResetDisplay = true;
    });
  }

  void _equals() {
    if (_pendingOp == null || _stored == null) return;
    final current = double.tryParse(_display) ?? 0;
    double result;
    switch (_pendingOp) {
      case '+':
        result = _stored! + current;
        break;
      case '-':
        result = _stored! - current;
        break;
      case '×':
        result = _stored! * current;
        break;
      case '÷':
        result = current == 0 ? 0 : _stored! / current;
        break;
      default:
        result = current;
    }
    setState(() {
      _display = result == result.roundToDouble() ? result.toInt().toString() : result.toString();
      _stored = null;
      _pendingOp = null;
      _shouldResetDisplay = true;
    });
  }

  Widget _button(String label, {Gradient? gradient, Color? fg, VoidCallback? onTap}) {
    return Builder(builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AspectRatio(
            aspectRatio: 1.3,
            child: Material(
              color: gradient == null ? scheme.surfaceContainerHighest : null,
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(16)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap ?? () => _inputDigit(label),
                  child: Center(
                    child: Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: fg ?? scheme.onSurface)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(width: 44, height: 4, decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(4))),
          ),
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerLeft, child: Text('Calculator', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: AppTheme.heroGradient(context), borderRadius: BorderRadius.circular(18)),
            alignment: Alignment.centerRight,
            child: Text(_display, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(height: 14),
          Row(children: [_button('7'), _button('8'), _button('9'), _button('÷', gradient: AppTheme.heroGradient(context), fg: Colors.white, onTap: () => _setOperator('÷'))]),
          Row(children: [_button('4'), _button('5'), _button('6'), _button('×', gradient: AppTheme.heroGradient(context), fg: Colors.white, onTap: () => _setOperator('×'))]),
          Row(children: [_button('1'), _button('2'), _button('3'), _button('-', gradient: AppTheme.heroGradient(context), fg: Colors.white, onTap: () => _setOperator('-'))]),
          Row(children: [
            _button('C', gradient: const LinearGradient(colors: [kCoralAccent, Color(0xFFE04848)]), fg: Colors.white, onTap: _clear),
            _button('0'),
            _button('.', onTap: _inputDecimal),
            _button('+', gradient: AppTheme.heroGradient(context), fg: Colors.white, onTap: () => _setOperator('+')),
          ]),
          const SizedBox(height: 8),
          GradientButton(label: '=', onPressed: _equals, height: 52),
        ],
      ),
    );
  }
}

/// =========================================================================
/// 👤 PROFILE SCREEN — redesigned
/// =========================================================================

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  static const Map<String, String> _badgeDescriptions = {
    'Getting Started': 'Reached a 3-day streak',
    'Streak Master': 'Reached a 7-day streak',
    'Unstoppable': 'Reached a 30-day streak',
    'Scholar': 'Earned 1,000 XP',
    'Sage': 'Earned 5,000 XP',
    'Rising Star': 'Reached Level 5',
    'Grandmaster': 'Reached Level 10',
    'Legend': 'Reached Level 25',
    'Subject Expert': 'Gold mastery in a subject',
    'Subject Master': 'Gold mastery in 5 subjects',
    'Polymath': 'Gold mastery in 10 subjects',
    'Century Club': 'Answered 100 questions',
    'Marathoner': 'Answered 500 questions',
    'Iron Will': 'Answered 2,000 questions',
    'Well Rounded': 'Practiced every subject at least once',
    'Goal Getter': 'Met your daily goal 7 times',
    'Goal Crusher': 'Met your daily goal 30 times',
    'Study Buddy': 'Studied 60+ minutes with the timer',
    'Study Master': 'Studied 500+ minutes with the timer',
    'Quiz Regular': 'Completed 10 quizzes',
    'Quiz Champion': 'Completed 50 quizzes',
    'Perfectionist': '100% accuracy in a subject (10+ attempts)',
    'Battle Winner': 'Won a Live Quiz Battle',
    'Battle Champion': 'Won 10 Live Quiz Battles',
  };

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final stats = provider.stats;
    final coinService = context.watch<CoinService>();
    final frameColor = CoinService.frameColorFor(coinService.equippedFrameId);
    final titleLabel = CoinService.titleLabelFor(coinService.equippedTitleId);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 32),
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient(context),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Material(
                      color: Colors.white.withOpacity(0.16),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).maybePop(),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: frameColor ?? Colors.white, width: 4),
                      boxShadow: frameColor != null ? [BoxShadow(color: frameColor.withOpacity(0.6), blurRadius: 16, spreadRadius: 1)] : null,
                    ),
                    child: Center(child: Text(provider.avatarEmoji, style: const TextStyle(fontSize: 42))),
                  ),
                  const SizedBox(height: 14),
                  Text(provider.userName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  if (titleLabel != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                      child: Text(titleLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      _StatChip(label: 'Rank', value: rankTitleForLevel(stats.level), subtitle: 'Lv. ${stats.level}', color: rankColor(stats.level)),
                      const SizedBox(width: 10),
                      _StatChip(label: 'XP', value: '${stats.xp}', color: kGoldAccent),
                      const SizedBox(width: 10),
                      _StatChip(label: 'Streak', value: '${stats.streak}', color: kCoralAccent),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StatChip(label: 'Study (min)', value: '${provider.totalStudyMinutes}', color: kTealAccent),
                      const SizedBox(width: 10),
                      _StatChip(label: 'Quizzes', value: '${stats.quizzesCompleted}', color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 10),
                      _StatChip(label: 'Goals Met', value: '${stats.goalsMetCount}', color: const Color(0xFFEC4899)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ShinyCard(
                    tint: kTealAccent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.flag_rounded, size: 20, color: kTealAccent),
                            const SizedBox(width: 8),
                            const Text("Today's Goal", style: TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            TextButton(
                              onPressed: () => showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => const GoalSelectorSheet(),
                              ),
                              child: const Text('Change'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: provider.dailyGoalProgress,
                            minHeight: 10,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(provider.dailyGoalMet ? kTealAccent : Theme.of(context).colorScheme.primary),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(dailyGoalStatusText(provider), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Align(alignment: Alignment.centerLeft, child: Text('🎖️ Subject Mastery', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                  const SizedBox(height: 10),
                  ...provider.getAvailableSubjects().map((sub) {
                    final tier = provider.getSubjectMastery(sub);
                    final attempts = stats.subjectAttempts[sub] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ShinyCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.shield_rounded, color: masteryColor(tier), size: 22),
                            const SizedBox(width: 10),
                            Expanded(child: Text(sub)),
                            Text(attempts < 10 ? 'Locked (10 needed)' : masteryLabel(tier),
                                style: TextStyle(fontWeight: FontWeight.bold, color: masteryColor(tier), fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  Align(alignment: Alignment.centerLeft, child: Text('🏅 Badges', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                  const SizedBox(height: 10),
                  stats.badges.isEmpty
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Text('No badges yet — keep practising!', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
                      : Column(
                          children: stats.badges.map((b) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ShinyCard(
                                tint: kGoldAccent,
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: kGoldAccent.withOpacity(0.15), shape: BoxShape.circle),
                                      child: const Icon(Icons.emoji_events_rounded, color: kGoldAccent, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(b, style: const TextStyle(fontWeight: FontWeight.w700)),
                                          if (_badgeDescriptions[b] != null)
                                            Text(_badgeDescriptions[b]!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                  const SizedBox(height: 24),
                  ShinyCard(
                    child: TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Change your name',
                        border: InputBorder.none,
                        suffixIcon: IconButton(
                          icon: Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary),
                          onPressed: () {
                            if (_nameController.text.trim().isNotEmpty) {
                              provider.setUserName(_nameController.text);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name updated!')));
                              _nameController.clear();
                            }
                          },
                        ),
                      ),
                      onSubmitted: (val) {
                        provider.setUserName(val);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name updated!')));
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String? subtitle;
  const _StatChip({required this.label, required this.value, required this.color, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
            if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 10, color: color.withOpacity(0.85))),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: color), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// 📊 ANALYTICS SCREEN — redesigned
/// =========================================================================

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final stats = provider.stats;
    final weeklyXp = provider.getWeeklyXp();
    final maxWeeklyXp = weeklyXp.fold<int>(1, (m, e) => e.value > m ? e.value : m);
    final weeklyAcc = provider.getWeeklyAccuracy();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: GradientHeader(title: '📊 Analytics', subtitle: 'Your performance, at a glance')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                children: [
                  ShinyCard(
                    tint: Theme.of(context).colorScheme.primary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Overall Performance', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _statLine(context, 'Total XP', '${stats.xp}'),
                        _statLine(context, 'Rank', '${rankTitleForLevel(stats.level)} (Lv. ${stats.level})'),
                        _statLine(context, 'Streak', '${stats.streak} days'),
                        _statLine(context, 'Badges earned', '${stats.badges.length}'),
                        _statLine(context, 'Questions attempted', '${stats.subjectAttempts.values.fold(0, (a, b) => a + b)}'),
                        _statLine(context, 'Study time', '${provider.totalStudyMinutes} minutes'),
                        _statLine(context, 'Quizzes completed', '${stats.quizzesCompleted}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ShinyCard(
                    tint: kTealAccent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('This Week', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text('${provider.weeklyXpTotal} XP', style: const TextStyle(color: kTealAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 100,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: weeklyXp.map((e) {
                              final heightFactor = maxWeeklyXp == 0 ? 0.0 : e.value / maxWeeklyXp;
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text('${e.value}', style: const TextStyle(fontSize: 10)),
                                      const SizedBox(height: 4),
                                      Container(
                                        height: 50 * heightFactor + 6,
                                        decoration: BoxDecoration(gradient: AppTheme.heroGradient(context), borderRadius: BorderRadius.circular(6)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(e.key, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text('Weekly Accuracy', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        ...weeklyAcc.map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  SizedBox(width: 32, child: Text(e.key, style: const TextStyle(fontSize: 11))),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: (e.value / 100).clamp(0.0, 1.0),
                                        minHeight: 8,
                                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        valueColor: const AlwaysStoppedAnimation(kTealAccent),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(width: 36, child: Text('${e.value.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11))),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(alignment: Alignment.centerLeft, child: Text('Subject Breakdown', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                  const SizedBox(height: 10),
                  ...provider.getAvailableSubjects().map((sub) {
                    final score = provider.getSubjectScore(sub);
                    final attempted = stats.subjectAttempts[sub] ?? 0;
                    final tier = provider.getSubjectMastery(sub);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ShinyCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(score >= 70 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                    color: score >= 70 ? kTealAccent : kGoldAccent, size: 20),
                                const SizedBox(width: 10),
                                Expanded(child: Text(sub, style: const TextStyle(fontWeight: FontWeight.w600))),
                                Text('${score.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('$attempted attempted • ${masteryLabel(tier)}', style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: (score / 100).clamp(0.0, 1.0),
                                minHeight: 6,
                                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation(masteryColor(tier)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statLine(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// =========================================================================
/// 🎯 GOAL SELECTOR SHEET — redesigned
/// =========================================================================

class GoalSelectorSheet extends StatelessWidget {
  const GoalSelectorSheet({super.key});

  static const List<int> _options = [5, 10, 20, 30, 50];

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 16),
          Text('Set Daily Goal', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('How many questions do you want to answer each day?', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _options.map((opt) {
              final isSelected = provider.dailyGoalQuestions == opt;
              return _SelectChip(
                label: '$opt questions',
                selected: isSelected,
                disabled: false,
                onTap: () {
                  provider.setDailyGoal(opt);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// =========================================================================
/// ⏱️ STUDY TIMER SCREEN — redesigned
/// =========================================================================

class StudyTimerScreen extends StatefulWidget {
  const StudyTimerScreen({super.key});

  @override
  State<StudyTimerScreen> createState() => _StudyTimerScreenState();
}

class _StudyTimerScreenState extends State<StudyTimerScreen> {
  Timer? _ticker;
  int _elapsedSeconds = 0;
  bool _running = false;
  final String _quote = QuoteService.getRandomQuote();

  static const int _maxXpEligibleMinutesPerSession = 120;

  void _toggle() {
    if (_running) {
      _ticker?.cancel();
      setState(() => _running = false);
    } else {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsedSeconds++);
      });
      setState(() => _running = true);
    }
  }

  Future<void> _saveSession() async {
    _ticker?.cancel();
    final seconds = _elapsedSeconds;
    if (seconds > 0) {
      final provider = context.read<AppProvider>();
      await provider.addStudySeconds(seconds);

      final minutes = (seconds / 60).ceil();
      final xpEligibleMinutes = minutes > _maxXpEligibleMinutesPerSession ? _maxXpEligibleMinutesPerSession : minutes;
      final xpEarned = xpEligibleMinutes * 2;
      if (xpEarned > 0) {
        await provider.addXP(xpEarned);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $minutes minute${seconds >= 120 ? 's' : ''} of study time (+$xpEarned XP).')),
      );
    }
    if (!mounted) return;
    setState(() {
      _elapsedSeconds = 0;
      _running = false;
    });
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _elapsedSeconds = 0;
      _running = false;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _formatted {
    final h = (_elapsedSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((_elapsedSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              GlassPillOnLight(icon: Icons.school_rounded, text: 'Today: ${provider.studyMinutesToday} min • All-time: ${provider.totalStudyMinutes} min'),
              const SizedBox(height: 10),
              Text('Earn 2 XP per minute studied (up to 120 min per session)',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
              const SizedBox(height: 30),
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.heroGradient(context),
                  boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: Center(
                  child: Text(_formatted,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    child: GradientButton(label: _running ? 'Pause' : 'Start', icon: _running ? Icons.pause_rounded : Icons.play_arrow_rounded, onPressed: _toggle),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 60,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _elapsedSeconds == 0 ? null : _reset,
                      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _elapsedSeconds == 0 ? null : _saveSession,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save Session'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                ),
              ),
              const Spacer(),
              Text('"$_quote"', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glassy pill for use on a light (non-gradient) background.
class GlassPillOnLight extends StatelessWidget {
  final IconData icon;
  final String text;
  const GlassPillOnLight({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
        ],
      ),
    );
  }
}

/// =========================================================================
/// 📅 WEEKLY STATS SCREEN — redesigned
/// =========================================================================

class WeeklyStatsScreen extends StatelessWidget {
  const WeeklyStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final weeklyXp = provider.getWeeklyXp();
    final weeklyAcc = provider.getWeeklyAccuracy();
    final maxXp = weeklyXp.fold<int>(1, (m, e) => e.value > m ? e.value : m);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: GradientHeader(title: '📅 Weekly Stats', subtitle: 'Your last 7 days')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                children: [
                  ShinyCard(
                    tint: kGoldAccent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('XP This Week', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('${provider.weeklyXpTotal} total XP', style: const TextStyle(color: kGoldAccent, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        ...weeklyXp.map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(width: 36, child: Text(e.key, style: const TextStyle(fontSize: 12))),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: maxXp == 0 ? 0 : e.value / maxXp,
                                        minHeight: 12,
                                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        valueColor: const AlwaysStoppedAnimation(kGoldAccent),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(width: 40, child: Text('${e.value}', style: const TextStyle(fontSize: 12))),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ShinyCard(
                    tint: kTealAccent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Accuracy This Week', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 16),
                        ...weeklyAcc.map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(width: 36, child: Text(e.key, style: const TextStyle(fontSize: 12))),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: (e.value / 100).clamp(0.0, 1.0),
                                        minHeight: 12,
                                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        valueColor: AlwaysStoppedAnimation(e.value >= 70 ? kTealAccent : (e.value >= 50 ? kGoldAccent : kCoralAccent)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(width: 40, child: Text('${e.value.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12))),
                                ],
                              ),
                            )),
                      ],
                    ),
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
