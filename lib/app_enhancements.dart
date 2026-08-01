// lib/app_enhancements.dart
// Gamification layer for NaijaLearn: XP, streaks, badges, leaderboard,
// daily challenge, mock exams, subject mastery tiers, profile, analytics.
//
// This file does NOT define its own app shell, HomeScreen, or MaterialApp —
// it plugs into main.dart's existing NaijaLearnApp via AppProvider.
//
// Leaderboard is backed by Supabase (table: leaderboard_entries) so it's
// a real shared leaderboard across users, not on-device-only storage.
// Every user's own row is upserted automatically whenever their XP
// changes (see AppProvider._syncLeaderboard), keyed by their Supabase
// user id — not by display name, so duplicate/changed names never cause
// duplicate rows or a broken "Your Rank" lookup.
//
// UserStats itself (XP, streak, badges, daily goal, study time, dark
// mode, avatar) is now ALSO backed by Supabase (table: user_stats), via
// UserStatsSyncService. SharedPreferences is kept as a fast local cache
// so the UI has something to show instantly on launch, but Supabase is
// the source of truth: on startup, AppProvider pulls the remote row (if
// one exists) and overwrites the local cache with it; every mutation
// (addXP, recordAnswer, dark mode toggle, avatar change, daily goal,
// study seconds, battle wins) pushes the updated stats back up,
// fire-and-forget, the same way the leaderboard sync already works.
// If no remote row exists yet (brand-new account, or first launch after
// this feature shipped), the current local data is pushed up instead so
// the remote row gets seeded rather than silently staying empty.
//
// STREAK FREEZE: StreakService.checkStreak now consults CoinService
// (features5.dart) before resetting a streak after a missed day. If the
// user owns at least one Streak Freeze, one is consumed and the streak
// is preserved instead of reset to zero — making the Coin Shop's Streak
// Freeze item actually functional instead of a no-op purchase.
//
// EQUIPPED FRAME/TITLE: ProfileScreen now reads CoinService's equipped
// frame and title (set from the Coin Shop) and renders them on the
// avatar and name — so those purchases are visibly, permanently useful
// rather than sitting unseen in an "owned items" list.

import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import 'questions_english.dart';
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

/// =========================================================================
/// DATA MODELS
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

/// Mastery tier for a single subject, based on accuracy across attempts.
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

/// Competitive rank title for a given level — shown instead of a bare
/// "Level N" so progress feels more like climbing ranks in a game.
/// The numeric level is still shown alongside it as a small subtitle
/// wherever this is displayed.
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
/// SERVICES
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
}

class StreakService {
  /// Advances or resets the streak based on how many days have passed
  /// since lastActive. On a missed day (gap > 1 day), a Streak Freeze
  /// (CoinService) is consumed automatically if the user owns one —
  /// preserving the current streak count instead of resetting it to
  /// zero. If no freeze is available, the streak resets as before.
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
        // Streak preserved — just bump lastActive so we don't re-check
        // (and re-consume another freeze) on the very next launch today.
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

  /// Checks all badge conditions and returns the updated badge list.
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

/// Random motivational quotes, shown around the app (home card, celebration
/// dialog, study timer).
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

/// Real, shared leaderboard backed by Supabase — replaces the old
/// on-device-only version, which could never show anyone else's scores
/// and was never actually being written to.
class LeaderboardService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<List<LeaderboardEntry>> getTopEntries({int limit = 50}) async {
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

/// Persists the full UserStats blob (plus dark mode + avatar) to Supabase
/// (table: user_stats) so progress follows the user across devices
/// instead of staying stuck on-device in SharedPreferences. Mirrors the
/// same fire-and-forget pattern already used for the leaderboard sync —
/// failures are logged, never surfaced to the user, since this must
/// never block normal app usage.
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
/// APP PROVIDER (state management)
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
    _stats = await _streak.checkStreak(_stats);

