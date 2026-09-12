// lib/challenge_feature.dart
//
// ⚡ v3 — SOCIAL FRIEND-TO-FRIEND, NOT ANOTHER COMPETITION SYSTEM.
//
// NaijaLearn already has Bot Battle, Connect Baba, World Challenge, and
// Tutor Competition covering AI, head-to-head, large recurring, and
// classroom competition respectively. This feature's job stays narrow on
// purpose: quick, social, friend-to-friend bragging rights. That's why
// there's no tournament mode, no teams, no seasons, and no Cent-money
// mode here (that's a deliberate future add, kept separate — see notes
// at the bottom).
//
// Backed by challenges_migration_v2.sql + challenges_migration_v3_patch.sql
// (adds anti-cheat validation on submit + overtake-alert tracking).
//
// WHAT'S NEW IN v3:
//   - Share text leads with the score: "CAN YOU BEAT ME? I scored 8/10"
//   - Rematch: one tap recreates the same subject/count, no reconfiguring
//   - Leaderboard shows a compact "Your Stats" strip (best score, accuracy,
//     attempts, rank, points behind #1) instead of turning into an
//     analytics page
//   - My Challenges shows a status badge per card (Waiting / Leading /
//     Beaten) with a one-tap "Take Back #1" retake when beaten
//   - ChallengesHubScreen checks for overtake alerts on open — "X just
//     beat your score" — and offers Take Back #1 right there
//
// WHAT'S DELIBERATELY NOT HERE (see conversation notes, not a bug):
//   - Difficulty filtering — the Question model has no difficulty field
//     anywhere in the app; faking a selector that doesn't filter anything
//     would be worse than not having one
//   - Real push notifications — "beat your score" while the app is fully
//     closed needs FCM/device tokens/a server trigger, a separate
//     infrastructure project. What's here is an in-app check on open.
//   - Cent Challenge (paid mode) — intentionally deferred and kept out of
//     the free social flow

import 'dart:async';
import 'dart:math';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart' show Question, QuestionRepository, SubjectInfo, kSubjects;

const String kChallengeLandingPageBaseUrl = 'https://zetrasystemsq8-beep.github.io/Naijalearn-landing-page/';

class _ChallengeTheme {
  static const bg = Color(0xFF0B0E1A);
  static const cardTop = Color(0xFF12122A);
  static const cardBottom = Color(0xFF1A1440);
  static const cyan = Color(0xFF00E5FF);
  static const purple = Color(0xFFB388FF);
  static const gold = Color(0xFFFFD700);
  static const silver = Color(0xFFC0C0C0);
  static const bronze = Color(0xFFCD7F32);
  static const danger = Color(0xFFFF5A5F);

  static BoxDecoration glassCard({Color accent = cyan}) => BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cardTop, cardBottom]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.35)),
        boxShadow: [BoxShadow(color: accent.withOpacity(0.18), blurRadius: 30, spreadRadius: 1)],
      );

  static AppBar appBar(String title, {bool showBack = true}) => AppBar(
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: bg,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        automaticallyImplyLeading: showBack,
        elevation: 0,
      );
}

/// =========================================================================
/// SERVICE
/// =========================================================================

class ChallengeAttempt {
  final String userId;
  final String username;
  final int score;
  final int total;
  final int attemptCount;
  final bool isMe;

  ChallengeAttempt({
    required this.userId,
    required this.username,
    required this.score,
    required this.total,
    required this.attemptCount,
    required this.isMe,
  });

  factory ChallengeAttempt.fromMap(Map<String, dynamic> map) => ChallengeAttempt(
        userId: map['user_id'] as String? ?? '',
        username: map['username'] as String? ?? 'Player',
        score: (map['score'] as num?)?.toInt() ?? 0,
        total: (map['total'] as num?)?.toInt() ?? 0,
        attemptCount: (map['attempt_count'] as num?)?.toInt() ?? 1,
        isMe: map['is_me'] as bool? ?? false,
      );

  double get pct => total > 0 ? score / total : 0.0;
}

class ChallengeWithAttempts {
  final String id;
  final String subject;
  final String creatorUsername;
  final String creatorId;
  final List<String> questionIds;
  final List<ChallengeAttempt> attempts;

  ChallengeWithAttempts({
    required this.id,
    required this.subject,
    required this.creatorUsername,
    required this.creatorId,
    required this.questionIds,
    required this.attempts,
  });

