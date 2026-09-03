// lib/academic_arena.dart
//
// ⚡ REDESIGNED VERSION — visuals only. League/Faculty/Companion models,
// ArenaService (all Supabase RPC calls), and every method signature below
// are 100% unchanged from your original file — copy this in as a straight
// replacement, nothing breaks.
//
// Reuses the shared design system (kHeroGradient, ShinyCard,
// GradientButton, GradientHeader, GlassPill, accent colors) defined in
// the redesigned app_enhancements.dart — make sure that file is updated
// first, since this one imports those widgets from it.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show Question, QuestionRepository, kSubjects, SubjectInfo;
import 'zetra_pay.dart';
import 'app_enhancements.dart'
    show kHeroGradient, kGoldAccent, kTealAccent, kCoralAccent, kVioletAccent, ShinyCard, GradientButton, GradientHeader, GlassPill;

/// =========================================================================
/// LEAGUES  (unchanged — logic only)
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
/// FACULTY (dream course)  (unchanged)
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
/// COMPANION  (unchanged)
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
/// PROGRESS SNAPSHOT + SERVICE  (unchanged — logic only)
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

  Future<void> recordSession({required int correct, required int total}) async {
    try {
      await _client.rpc('arena_record_session', params: {'p_correct': correct, 'p_total': total});
      await load();
    } catch (_) {
      // Non-fatal — gamification shouldn't block the results screen.
    }
  }

  Future<int> answerBoss({required String subject, required bool correct}) async {
    final result = await _client.rpc('arena_boss_answer', params: {
      'p_subject': subject,
      'p_correct': correct,
    });
    final hp = (result as num).toInt();
    if (hp == 0) {
      await ZetraPay.creditAppCurrency(appId: ZetraPay.naijaLearnAppId, unitAmount: 5);
      await load();
    }
    return hp;
  }

  Future<List<Map<String, dynamic>>> getLeagueLeaderboard({int limit = 20}) async {
    final rows = await _client.rpc('arena_get_league_leaderboard', params: {'p_limit': limit});
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getFacultyStandings() async {
    final rows = await _client.rpc('arena_get_faculty_standings');
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getBossHallOfFame({int limit = 20}) async {
    final rows = await _client.rpc('arena_get_boss_hall_of_fame', params: {'p_limit': limit});
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<Map<String, dynamic>?> getRival() async {
    final result = await _client.rpc('arena_get_rival');
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }
}

/// =========================================================================
/// 🎮 DASHBOARD CARD — redesigned (embed in HomeScreen's Home tab)
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

  Future<void> _openAndRefresh(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    ArenaService.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ArenaService.instance,
      builder: (context, _) {
        final progress = ArenaService.instance.progress;
        if (progress == null) return const SizedBox.shrink();

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
                      subtitle: ArenaService.instance.leagueRank != null ? 'Rank #${ArenaService.instance.leagueRank}' : 'Unranked',
                      accent: progress.league.color,
                      onTap: () => _openAndRefresh(const LeagueScreen()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ArenaMiniTile(
                      icon: Text(facultyInfo?.icon ?? '🎓', style: const TextStyle(fontSize: 22)),
                      title: facultyInfo?.displayName ?? 'Pick a Faculty',
                      subtitle: ArenaService.instance.facultyRank != null ? 'Team Rank #${ArenaService.instance.facultyRank}' : 'Join a team',
                      accent: kVioletAccent,
                      onTap: () => _openAndRefresh(const FacultyWarScreen()),
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
                      accent: kTealAccent,
                      onTap: () => _openAndRefresh(const CompanionScreen()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ArenaMiniTile(
                      icon: const Text('🧬', style: TextStyle(fontSize: 22)),
                      title: 'Boss Battle',
                      subtitle: '${progress.bossDefeatedCount} defeated',
                      accent: kCoralAccent,
                      onTap: () => _openAndRefresh(const BossSelectScreen()),
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
  final Color accent;
  final VoidCallback onTap;
  const _ArenaMiniTile({required this.icon, required this.title, required this.subtitle, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: accent.withOpacity(0.15), shape: BoxShape.circle),
                child: icon,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(subtitle, style: TextStyle(fontSize: 10, color: accent), maxLines: 1, overflow: TextOverflow.ellipsis),
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
/// 🏅 LEAGUE SCREEN — redesigned
/// =========================================================================

class LeagueScreen extends StatefulWidget {
  const LeagueScreen({super.key});

  @override
  State<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends State<LeagueScreen> {
  late Future<List<Map<String, dynamic>>> _leaderboardFuture;
  late Future<Map<String, dynamic>?> _rivalFuture;

  @override
  void initState() {
    super.initState();
    _leaderboardFuture = ArenaService.instance.getLeagueLeaderboard();
    _rivalFuture = ArenaService.instance.getRival();
  }

  Future<void> _refresh() async {
    final next = ArenaService.instance.getLeagueLeaderboard();
    final nextRival = ArenaService.instance.getRival();
    setState(() {
      _leaderboardFuture = next;
      _rivalFuture = nextRival;
    });
    await Future.wait([next, nextRival]);
  }

  Widget _rivalCard(BuildContext context, Map<String, dynamic>? rival) {
    if (rival == null) return const SizedBox.shrink();
    if (rival['is_top'] == true) {
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA000)]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: kGoldAccent.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: const Row(
          children: [
            Text('👑', style: TextStyle(fontSize: 28)),
            SizedBox(width: 12),
            Expanded(
              child: Text("You're #1 in your league this week!",
                  style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ],
        ),
      );
    }
    final gap = (rival['xp_gap'] as num?)?.toInt() ?? 0;
    final username = rival['username'] as String? ?? 'Rival';
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: ShinyCard(
        tint: kCoralAccent,
        child: Row(
          children: [
            Text(rival['avatar_emoji'] as String? ?? '🎯', style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your Rival', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(
                    gap > 0 ? '$username is $gap XP ahead of you this week — catch up!' : "You're tied with $username!",
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = ArenaService.instance.progress;
    final myUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: GradientHeader(title: '🏅 Academic Leagues', subtitle: 'Climb the weekly ladder')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  children: [
                    if (progress != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [progress.league.color.withOpacity(0.85), progress.league.color]),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: progress.league.color.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))],
                        ),
                        child: Column(
                          children: [
                            Text(progress.league.emoji, style: const TextStyle(fontSize: 52)),
                            const SizedBox(height: 8),
                            Text('${progress.league.label} League', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 21, color: Colors.white)),
                            const SizedBox(height: 4),
                            Text(
                              ArenaService.instance.leagueRank != null
                                  ? 'Rank #${ArenaService.instance.leagueRank} of ${ArenaService.instance.leagueRankTotal}'
                                  : 'Unranked yet — start practicing!',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    FutureBuilder<Map<String, dynamic>?>(future: _rivalFuture, builder: (context, s) => _rivalCard(context, s.data)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text("This Week's League Leaderboard", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _leaderboardFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
                        }
                        final rows = snapshot.data ?? [];
                        if (rows.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text('No one ranked yet this week.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          );
                        }
                        final medalColors = [const Color(0xFFFFD700), const Color(0xFFC0C0C0), const Color(0xFFCD7F32)];
                        return Column(
                          children: rows.map((r) {
                            final rank = (r['rank'] as num).toInt();
                            final isMe = r['user_id'] == myUserId;
                            final isTop3 = rank <= 3;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ShinyCard(
                                padding: const EdgeInsets.all(12),
                                tint: isMe ? kVioletAccent : (isTop3 ? medalColors[rank - 1] : null),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: isTop3 ? medalColors[rank - 1] : kVioletAccent.withOpacity(0.12),
                                      child: Text('$rank', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isTop3 ? Colors.white : kVioletAccent)),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(r['avatar_emoji'] as String? ?? '🙂', style: const TextStyle(fontSize: 16)),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(r['username'] as String? ?? 'Student', style: const TextStyle(fontWeight: FontWeight.w600))),
                                    if (isMe)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(gradient: kHeroGradient, borderRadius: BorderRadius.circular(8)),
                                        child: const Text('You', style: TextStyle(fontSize: 10, color: Colors.white)),
                                      ),
                                    Text('${r['weekly_xp']} XP', style: const TextStyle(fontWeight: FontWeight.bold, color: kVioletAccent)),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    ShinyCard(
                      tint: kTealAccent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('How promotion works', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text(
                            'Every Monday, the top 20% of each league move up a tier, the bottom 20% move down, '
                            'and everyone else stays. Keep practicing to hold or climb your rank.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Align(alignment: Alignment.centerLeft, child: Text('League Ladder', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                    const SizedBox(height: 10),
                    ...League.values.reversed.map((l) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: progress?.league == l ? l.color.withOpacity(0.15) : Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                              border: progress?.league == l ? Border.all(color: l.color, width: 1.6) : null,
                            ),
                            child: Row(
                              children: [
                                Text(l.emoji, style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: 10),
                                Text(l.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (progress?.league == l) ...[
                                  const Spacer(),
                                  Text('You are here', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: l.color, fontWeight: FontWeight.w600)),
                                ],
                              ],
                            ),
                          ),
                        )),
                    const SizedBox(height: 24),
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

/// =========================================================================
/// ⚔️ FACULTY WAR SCREEN — redesigned
/// =========================================================================

class FacultyWarScreen extends StatefulWidget {
  const FacultyWarScreen({super.key});

  @override
  State<FacultyWarScreen> createState() => _FacultyWarScreenState();
}

class _FacultyWarScreenState extends State<FacultyWarScreen> {
  bool _saving = false;
  late Future<List<Map<String, dynamic>>> _standingsFuture;

  @override
  void initState() {
    super.initState();
    _standingsFuture = ArenaService.instance.getFacultyStandings();
  }

  Future<void> _refreshStandings() async {
    final next = ArenaService.instance.getFacultyStandings();
    setState(() => _standingsFuture = next);
    await next;
  }

  Future<void> _pick(String facultyId) async {
    setState(() => _saving = true);
    try {
      await ArenaService.instance.setFaculty(facultyId);
      _refreshStandings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not join that faculty — please try again.')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final progress = ArenaService.instance.progress;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshStandings,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: GradientHeader(title: '⚔️ Faculty War', subtitle: 'Team up for your dream course')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        progress?.faculty == null
                            ? 'Pick your dream course. Every correct answer earns XP for you AND your team.'
                            : "You're on Team ${kFaculties.firstWhere((f) => f.id == progress!.faculty).displayName}. Every correct answer helps your team's weekly rank.",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ...kFaculties.map((f) {
                      final isSelected = progress?.faculty == f.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: _saving ? null : () => _pick(f.id),
                            child: Builder(builder: (context) {
                              final scheme = Theme.of(context).colorScheme;
                              final isDark = Theme.of(context).brightness == Brightness.dark;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  gradient: isSelected ? kHeroGradient : null,
                                  color: isSelected ? null : scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: isDark ? null : [BoxShadow(color: (isSelected ? kVioletAccent : Colors.black).withOpacity(isSelected ? 0.3 : 0.05), blurRadius: 12, offset: const Offset(0, 4))],
                                ),
                                child: Row(
                                  children: [
                                    Text(f.icon, style: const TextStyle(fontSize: 24)),
                                    const SizedBox(width: 14),
                                    Expanded(child: Text(f.displayName, style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? Colors.white : scheme.onSurface))),
                                    if (isSelected) const Icon(Icons.check_circle_rounded, color: Colors.white),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                    Align(alignment: Alignment.centerLeft, child: Text("This Week's Standings", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                    const SizedBox(height: 10),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _standingsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
                        }
                        final rows = snapshot.data ?? [];
                        final medalColors = [const Color(0xFFFFD700), const Color(0xFFC0C0C0), const Color(0xFFCD7F32)];
                        return Column(
                          children: rows.map((r) {
                            final rank = (r['rank'] as num).toInt();
                            final isMine = r['faculty'] == progress?.faculty;
                            final isTop3 = rank <= 3;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ShinyCard(
                                padding: const EdgeInsets.all(12),
                                tint: isMine ? kVioletAccent : (isTop3 ? medalColors[rank - 1] : null),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: isTop3 ? medalColors[rank - 1] : kVioletAccent.withOpacity(0.12),
                                      child: Text('$rank', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isTop3 ? Colors.white : kVioletAccent)),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(r['icon'] as String? ?? '🎓', style: const TextStyle(fontSize: 18)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(r['display_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                          Text('${r['member_count']} members', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                        ],
                                      ),
                                    ),
                                    Text('${r['weekly_xp']} XP', style: const TextStyle(fontWeight: FontWeight.bold, color: kVioletAccent)),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
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

/// =========================================================================
/// 🧬 BOSS BATTLES — redesigned
/// =========================================================================

class BossSelectScreen extends StatelessWidget {
  const BossSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: GradientHeader(
              title: '🧬 Boss Battles',
              subtitle: 'Defeat subject bosses for rewards',
              trailing: IconButton(
                icon: const Icon(Icons.emoji_events_rounded, color: Colors.white),
                tooltip: 'Hall of Fame',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BossHallOfFameScreen())),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final subject = kSubjects[i];
                  final count = QuestionRepository.getForSubject(subject.name).length;
                  if (count == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ShinyCard(
                      padding: const EdgeInsets.all(16),
                      tint: subject.color,
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BossBattleScreen(subject: subject))),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: subject.color.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
                              child: Icon(subject.icon, color: subject.color, size: 26),
                            ),
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
                childCount: kSubjects.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =========================================================================
/// 🏆 BOSS HALL OF FAME — redesigned
/// =========================================================================

class BossHallOfFameScreen extends StatefulWidget {
  const BossHallOfFameScreen({super.key});

  @override
  State<BossHallOfFameScreen> createState() => _BossHallOfFameScreenState();
}

class _BossHallOfFameScreenState extends State<BossHallOfFameScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = ArenaService.instance.getBossHallOfFame();
  }

  Future<void> _refresh() async {
    final next = ArenaService.instance.getBossHallOfFame();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: GradientHeader(title: '🧬 Boss Hall of Fame', subtitle: 'Ranked by bosses defeated')),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));
                }
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(child: Text('No bosses defeated yet — be the first!', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                    ),
                  );
                }
                final medalColors = [const Color(0xFFFFD700), const Color(0xFFC0C0C0), const Color(0xFFCD7F32)];
                return SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final r = rows[i];
                        final rank = (r['rank'] as num).toInt();
                        final isMe = r['user_id'] == myUserId;
                        final isTop3 = rank <= 3;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ShinyCard(
                            padding: const EdgeInsets.all(14),
                            tint: isMe ? kVioletAccent : (isTop3 ? medalColors[rank - 1] : null),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: isTop3 ? medalColors[rank - 1] : kVioletAccent.withOpacity(0.12),
                                  child: Text('$rank', style: TextStyle(fontWeight: FontWeight.bold, color: isTop3 ? Colors.white : kVioletAccent)),
                                ),
                                const SizedBox(width: 12),
                                Text(r['avatar_emoji'] as String? ?? '🙂', style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 8),
                                Expanded(child: Text(r['username'] as String? ?? 'Student', style: const TextStyle(fontWeight: FontWeight.w600))),
                                if (isMe)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(gradient: kHeroGradient, borderRadius: BorderRadius.circular(8)),
                                    child: const Text('You', style: TextStyle(fontSize: 10, color: Colors.white)),
                                  ),
                                Row(children: [
                                  const Text('🧬', style: TextStyle(fontSize: 14)),
                                  const SizedBox(width: 4),
                                  Text('${r['boss_defeated_count']}', style: const TextStyle(fontWeight: FontWeight.bold, color: kVioletAccent)),
                                ]),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: rows.length,
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
    _hp = ArenaService.instance.progress?.activeBossSubject == widget.subject.name ? ArenaService.instance.progress!.bossHpRemaining : 100;
  }

  Future<void> _answer(int optionIndex) async {
    if (_answering || _defeated) return;
    final question = _questions[_index];
    final correct = optionIndex == question.correctIndex;
    setState(() => _answering = true);

    int newHp;
    try {
      newHp = await ArenaService.instance.answerBoss(subject: widget.subject.name, correct: correct);
    } catch (e) {
      if (mounted) {
        setState(() => _answering = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not reach the server — please try again.')));
      }
      return;
    }

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
    if (_questions.isEmpty) {
      return const Scaffold(body: Center(child: Text('No questions available for this boss yet.')));
    }

    if (_defeated) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: kHeroGradient),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏆', style: TextStyle(fontSize: 72)),
                const SizedBox(height: 16),
                Text('${widget.subject.name} Boss Defeated!',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text('+5 CP earned', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 28),
                SizedBox(
                  width: 200,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kVioletAccent),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to Bosses'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final question = _questions[_index];
    final hpColor = _hp > 40 ? kCoralAccent : kGoldAccent;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close_rounded)),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: widget.subject.color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                    child: Icon(widget.subject.icon, color: widget.subject.color, size: 26),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${widget.subject.name} Boss', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Boss HP: $_hp%', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(value: _hp / 100, minHeight: 16, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest, valueColor: AlwaysStoppedAnimation(hpColor)),
              ),
              const SizedBox(height: 28),
              ShinyCard(child: Text(question.questionText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4))),
              const SizedBox(height: 18),
              ...List.generate(question.options.length, (i) {
                final letter = String.fromCharCode(65 + i);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 0,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _answering ? null : () => _answer(i),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
                        child: Text('$letter. ${question.options[i]}'),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// 🐾 COMPANION SCREEN — redesigned
/// =========================================================================

class CompanionScreen extends StatelessWidget {
  const CompanionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = ArenaService.instance.progress;

    if (progress == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final xpIntoLevel = progress.companionXp % 200;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: kHeroGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(children: [IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white))]),
                const Spacer(),
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.35), width: 3)),
                  child: Center(child: Text(progress.companionSpecies.emoji, style: const TextStyle(fontSize: 84))),
                ),
                const SizedBox(height: 18),
                Text('${progress.companionSpecies.name} — Level ${progress.companionLevel}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
                const SizedBox(height: 8),
                Text(
                  progress.companionFedToday ? 'Fed today — great job keeping the streak alive!' : "Hasn't been fed today. Complete a study session to feed it.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(value: xpIntoLevel / 200, minHeight: 12, backgroundColor: Colors.white.withOpacity(0.25), valueColor: const AlwaysStoppedAnimation(Colors.white)),
                ),
                const SizedBox(height: 6),
                Text('$xpIntoLevel / 200 XP to next level', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// 🎫 SEASON PASS BANNER — redesigned
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
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: const Color(0xFF7B2FF7).withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Season ${progress.seasonId} · $daysLeft days left', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
