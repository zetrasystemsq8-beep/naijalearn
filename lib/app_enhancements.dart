// lib/app_enhancements.dart
// Gamification layer for NaijaLearn: XP, streaks, badges, leaderboard,
// daily challenge, mock exams, subject mastery tiers, profile, analytics.
//
// This file does NOT define its own app shell, HomeScreen, or MaterialApp —
// it plugs into main.dart's existing NaijaLearnApp via AppProvider.

import 'dart:convert';
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

  UserStats({
    this.xp = 0,
    this.streak = 0,
    this.level = 1,
    this.subjectScores = const {},
    this.subjectAttempts = const {},
    this.badges = const [],
    DateTime? lastActive,
  }) : lastActive = lastActive ?? DateTime.now();

  UserStats copyWith({
    int? xp,
    int? streak,
    int? level,
    Map<String, int>? subjectScores,
    Map<String, int>? subjectAttempts,
    List<String>? badges,
    DateTime? lastActive,
  }) {
    return UserStats(
      xp: xp ?? this.xp,
      streak: streak ?? this.streak,
      level: level ?? this.level,
      subjectScores: subjectScores ?? this.subjectScores,
      subjectAttempts: subjectAttempts ?? this.subjectAttempts,
      badges: badges ?? this.badges,
      lastActive: lastActive ?? this.lastActive,
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
      };

  factory UserStats.fromJson(Map<String, dynamic> json) => UserStats(
        xp: json['xp'] ?? 0,
        streak: json['streak'] ?? 0,
        level: json['level'] ?? 1,
        subjectScores: Map<String, int>.from(json['subjectScores'] ?? {}),
        subjectAttempts: Map<String, int>.from(json['subjectAttempts'] ?? {}),
        badges: List<String>.from(json['badges'] ?? []),
        lastActive: DateTime.tryParse(json['lastActive'] ?? '') ?? DateTime.now(),
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

    return badges;
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
    _applyBadgeCheck();
    await _storage.saveUserStats(_stats);
    notifyListeners();
  }

  Future<void> recordAnswer(String subject, int score, int total) async {
    final newScore = (stats.subjectScores[subject] ?? 0) + score;
    final newAttempts = (stats.subjectAttempts[subject] ?? 0) + total;
    _stats = _stats.copyWith(
      subjectScores: Map.from(_stats.subjectScores)..[subject] = newScore,
      subjectAttempts: Map.from(_stats.subjectAttempts)..[subject] = newAttempts,
    );
    _stats = _streak.checkStreak(_stats);
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
      await addXP(score * 2);
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> generateMockExam(String subject, int count) {
    final allQuestions = _getQuestionsForSubject(subject);
    final shuffled = List<Map<String, dynamic>>.from(allQuestions)..shuffle();
    return shuffled.take(count).toList();
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
/// LEADERBOARD SCREEN
/// =========================================================================

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final entries = provider.getLeaderboard();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('🏆 Leaderboard')),
      body: entries.isEmpty
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
                final medalColors = [Colors.amber, Colors.grey, Colors.brown];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
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
                            Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
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
  String? selectedSubject;
  int questionCount = 60;
  bool started = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    selectedSubject ??= provider.getAvailableSubjects().first;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('📝 Mock Exam')),
      body: started
          ? _buildExam(context, provider)
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: selectedSubject,
                          items: provider
                              .getAvailableSubjects()
                              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (val) => setState(() => selectedSubject = val),
                          decoration: const InputDecoration(labelText: 'Choose Subject'),
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<int>(
                          initialValue: questionCount,
                          items: const [
                            DropdownMenuItem(value: 20, child: Text('20 questions')),
                            DropdownMenuItem(value: 40, child: Text('40 questions')),
                            DropdownMenuItem(value: 60, child: Text('60 questions')),
                            DropdownMenuItem(value: 100, child: Text('100 questions')),
                          ],
                          onChanged: (val) => setState(() => questionCount = val!),
                          decoration: const InputDecoration(labelText: 'Number of Questions'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => setState(() => started = true),
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
    final subject = selectedSubject!;
    final questions = provider.generateMockExam(subject, questionCount);
    return QuizScreen(
      questions: questions,
      title: 'Mock Exam — $subject',
      onComplete: (score) {
        provider.recordAnswer(subject, score, questions.length);
        provider.addXP(score * 2);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('You scored $score out of ${questions.length}'),
          backgroundColor: score >= (questions.length * 0.6) ? Colors.green : Colors.red,
        ));
      },
    );
  }
}

/// =========================================================================
/// QUIZ SCREEN (reusable — for daily challenge and mock exams)
/// =========================================================================

class QuizScreen extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  final String title;
  final void Function(int score) onComplete;

  const QuizScreen({super.key, required this.questions, required this.title, required this.onComplete});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int currentIndex = 0;
  int score = 0;
  int selectedOption = -1;
  bool answered = false;
  late List<Map<String, dynamic>> shuffledQuestions;

  @override
  void initState() {
    super.initState();
    shuffledQuestions = List<Map<String, dynamic>>.from(widget.questions)..shuffle();
  }

  void submitAnswer() {
    if (selectedOption == -1) return;
    final q = shuffledQuestions[currentIndex];
    if (selectedOption == q['correctIndex']) score++;
    setState(() => answered = true);
  }

  void nextQuestion() {
    if (currentIndex < shuffledQuestions.length - 1) {
      setState(() {
        currentIndex++;
        selectedOption = -1;
        answered = false;
      });
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
            Text('Question ${currentIndex + 1} of ${shuffledQuestions.length}',
                style: Theme.of(context).textTheme.bodySmall),
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
            Text(label, style: TextStyle(fontSize: 12, color: color)),
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
              child: ListTile(
                title: Text(sub),
                trailing: Text('${score.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('$attempted questions attempted • ${masteryLabel(tier)}'),
                leading: Icon(
                  score >= 70 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                  color: score >= 70 ? Colors.green : Colors.orange,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
