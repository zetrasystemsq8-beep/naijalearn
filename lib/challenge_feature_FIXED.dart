// lib/challenge_feature.dart
//
// ⚡ FIXED VERSION.
//
// FIX 1 — creator never answered their own challenge: CreateChallengeScreen
// now pushes the creator through the SAME answer screen as their friend
// immediately after creating the challenge, submits their score via the
// existing submitAttempt RPC (which — per your codebase's established
// security-definer/auth.uid() pattern — should attribute the score to
// the creator server-side), and only offers the WhatsApp share step
// afterward. Previously it shared before anyone had answered anything.
//
// FIX 2 — unreliable subject pills: ChoiceChip (Material's built-in
// widget) is replaced with _SubjectPillButton, a hand-built pill that
// renders identically every time — no dependency on Material 3's chip
// theming, which is what was producing the washed-out/no-icon look.
//
// FIX 3 — AppBar contrast: every AppBar in this file now sets an
// explicit iconTheme + titleTextStyle in addition to foregroundColor,
// so there's no ambiguity about where the white color comes from.
//
// FIX 4 — one shared answer screen: ChallengeAnswerScreen now accepts
// EITHER a challengeId (friend, via deep link — fetches from Supabase)
// OR pre-resolved questions + challengeId (creator, right after
// creation — no extra round trip needed). Same UI, same code path,
// instead of two separate quiz implementations to keep in sync.
//
// Everything else — ChallengeService, deep link handling, share-text
// builders — is unchanged from your version.

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

  static BoxDecoration glassCard({Color accent = cyan}) => BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cardTop, cardBottom]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.35)),
        boxShadow: [BoxShadow(color: accent.withOpacity(0.18), blurRadius: 30, spreadRadius: 1)],
      );

  // FIX 3: explicit iconTheme + titleTextStyle, not just foregroundColor,
  // so the AppBar's text/back-arrow contrast can never be ambiguous.
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
/// SERVICE  (unchanged — logic only)
/// =========================================================================

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

  Future<Map<String, dynamic>?> getChallenge(String challengeId) async {
    final result = await _client.rpc('get_challenge', params: {'p_challenge_id': challengeId});
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> submitAttempt({required String challengeId, required int score, required int total}) async {
    await _client.rpc('submit_challenge_attempt', params: {'p_challenge_id': challengeId, 'p_score': score, 'p_total': total});
  }

  Future<List<Map<String, dynamic>>> getLeaderboard(String challengeId) async {
    final rows = await _client.rpc('get_challenge_leaderboard', params: {'p_challenge_id': challengeId});
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }
}

/// =========================================================================
/// SHARE TEXT + WHATSAPP  (unchanged — logic only)
/// =========================================================================

String _landingLink(String challengeId) => '$kChallengeLandingPageBaseUrl?id=$challengeId';

String buildFriendChallengeShareText({required String subject, required int questionCount, required String challengeId}) {
  return '🔥 *Connect challenged you!*\n\n'
      'Answer $questionCount $subject questions and see how you compare.\n\n'
      'Timed · Shareable · No excuses 😏\n\n'
      'Accept the challenge → ${_landingLink(challengeId)}';
}

String buildResultShareText({required String subject, required int score, required int total, required String challengeId}) {
  return '🏆 *NaijaLearn Challenge Result*\n\n'
      '$subject · $total questions\n\n'
      '*$score/$total* 💪\n\n'
      'Can you beat my score?\n'
      'Join the challenge → ${_landingLink(challengeId)}';
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
/// DEEP LINK LISTENER  (unchanged — logic only)
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
      debugPrint('[ChallengeDeepLink] getInitialAppLink failed: $e');
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
/// HUB
/// =========================================================================

class ChallengesHubScreen extends StatelessWidget {
  const ChallengesHubScreen({super.key});

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
                Text('Every question is a reason to challenge a friend.', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                const SizedBox(height: 20),
                _HubCard(
                  accent: _ChallengeTheme.cyan,
                  icon: Icons.bolt_rounded,
                  title: 'Challenge a Friend',
                  subtitle: 'Pick a subject, answer it yourself first, then share it',
                  ctaLabel: 'Create Challenge',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateChallengeScreen())),
                ),
                const SizedBox(height: 16),
                _HubCard(
                  accent: _ChallengeTheme.gold,
                  icon: Icons.wb_sunny_rounded,
                  title: 'Daily Question',
                  subtitle: "Share today's question — answer is hidden until they open the app",
                  ctaLabel: "Share Today's Question",
                  onTap: () => _shareDaily(context),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withOpacity(0.08))),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('How it works', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      SizedBox(height: 10),
                      _HowItWorksLine(number: '1', text: 'Create a challenge and answer it yourself'),
                      _HowItWorksLine(number: '2', text: 'Share it to WhatsApp — your friend taps the link and answers inside NaijaLearn'),
                      _HowItWorksLine(number: '3', text: 'You both see the scores — share the result to invite the next person'),
                    ],
                  ),
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