  factory ChallengeWithAttempts.fromMap(Map<String, dynamic> map) => ChallengeWithAttempts(
        id: map['id'] as String,
        subject: map['subject'] as String? ?? 'Practice',
        creatorUsername: map['creator_username'] as String? ?? 'Someone',
        creatorId: map['creator_id'] as String? ?? '',
        questionIds: (map['question_ids'] as List? ?? []).cast<String>(),
        attempts: (map['attempts'] as List? ?? [])
            .map((a) => ChallengeAttempt.fromMap(Map<String, dynamic>.from(a as Map)))
            .toList(),
      );
}

class OvertakeAlert {
  final String challengeId;
  final String subject;
  final int yourScore;
  final int yourTotal;
  final String leaderUsername;
  final int leaderScore;

  OvertakeAlert({
    required this.challengeId,
    required this.subject,
    required this.yourScore,
    required this.yourTotal,
    required this.leaderUsername,
    required this.leaderScore,
  });

  factory OvertakeAlert.fromMap(Map<String, dynamic> map) => OvertakeAlert(
        challengeId: map['challenge_id'] as String,
        subject: map['subject'] as String? ?? 'Practice',
        yourScore: (map['your_score'] as num?)?.toInt() ?? 0,
        yourTotal: (map['your_total'] as num?)?.toInt() ?? 0,
        leaderUsername: map['leader_username'] as String? ?? 'Someone',
        leaderScore: (map['leader_score'] as num?)?.toInt() ?? 0,
      );
}

class ChallengeService {
  ChallengeService._();
  static final ChallengeService instance = ChallengeService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<String> createChallenge({required String type, required String subject, required List<String> questionIds}) async {
    final result = await _client.rpc('create_challenge', params: {'p_type': type, 'p_subject': subject, 'p_question_ids': questionIds});
    return result as String;
  }

  Future<String> getOrCreateDailyChallenge({required String subject, required List<String> questionIds}) async {
    final result = await _client.rpc('get_or_create_daily_challenge', params: {'p_subject': subject, 'p_question_ids': questionIds});
    return result as String;
  }

  Future<void> submitAttempt({required String challengeId, required int score, required int total}) async {
    await _client.rpc('submit_challenge_attempt', params: {'p_challenge_id': challengeId, 'p_score': score, 'p_total': total});
  }

  Future<ChallengeWithAttempts?> getChallengeWithAttempts(String challengeId) async {
    final result = await _client.rpc('get_challenge_with_attempts', params: {'p_challenge_id': challengeId});
    if (result == null) return null;
    return ChallengeWithAttempts.fromMap(Map<String, dynamic>.from(result as Map));
  }

  Future<List<ChallengeWithAttempts>> getMyChallenges() async {
    final result = await _client.rpc('get_my_challenges');
    return (result as List)
        .map((c) => ChallengeWithAttempts.fromMap(Map<String, dynamic>.from(c as Map)))
        .toList();
  }

  /// Challenges where someone else's score has passed the current user's
  /// since they last checked. Call once when the hub opens.
  Future<List<OvertakeAlert>> getOvertakeAlerts() async {
    final result = await _client.rpc('get_overtake_alerts');
    return (result as List)
        .map((a) => OvertakeAlert.fromMap(Map<String, dynamic>.from(a as Map)))
        .toList();
  }

  Future<void> acknowledgeOvertakeAlert(String challengeId) async {
    await _client.rpc('acknowledge_overtake_alert', params: {'p_challenge_id': challengeId});
  }
}

/// =========================================================================
/// SHARE TEXT + WHATSAPP
/// =========================================================================

String _landingLink(String challengeId) => '$kChallengeLandingPageBaseUrl?id=$challengeId';

/// Leads with the score — this is the viral hook, not a generic invite.
String buildFriendChallengeShareText({
  required String subject,
  required int score,
  required int total,
  required String challengeId,
}) {
  return '⚔️ *CAN YOU BEAT ME?*\n\n'
      'I scored *$score/$total* on $subject in NaijaLearn.\n\n'
      "I'm waiting for you 👀\n"
      'Take the challenge → ${_landingLink(challengeId)}';
}

String buildDailyQuestionShareText({required Question question, required String challengeId}) {
  final letters = ['A', 'B', 'C', 'D'];
  final optionsText = List.generate(question.options.length, (i) => '${letters[i]}. ${question.options[i]}').join('\n');
  return '🧠 *NaijaLearn Daily Challenge*\n\n'
      "Today's question:\n${question.questionText}\n\n"
      '$optionsText\n\n'
      "Don't just guess. Challenge your friends. 😏\n"
      'Answer here → ${_landingLink(challengeId)}';
}