    if (_stats.streak > 0 && _stats.questionsToday == 0 && DateTime.now().hour >= 17) {
      NotificationService.instance.showStreakAtRisk(_stats.streak);
    }
    
    _stats = _rolloverDailyIfNeeded(_stats);
    await _storage.saveUserStats(_stats);

    // Local cache is loaded above so the UI has something to show right
    // away. Now reconcile with Supabase — the real source of truth.
    await _pullFromSupabase();

    _loadOrGenerateDailyChallenge();
    notifyListeners();
  }

  /// Pulls this user's stats/dark-mode/avatar from Supabase on startup so
  /// progress follows them across devices. If no remote row exists yet
  /// (brand-new account, or first launch after this feature shipped),
  /// the current local data is pushed up instead so the remote row gets
  /// seeded rather than silently staying empty.
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

  /// Fire-and-forget push of the current stats/dark-mode/avatar to
  /// Supabase. Called after every mutation below.
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

  /// Pushes the current XP/level/streak/name/avatar to the shared Supabase
  /// leaderboard. Fire-and-forget — failures are logged, never surfaced
  /// to the user, since this should never block normal app usage.
  Future<void> _syncLeaderboard() async {
    await _leaderboard.upsertEntry(name: _userName, stats: _stats, avatarEmoji: _avatarEmoji);
  }

  /// Public trigger for an immediate leaderboard sync — call once after
  /// login so a fresh account shows up right away.
  Future<void> syncLeaderboardNow() => _syncLeaderboard();

  /// Sets and persists the player's chosen avatar emoji (unlocked via
  /// Career Mode), and syncs it to the shared leaderboard and stats table.
  Future<void> setAvatarEmoji(String emoji) async {
    _avatarEmoji = emoji;
    await _storage.saveAvatarEmoji(emoji);
    notifyListeners();
    _syncLeaderboard();
    _pushToSupabase();
  }

  /// Pushes this subject's current best accuracy to the shared, per-subject
  /// Hall of Fame leaderboard. Skipped below 5 attempts to avoid noisy,
  /// low-sample entries. Fire-and-forget, like the main leaderboard sync.
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

  /// Records a Live Quiz Battle outcome — increments the win counter (which
  /// feeds the Battle Winner / Battle Champion badges) when the battle was
  /// won. XP for the battle is awarded separately by the caller.
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

  // =========================================================================
  // Daily goals, study timer, weekly stats helpers
  // =========================================================================

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

  /// Adds completed study time (in seconds) from the study timer. Note:
  /// this only tracks time — XP for studying is awarded separately by
  /// StudyTimerScreen calling addXP(), so the timer actually contributes
  /// to Rank/XP progress instead of just sitting there as a number.
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
/// BADGE ANNOUNCEMENT (call from HomeScreen after build)
/// =========================================================================

void showBadgeAnnouncementIfAny(BuildContext context, AppProvider provider) {
  final badge = provider.pendingBadgeAnnouncement;
  if (badge == null) return;
  provider.clearBadgeAnnouncement();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: const [
          Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 28),
          SizedBox(width: 10),
          Text('Badge Earned!'),
        ],
      ),
      content: Text('You just unlocked "$badge" 🎉', style: const TextStyle(fontSize: 16)),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nice!')),
      ],
    ),
  );
}

