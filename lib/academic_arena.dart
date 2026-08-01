// lib/academic_arena.dart
//
// Academic Arena — the four connected gamification systems:
//   1. Leagues (weekly competitive tiers, promotion/relegation)
//   2. Faculty War (dream-course team XP competition)
//   3. Boss Battles (subject bosses with an HP bar)
//   4. Study Companion (a pet that grows with daily consistency)
// Plus a lightweight Season Pass label tying them all to a monthly cycle.
//
// Backed by the arena_progress table and its RPCs (all security-definer,
// always acting on auth.uid() — never a client-supplied user id, so
// nothing here can be spoofed by editing local state).
//
// Regular practice/exam sessions feed League XP, Faculty XP, and the
// Companion via arena_record_session() — call ArenaService.instance
// .recordSession(correct, total) from ExamScreen._submitExam. Boss
// fights are a separate flow (BossBattleScreen below) and do NOT also
// call recordSession, since their HP mechanic already IS their scoring.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show Question, QuestionRepository, kSubjects, SubjectInfo;
import 'zetra_pay.dart';

/// =========================================================================
/// LEAGUES
/// =========================================================================

enum League { bronze, silver, gold, platinum, diamond, legend, grandScholar }

extension LeagueInfo on League {
  static League fromString(String s) {
    switch (s) {
      case 'bronze': return League.bronze;
      case 'silver': return League.silver;
      case 'gold': return League.gold;
      case 'platinum': return League.platinum;
      case 'diamond': return League.diamond;
      case 'legend': return League.legend;
      case 'grand_scholar': return League.grandScholar;
      default: return League.bronze;
    }
  }

  String get label {
    switch (this) {
      case League.bronze: return 'Bronze';
      case League.silver: return 'Silver';
      case League.gold: return 'Gold';
      case League.platinum: return 'Platinum';
      case League.diamond: return 'Diamond';
      case League.legend: return 'Legend';
      case League.grandScholar: return 'Grand Scholar';
    }
  }

  String get emoji {
    switch (this) {
      case League.bronze: return '🥉';
      case League.silver: return '🥈';
      case League.gold: return '🥇';
      case League.platinum: return '💎';
      case League.diamond: return '💠';
      case League.legend: return '👑';
      case League.grandScholar: return '🌍';
    }
  }

  Color get color {
    switch (this) {
      case League.bronze: return const Color(0xFFCD7F32);
      case League.silver: return const Color(0xFFB0B0B0);
      case League.gold: return const Color(0xFFFFD700);
      case League.platinum: return const Color(0xFF00CFFF);
      case League.diamond: return const Color(0xFF4FC3F7);
      case League.legend: return const Color(0xFFFF6B6B);
      case League.grandScholar: return const Color(0xFF9C27B0);
    }
  }
}

/// =========================================================================
/// FACULTY (dream course)
/// =========================================================================

class FacultyInfo {
  final String id;
  final String displayName;
  final String icon;
  const FacultyInfo(this.id, this.displayName, this.icon);
}

const List<FacultyInfo> kFaculties = [
  FacultyInfo('medicine', 'Medicine', '⚕️'),
  FacultyInfo('law', 'Law', '⚖️'),
  FacultyInfo('computer_science', 'Computer Science', '💻'),
  FacultyInfo('engineering', 'Engineering', '⚙️'),
  FacultyInfo('accounting', 'Accounting', '📊'),
  FacultyInfo('pharmacy', 'Pharmacy', '💊'),
  FacultyInfo('nursing', 'Nursing', '🩺'),
];

/// =========================================================================
/// COMPANION
/// =========================================================================

enum CompanionSpecies { owl, panda, fox, eagle }

extension CompanionInfo on CompanionSpecies {
  static CompanionSpecies fromString(String s) {
    switch (s) {
      case 'owl': return CompanionSpecies.owl;
      case 'panda': return CompanionSpecies.panda;
      case 'fox': return CompanionSpecies.fox;
      case 'eagle': return CompanionSpecies.eagle;
      default: return CompanionSpecies.owl;
    }
  }

  String get emoji {
    switch (this) {
      case CompanionSpecies.owl: return '🦉';
      case CompanionSpecies.panda: return '🐼';
      case CompanionSpecies.fox: return '🦊';
      case CompanionSpecies.eagle: return '🦅';
    }
  }

  String get name {
    switch (this) {
      case CompanionSpecies.owl: return 'Owl';
      case CompanionSpecies.panda: return 'Panda';
      case CompanionSpecies.fox: return 'Fox';
      case CompanionSpecies.eagle: return 'Eagle';
    }
  }
}