Future<void> shareToWhatsApp(String text) async {
  final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// =========================================================================
/// DEEP LINK LISTENER
/// =========================================================================

class ChallengeDeepLinkListener {
  ChallengeDeepLinkListener._();
  static StreamSubscription<Uri>? _sub;

  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    final appLinks = AppLinks();
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) _handle(initial, navigatorKey);
    } catch (e) {
      debugPrint('[ChallengeDeepLink] getInitialLink failed: $e');
    }
    _sub?.cancel();
    _sub = appLinks.uriLinkStream.listen((uri) => _handle(uri, navigatorKey), onError: (e) => debugPrint('[ChallengeDeepLink] stream error: $e'));
  }

  static void _handle(Uri uri, GlobalKey<NavigatorState> navigatorKey) {
    debugPrint('[ChallengeDeepLink] received: $uri');
    if (uri.scheme != 'naijalearn') return;
    final segments = uri.pathSegments;
    String? challengeId;
    if (uri.host == 'challenge' && segments.isNotEmpty) {
      challengeId = segments.first;
    } else if (segments.length >= 2 && segments.first == 'challenge') {
      challengeId = segments[1];
    }
    if (challengeId == null || challengeId.isEmpty) return;
    navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ChallengeAnswerScreen(challengeId: challengeId!)));
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

/// =========================================================================
/// SHARED HELPER — start a brand-new challenge for a subject/count and
/// route the caller through answering it. Used by both "Create" and
/// "Rematch" so there's exactly one code path for "make a new challenge".
/// =========================================================================

Future<void> _startNewChallengeFlow(BuildContext context, {required SubjectInfo subject, required int questionCount}) async {
  try {
    final pool = QuestionRepository.getForSubject(subject.name)..shuffle();
    final picked = pool.take(questionCount).toList();
    if (picked.isEmpty) {
      throw Exception('No questions available for ${subject.name} yet.');
    }

    final challengeId = await ChallengeService.instance.createChallenge(
      type: 'challenge',
      subject: subject.name,
      questionIds: picked.map((q) => q.id).toList(),
    );

    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ChallengeAnswerScreen(
        challengeId: challengeId,
        preloadedQuestions: picked,
        preloadedSubject: subject.name,
        isCreatorFirstAttempt: true,
      ),
    ));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create challenge: $e')));
    }
  }
}

/// =========================================================================
/// HUB — checks for overtake alerts on open
/// =========================================================================

class ChallengesHubScreen extends StatefulWidget {
  const ChallengesHubScreen({super.key});

  @override
  State<ChallengesHubScreen> createState() => _ChallengesHubScreenState();
}

class _ChallengesHubScreenState extends State<ChallengesHubScreen> {
  List<OvertakeAlert> _alerts = [];
  bool _alertsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    try {
      final alerts = await ChallengeService.instance.getOvertakeAlerts();
      if (mounted) setState(() {
        _alerts = alerts;
        _alertsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _alertsLoading = false);
    }
  }

  Future<void> _dismissAlert(OvertakeAlert alert) async {
    setState(() => _alerts.removeWhere((a) => a.challengeId == alert.challengeId));
    try {
      await ChallengeService.instance.acknowledgeOvertakeAlert(alert.challengeId);
    } catch (_) {
      // non-fatal — worst case the alert reappears next open
    }
  }

