// lib/challenge_feature.dart
//
// WhatsApp growth loop — "Challenge a Friend", shareable results, and
// the Daily Challenge share button. See challenges_migration.sql for
// the backing Supabase schema/RPCs.
//
// DESIGN: challenges store only question IDs — never question content.
// Question text/options/correct answers are resolved LOCALLY from the
// app's own QuestionRepository (main.dart), exactly like the existing
// exam flow. This keeps the web fallback page (for friends without the
// app yet) completely dumb — it never needs question content, since the
// WhatsApp share text itself (built here, where the app already has the
// real Question objects) carries the human-readable preview.
//
// DEEP LINKS: tapping a `naijalearn://challenge/<id>` link (from the
// landing page's app-scheme handoff, or directly if already installed)
// is caught by ChallengeDeepLinkListener and pushed onto the app's
// navigatorKey — see the wiring notes at the bottom of this file for
// the two small edits needed in main.dart and AndroidManifest.xml.

import 'dart:async';
import 'dart:math';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart' show Question, QuestionRepository, SubjectInfo, kSubjects;

/// Base URL for the web fallback landing page (friends without the app
/// yet land here; friends who already have it get handed straight to
/// the app via the custom scheme before this URL is ever fetched).
const String kChallengeLandingPageBaseUrl =
    'https://zetrasystemsq8-beep.github.io/Naijalearn-landing-page/';

/// =========================================================================
/// SERVICE
/// =========================================================================

class ChallengeService {
  ChallengeService._();
  static final ChallengeService instance = ChallengeService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<String> createChallenge({
    required String type, // 'single' | 'challenge'
    required String subject,
    required List<String> questionIds,
  }) async {
    final result = await _client.rpc('create_challenge', params: {
      'p_type': type,
      'p_subject': subject,
      'p_question_ids': questionIds,
    });
    return result as String;
  }

  Future<String> getOrCreateDailyChallenge({
    required String subject,
    required List<String> questionIds,
  }) async {
    final result = await _client.rpc('get_or_create_daily_challenge', params: {
      'p_subject': subject,
      'p_question_ids': questionIds,
    });
    return result as String;
  }

  Future<Map<String, dynamic>?> getChallenge(String challengeId) async {
    final result = await _client.rpc('get_challenge', params: {'p_challenge_id': challengeId});
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> submitAttempt({
    required String challengeId,
    required int score,
    required int total,
  }) async {
    await _client.rpc('submit_challenge_attempt', params: {
      'p_challenge_id': challengeId,
      'p_score': score,
      'p_total': total,
    });
  }

  Future<List<Map<String, dynamic>>> getLeaderboard(String challengeId) async {
    final rows = await _client.rpc('get_challenge_leaderboard', params: {'p_challenge_id': challengeId});
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }
}

/// =========================================================================
/// SHARE TEXT BUILDERS + WHATSAPP LAUNCH
/// =========================================================================

String _landingLink(String challengeId) => '$kChallengeLandingPageBaseUrl?id=$challengeId';

/// A single-question share — the actual question text IS revealed here,
/// matching the "JAMB Challenge #001" example: the whole point is
/// letting it be answered right inside the WhatsApp preview mentally,
/// then proven on NaijaLearn.
String buildSingleQuestionShareText({
  required Question question,
  required String challengeId,
}) {
  final letters = ['A', 'B', 'C', 'D'];
  final optionsText = List.generate(
    question.options.length,
    (i) => '${letters[i]}. ${question.options[i]}',
  ).join(' · ');

  return '🧠 *NaijaLearn Challenge*\n\n'
      '${question.questionText}\n\n'
      '$optionsText\n\n'
      "Can you get it right? 👀\n"
      'Answer here → ${_landingLink(challengeId)}';
}

/// A multi-question "Challenge a friend" share — deliberately does NOT
/// reveal any question content, since the friend answers a full set
/// inside the app and the two of you compare full scores, not a single
/// answer.
String buildFriendChallengeShareText({
  required String subject,
  required int questionCount,
  required String challengeId,
}) {
  return '🔥 *Connect challenged you!*\n\n'
      'Answer $questionCount $subject questions and see how you compare.\n\n'
      'Timed · Shareable · No excuses 😏\n\n'
      'Accept the challenge → ${_landingLink(challengeId)}';
}

/// A result share — "I scored 8/10, beat me" — the natural invitation
/// loop. Reuses the SAME challenge id so whoever taps it competes on
/// the same question set, not a fresh unrelated one.
String buildResultShareText({
  required String subject,
  required int score,
  required int total,
  required String challengeId,
}) {
  return '🏆 *NaijaLearn Challenge Result*\n\n'
      '$subject · $total questions\n\n'
      '*$score/$total* 💪\n\n'
      'Can you beat my score?\n'
      'Join the challenge → ${_landingLink(challengeId)}';
}

/// Daily question share — deliberately withholds both the answer AND
/// which option is correct; the friend must open the app to actually
/// engage, not just read the answer off WhatsApp.
String buildDailyQuestionShareText({
  required Question question,
  required String challengeId,
}) {
  final letters = ['A', 'B', 'C', 'D'];
  final optionsText = List.generate(
    question.options.length,
    (i) => '${letters[i]}. ${question.options[i]}',
  ).join('\n');

  return "🧠 *NaijaLearn Daily Challenge*\n\n"
      "Today's question:\n${question.questionText}\n\n'"
          '$optionsText\n\n'
      "Don't just guess. Challenge your friends. 😏\n"
      'Answer here → ${_landingLink(challengeId)}';
}

Future<void> shareToWhatsApp(String text) async {
  final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// =========================================================================
/// DEEP LINK LISTENER — wire this up once in main() (see notes at the
/// bottom of this file for the exact two-line change needed there).
/// =========================================================================

class ChallengeDeepLinkListener {
  ChallengeDeepLinkListener._();

  static StreamSubscription<Uri>? _sub;

  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    final appLinks = AppLinks();

    // Cold start: app was launched fresh BY tapping the link.
    try {
      final initial = await appLinks.getInitialAppLink();
      if (initial != null) _handle(initial, navigatorKey);
    } catch (e) {
      debugPrint('[ChallengeDeepLink] getInitialAppLink failed: $e');
    }

    // Warm start: app was already running in the background.
    _sub?.cancel();
    _sub = appLinks.uriLinkStream.listen(
      (uri) => _handle(uri, navigatorKey),
      onError: (e) => debugPrint('[ChallengeDeepLink] stream error: $e'),
    );
  }

  static void _handle(Uri uri, GlobalKey<NavigatorState> navigatorKey) {
    debugPrint('[ChallengeDeepLink] received: $uri');
    if (uri.scheme != 'naijalearn') return;

    // Accepts naijalearn://challenge/<id>
    final segments = uri.pathSegments;
    String? challengeId;
    if (uri.host == 'challenge' && segments.isNotEmpty) {
      challengeId = segments.first;
    } else if (segments.length >= 2 && segments.first == 'challenge') {
      challengeId = segments[1];
    }

    if (challengeId == null || challengeId.isEmpty) return;

    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => ChallengeAnswerScreen(challengeId: challengeId!)),
    );
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

/// =========================================================================
/// SCREEN 1 — CREATE A CHALLENGE ("Challenge a Friend")
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

