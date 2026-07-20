// lib/app_enhancements.dart
// Gamification layer for NaijaLearn: XP, streaks, badges, leaderboard,
// daily challenge, mock exams, subject mastery tiers, profile, analytics.
//
// This file does NOT define its own app shell, HomeScreen, or MaterialApp —
// it plugs into main.dart's existing NaijaLearnApp via AppProvider.

import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
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

  // --- Added: daily goals / study timer / weekly stats tracking ---
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
      );
}

class LeaderboardEntry {
  final String name;
  final int xp;
  final int level;
  final int streak;

  LeaderboardEntry({required this.name, required this.xp, required this.level, required this.streak});

  Map<String, dynamic> toJson() => {'name': name, 'xp': xp, 'level': level, 'streak': streak};

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) => LeaderboardEntry(
        name: json['name'] ?? 'Anonymous',
        xp: json['xp'] ?? 0,
        level: json['level'] ?? 1,
        streak: json['streak'] ?? 0,
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

  Future<void> saveLeaderboard(List<LeaderboardEntry> entries) async {
    final list = entries.map((e) => e.toJson()).toList();
    await _prefs.setString('leaderboard', jsonEncode(list));
  }

  List<LeaderboardEntry> loadLeaderboard() {
    final data = _prefs.getString('leaderboard');
    if (data != null) {
      try {
        final list = jsonDecode(data) as List;
        return list.map((e) => LeaderboardEntry.fromJson(e)).toList();
      } catch (_) {}
    }
    return [];
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
}

class StreakService {
  UserStats checkStreak(UserStats stats) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = DateTime(stats.lastActive.year, stats.lastActive.month, stats.lastActive.day);

    if (today == last) {
      return stats;
    } else if (today.difference(last).inDays == 1) {
      return stats.copyWith(streak: stats.streak + 1, lastActive: now);
    } else {
      return stats.copyWith(streak: 0, lastActive: now);
    }
  }

  UserStats addXP(UserStats stats, int amount) {
    final newXP = stats.xp + amount;
    final newLevel = (newXP / 100).floor() + 1;
    return stats.copyWith(xp: newXP, level: newLevel);
  }

  /// Checks all badge conditions and returns the updated badge list.
  /// Also returns (via out-param pattern) which badge, if any, is new.
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

    // --- Added: extra achievements for goals / study timer / quizzes ---
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

class LeaderboardService {
  final StorageService storage = StorageService();

  List<LeaderboardEntry> getTopEntries({int limit = 20}) {
    final list = storage.loadLeaderboard();
    list.sort((a, b) => b.xp.compareTo(a.xp));
    return list.take(limit).toList();
  }

  Future<void> addEntry(String name, UserStats stats) async {
    final list = storage.loadLeaderboard();
    final entry = LeaderboardEntry(name: name, xp: stats.xp, level: stats.level, streak: stats.streak);
    list.add(entry);
    await storage.saveLeaderboard(list);
  }
}

/// =========================================================================
/// APP PROVIDER (state management)
/// =========================================================================

class AppProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final StreakService _streak = StreakService();
  final LeaderboardService _leaderboard = LeaderboardService();

  UserStats _stats = UserStats();
  bool _darkMode = false;
  String _userName = 'Student';
  DailyChallenge? _dailyChallenge;
  String? _pendingBadgeAnnouncement;

  UserStats get stats => _stats;
  bool get darkMode => _darkMode;
  String get userName => _userName;
  DailyChallenge? get dailyChallenge => _dailyChallenge;
  String? get pendingBadgeAnnouncement => _pendingBadgeAnnouncement;

  AppProvider() {
    _init();
  }

  Future<void> _init() async {
    await _storage.init();
    _stats = _storage.loadUserStats();
    _darkMode = _storage.loadDarkMode();
    _stats = _streak.checkStreak(_stats);
    _stats = _rolloverDailyIfNeeded(_stats);
    await _storage.saveUserStats(_stats);
    _loadOrGenerateDailyChallenge();
    notifyListeners();
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
  }

  void setUserName(String name) {
    if (name.trim().isEmpty) return;
    _userName = name.trim();
    notifyListeners();
  }

  Future<void> addXP(int amount) async {
    _stats = _streak.addXP(_stats, amount);
    // --- Added: track XP per-day for weekly stats ---
    final key = todayKey();
    final xpMap = Map<String, int>.from(_stats.dailyXp);
    xpMap[key] = (xpMap[key] ?? 0) + amount;
    _pruneOldDailyKeys(xpMap);
    _stats = _stats.copyWith(dailyXp: xpMap);
    _applyBadgeCheck();
    await _storage.saveUserStats(_stats);
    notifyListeners();
  }

  Future<void> recordAnswer(String subject, int score, int total) async {
    if (total <= 0) return;
    final newScore = (stats.subjectScores[subject] ?? 0) + score;
    final newAttempts = (stats.subjectAttempts[subject] ?? 0) + total;
    _stats = _stats.copyWith(
      subjectScores: Map.from(_stats.subjectScores)..[subject] = newScore,
      subjectAttempts: Map.from(_stats.subjectAttempts)..[subject] = newAttempts,
    );
    _stats = _streak.checkStreak(_stats);
    _stats = _trackDailyProgress(correct: score, total: total);
    _applyBadgeCheck();
    await _storage.saveUserStats(_stats);
    notifyListeners();
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

  Future<void> submitLeaderboard() async {
    await _leaderboard.addEntry(_userName, _stats);
  }

  List<LeaderboardEntry> getLeaderboard() => _leaderboard.getTopEntries();

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

  /// --- Added: generates a combined mock exam pulling questions from
  /// several subjects at once (e.g. a 4-subject JAMB-style combo).
  /// Each question is tagged with its originating subject under the
  /// 'subject' key so results can be scored and recorded per-subject
  /// once the exam is finished.
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
  // --- Added: daily goals, study timer, weekly stats helpers ---
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

  /// Resets today's question/study counters if the stored date has rolled
  /// over to a new day. Weekly/history maps (dailyXp, dailyAccuracy) are
  /// never reset here — only the "today" counters.
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

  /// Sets the daily goal (in number of questions answered per day).
  Future<void> setDailyGoal(int questions) async {
    _stats = _rolloverDailyIfNeeded(_stats).copyWith(dailyGoalQuestions: questions);
    await _storage.saveUserStats(_stats);
    notifyListeners();
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

  /// Adds completed study time (in seconds) from the study timer.
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
  }

  int get studyMinutesToday {
    final s = _rolloverDailyIfNeeded(_stats);
    return s.studySecondsToday ~/ 60;
  }

  int get totalStudyMinutes => _stats.totalStudySeconds ~/ 60;

  /// Last 7 days of XP earned, oldest first. Each entry is (label, xp).
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

  /// Last 7 days of accuracy %, oldest first. Days with no attempts show 0.
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
/// CELEBRATION DIALOG (added — shown after quiz completion)
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

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final entries = provider.getLeaderboard();
    final scheme = Theme.of(context).colorScheme;

    // --- Added: find current user's best rank/entry for a "Your Rank" card ---
    int? myRank;
    LeaderboardEntry? myEntry;
    for (int i = 0; i < entries.length; i++) {
      if (entries[i].name == provider.userName) {
        myRank = i + 1;
        myEntry = entries[i];
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('🏆 Leaderboard')),
      body: Column(
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
                ? Center(
                    child: Text('No entries yet. Be the first!',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final e = entries[i];
                      final isTop3 = i < 3;
                      final isMe = e.name == provider.userName && myRank == i + 1;
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
                                  Text('Level ${e.level} • Streak ${e.streak} days',
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
      ),
    );
  }
}

/// =========================================================================
/// MOCK EXAM SCREEN
/// =========================================================================
/// --- Updated: users can now pick up to 4 subjects for a combined exam,
/// instead of being limited to a single subject. Each subject contributes
/// the chosen number of questions, and results are recorded per-subject
/// once the exam is finished.

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
        // Fallback path (shouldn't normally be hit since onCompleteDetailed is provided).
        Navigator.pop(context);
      },
      onCompleteDetailed: (gradedQuestions) {
        // Tally correctness per subject using the 'subject' tag on each question.
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
/// --- Updated: added an optional onCompleteDetailed callback that returns
/// each answered question tagged with whether it was answered correctly
/// (and its 'subject', if present), so callers like the multi-subject
/// mock exam can score/record results per subject.

class QuizScreen extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  final String title;
  final void Function(int score) onComplete;
  final void Function(List<Map<String, dynamic>> gradedQuestions)? onCompleteDetailed;

  const QuizScreen({
    super.key,
    required this.questions,
    required this.title,
    required this.onComplete,
    this.onCompleteDetailed,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int currentIndex = 0;
  int score = 0;
  int selectedOption = -1;
  bool answered = false;
  late List<Map<String, dynamic>> shuffledQuestions;
  final List<Map<String, dynamic>> _gradedQuestions = [];

  @override
  void initState() {
    super.initState();
    shuffledQuestions = List<Map<String, dynamic>>.from(widget.questions)..shuffle();
  }

  void submitAnswer() {
    if (selectedOption == -1) return;
    final q = shuffledQuestions[currentIndex];
    final isCorrect = selectedOption == q['correctIndex'];
    if (isCorrect) score++;
    _gradedQuestions.add({
      ...q,
      '__correct': isCorrect,
    });
    setState(() => answered = true);
  }

  Future<void> nextQuestion() async {
    if (currentIndex < shuffledQuestions.length - 1) {
      setState(() {
        currentIndex++;
        selectedOption = -1;
        answered = false;
      });
    } else {
      // --- Added: celebration dialog before reporting completion ---
      await showCelebrationDialog(
        context,
        score: score,
        total: shuffledQuestions.length,
        xpEarned: score * 2,
      );
      if (!mounted) return;
      if (widget.onCompleteDetailed != null) {
        widget.onCompleteDetailed!(_gradedQuestions);
      } else {
        widget.onComplete(score);
      }
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

    final q = shuffledQuestions[currentIndex];
    final options = List<String>.from(q['options']);
    final correctIndex = q['correctIndex'] as int;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title), leading: const CloseButton()),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (currentIndex + 1) / shuffledQuestions.length,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Question ${currentIndex + 1} of ${shuffledQuestions.length}',
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
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(q['question'] as String,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final isSelected = selectedOption == i;
                  final isCorrectOption = i == correctIndex;
                  Color? bg;
                  Color borderColor = scheme.outlineVariant;
                  if (answered) {
                    if (isCorrectOption) {
                      bg = Colors.green.withOpacity(0.15);
                      borderColor = Colors.green;
                    } else if (isSelected) {
                      bg = Colors.red.withOpacity(0.15);
                      borderColor = Colors.red;
                    }
                  } else if (isSelected) {
                    bg = scheme.primaryContainer;
                    borderColor = scheme.primary;
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: bg ?? scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: answered ? null : () => setState(() => selectedOption = i),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderColor, width: isSelected || (answered && isCorrectOption) ? 2 : 1),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: isSelected || (answered && isCorrectOption)
                                    ? borderColor
                                    : scheme.surfaceContainerHighest,
                                child: Text(String.fromCharCode(65 + i),
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected || (answered && isCorrectOption)
                                            ? Colors.white
                                            : scheme.onSurfaceVariant)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Text(options[i], style: const TextStyle(fontSize: 15))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: !answered
                  ? FilledButton(
                      onPressed: selectedOption == -1 ? null : submitAnswer,
                      child: const Text('Submit Answer'),
                    )
                  : FilledButton(
                      onPressed: nextQuestion,
                      child: Text(currentIndex == shuffledQuestions.length - 1 ? 'Finish' : 'Next'),
                    ),
            ),
          ],
        ),
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
    // --- Added descriptions for new badges ---
    'Goal Getter': 'Met your daily goal 7 times',
    'Goal Crusher': 'Met your daily goal 30 times',
    'Study Buddy': 'Studied 60+ minutes with the timer',
    'Study Master': 'Studied 500+ minutes with the timer',
    'Quiz Regular': 'Completed 10 quizzes',
    'Quiz Champion': 'Completed 50 quizzes',
    'Perfectionist': '100% accuracy in a subject (10+ attempts)',
  };

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final stats = provider.stats;
    final scheme = Theme.of(context).colorScheme;

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
              ),
              child: Center(
                child: Text(
                  provider.userName.isNotEmpty ? provider.userName[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(provider.userName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _ProfileStat(label: 'Level', value: '${stats.level}', color: scheme.primary),
              const SizedBox(width: 10),
              _ProfileStat(label: 'XP', value: '${stats.xp}', color: Colors.amber),
              const SizedBox(width: 10),
              _ProfileStat(label: 'Streak', value: '${stats.streak}', color: Colors.deepOrange),
            ],
          ),
          // --- Added: second row of profile stat cards (study + goal) ---
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
          // --- Added: daily goal progress card ---
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
                Text('${provider.questionsToday} / ${provider.dailyGoalQuestions} questions today',
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
  const _ProfileStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
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
                Text('Level: ${stats.level}'),
                Text('Streak: ${stats.streak} days'),
                Text('Badges earned: ${stats.badges.length}'),
                Text('Total questions attempted: ${stats.subjectAttempts.values.fold(0, (a, b) => a + b)}'),
                // --- Added ---
                Text('Total study time: ${provider.totalStudyMinutes} minutes'),
                Text('Quizzes completed: ${stats.quizzesCompleted}'),
              ],
            ),
          ),
          // --- Added: weekly XP + accuracy section ---
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
                  // --- Added: subject progress bar ---
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
/// GOAL SELECTOR SHEET (added)
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
/// STUDY TIMER SCREEN (added)
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
      await context.read<AppProvider>().addStudySeconds(seconds);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${(seconds / 60).ceil()} minute${seconds >= 120 ? 's' : ''} of study time.')),
    );
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
            const SizedBox(height: 40),
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
/// WEEKLY STATS SCREEN (added)
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