/// =========================================================================
/// PROGRESS SNAPSHOT + SERVICE
/// =========================================================================

class ArenaProgress {
  final League league;
  final String? faculty;
  final CompanionSpecies companionSpecies;
  final int companionXp;
  final int companionLevel;
  final DateTime? companionLastFedAt;
  final String? activeBossSubject;
  final int bossHpRemaining;
  final int bossDefeatedCount;
  final String seasonId;

  ArenaProgress({
    required this.league,
    required this.faculty,
    required this.companionSpecies,
    required this.companionXp,
    required this.companionLevel,
    required this.companionLastFedAt,
    required this.activeBossSubject,
    required this.bossHpRemaining,
    required this.bossDefeatedCount,
    required this.seasonId,
  });

  factory ArenaProgress.fromMap(Map<String, dynamic> map) {
    return ArenaProgress(
      league: LeagueInfo.fromString(map['league'] as String? ?? 'bronze'),
      faculty: map['faculty'] as String?,
      companionSpecies: CompanionInfo.fromString(map['companion_species'] as String? ?? 'owl'),
      companionXp: (map['companion_xp'] as num?)?.toInt() ?? 0,
      companionLevel: (map['companion_level'] as num?)?.toInt() ?? 1,
      companionLastFedAt: map['companion_last_fed_at'] != null
          ? DateTime.tryParse(map['companion_last_fed_at'] as String)
          : null,
      activeBossSubject: map['active_boss_subject'] as String?,
      bossHpRemaining: (map['boss_hp_remaining'] as num?)?.toInt() ?? 100,
      bossDefeatedCount: (map['boss_defeated_count'] as num?)?.toInt() ?? 0,
      seasonId: map['season_id'] as String? ?? '',
    );
  }

  bool get companionFedToday {
    if (companionLastFedAt == null) return false;
    final now = DateTime.now();
    return companionLastFedAt!.year == now.year &&
        companionLastFedAt!.month == now.month &&
        companionLastFedAt!.day == now.day;
  }
}

class ArenaService extends ChangeNotifier {
  ArenaService._();
  static final ArenaService instance = ArenaService._();

  SupabaseClient get _client => Supabase.instance.client;

  ArenaProgress? _progress;
  ArenaProgress? get progress => _progress;

  int? _leagueRank;
  int? _leagueRankTotal;
  int? get leagueRank => _leagueRank;
  int? get leagueRankTotal => _leagueRankTotal;

  int? _facultyRank;
  int? get facultyRank => _facultyRank;

  Future<void> load() async {
    if (_client.auth.currentUser == null) return;
    try {
      final row = await _client.rpc('arena_get_my_progress');
      if (row is Map) {
        _progress = ArenaProgress.fromMap(Map<String, dynamic>.from(row));
      }
      final rankRows = await _client.rpc('arena_get_league_rank');
      if (rankRows is List && rankRows.isNotEmpty) {
        final r = Map<String, dynamic>.from(rankRows.first as Map);
        _leagueRank = (r['rank'] as num?)?.toInt();
        _leagueRankTotal = (r['total_in_league'] as num?)?.toInt();
      }
      final facultyRankRows = await _client.rpc('arena_get_faculty_rank');
      if (facultyRankRows is List && facultyRankRows.isNotEmpty) {
        final r = Map<String, dynamic>.from(facultyRankRows.first as Map);
        _facultyRank = (r['rank'] as num?)?.toInt();
      }
      notifyListeners();
    } catch (_) {
      // Non-fatal — dashboard just shows nothing until next load.
    }
  }

  Future<void> setFaculty(String facultyId) async {
    await _client.rpc('arena_set_faculty', params: {'p_faculty': facultyId});
    await load();
  }

  /// Call this from ExamScreen._submitExam for ordinary practice/exam
  /// sessions (NOT boss fights). Feeds League XP, Faculty XP, and the
  /// Companion all in one server-side call.
  Future<void> recordSession({required int correct, required int total}) async {
    try {
      await _client.rpc('arena_record_session', params: {'p_correct': correct, 'p_total': total});
      await load();
    } catch (_) {
      // Non-fatal — gamification shouldn't block the results screen.
    }
  }

  /// Call once per answer during a boss fight. Returns the boss's new HP.
  Future<int> answerBoss({required String subject, required bool correct}) async {
    final result = await _client.rpc('arena_boss_answer', params: {
      'p_subject': subject,
      'p_correct': correct,
    });
    final hp = (result as num).toInt();
    if (hp == 0) {
      // Reward for defeating a boss: 5 CP-app-currency + refresh state.
      await ZetraPay.creditAppCurrency(appId: ZetraPay.naijaLearnAppId, unitAmount: 5);
      await load();
    }
    return hp;
  }
}