class _HowItWorksLine extends StatelessWidget {
  final String number;
  final String text;
  const _HowItWorksLine({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 20, height: 20, alignment: Alignment.center, decoration: BoxDecoration(color: _ChallengeTheme.cyan.withOpacity(0.15), shape: BoxShape.circle), child: Text(number, style: const TextStyle(color: _ChallengeTheme.cyan, fontSize: 11, fontWeight: FontWeight.bold))),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12.5, height: 1.4))),
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

  const _HubCard({required this.accent, required this.icon, required this.title, required this.subtitle, required this.ctaLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _ChallengeTheme.glassCard(accent: accent),
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

/// FIX 2: reliable subject pill — replaces ChoiceChip entirely. No
/// dependency on Material 3 chip theming; renders the same every time.
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
/// CREATE A CHALLENGE
/// FIX 1: creator now answers before sharing — see _createAndAnswer.
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

  /// FIX 1: creates the challenge, then immediately routes the CREATOR
  /// through the same answer screen their friend will see — instead of
  /// jumping straight to sharing before anyone has a score on record.
  Future<void> _createAndAnswer() async {
    final subject = _selectedSubject;
    if (subject == null) return;

    setState(() => _creating = true);
    try {
      final pool = QuestionRepository.getForSubject(subject.name)..shuffle();
      final picked = pool.take(_questionCount).toList();
      if (picked.isEmpty) {
        throw Exception('No questions available for ${subject.name} yet.');
      }

      final challengeId = await ChallengeService.instance.createChallenge(
        type: 'challenge',
        subject: subject.name,
        questionIds: picked.map((q) => q.id).toList(),
      );

      if (!mounted) return;
      // Creator answers their own challenge right now — same screen a
      // friend uses via deep link, just given the questions directly
      // instead of fetching them (they were just picked above).
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChallengeAnswerScreen(
          challengeId: challengeId,
          preloadedQuestions: picked,
          preloadedSubject: subject.name,
          isCreatorFirstAttempt: true,
        ),
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create challenge: $e')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
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
            const SizedBox(height: 8),
            Text('You\'ll answer these yourself first, then share to WhatsApp.', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
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
                    : const Text('Create & Answer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                onPressed: (_selectedSubject == null || _creating) ? null : _createAndAnswer,
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
/// ANSWER A CHALLENGE — shared by creator (immediately after creating)
/// and friend (via deep link). FIX 4: one screen, one code path.
/// =========================================================================

class ChallengeAnswerScreen extends StatefulWidget {
  final String challengeId;
  /// If provided (creator's first attempt), questions are used directly
  /// instead of fetching the challenge from Supabase — skips a round
  /// trip and the "resolve question IDs" step entirely.
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
  Map<String, dynamic>? _challenge;
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
      final challenge = await ChallengeService.instance.getChallenge(widget.challengeId);
      if (challenge == null) {
        setState(() {
          _error = 'This challenge no longer exists.';
          _loading = false;
        });
        return;
      }

      final ids = (challenge['question_ids'] as List).cast<String>();
      final all = QuestionRepository.getAll();
      final byId = {for (final q in all) q.id: q};
      final resolved = ids.map((id) => byId[id]).whereType<Question>().toList();

      if (resolved.isEmpty) {
        setState(() {
          _error = "This challenge's questions aren't available on your app version.";
          _loading = false;
        });
        return;
      }

      setState(() {
        _challenge = challenge;
        _questions = resolved;
        _subject = challenge['subject'] as String? ?? 'Practice';
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
      // Creator just answered their own challenge — take them to share,
      // not to a "you vs them" comparison (there's no opponent score yet).
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChallengeCreatedResultScreen(subject: _subject, score: _correctCount, total: _questions.length, challengeId: widget.challengeId),
      ));
      return;
    }

    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ChallengeResultScreen(
        subject: _challenge?['subject'] as String? ?? _subject,
        score: _correctCount,
        total: _questions.length,
        challengeId: widget.challengeId,
        creatorScore: (_challenge?['creator_score'] as num?)?.toInt(),
        creatorTotal: (_challenge?['creator_total'] as num?)?.toInt(),
        creatorUsername: _challenge?['creator_username'] as String?,
      ),
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
/// NEW — shown to the CREATOR right after they finish their own attempt.
/// No "vs" comparison (no opponent yet) — just their score + the share CTA
/// that used to fire immediately on creation, now correctly placed after
/// they actually have a score to challenge people with.
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
                  onPressed: () => shareToWhatsApp(buildFriendChallengeShareText(subject: subject, questionCount: total, challengeId: challengeId)),
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
/// RESULT + SHARE — shown to a FRIEND after answering someone else's
/// challenge (has a creator score to compare against).
/// =========================================================================

class ChallengeResultScreen extends StatelessWidget {
  final String subject;
  final int score;
  final int total;
  final String challengeId;
  final int? creatorScore;
  final int? creatorTotal;
  final String? creatorUsername;

  const ChallengeResultScreen({
    super.key,
    required this.subject,
    required this.score,
    required this.total,
    required this.challengeId,
    this.creatorScore,
    this.creatorTotal,
    this.creatorUsername,
  });

  @override
  Widget build(BuildContext context) {
    final hasComparison = creatorScore != null && creatorTotal != null && creatorTotal! > 0;
    final myPct = total > 0 ? score / total : 0.0;
    final theirPct = hasComparison ? creatorScore! / creatorTotal! : 0.0;
    final iWon = hasComparison && myPct > theirPct;
    final tied = hasComparison && myPct == theirPct;

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
                    Text('${(myPct * 100).toStringAsFixed(0)}% correct', style: const TextStyle(color: Colors.white60)),
                    if (hasComparison) ...[
                      const SizedBox(height: 20),
                      Container(height: 1, color: Colors.white12),
                      const SizedBox(height: 16),
                      Text(
                        tied ? "It's a tie with ${creatorUsername ?? 'them'}! 🤝" : iWon ? 'You beat ${creatorUsername ?? 'them'}! 🎉' : '${creatorUsername ?? 'They'} scored higher — run it back 👀',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
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
                  label: const Text('Share Result — Beat My Score', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => shareToWhatsApp(buildResultShareText(subject: subject, score: score, total: total, challengeId: challengeId)),
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