  Future<void> _takeBackFirst(OvertakeAlert alert) async {
    await _dismissAlert(alert);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChallengeAnswerScreen(challengeId: alert.challengeId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ChallengeTheme.bg,
      appBar: _ChallengeTheme.appBar('Challenges'),
      body: Stack(
        children: [
          Positioned(top: -80, left: -60, child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: _ChallengeTheme.purple.withOpacity(0.18)))),
          Positioned(bottom: -100, right: -60, child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, color: _ChallengeTheme.cyan.withOpacity(0.12)))),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!_alertsLoading && _alerts.isNotEmpty) ...[
                  ..._alerts.map((a) => _OvertakeBanner(
                        alert: a,
                        onTakeBack: () => _takeBackFirst(a),
                        onDismiss: () => _dismissAlert(a),
                      )),
                  const SizedBox(height: 8),
                ],
                Text('Quick, social, friend-to-friend. No leaderboards to grind — just bragging rights.', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                const SizedBox(height: 20),
                _HubCard(
                  accent: _ChallengeTheme.cyan,
                  icon: Icons.bolt_rounded,
                  title: 'Challenge a Friend',
                  subtitle: 'Pick a subject, answer it, share your score',
                  ctaLabel: 'Create Challenge',
                  primary: true,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateChallengeScreen())),
                ),
                const SizedBox(height: 16),
                _HubCard(
                  accent: _ChallengeTheme.gold,
                  icon: Icons.leaderboard_rounded,
                  title: 'My Challenges',
                  subtitle: "See who's leading, who beat you, who to take back",
                  ctaLabel: 'View My Challenges',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyChallengesScreen())),
                ),
                const SizedBox(height: 16),
                _HubCard(
                  accent: _ChallengeTheme.purple,
                  icon: Icons.wb_sunny_rounded,
                  title: 'Daily Question',
                  subtitle: "Share today's question — answer is hidden until they open the app",
                  ctaLabel: "Share Today's Question",
                  onTap: () => _shareDaily(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareDaily(BuildContext context) async {
    try {
      final all = QuestionRepository.getAll()..shuffle(Random(DateTime.now().day));
      final question = all.first;
      final challengeId = await ChallengeService.instance.getOrCreateDailyChallenge(subject: question.subject, questionIds: [question.id]);
      await shareToWhatsApp(buildDailyQuestionShareText(question: question, challengeId: challengeId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not share today's question: $e")));
      }
    }
  }
}

class _OvertakeBanner extends StatelessWidget {
  final OvertakeAlert alert;
  final VoidCallback onTakeBack;
  final VoidCallback onDismiss;
  const _OvertakeBanner({required this.alert, required this.onTakeBack, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_ChallengeTheme.danger.withOpacity(0.18), _ChallengeTheme.danger.withOpacity(0.06)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _ChallengeTheme.danger.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alert.leaderUsername} just beat your ${alert.subject} score!',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                const SizedBox(height: 3),
                Text(
                  'You: ${alert.yourScore}/${alert.yourTotal}  ·  Them: ${alert.leaderScore}/${alert.yourTotal}',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      height: 36,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _ChallengeTheme.danger, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 14)),
                        onPressed: onTakeBack,
                        child: const Text('Take Back #1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onDismiss,
                      child: Text('Dismiss', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback onTap;
  final bool primary;

  const _HubCard({required this.accent, required this.icon, required this.title, required this.subtitle, required this.ctaLabel, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: primary
          ? BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accent.withOpacity(0.25), _ChallengeTheme.cardBottom]),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent, width: 1.6),
              boxShadow: [BoxShadow(color: accent.withOpacity(0.3), blurRadius: 36, spreadRadius: 1)],
            )
          : _ChallengeTheme.glassCard(accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 48, height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: accent.withOpacity(0.15), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: accent, size: 24)),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: onTap,
              child: Text(ctaLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectPillButton extends StatelessWidget {
  final SubjectInfo subject;
  final bool selected;
  final VoidCallback onTap;
  const _SubjectPillButton({required this.subject, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _ChallengeTheme.cyan : Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? _ChallengeTheme.cyan : Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(subject.icon, size: 16, color: selected ? Colors.black : subject.color),
              const SizedBox(width: 6),
              Text(subject.name, style: TextStyle(color: selected ? Colors.black : Colors.white.withOpacity(0.85), fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// CREATE A CHALLENGE — deliberately just two questions asked: subject,
/// count. No difficulty step (no difficulty data exists yet — see file
/// header), no other configuration.
/// =========================================================================

class CreateChallengeScreen extends StatefulWidget {
  const CreateChallengeScreen({super.key});

  @override
  State<CreateChallengeScreen> createState() => _CreateChallengeScreenState();
}

class _CreateChallengeScreenState extends State<CreateChallengeScreen> {
  SubjectInfo? _selectedSubject;
  int _questionCount = 5;
  bool _creating = false;

  static const List<int> _counts = [5, 10, 15];

  Future<void> _create() async {
    final subject = _selectedSubject;
    if (subject == null) return;
    setState(() => _creating = true);
    await _startNewChallengeFlow(context, subject: subject, questionCount: _questionCount);
    if (mounted) setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ChallengeTheme.bg,
      appBar: _ChallengeTheme.appBar('Challenge a Friend'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('1. Pick a subject', style: _sectionStyle()),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kSubjects.map((s) {
                final selected = _selectedSubject?.name == s.name;
                return _SubjectPillButton(subject: s, selected: selected, onTap: () => setState(() => _selectedSubject = s));
              }).toList(),
            ),
            const SizedBox(height: 28),
            Text('2. Number of questions', style: _sectionStyle()),
            const SizedBox(height: 12),
            Row(
              children: _counts.map((c) {
                final selected = _questionCount == c;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: selected ? _ChallengeTheme.cyan.withOpacity(0.15) : Colors.transparent,
                        side: BorderSide(color: selected ? _ChallengeTheme.cyan : Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => setState(() => _questionCount = c),
                      child: Text('$c', style: TextStyle(color: selected ? _ChallengeTheme.cyan : Colors.white70, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _selectedSubject == null ? Colors.white24 : _ChallengeTheme.cyan,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: _creating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Start', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                onPressed: (_selectedSubject == null || _creating) ? null : _create,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _sectionStyle() => const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold);
}

/// =========================================================================
/// ANSWER A CHALLENGE
/// =========================================================================

class ChallengeAnswerScreen extends StatefulWidget {
  final String challengeId;
  final List<Question>? preloadedQuestions;
  final String? preloadedSubject;
  final bool isCreatorFirstAttempt;

  const ChallengeAnswerScreen({
    super.key,
    required this.challengeId,
    this.preloadedQuestions,
    this.preloadedSubject,
    this.isCreatorFirstAttempt = false,
  });

  @override
  State<ChallengeAnswerScreen> createState() => _ChallengeAnswerScreenState();
}

class _ChallengeAnswerScreenState extends State<ChallengeAnswerScreen> {
  List<Question> _questions = [];
  String _subject = '';
  bool _loading = true;
  String? _error;

  int _currentIndex = 0;
  int? _selectedOption;
  int _correctCount = 0;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedQuestions != null) {
      _questions = widget.preloadedQuestions!;
      _subject = widget.preloadedSubject ?? '';
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final challenge = await ChallengeService.instance.getChallengeWithAttempts(widget.challengeId);
      if (challenge == null) {
        setState(() {
          _error = 'This challenge no longer exists.';
          _loading = false;
        });
        return;
      }

      final all = QuestionRepository.getAll();
      final byId = {for (final q in all) q.id: q};
      final resolved = challenge.questionIds.map((id) => byId[id]).whereType<Question>().toList();

      if (resolved.isEmpty) {
        setState(() {
          _error = "This challenge's questions aren't available on your app version.";
          _loading = false;
        });
        return;
      }

      setState(() {
        _questions = resolved;
        _subject = challenge.subject;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load this challenge. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  void _selectOption(int i) => setState(() => _selectedOption = i);

  void _next() {
    if (_currentIndex < 0 || _currentIndex >= _questions.length) return;

    final question = _questions[_currentIndex];
    final wasCorrect = _selectedOption == question.correctIndex;
    if (wasCorrect) _correctCount++;

    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOption = null;
      });
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await ChallengeService.instance.submitAttempt(challengeId: widget.challengeId, score: _correctCount, total: _questions.length);
    } catch (e) {
      debugPrint('[ChallengeAnswerScreen] submitAttempt failed (non-fatal): $e');
    }
    if (!mounted) return;

    if (widget.isCreatorFirstAttempt) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChallengeCreatedResultScreen(subject: _subject, score: _correctCount, total: _questions.length, challengeId: widget.challengeId),
      ));
      return;
    }

    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ChallengeResultScreen(subject: _subject, score: _correctCount, total: _questions.length, challengeId: widget.challengeId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: _ChallengeTheme.bg, body: Center(child: CircularProgressIndicator(color: _ChallengeTheme.cyan)));
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: _ChallengeTheme.bg,
        appBar: _ChallengeTheme.appBar('Challenge'),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)))),
      );
    }
    if (_currentIndex < 0 || _currentIndex >= _questions.length) {
      return Scaffold(
        backgroundColor: _ChallengeTheme.bg,
        appBar: _ChallengeTheme.appBar('Challenge'),
        body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Something went wrong loading this question.', style: TextStyle(color: Colors.white70)))),
      );
    }

    final question = _questions[_currentIndex];

    return Scaffold(
      backgroundColor: _ChallengeTheme.bg,
      appBar: _ChallengeTheme.appBar('Question ${_currentIndex + 1} of ${_questions.length}', showBack: !widget.isCreatorFirstAttempt),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: _currentIndex / _questions.length, backgroundColor: Colors.white12, valueColor: const AlwaysStoppedAnimation(_ChallengeTheme.cyan), minHeight: 6),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: _ChallengeTheme.glassCard(),
                child: Text(question.questionText, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4, color: Colors.white)),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView.separated(
                  itemCount: question.options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final isSelected = _selectedOption == i;
                    final letter = String.fromCharCode(65 + i);
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _selectOption(i),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected ? _ChallengeTheme.cyan.withOpacity(0.15) : Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSelected ? _ChallengeTheme.cyan : Colors.white12, width: isSelected ? 2 : 1),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(radius: 14, backgroundColor: isSelected ? _ChallengeTheme.cyan : Colors.white12, child: Text(letter, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? Colors.black : Colors.white70))),
                              const SizedBox(width: 14),
                              Expanded(child: Text(question.options[i], style: const TextStyle(fontSize: 15, color: Colors.white))),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _selectedOption == null ? Colors.white24 : _ChallengeTheme.cyan, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: (_selectedOption == null || _finishing) ? null : _next,
                  child: _finishing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Text(_currentIndex == _questions.length - 1 ? 'Finish' : 'Next', style: const TextStyle(fontWeight: FontWeight.bold)),
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
/// CREATOR'S OWN-SCORE SCREEN — the primary CTA is sharing, not exploring
/// a leaderboard. Rematch sits right there too.
/// =========================================================================

class ChallengeCreatedResultScreen extends StatelessWidget {
  final String subject;
  final int score;
  final int total;
  final String challengeId;

  const ChallengeCreatedResultScreen({super.key, required this.subject, required this.score, required this.total, required this.challengeId});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? score / total : 0.0;

    return Scaffold(
      backgroundColor: _ChallengeTheme.bg,
      appBar: _ChallengeTheme.appBar('Your Score', showBack: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: _ChallengeTheme.glassCard(),
                child: Column(
                  children: [
                    Text(subject.toUpperCase(), style: const TextStyle(color: _ChallengeTheme.cyan, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12)),
                    const SizedBox(height: 14),
                    Text('$score/$total', style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('${(pct * 100).toStringAsFixed(0)}% correct', style: const TextStyle(color: Colors.white60)),
                    const SizedBox(height: 18),
                    Text('Now challenge a friend to beat it 👀', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _ChallengeTheme.cyan, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('Share to WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => shareToWhatsApp(buildFriendChallengeShareText(subject: subject, score: score, total: total, challengeId: challengeId)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  icon: const Icon(Icons.leaderboard_rounded),
                  label: const Text('View Leaderboard', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChallengeLeaderboardScreen(challengeId: challengeId, subject: subject),
                  )),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done', style: TextStyle(color: Colors.white54))),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// FRIEND'S RESULT SCREEN — Rematch is the headline action here, since
/// they just played and beating the person back is the natural next step.
/// =========================================================================

class ChallengeResultScreen extends StatelessWidget {
  final String subject;
  final int score;
  final int total;
  final String challengeId;

  const ChallengeResultScreen({
    super.key,
    required this.subject,
    required this.score,
    required this.total,
    required this.challengeId,
  });

  Future<void> _rematch(BuildContext context) async {
    final matches = kSubjects.where((s) => s.name == subject);
    final subjectInfo = matches.isEmpty ? kSubjects.first : matches.first;
    await _startNewChallengeFlow(context, subject: subjectInfo, questionCount: total);
  }

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? score / total : 0.0;

    return Scaffold(
      backgroundColor: _ChallengeTheme.bg,
      appBar: _ChallengeTheme.appBar('Result', showBack: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: _ChallengeTheme.glassCard(),
                child: Column(
                  children: [
                    Text(subject.toUpperCase(), style: const TextStyle(color: _ChallengeTheme.cyan, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12)),
                    const SizedBox(height: 14),
                    Text('$score/$total', style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('${(pct * 100).toStringAsFixed(0)}% correct', style: const TextStyle(color: Colors.white60)),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _ChallengeTheme.cyan, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Rematch ⚔️', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => _rematch(context),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  icon: const Icon(Icons.leaderboard_rounded),
                  label: const Text('See Where You Rank', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChallengeLeaderboardScreen(challengeId: challengeId, subject: subject),
                  )),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('Back to Home', style: TextStyle(color: Colors.white54))),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// LEADERBOARD — top scores plus a compact "Your Stats" strip. Deliberately
/// NOT an analytics page: five numbers, not fifteen.
/// =========================================================================

class ChallengeLeaderboardScreen extends StatefulWidget {
  final String challengeId;
  final String subject;
  const ChallengeLeaderboardScreen({super.key, required this.challengeId, required this.subject});

  @override
  State<ChallengeLeaderboardScreen> createState() => _ChallengeLeaderboardScreenState();
}

class _ChallengeLeaderboardScreenState extends State<ChallengeLeaderboardScreen> {
  ChallengeWithAttempts? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ChallengeService.instance.getChallengeWithAttempts(widget.challengeId);
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load the leaderboard. Pull down to try again.';
        _loading = false;
      });
    }
  }

  Future<void> _rematch() async {
    final matches = kSubjects.where((s) => s.name == widget.subject);
    final subjectInfo = matches.isEmpty ? kSubjects.first : matches.first;
    final myTotal = _data?.attempts.firstWhere((a) => a.isMe, orElse: () => _data!.attempts.first).total ?? 10;
    await _startNewChallengeFlow(context, subject: subjectInfo, questionCount: myTotal);
  }

  @override
  Widget build(BuildContext context) {
    final myAttempt = _data?.attempts.where((a) => a.isMe).cast<ChallengeAttempt?>().firstWhere((a) => true, orElse: () => null);
    final myRankIndex = _data?.attempts.indexWhere((a) => a.isMe) ?? -1;
    final topScore = (_data != null && _data!.attempts.isNotEmpty) ? _data!.attempts.first.score : 0;

    return Scaffold(
      backgroundColor: _ChallengeTheme.bg,
      appBar: _ChallengeTheme.appBar('${widget.subject} Leaderboard'),
      body: SafeArea(
        child: RefreshIndicator(
          color: _ChallengeTheme.cyan,
          backgroundColor: _ChallengeTheme.cardTop,
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _ChallengeTheme.cyan))
              : _error != null
                  ? ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)))])
                  : (_data == null || _data!.attempts.isEmpty)
                      ? ListView(children: const [
                          Padding(
                            padding: EdgeInsets.all(40),
                            child: Text('No one has played this yet — be the first!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                          ),
                        ])
                      : ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            if (myAttempt != null && myRankIndex >= 0)
                              _YourStatsStrip(
                                attempt: myAttempt,
                                rank: myRankIndex + 1,
                                pointsBehindLeader: topScore - myAttempt.score,
                                onRematch: _rematch,
                              ),
                            const SizedBox(height: 8),
                            ..._data!.attempts.asMap().entries.map((e) => _LeaderboardRow(rank: e.key + 1, attempt: e.value)),
                          ],
                        ),
        ),
      ),
    );
  }
}

class _YourStatsStrip extends StatelessWidget {
  final ChallengeAttempt attempt;
  final int rank;
  final int pointsBehindLeader;
  final VoidCallback onRematch;

  const _YourStatsStrip({required this.attempt, required this.rank, required this.pointsBehindLeader, required this.onRematch});

  @override
  Widget build(BuildContext context) {
    final isLeading = rank == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: _ChallengeTheme.glassCard(accent: isLeading ? _ChallengeTheme.gold : _ChallengeTheme.cyan),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Your Stats', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              if (!isLeading)
                TextButton.icon(
                  onPressed: onRematch,
                  icon: const Icon(Icons.replay_rounded, size: 16, color: _ChallengeTheme.cyan),
                  label: const Text('Rematch', style: TextStyle(color: _ChallengeTheme.cyan, fontWeight: FontWeight.bold, fontSize: 12.5)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatColumn(label: 'Best', value: '${attempt.score}/${attempt.total}'),
              _StatColumn(label: 'Accuracy', value: '${(attempt.pct * 100).toStringAsFixed(0)}%'),
              _StatColumn(label: 'Attempts', value: '${attempt.attemptCount}'),
              _StatColumn(label: 'Rank', value: '#$rank'),
              _StatColumn(label: isLeading ? 'Lead' : 'Behind', value: isLeading ? "You're #1" : '$pointsBehindLeader pts'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10.5), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final ChallengeAttempt attempt;
  const _LeaderboardRow({required this.rank, required this.attempt});

  Color? get _medalColor {
    switch (rank) {
      case 1:
        return _ChallengeTheme.gold;
      case 2:
        return _ChallengeTheme.silver;
      case 3:
        return _ChallengeTheme.bronze;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final medal = _medalColor;
    final isTop = rank == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: attempt.isMe ? _ChallengeTheme.cyan.withOpacity(0.12) : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: attempt.isMe ? _ChallengeTheme.cyan : (medal ?? Colors.white12),
          width: attempt.isMe || medal != null ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: medal != null
                ? Icon(isTop ? Icons.emoji_events_rounded : Icons.military_tech_rounded, color: medal, size: 26)
                : Text('#$rank', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    attempt.username,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                ),
                if (attempt.isMe) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: _ChallengeTheme.cyan, borderRadius: BorderRadius.circular(6)),
                    child: const Text('YOU', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 9)),
                  ),
                ],
              ],
            ),
          ),
          Text('${attempt.score}/${attempt.total}', style: TextStyle(color: medal ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}

/// =========================================================================
/// MY CHALLENGES — status badge per card, one-tap retake when beaten.
/// =========================================================================

class MyChallengesScreen extends StatefulWidget {
  const MyChallengesScreen({super.key});

  @override
  State<MyChallengesScreen> createState() => _MyChallengesScreenState();
}

class _MyChallengesScreenState extends State<MyChallengesScreen> {
  List<ChallengeWithAttempts> _challenges = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final challenges = await ChallengeService.instance.getMyChallenges();
      setState(() {
        _challenges = challenges;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load your challenges. Pull down to try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ChallengeTheme.bg,
      appBar: _ChallengeTheme.appBar('My Challenges'),
      body: SafeArea(
        child: RefreshIndicator(
          color: _ChallengeTheme.cyan,
          backgroundColor: _ChallengeTheme.cardTop,
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _ChallengeTheme.cyan))
              : _error != null
                  ? ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)))])
                  : _challenges.isEmpty
                      ? ListView(children: const [
                          Padding(
                            padding: EdgeInsets.all(40),
                            child: Text('You haven\'t created or played any challenges yet.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                          ),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: _challenges.length,
                          itemBuilder: (context, index) => _MyChallengeCard(challenge: _challenges[index], onChanged: _load),
                        ),
        ),
      ),
    );
  }
}

enum _ChallengeStatus { waiting, leading, beaten }

class _MyChallengeCard extends StatelessWidget {
  final ChallengeWithAttempts challenge;
  final VoidCallback onChanged;
  const _MyChallengeCard({required this.challenge, required this.onChanged});

  _ChallengeStatus get _status {
    if (challenge.attempts.length <= 1) return _ChallengeStatus.waiting;
    final myRank = challenge.attempts.indexWhere((a) => a.isMe);
    if (myRank == 0) return _ChallengeStatus.leading;
    return _ChallengeStatus.beaten;
  }

  Future<void> _takeBack(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChallengeAnswerScreen(challengeId: challenge.id),
    ));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final top3 = challenge.attempts.take(3).toList();
    final myRank = challenge.attempts.indexWhere((a) => a.isMe);

    final accent = switch (status) {
      _ChallengeStatus.leading => _ChallengeTheme.gold,
      _ChallengeStatus.beaten => _ChallengeTheme.danger,
      _ChallengeStatus.waiting => _ChallengeTheme.cyan,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChallengeLeaderboardScreen(challengeId: challenge.id, subject: challenge.subject),
          )),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: _ChallengeTheme.glassCard(accent: accent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(challenge.subject, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text('by ${challenge.creatorUsername}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11.5)),
                        ],
                      ),
                    ),
                    _StatusPill(status: status),
                  ],
                ),
                const SizedBox(height: 14),
                ...top3.asMap().entries.map((e) {
                  final rank = e.key + 1;
                  final a = e.value;
                  final medalColor = rank == 1
                      ? _ChallengeTheme.gold
                      : rank == 2
                          ? _ChallengeTheme.silver
                          : rank == 3
                              ? _ChallengeTheme.bronze
                              : Colors.white38;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 18, child: Text('$rank', style: TextStyle(color: medalColor, fontWeight: FontWeight.bold, fontSize: 12))),
                        Expanded(
                          child: Text(
                            a.isMe ? '${a.username} (you)' : a.username,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: a.isMe ? _ChallengeTheme.cyan : Colors.white.withOpacity(0.8), fontSize: 13, fontWeight: a.isMe ? FontWeight.bold : FontWeight.normal),
                          ),
                        ),
                        Text('${a.score}/${a.total}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }),
                if (challenge.attempts.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text('+${challenge.attempts.length - 3} more · tap to see full board', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                  ),
                if (status == _ChallengeStatus.beaten) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _ChallengeTheme.danger, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: Text(myRank >= 0 ? 'Take Back #1 (currently #${myRank + 1})' : 'Take Back #1', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () => _takeBack(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _ChallengeStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, emoji, color) = switch (status) {
      _ChallengeStatus.leading => ('LEADING', '👑', _ChallengeTheme.gold),
      _ChallengeStatus.beaten => ('BEATEN', '⚡', _ChallengeTheme.danger),
      _ChallengeStatus.waiting => ('WAITING', '🟢', _ChallengeTheme.cyan),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10)),
        ],
      ),
    );
  }
}

/// =========================================================================
/// WIRING NOTES (unchanged from earlier setup):
/// =========================================================================
///
/// 1. pubspec.yaml: app_links: ^6.3.2
/// 2. AndroidManifest.xml: naijalearn://challenge intent-filter
/// 3. main.dart: navigatorKey, ChallengeDeepLinkListener.init(...),
///    import 'challenge_feature.dart' — already in place.
/// 4. Community tab entry point already points at ChallengesHubScreen —
///    no change needed there.
/// 5. NEW SQL: run challenges_migration_v3_patch.sql after v2. It adds
///    anti-cheat validation to submit_challenge_attempt and the
///    was_notified_of_overtake tracking that powers the hub's alert
///    banner.
///
/// DELIBERATELY DEFERRED (see file header for why):
///   - Difficulty selector in create flow
///   - True push notifications (current version is in-app, checked on
///     hub open)
///   - Cent Challenge (paid mode) — build as a SEPARATE screen/flow when
///     ready, don't fold it into this one