/// =========================================================================
/// DASHBOARD CARD — embed in HomeScreen's Home tab
/// =========================================================================

class ArenaDashboardCard extends StatefulWidget {
  const ArenaDashboardCard({super.key});

  @override
  State<ArenaDashboardCard> createState() => _ArenaDashboardCardState();
}

class _ArenaDashboardCardState extends State<ArenaDashboardCard> {
  @override
  void initState() {
    super.initState();
    ArenaService.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ArenaService.instance,
      builder: (context, _) {
        final progress = ArenaService.instance.progress;
        final scheme = Theme.of(context).colorScheme;

        if (progress == null) {
          return const SizedBox.shrink();
        }

        final faculty = kFaculties.where((f) => f.id == progress.faculty);
        final facultyInfo = faculty.isEmpty ? null : faculty.first;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ArenaMiniTile(
                      icon: Text(progress.league.emoji, style: const TextStyle(fontSize: 22)),
                      title: '${progress.league.label} League',
                      subtitle: ArenaService.instance.leagueRank != null
                          ? 'Rank #${ArenaService.instance.leagueRank}'
                          : 'Unranked',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeagueScreen())),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ArenaMiniTile(
                      icon: Text(facultyInfo?.icon ?? '🎓', style: const TextStyle(fontSize: 22)),
                      title: facultyInfo?.displayName ?? 'Pick a Faculty',
                      subtitle: ArenaService.instance.facultyRank != null
                          ? 'Team Rank #${ArenaService.instance.facultyRank}'
                          : 'Join a team',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FacultyWarScreen())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ArenaMiniTile(
                      icon: Text(progress.companionSpecies.emoji, style: const TextStyle(fontSize: 22)),
                      title: '${progress.companionSpecies.name} Lv.${progress.companionLevel}',
                      subtitle: progress.companionFedToday ? 'Fed today ✅' : 'Feed me — study today!',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompanionScreen())),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ArenaMiniTile(
                      icon: const Text('🧬', style: TextStyle(fontSize: 22)),
                      title: 'Boss Battle',
                      subtitle: '${progress.bossDefeatedCount} defeated',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BossSelectScreen())),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArenaMiniTile extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ArenaMiniTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(subtitle, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
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
/// LEAGUE SCREEN
/// =========================================================================

class LeagueScreen extends StatelessWidget {
  const LeagueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = ArenaService.instance.progress;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Academic Leagues')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (progress != null)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: progress.league.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: progress.league.color, width: 1.5),
              ),
              child: Column(
                children: [
                  Text(progress.league.emoji, style: const TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                  Text('${progress.league.label} League', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                  const SizedBox(height: 4),
                  Text(
                    ArenaService.instance.leagueRank != null
                        ? 'Rank #${ArenaService.instance.leagueRank} of ${ArenaService.instance.leagueRankTotal}'
                        : 'Unranked yet — start practicing!',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          const Text('How promotion works', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Every Monday, the top 20% of each league move up a tier, the bottom 20% move down, '
            'and everyone else stays. Keep practicing to hold or climb your rank.',
          ),
          const SizedBox(height: 24),
          const Text('League Ladder', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...League.values.reversed.map((l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: progress?.league == l ? l.color.withOpacity(0.2) : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(l.emoji, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Text(l.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (progress?.league == l) ...[
                        const Spacer(),
                        const Text('You are here', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

/// =========================================================================
/// FACULTY WAR SCREEN
/// =========================================================================

class FacultyWarScreen extends StatefulWidget {
  const FacultyWarScreen({super.key});

  @override
  State<FacultyWarScreen> createState() => _FacultyWarScreenState();
}

class _FacultyWarScreenState extends State<FacultyWarScreen> {
  bool _saving = false;

  Future<void> _pick(String facultyId) async {
    setState(() => _saving = true);
    await ArenaService.instance.setFaculty(facultyId);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = ArenaService.instance.progress;

    return Scaffold(
      appBar: AppBar(title: const Text('Faculty War')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            progress?.faculty == null
                ? 'Pick your dream course. Every correct answer earns XP for you AND your team.'
                : "You're on Team ${kFaculties.firstWhere((f) => f.id == progress!.faculty).displayName}. Every correct answer helps your team's weekly rank.",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          ...kFaculties.map((f) {
            final isSelected = progress?.faculty == f.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: isSelected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _saving ? null : () => _pick(f.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Text(f.icon, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 14),
                        Expanded(child: Text(f.displayName, style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (isSelected) const Icon(Icons.check_circle_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// =========================================================================
/// BOSS BATTLES
/// =========================================================================

class BossSelectScreen extends StatelessWidget {
  const BossSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Boss Battles')),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: kSubjects.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final subject = kSubjects[i];
          final count = QuestionRepository.getForSubject(subject.name).length;
          if (count == 0) return const SizedBox.shrink();
          return Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => BossBattleScreen(subject: subject)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(subject.icon, color: subject.color, size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${subject.name} Boss', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Text('Defeat it to earn CP and a badge', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class BossBattleScreen extends StatefulWidget {
  final SubjectInfo subject;
  const BossBattleScreen({super.key, required this.subject});

  @override
  State<BossBattleScreen> createState() => _BossBattleScreenState();
}

class _BossBattleScreenState extends State<BossBattleScreen> {
  late List<Question> _questions;
  int _index = 0;
  int _hp = 100;
  bool _answering = false;
  bool _defeated = false;

  @override
  void initState() {
    super.initState();
    final all = QuestionRepository.getForSubject(widget.subject.name);
    _questions = (List<Question>.from(all)..shuffle()).take(30).toList();
    _hp = ArenaService.instance.progress?.activeBossSubject == widget.subject.name
        ? ArenaService.instance.progress!.bossHpRemaining
        : 100;
  }

  Future<void> _answer(int optionIndex) async {
    if (_answering || _defeated) return;
    final question = _questions[_index];
    final correct = optionIndex == question.correctIndex;
    setState(() => _answering = true);

    final newHp = await ArenaService.instance.answerBoss(subject: widget.subject.name, correct: correct);

    if (!mounted) return;
    setState(() {
      _hp = newHp;
      _answering = false;
      if (newHp == 0) {
        _defeated = true;
      } else {
        _index = (_index + 1) % _questions.length;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('${widget.subject.name} Boss')),
        body: const Center(child: Text('No questions available for this boss yet.')),
      );
    }

    if (_defeated) {
      return Scaffold(
        appBar: AppBar(title: Text('${widget.subject.name} Boss')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text('${widget.subject.name} Boss Defeated!', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 8),
              const Text('+5 CP earned'),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back to Bosses')),
            ],
          ),
        ),
      );
    }

    final question = _questions[_index];

    return Scaffold(
      appBar: AppBar(title: Text('${widget.subject.name} Boss')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(widget.subject.icon == Icons.science_rounded ? '🧬' : '👾', style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${widget.subject.name} Boss', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Boss HP: $_hp%', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _hp / 100,
                minHeight: 14,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(_hp > 40 ? Colors.red : Colors.orange),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
              child: Text(question.questionText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4)),
            ),
            const SizedBox(height: 18),
            ...List.generate(question.options.length, (i) {
              final letter = String.fromCharCode(65 + i);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton(
                  onPressed: _answering ? null : () => _answer(i),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14), alignment: Alignment.centerLeft),
                  child: Text('$letter. ${question.options[i]}'),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// COMPANION SCREEN
/// =========================================================================

class CompanionScreen extends StatelessWidget {
  const CompanionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = ArenaService.instance.progress;
    final scheme = Theme.of(context).colorScheme;

    if (progress == null) {
      return Scaffold(appBar: AppBar(title: const Text('Study Companion')), body: const Center(child: CircularProgressIndicator()));
    }

    final xpIntoLevel = progress.companionXp % 200;

    return Scaffold(
      appBar: AppBar(title: const Text('Study Companion')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(progress.companionSpecies.emoji, style: const TextStyle(fontSize: 96)),
            const SizedBox(height: 12),
            Text('${progress.companionSpecies.name} — Level ${progress.companionLevel}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 8),
            Text(
              progress.companionFedToday
                  ? 'Fed today — great job keeping the streak alive!'
                  : "Hasn't been fed today. Complete a study session to feed it.",
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: xpIntoLevel / 200, minHeight: 12, backgroundColor: scheme.surfaceContainerHighest),
            ),
            const SizedBox(height: 6),
            Text('$xpIntoLevel / 200 XP to next level', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// SEASON PASS BANNER
/// =========================================================================

class SeasonPassBanner extends StatelessWidget {
  const SeasonPassBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = ArenaService.instance.progress;
    if (progress == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = lastDay - now.day;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Season ${progress.seasonId} · $daysLeft days left',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