/// =========================================================================
/// CELEBRATION DIALOG (shown after quiz/exam completion)
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
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ScaleTransition(
        scale: _scale,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final filled = i < _stars;
                  return Icon(
                    Icons.star_rounded,
                    size: 40,
                    color: filled ? Colors.amber : scheme.surfaceContainerHighest,
                  );
                }),
              ),
              const SizedBox(height: 14),
              Text(_headline,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('You scored ${widget.score} out of ${widget.total}',
                  style: TextStyle(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Text('+${widget.xpEarned} XP', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
              Text('"${QuoteService.getRandomQuote()}"',
                  style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// LEADERBOARD SCREEN
/// =========================================================================

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late Future<List<LeaderboardEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = LeaderboardService().getTopEntries();
  }

  Future<void> _refresh() async {
    final next = LeaderboardService().getTopEntries();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final myUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('🏆 Leaderboard')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<LeaderboardEntry>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final entries = snapshot.data ?? [];
            int? myRank;
            LeaderboardEntry? myEntry;
            for (int i = 0; i < entries.length; i++) {
              if (entries[i].userId == myUserId) {
                myRank = i + 1;
                myEntry = entries[i];
                break;
              }
            }

            return Column(
              children: [
                if (myEntry != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [scheme.primary, scheme.primary.withOpacity(0.75)]),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Your Rank', style: TextStyle(color: Colors.white, fontSize: 12)),
                                Text('#$myRank of ${entries.length}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                          ),
                          Text('${myEntry.xp} XP', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: entries.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                            Center(
                              child: Text('No entries yet. Be the first!',
                                  style: TextStyle(color: scheme.onSurfaceVariant)),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            final e = entries[i];
                            final isTop3 = i < 3;
                            final isMe = e.userId == myUserId;
                            final medalColors = [Colors.amber, Colors.grey, Colors.brown];
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isMe ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                                border: isTop3 ? Border.all(color: medalColors[i], width: 1.6) : null,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isTop3 ? medalColors[i] : scheme.primaryContainer,
                                    child: Text('${i + 1}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isTop3 ? Colors.white : scheme.onPrimaryContainer)),
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
                                            Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                            if (isMe) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(
                                                    color: scheme.primary, borderRadius: BorderRadius.circular(8)),
                                                child: const Text('You',
                                                    style: TextStyle(fontSize: 10, color: Colors.white)),
                                              ),
                                            ],
                                          ],
                                        ),
                                        Text('${rankTitleForLevel(e.level)} (Lv. ${e.level}) • Streak ${e.streak} days',
                                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                  Text('${e.xp} XP', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary)),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// =========================================================================
/// MOCK EXAM SCREEN
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
    final scheme = Theme.of(context).colorScheme;
    final subjects = provider.getAvailableSubjects();

    return Scaffold(
      appBar: AppBar(title: const Text('📝 Mock Exam')),
      body: started
          ? _buildExam(context, provider)
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose up to $maxSubjects subjects (${selectedSubjects.length}/$maxSubjects selected)',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Great for practising subject combinations together.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: subjects.map((s) {
                      final isSelected = selectedSubjects.contains(s);
                      final disabled = !isSelected && selectedSubjects.length >= maxSubjects;
                      return FilterChip(
                        label: Text(s),
                        selected: isSelected,
                        onSelected: disabled ? null : (_) => _toggleSubject(s),
                        selectedColor: scheme.primaryContainer,
                        checkmarkColor: scheme.onPrimaryContainer,
                        disabledColor: scheme.surfaceContainerHighest.withOpacity(0.5),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: DropdownButtonFormField<int>(
                      initialValue: perSubjectCount,
                      items: const [
                        DropdownMenuItem(value: 10, child: Text('10 questions per subject')),
                        DropdownMenuItem(value: 15, child: Text('15 questions per subject')),
                        DropdownMenuItem(value: 20, child: Text('20 questions per subject')),
                        DropdownMenuItem(value: 25, child: Text('25 questions per subject')),
                      ],
                      onChanged: (val) => setState(() => perSubjectCount = val!),
                      decoration: const InputDecoration(labelText: 'Questions per subject'),
                    ),
                  ),
                  const Spacer(),
                  if (selectedSubjects.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Total: ${selectedSubjects.length * perSubjectCount} questions',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: selectedSubjects.isEmpty ? null : () => setState(() => started = true),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start Mock Exam'),
                    ),
                  ),
                ],
              ),
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
          backgroundColor: overallScore >= (gradedQuestions.length * 0.6) ? Colors.green : Colors.red,
        ));
      },
    );
  }
}