  Future<void> _createAndShare() async {
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

      final text = buildFriendChallengeShareText(
        subject: subject.name,
        questionCount: picked.length,
        challengeId: challengeId,
      );

      if (!mounted) return;
      await shareToWhatsApp(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create challenge: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Challenge a Friend')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary.withOpacity(0.15), scheme.tertiary.withOpacity(0.1)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, color: scheme.primary, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Every question is a reason to challenge a friend. Pick a subject, share the link, and see who scores higher.',
                    style: TextStyle(fontSize: 13.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Subject', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kSubjects.map((s) {
              final selected = _selectedSubject?.name == s.name;
              return ChoiceChip(
                label: Text(s.name),
                selected: selected,
                avatar: Icon(s.icon, size: 16, color: selected ? Colors.white : s.color),
                onSelected: (_) => setState(() => _selectedSubject = s),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text('Number of questions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: _counts.map((c) {
              final selected = _questionCount == c;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: selected ? scheme.primaryContainer : null,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => setState(() => _questionCount = c),
                    child: Text('$c'),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              icon: const Icon(Icons.chat_rounded),
              label: _creating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create & Share on WhatsApp', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              onPressed: (_selectedSubject == null || _creating) ? null : _createAndShare,
            ),
          ),
        ],
      ),
    );
  }
}

/// =========================================================================
/// SCREEN 2 — ANSWER A CHALLENGE (reached via deep link)
/// =========================================================================

class ChallengeAnswerScreen extends StatefulWidget {
  final String challengeId;
  const ChallengeAnswerScreen({super.key, required this.challengeId});

  @override
  State<ChallengeAnswerScreen> createState() => _ChallengeAnswerScreenState();
}

class _ChallengeAnswerScreenState extends State<ChallengeAnswerScreen> {
  Map<String, dynamic>? _challenge;
  List<Question> _questions = [];
  bool _loading = true;
  String? _error;

  int _currentIndex = 0;
  int? _selectedOption;
  int _correctCount = 0;
  final List<int?> _answers = [];