/// =========================================================================
/// QUIZ SCREEN (reusable — for daily challenge and mock exams)
/// =========================================================================
/// Redesigned to match the regular subject practice exams: selecting an
/// answer never reveals whether it's right or wrong, and Previous/Next
/// let you move freely between questions. Grading only happens once, when
/// "Finish" is tapped on the last question — nothing is graded early.
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

    await showCelebrationDialog(
      context,
      score: score,
      total: shuffledQuestions.length,
      xpEarned: score * 2,
    );
    if (!mounted) return;

    if (widget.onCompleteDetailed != null) {
      widget.onCompleteDetailed!(graded);
    } else {
      widget.onComplete(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
      appBar: AppBar(
        title: Text(widget.title),
        leading: const CloseButton(),
        actions: [
          if (widget.showCalculator)
            IconButton(
              icon: const Icon(Icons.calculate_outlined),
              tooltip: 'Calculator',
              onPressed: _openCalculator,
            ),
          if (widget.showNavigator)
            IconButton(
              icon: const Icon(Icons.grid_view_rounded),
              tooltip: 'Navigator',
              onPressed: _openNavigator,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: answeredCount / shuffledQuestions.length,
                    minHeight: 8,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Question ${_currentIndex + 1} of ${shuffledQuestions.length}',
                        style: Theme.of(context).textTheme.bodySmall),
                    if (q['subject'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          q['subject'] as String,
                          style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600),
                        ),
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
                      child: Text(q['question'] as String,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
                    ),
                    const SizedBox(height: 18),
                    ...List.generate(options.length, (i) {
                      final isSelected = _selectedAnswers[_currentIndex] == i;
                      final letter = String.fromCharCode(65 + i);
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
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isSelected ? scheme.primary : scheme.outlineVariant, width: isSelected ? 2 : 1),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
                                    child: Text(letter,
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant)),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(child: Text(options[i], style: const TextStyle(fontSize: 15))),
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _currentIndex > 0 ? () => _goTo(_currentIndex - 1) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: const Text('Previous'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _currentIndex == shuffledQuestions.length - 1
                        ? FilledButton.icon(
                            onPressed: _finishing ? null : _finish,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Finish'),
                          )
                        : FilledButton.icon(
                            onPressed: () => _goTo(_currentIndex + 1),
                            icon: const Icon(Icons.chevron_right_rounded),
                            label: const Text('Next'),
                          ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.showNavigator && _currentIndex != shuffledQuestions.length - 1)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _finishing ? null : _confirmEarlySubmit,
                    child: const Text('Submit Now'),
                  ),
                ),
              ),
            ),
        ],
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

  Widget _button(String label, {Color? bg, Color? fg, VoidCallback? onTap}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AspectRatio(
          aspectRatio: 1.3,
          child: Material(
            color: bg ?? Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap ?? () => _inputDigit(label),
              child: Center(
                child: Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: fg)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(color: scheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Calculator', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.centerRight,
            child: Text(_display, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          Row(children: [_button('7'), _button('8'), _button('9'), _button('÷', onTap: () => _setOperator('÷'))]),
          Row(children: [_button('4'), _button('5'), _button('6'), _button('×', onTap: () => _setOperator('×'))]),
          Row(children: [_button('1'), _button('2'), _button('3'), _button('-', onTap: () => _setOperator('-'))]),
          Row(children: [
            _button('C', bg: scheme.errorContainer, fg: scheme.onErrorContainer, onTap: _clear),
            _button('0'),
            _button('.', onTap: _inputDecimal),
            _button('+', onTap: () => _setOperator('+')),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(onPressed: _equals, child: const Text('=', style: TextStyle(fontSize: 20))),
          ),
        ],
      ),
    );
  }
}
/// =========================================================================
/// PROFILE SCREEN
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
    final scheme = Theme.of(context).colorScheme;
    final coinService = context.watch<CoinService>();
    final frameColor = CoinService.frameColorFor(coinService.equippedFrameId);
    final titleLabel = CoinService.titleLabelFor(coinService.equippedTitleId);

    return Scaffold(
      appBar: AppBar(title: const Text('👤 Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [scheme.primary, scheme.primaryContainer]),
                shape: BoxShape.circle,
                border: frameColor != null ? Border.all(color: frameColor, width: 4) : null,
                boxShadow: frameColor != null
                    ? [BoxShadow(color: frameColor.withOpacity(0.5), blurRadius: 14, spreadRadius: 1)]
                    : null,
              ),
              child: Center(
                child: Text(provider.avatarEmoji, style: const TextStyle(fontSize: 40)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(provider.userName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
          if (titleLabel != null) ...[
            const SizedBox(height: 6),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(titleLabel,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer)),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              _ProfileStat(
                label: 'Rank',
                value: rankTitleForLevel(stats.level),
                subtitle: 'Lv. ${stats.level}',
                color: rankColor(stats.level),
              ),
              const SizedBox(width: 10),
              _ProfileStat(label: 'XP', value: '${stats.xp}', color: Colors.amber),
              const SizedBox(width: 10),
              _ProfileStat(label: 'Streak', value: '${stats.streak}', color: Colors.deepOrange),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ProfileStat(label: 'Study (min)', value: '${provider.totalStudyMinutes}', color: Colors.teal),
              const SizedBox(width: 10),
              _ProfileStat(label: 'Quizzes', value: '${stats.quizzesCompleted}', color: Colors.indigo),
              const SizedBox(width: 10),
              _ProfileStat(label: 'Goals Met', value: '${stats.goalsMetCount}', color: Colors.pink),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag_rounded, size: 20),
                    const SizedBox(width: 8),
                    const Text('Today\'s Goal', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: provider.dailyGoalProgress,
                    minHeight: 10,
                    backgroundColor: scheme.surface,
                    valueColor: AlwaysStoppedAnimation(provider.dailyGoalMet ? Colors.green : scheme.primary),
                  ),
                ),
                const SizedBox(height: 6),
                Text(dailyGoalStatusText(provider),
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('🎖️ Subject Mastery', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...provider.getAvailableSubjects().map((sub) {
            final tier = provider.getSubjectMastery(sub);
            final attempts = stats.subjectAttempts[sub] ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(Icons.shield_rounded, color: masteryColor(tier), size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text(sub)),
                  Text(
                    attempts < 10 ? 'Locked (10 needed)' : masteryLabel(tier),
                    style: TextStyle(fontWeight: FontWeight.bold, color: masteryColor(tier), fontSize: 12),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 24),
          const Text('🏅 Badges', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          stats.badges.isEmpty
              ? Text('No badges yet — keep practising!', style: TextStyle(color: scheme.onSurfaceVariant))
              : Column(
                  children: stats.badges.map((b) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (_badgeDescriptions[b] != null)
                                  Text(_badgeDescriptions[b]!,
                                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
          const SizedBox(height: 28),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Change your name',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check_rounded),
                onPressed: () {
                  if (_nameController.text.trim().isNotEmpty) {
                    provider.setUserName(_nameController.text);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Name updated!')));
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
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String? subtitle;
  const _ProfileStat({required this.label, required this.value, required this.color, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
            if (subtitle != null)
              Text(subtitle!, style: TextStyle(fontSize: 10, color: color.withOpacity(0.85))),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: color), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// ANALYTICS SCREEN
/// =========================================================================

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final stats = provider.stats;
    final scheme = Theme.of(context).colorScheme;
    final weeklyXp = provider.getWeeklyXp();
    final maxWeeklyXp = weeklyXp.fold<int>(1, (m, e) => e.value > m ? e.value : m);
    final weeklyAcc = provider.getWeeklyAccuracy();

    return Scaffold(
      appBar: AppBar(title: const Text('📊 Analytics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Overall Performance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text('Total XP: ${stats.xp}'),
                Text('Rank: ${rankTitleForLevel(stats.level)} (Lv. ${stats.level})'),
                Text('Streak: ${stats.streak} days'),
                Text('Badges earned: ${stats.badges.length}'),
                Text('Total questions attempted: ${stats.subjectAttempts.values.fold(0, (a, b) => a + b)}'),
                Text('Total study time: ${provider.totalStudyMinutes} minutes'),
                Text('Quizzes completed: ${stats.quizzesCompleted}'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('This Week', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${provider.weeklyXpTotal} XP', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 90,
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
                                height: 46 * heightFactor + 4,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(e.key, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Weekly Accuracy', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
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
                                backgroundColor: scheme.surface,
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
          const Text('Subject Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...provider.getAvailableSubjects().map((sub) {
            final score = provider.getSubjectScore(sub);
            final attempted = stats.subjectAttempts[sub] ?? 0;
            final tier = provider.getSubjectMastery(sub);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  ListTile(
                    title: Text(sub),
                    trailing: Text('${score.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('$attempted questions attempted • ${masteryLabel(tier)}'),
                    leading: Icon(
                      score >= 70 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                      color: score >= 70 ? Colors.green : Colors.orange,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (score / 100).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: scheme.surface,
                        valueColor: AlwaysStoppedAnimation(masteryColor(tier)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// =========================================================================
/// GOAL SELECTOR SHEET
/// =========================================================================

class GoalSelectorSheet extends StatelessWidget {
  const GoalSelectorSheet({super.key});

  static const List<int> _options = [5, 10, 20, 30, 50];

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(color: scheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Set Daily Goal', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('How many questions do you want to answer each day?',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _options.map((opt) {
              final isSelected = provider.dailyGoalQuestions == opt;
              return ChoiceChip(
                label: Text('$opt questions'),
                selected: isSelected,
                onSelected: (_) {
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
/// STUDY TIMER SCREEN
/// =========================================================================
/// Now actually contributes to progress: saving a session awards XP
/// (2 XP per minute studied, capped at 120 counted minutes per single
/// session so leaving the timer running indefinitely can't be abused for
/// unlimited XP), in addition to tracking total study time and unlocking
/// the Study Buddy / Study Master badges as before.

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
    final scheme = Theme.of(context).colorScheme;
    final provider = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('⏱️ Study Timer')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
              child: Text('Today: ${provider.studyMinutesToday} min • All-time: ${provider.totalStudyMinutes} min',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 12),
            Text('Earn 2 XP per minute studied (up to 120 min per session)',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
            const SizedBox(height: 28),
            Text(_formatted,
                style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 140,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _toggle,
                    icon: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    label: Text(_running ? 'Pause' : 'Start'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _elapsedSeconds == 0 ? null : _reset,
                    child: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _elapsedSeconds == 0 ? null : _saveSession,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Save Session'),
              ),
            ),
            const Spacer(),
            Text('"$_quote"',
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// WEEKLY STATS SCREEN
/// =========================================================================

class WeeklyStatsScreen extends StatelessWidget {
  const WeeklyStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final scheme = Theme.of(context).colorScheme;
    final weeklyXp = provider.getWeeklyXp();
    final weeklyAcc = provider.getWeeklyAccuracy();
    final maxXp = weeklyXp.fold<int>(1, (m, e) => e.value > m ? e.value : m);

    return Scaffold(
      appBar: AppBar(title: const Text('📅 Weekly Stats')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('XP This Week', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('${provider.weeklyXpTotal} total XP', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ...weeklyXp.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(width: 36, child: Text(e.key, style: const TextStyle(fontSize: 12))),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: maxXp == 0 ? 0 : e.value / maxXp,
                                minHeight: 12,
                                backgroundColor: scheme.surface,
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
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
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
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: (e.value / 100).clamp(0.0, 1.0),
                                minHeight: 12,
                                backgroundColor: scheme.surface,
                                valueColor: AlwaysStoppedAnimation(
                                  e.value >= 70 ? Colors.green : (e.value >= 50 ? Colors.amber : Colors.orange),
                                ),
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
    );
  }
}