  @override
  void initState() {
    super.initState();
    _load();
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
    final question = _questions[_currentIndex];
    final wasCorrect = _selectedOption == question.correctIndex;
    if (wasCorrect) _correctCount++;
    _answers.add(_selectedOption);

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
    try {
      await ChallengeService.instance.submitAttempt(
        challengeId: widget.challengeId,
        score: _correctCount,
        total: _questions.length,
      );
    } catch (e) {
      debugPrint('[ChallengeAnswerScreen] submitAttempt failed (non-fatal): $e');
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChallengeResultScreen(
          subject: _challenge?['subject'] as String? ?? 'Practice',
          score: _correctCount,
          total: _questions.length,
          challengeId: widget.challengeId,
          creatorScore: (_challenge?['creator_score'] as num?)?.toInt(),
          creatorTotal: (_challenge?['creator_total'] as num?)?.toInt(),
          creatorUsername: _challenge?['creator_username'] as String?,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Challenge')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final question = _questions[_currentIndex];

    return Scaffold(
      appBar: AppBar(title: Text('Question ${_currentIndex + 1} of ${_questions.length}')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: (_currentIndex) / _questions.length),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
              child: Text(question.questionText, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
            ),
            const SizedBox(height: 18),
            ...List.generate(question.options.length, (i) {
              final isSelected = _selectedOption == i;
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
                            child: Text(letter, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Text(question.options[i], style: const TextStyle(fontSize: 15))),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const Spacer(),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _selectedOption == null ? null : _next,
                child: Text(_currentIndex == _questions.length - 1 ? 'Finish' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// SCREEN 3 — RESULT + SHARE ("Beat my score")
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
      backgroundColor: const Color(0xFF0B0E1A),
      appBar: AppBar(
        title: const Text('Result'),
        backgroundColor: const Color(0xFF0B0E1A),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF12122A), Color(0xFF1A1440)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                  boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.25), blurRadius: 40, spreadRadius: 2)],
                ),
                child: Column(
                  children: [
                    Text(subject.toUpperCase(),
                        style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12)),
                    const SizedBox(height: 14),
                    Text('$score/$total',
                        style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('${(myPct * 100).toStringAsFixed(0)}% correct', style: const TextStyle(color: Colors.white60)),
                    if (hasComparison) ...[
                      const SizedBox(height: 20),
                      Container(height: 1, color: Colors.white12),
                      const SizedBox(height: 16),
                      Text(
                        tied
                            ? "It's a tie with ${creatorUsername ?? 'them'}! 🤝"
                            : iWon
                                ? 'You beat ${creatorUsername ?? 'them'}! 🎉'
                                : '${creatorUsername ?? 'They'} scored higher — run it back 👀',
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
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('Share Result — Beat My Score', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => shareToWhatsApp(
                    buildResultShareText(subject: subject, score: score, total: total, challengeId: challengeId),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Back to Home', style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// DAILY CHALLENGE SHARE BUTTON — drop this widget anywhere (e.g. Home
/// tab) to let users share today's shared daily question.
/// =========================================================================

class DailyChallengeShareButton extends StatelessWidget {
  const DailyChallengeShareButton({super.key});

  Future<void> _share(BuildContext context) async {
    try {
      final all = QuestionRepository.getAll()..shuffle(Random(DateTime.now().day));
      final question = all.first;

      final challengeId = await ChallengeService.instance.getOrCreateDailyChallenge(
        subject: question.subject,
        questionIds: [question.id],
      );

      await shareToWhatsApp(buildDailyQuestionShareText(question: question, challengeId: challengeId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share today\'s question: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _share(context),
      icon: const Icon(Icons.share_rounded),
      label: const Text('Share Daily Question'),
    );
  }
}

/// =========================================================================
/// WIRING NOTES — two small edits needed elsewhere (not in this file):
/// =========================================================================
///
/// 1. pubspec.yaml — add:
///      app_links: ^6.3.2
///
/// 2. android/app/src/main/AndroidManifest.xml — inside your main
///    <activity> tag (the one with the LAUNCHER intent-filter already),
///    ADD a second intent-filter block for the custom scheme:
///
///      <intent-filter>
///        <action android:name="android.intent.action.VIEW" />
///        <category android:name="android.intent.category.DEFAULT" />
///        <category android:name="android.intent.category.BROWSABLE" />
///        <data android:scheme="naijalearn" android:host="challenge" />
///      </intent-filter>
///
/// 3. main.dart — two small additions:
///    a) At the top level (outside any class), add:
///         final navigatorKey = GlobalKey<NavigatorState>();
///    b) In NaijaLearnApp.build(), add `navigatorKey: navigatorKey,` as a
///       parameter to the MaterialApp(...) call (alongside `theme:`,
///       `home:`, etc).
///    c) In main(), right after `runApp(...)`, add:
///         ChallengeDeepLinkListener.init(navigatorKey);
///       (import 'challenge_feature.dart' at the top of main.dart too)
///
/// 4. To let users START a challenge, add a button/menu item anywhere
///    that pushes CreateChallengeScreen(), e.g. in the Community tab:
///         Navigator.of(context).push(MaterialPageRoute(
///           builder: (_) => const CreateChallengeScreen(),
///         ));
