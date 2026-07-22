// lib/main.dart
//
// NaijaLearn — CBT Practice App
// Material 3.
//
// Question content lives in per-subject files (questions_*.dart).
// Gamification (XP, streak, badges, leaderboard, daily challenge, mock
// exams, analytics) lives in app_enhancements.dart and plugs in via
// AppProvider, without replacing any of the CBT screens below.
//
// Authentication (email OTP via Supabase) is self-contained in this file:
// AuthService, LoginScreen, VerifyOtpScreen. No Riverpod, no separate
// auth/ folder, no code from any other project.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_enhancements.dart';

import 'questions_english.dart';
import 'questions_accounting.dart';
import 'questions_arabic.dart';
import 'questions_biology.dart';
import 'questions_commerce.dart';
import 'questions_crs.dart';
import 'questions_economics.dart';
import 'questions_geography.dart';
import 'questions_government.dart';
import 'questions_irs.dart';
import 'questions_literature.dart';
import 'questions_mathematics.dart';
import 'questions_physics.dart';
import 'questions_chemistry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: const NaijaLearnApp(),
    ),
  );
}

/// =========================================================================
/// AUTHENTICATION (self-contained: service + screens)
/// =========================================================================

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Sends a 6-digit OTP code to the given email via Supabase Auth.
  Future<void> sendOtp(String email) async {
    await _client.auth.signInWithOtp(
      email: email,
      shouldCreateUser: true,
    );
  }

  /// Verifies the 6-digit OTP code entered by the user for the given email.
  /// Throws an [AuthException] if verification fails.
  Future<void> verifyOtp({
    required String email,
    required String token,
  }) async {
    await _client.auth.verifyOTP(
      type: OtpType.email,
      email: email,
      token: token,
    );
  }

  bool get isSignedIn => _client.auth.currentSession != null;

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Please enter your email';
    final emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
    if (!emailRegex.hasMatch(email)) return 'Please enter a valid email';
    return null;
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();

    try {
      await AuthService.instance.sendOtp(email);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VerifyOtpScreen(email: email)),
      );
    } catch (e) {
      setState(() => _errorMessage = 'Could not send code. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(Icons.school_rounded, size: 46, color: scheme.primary),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to NaijaLearn',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your email to sign in or create an account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.done,
                    validator: _validateEmail,
                    onFieldSubmitted: (_) => _sendCode(),
                    decoration: InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: TextStyle(color: scheme.error, fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _loading ? null : _sendCode,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : const Text('Send Code', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VerifyOtpScreen extends StatefulWidget {
  final String email;
  const VerifyOtpScreen({super.key, required this.email});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String? _validateCode(String? value) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) return 'Please enter the code';
    if (code.length != 6 || int.tryParse(code) == null) {
      return 'Enter the 6-digit code';
    }
    return null;
  }

  Future<void> _verifyCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.instance.verifyOtp(
        email: widget.email,
        token: _codeController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } catch (e) {
      setState(() => _errorMessage = 'Invalid or expired code. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _resending = true;
      _errorMessage = null;
    });
    try {
      await AuthService.instance.sendOtp(widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent.')),
      );
    } catch (e) {
      setState(() => _errorMessage = 'Could not resend code. Please try again.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Your Email')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.mark_email_read_rounded, size: 56, color: scheme.primary),
                  const SizedBox(height: 20),
                  Text(
                    'Enter the 6-digit code sent to',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.email,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                    validator: _validateCode,
                    onFieldSubmitted: (_) => _verifyCode(),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '------',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(_errorMessage!, style: TextStyle(color: scheme.error, fontSize: 13), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _loading ? null : _verifyCode,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : const Text('Verify', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _resending ? null : _resendCode,
                    child: _resending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Resend Code'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// MODELS
/// =========================================================================

class Question {
  final String id;
  final String subject;
  final int year;
  final String questionText;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const Question({
    required this.id,
    required this.subject,
    required this.year,
    required this.questionText,
    required this.options,
    required this.correctIndex,
    this.explanation = '',
  });

  factory Question.fromJson(Map<String, dynamic> json, {String? fallbackId}) {
    return Question(
      id: (json['id'] as String?) ?? fallbackId ?? '${json['subject']}_${json['year']}_${json.hashCode}',
      subject: json['subject'] as String,
      year: json['year'] as int,
      questionText: json['question'] as String,
      options: List<String>.from(json['options'] as List),
      correctIndex: json['correctIndex'] as int,
      explanation: (json['explanation'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'year': year,
        'question': questionText,
        'options': options,
        'correctIndex': correctIndex,
        'explanation': explanation,
      };
}

class SubjectInfo {
  final String name;
  final IconData icon;
  final Color color;
  const SubjectInfo(this.name, this.icon, this.color);
}

// Only subjects with a real question file wired in should appear here —
// otherwise SubjectCard will show "0 questions" for the rest. Add more
// entries as you wire in each new subject file.
const List<SubjectInfo> kSubjects = [
  SubjectInfo('English', Icons.menu_book_rounded, Color(0xFF3F51B5)),
  SubjectInfo('Mathematics', Icons.calculate_rounded, Colors.blue),
  SubjectInfo('Physics', Icons.science_rounded, Colors.deepPurple),
  SubjectInfo('Chemistry', Icons.biotech_rounded, Colors.red),
  SubjectInfo('Biology', Icons.eco_rounded, Colors.green),
  SubjectInfo('Economics', Icons.attach_money_rounded, Colors.teal),
  SubjectInfo('Government', Icons.account_balance_rounded, Colors.indigo),
  SubjectInfo('Geography', Icons.public_rounded, Colors.brown),
  SubjectInfo('Literature', Icons.menu_book_rounded, Colors.purple),
  SubjectInfo('Commerce', Icons.shopping_cart_rounded, Colors.orange),
  SubjectInfo('Accounting', Icons.receipt_long_rounded, Colors.cyan),
  SubjectInfo('CRS', Icons.auto_stories_rounded, Colors.deepOrange),
  SubjectInfo('IRS', Icons.mosque_rounded, Colors.green),
  SubjectInfo('Arabic', Icons.translate_rounded, Colors.lime),
];

/// =========================================================================
/// QUESTION REPOSITORY (swap-friendly data source)
/// =========================================================================

class QuestionRepository {
  QuestionRepository._();

  static List<Question> _questions = _buildFromRawData([
  ...englishQuestions,
  ...mathematicsQuestions,
  ...physicsQuestions,
  ...chemistryQuestions,
  ...biologyQuestions,
  ...economicsQuestions,
  ...governmentQuestions,
  ...geographyQuestions,
  ...literatureQuestions,
  ...commerceQuestions,
  ...accountingQuestions,
  ...crsQuestions,
  ...irsQuestions,
  ...arabicQuestions,
]);

  static List<Question> _buildFromRawData(List<Map<String, dynamic>> raw) {
    final List<Question> list = [];
    for (final map in raw) {
      list.add(Question.fromJson(map, fallbackId: '${map['subject']}_${map['year']}_${list.length}'));
    }
    return list;
  }

  static void loadFromJsonList(List<Map<String, dynamic>> jsonList) {
    _questions = _buildFromRawData(jsonList);
  }

  static void loadFromJsonString(String jsonStr) {
    final decoded = jsonDecode(jsonStr) as List<dynamic>;
    loadFromJsonList(decoded.cast<Map<String, dynamic>>());
  }

  static List<Question> getAll() => List.unmodifiable(_questions);

  static List<Question> getForSubject(String subject) =>
      _questions.where((q) => q.subject == subject).toList();
}

/// =========================================================================
/// APP ROOT — theming
/// =========================================================================

class NaijaLearnApp extends StatelessWidget {
  const NaijaLearnApp({super.key});

  static const Color _seed = Color(0xFF00A86B); // Nigerian green

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    return MaterialApp(
      title: 'NaijaLearn',
      debugShowCheckedModeBanner: false,
      themeMode: provider.darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF101312),
        fontFamily: 'Roboto',
      ),
      home: const SplashScreen(),
    );
  }
}

/// =========================================================================
/// SPLASH SCREEN
/// =========================================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _fade = CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.7, curve: Curves.easeIn));
    _scale = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    Timer(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: Supabase.instance.client.auth.currentSession == null
                ? const LoginScreen()
                : const HomeScreen(),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.primaryContainer],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))],
                    ),
                    child: Icon(Icons.school_rounded, size: 60, color: scheme.primary),
                  ),
                  const SizedBox(height: 24),
                  const Text('NaijaLearn',
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Text('Practice. Prepare. Pass.', style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.9))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// HOME SCREEN
/// =========================================================================

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _pickCountAndStart(BuildContext context, SubjectInfo subject) async {
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuestionCountPickerSheet(subject: subject),
    );
    if (count == null || !context.mounted) return;

    final allQuestions = QuestionRepository.getForSubject(subject.name);
    final shuffled = List<Question>.from(allQuestions)..shuffle();
    final questions = (count == -1 || count >= shuffled.length) ? shuffled : shuffled.take(count).toList();
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExamInstructionsScreen(subject: subject, questions: questions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.watch<AppProvider>();
    final stats = provider.stats;
    final daily = provider.dailyChallenge;
    provider.refreshDailyChallengeIfNeeded();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
                      child: Icon(Icons.school_rounded, color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('NaijaLearn', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                          Text('Choose a subject to practice', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Toggle dark mode',
                      onPressed: provider.toggleDarkMode,
                      icon: Icon(provider.darkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      children: [
                        _StatPill(icon: Icons.local_fire_department_rounded, color: Colors.deepOrange, value: '${stats.streak}', label: 'Streak'),
                        _StatPill(icon: Icons.star_rounded, color: Colors.amber, value: '${stats.xp}', label: 'XP'),
                        _StatPill(icon: Icons.military_tech_rounded, color: scheme.primary, value: '${stats.level}', label: 'Level'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      colors: [scheme.primary, scheme.primary.withOpacity(0.75)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('CBT Practice Mode',
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(
                              'Simulate real exam conditions with a timer,\nquestion navigator and instant results.',
                              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12.5, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.bolt_rounded, color: Colors.white.withOpacity(0.85), size: 42),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withOpacity(0.5), width: 1.4),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.calendar_today_rounded, color: Colors.amber),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Daily Challenge', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(
                              daily == null
                                  ? 'Loading...'
                                  : (daily.completed
                                      ? 'Completed today — ${daily.score}/${daily.questions.length} ✅'
                                      : '${daily.questions.length} mixed questions waiting'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: daily == null || daily.completed
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => QuizScreen(
                                      questions: daily.questions,
                                      title: 'Daily Challenge',
                                      onComplete: (score) {
                                        context.read<AppProvider>().submitDailyChallenge(score);
                                        Navigator.pop(context);
                                      },
                                    ),
                                  ),
                                ),
                        child: const Text('Start'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // --- Added: Daily Goal progress card ---
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.flag_rounded, size: 20, color: scheme.primary),
                          const SizedBox(width: 8),
                          const Text('Daily Goal', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _QuickActionChip(icon: Icons.leaderboard_rounded, label: 'Leaderboard', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen()))),
                      const SizedBox(width: 10),
                      _QuickActionChip(icon: Icons.school_rounded, label: 'Mock Exam', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MockExamScreen()))),
                      const SizedBox(width: 10),
                      _QuickActionChip(icon: Icons.bar_chart_rounded, label: 'Analytics', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnalyticsScreen()))),
                      const SizedBox(width: 10),
                      _QuickActionChip(icon: Icons.person_rounded, label: 'Profile', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()))),
                      // --- Added: Study Timer and Weekly Stats quick actions ---
                      const SizedBox(width: 10),
                      _QuickActionChip(icon: Icons.timer_rounded, label: 'Study Timer', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StudyTimerScreen()))),
                      const SizedBox(width: 10),
                      _QuickActionChip(icon: Icons.calendar_view_week_rounded, label: 'Weekly Stats', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeeklyStatsScreen()))),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.15,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final subject = kSubjects[index];
                    final count = QuestionRepository.getForSubject(subject.name).length;
                    return SubjectCard(
                      subject: subject,
                      questionCount: count,
                      onTap: () => _pickCountAndStart(context, subject),
                    );
                  },
                  childCount: kSubjects.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _StatPill({required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class SubjectCard extends StatelessWidget {
  final SubjectInfo subject;
  final int questionCount;
  final VoidCallback onTap;
  const SubjectCard({super.key, required this.subject, required this.questionCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: subject.color.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
                child: Icon(subject.icon, color: subject.color, size: 26),
              ),
              const Spacer(),
              Text(subject.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('$questionCount questions',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// QUESTION COUNT PICKER
/// =========================================================================

class QuestionCountPickerSheet extends StatelessWidget {
  final SubjectInfo subject;
  const QuestionCountPickerSheet({super.key, required this.subject});

  static const List<int> _counts = [10, 20, 40, 60];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = QuestionRepository.getForSubject(subject.name).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.35,
      maxChildSize: 0.75,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(color: scheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: scheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(4)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(subject.icon, color: subject.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('${subject.name} — Select Number of Questions',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    ..._counts.map((count) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.of(context).pop(count),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              child: Row(
                                children: [
                                  Text('$count questions', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const Spacer(),
                                  const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    Material(
                      color: subject.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).pop(-1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          child: Row(
                            children: [
                              Text('All Available ($total questions)',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: subject.color)),
                              const Spacer(),
                              Icon(Icons.chevron_right_rounded, color: subject.color),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// =========================================================================
/// EXAM INSTRUCTIONS
/// =========================================================================

class ExamInstructionsScreen extends StatelessWidget {
  final SubjectInfo subject;
  final List<Question> questions;
  const ExamInstructionsScreen({super.key, required this.subject, required this.questions});

  static const int durationMinutes = 20;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Exam Instructions')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: subject.color.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                  child: Icon(subject.icon, color: subject.color, size: 32),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    Text('Practice Set', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),
            _InfoTile(icon: Icons.quiz_rounded, label: 'Questions', value: '${questions.length}'),
            _InfoTile(icon: Icons.timer_rounded, label: 'Duration', value: '$durationMinutes minutes'),
            _InfoTile(icon: Icons.check_circle_rounded, label: 'Question type', value: 'Multiple choice (4 options)'),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Instructions', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('• Answer all questions before time runs out.\n'
                      '• You may skip a question and return to it later.\n'
                      '• Use the question navigator to jump to any question.\n'
                      '• The exam auto-submits when the timer reaches zero.\n'
                      '• Completing this exam also earns XP toward your level.'),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Exam', style: TextStyle(fontSize: 16)),
                onPressed: questions.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ExamScreen(
                              subject: subject,
                              questions: questions,
                              durationMinutes: durationMinutes,
                            ),
                          ),
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

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// =========================================================================
/// EXAM SCREEN (CBT interface)
/// =========================================================================

enum QuestionStatus { unanswered, answered, skipped }

class ExamScreen extends StatefulWidget {
  final SubjectInfo subject;
  final List<Question> questions;
  final int durationMinutes;

  const ExamScreen({
    super.key,
    required this.subject,
    required this.questions,
    required this.durationMinutes,
  });

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  late List<int?> _selectedAnswers;
  late List<QuestionStatus> _statuses;
  int _currentIndex = 0;
  late int _remainingSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _selectedAnswers = List<int?>.filled(widget.questions.length, null);
    _statuses = List<QuestionStatus>.filled(widget.questions.length, QuestionStatus.unanswered);
    _remainingSeconds = widget.durationMinutes * 60;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
        _submitExam();
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _selectOption(int optionIndex) {
    setState(() {
      _selectedAnswers[_currentIndex] = optionIndex;
      _statuses[_currentIndex] = QuestionStatus.answered;
    });
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.questions.length) return;
    setState(() => _currentIndex = index);
  }

  void _skipQuestion() {
    setState(() {
      if (_statuses[_currentIndex] == QuestionStatus.unanswered) {
        _statuses[_currentIndex] = QuestionStatus.skipped;
      }
    });
    if (_currentIndex < widget.questions.length - 1) {
      _goTo(_currentIndex + 1);
    }
  }

  Future<void> _confirmSubmit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Exam?'),
        content: Text(
          'You have answered ${_selectedAnswers.where((a) => a != null).length} of '
          '${widget.questions.length} questions. Submit now?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed == true) _submitExam();
  }

  void _submitExam() {
    _timer?.cancel();
    int correct = 0;
    for (int i = 0; i < widget.questions.length; i++) {
      if (_selectedAnswers[i] != null && _selectedAnswers[i] == widget.questions[i].correctIndex) {
        correct++;
      }
    }
    final skipped = _statuses.where((s) => s == QuestionStatus.skipped).length;
    final unanswered = _selectedAnswers.where((a) => a == null).length;

    final provider = context.read<AppProvider>();
    provider.recordAnswer(widget.subject.name, correct, widget.questions.length);
    provider.addXP(correct * 10);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          subject: widget.subject,
          questions: widget.questions,
          selectedAnswers: _selectedAnswers,
          correctCount: correct,
          skippedCount: skipped,
          unansweredCount: unanswered,
        ),
      ),
    );
  }

  void _openNavigator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QuestionNavigatorSheet(
        totalQuestions: widget.questions.length,
        statuses: _statuses,
        currentIndex: _currentIndex,
        onSelect: (index) {
          Navigator.pop(context);
          _goTo(index);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final question = widget.questions[_currentIndex];
    final answeredCount = _selectedAnswers.where((a) => a != null).length;
    final progress = (answeredCount) / widget.questions.length;
    final isLowTime = _remainingSeconds <= 60;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isLowTime ? scheme.errorContainer : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.timer_rounded, size: 18, color: isLowTime ? scheme.onErrorContainer : scheme.onPrimaryContainer),
                const SizedBox(width: 6),
                Text(_formattedTime,
                    style: TextStyle(fontWeight: FontWeight.bold, color: isLowTime ? scheme.onErrorContainer : scheme.onPrimaryContainer)),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: scheme.surfaceContainerHighest),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Question ${_currentIndex + 1} of ${widget.questions.length}', style: Theme.of(context).textTheme.bodySmall),
                    TextButton.icon(
                      onPressed: _openNavigator,
                      icon: const Icon(Icons.grid_view_rounded, size: 18),
                      label: const Text('Navigator'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
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
                      child: Text(question.questionText, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
                    ),
                    const SizedBox(height: 18),
                    ...List.generate(question.options.length, (i) {
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
                                  Expanded(child: Text(question.options[i], style: const TextStyle(fontSize: 15))),
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
                    child: OutlinedButton.icon(
                      onPressed: _skipQuestion,
                      icon: const Icon(Icons.skip_next_rounded),
                      label: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _currentIndex == widget.questions.length - 1
                        ? FilledButton.icon(onPressed: _confirmSubmit, icon: const Icon(Icons.check_rounded), label: const Text('Submit'))
                        : FilledButton.icon(onPressed: () => _goTo(_currentIndex + 1), icon: const Icon(Icons.chevron_right_rounded), label: const Text('Next')),
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

/// =========================================================================
/// QUESTION NAVIGATOR
/// =========================================================================

class QuestionNavigatorSheet extends StatelessWidget {
  final int totalQuestions;
  final List<QuestionStatus> statuses;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const QuestionNavigatorSheet({
    super.key,
    required this.totalQuestions,
    required this.statuses,
    required this.currentIndex,
    required this.onSelect,
  });

  Color _colorFor(BuildContext context, QuestionStatus status, bool isCurrent) {
    final scheme = Theme.of(context).colorScheme;
    if (isCurrent) return scheme.primary;
    switch (status) {
      case QuestionStatus.answered:
        return Colors.green;
      case QuestionStatus.skipped:
        return Colors.orange;
      case QuestionStatus.unanswered:
        return scheme.surfaceContainerHighest;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Question Navigator', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _LegendDot(color: Colors.green, label: 'Answered'),
                _LegendDot(color: Colors.orange, label: 'Skipped'),
                _LegendDot(color: scheme.surfaceContainerHighest, label: 'Unanswered', border: true),
                _LegendDot(color: scheme.primary, label: 'Current'),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1),
                itemCount: totalQuestions,
                itemBuilder: (context, index) {
                  final isCurrent = index == currentIndex;
                  final color = _colorFor(context, statuses[index], isCurrent);
                  final isFilled = isCurrent || statuses[index] != QuestionStatus.unanswered;
                  return Material(
                    color: isFilled ? color : Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color, width: isFilled ? 0 : 1.4)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelect(index),
                      child: Center(
                        child: Text('${index + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: isFilled ? Colors.white : scheme.onSurface)),
                      ),
                    ),
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

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool border;
  const _LegendDot({required this.color, required this.label, this.border = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: border ? Border.all(color: Theme.of(context).colorScheme.outline) : null),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// =========================================================================
/// RESULTS SCREEN
/// =========================================================================

class ResultsScreen extends StatelessWidget {
  final SubjectInfo subject;
  final List<Question> questions;
  final List<int?> selectedAnswers;
  final int correctCount;
  final int skippedCount;
  final int unansweredCount;

  const ResultsScreen({
    super.key,
    required this.subject,
    required this.questions,
    required this.selectedAnswers,
    required this.correctCount,
    required this.skippedCount,
    required this.unansweredCount,
  });

  double get _percentage => (correctCount / questions.length) * 100;

  String get _grade {
    final p = _percentage;
    if (p >= 75) return 'A';
    if (p >= 60) return 'B';
    if (p >= 50) return 'C';
    if (p >= 40) return 'D';
    return 'F';
  }

  String get _gradeLabel {
    switch (_grade) {
      case 'A':
        return 'Excellent';
      case 'B':
        return 'Very Good';
      case 'C':
        return 'Good';
      case 'D':
        return 'Pass';
      default:
        return 'Needs Improvement';
    }
  }

  Color _gradeColor(BuildContext context) {
    switch (_grade) {
      case 'A':
        return Colors.green;
      case 'B':
        return Colors.lightGreen;
      case 'C':
        return Colors.amber;
      case 'D':
        return Colors.orange;
      default:
        return Theme.of(context).colorScheme.error;
    }
  }

  String get _analysis {
    final p = _percentage;
    if (p >= 75) {
      return "Outstanding performance! You've demonstrated a strong grasp of ${subject.name}. Keep practising to maintain this level.";
    } else if (p >= 50) {
      return "Solid effort. You understand most of the ${subject.name} concepts, but reviewing the questions you missed will help you improve further.";
    } else {
      return "There's room for improvement. Focus on reviewing your wrong answers and revisit the core topics in ${subject.name} before your next attempt.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actualWrong = questions.length - correctCount - unansweredCount;

    return Scaffold(
      appBar: AppBar(title: const Text('Results'), automaticallyImplyLeading: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _percentage / 100),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 180,
                        height: 180,
                        child: CircularProgressIndicator(
                          value: value,
                          strokeWidth: 12,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(_gradeColor(context)),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${(value * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                          Text('Grade $_grade', style: TextStyle(color: _gradeColor(context), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(_gradeLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${subject.name} • Practice Set', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Text('+${correctCount * 10} XP earned', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _StatCard(label: 'Correct', value: '$correctCount', color: Colors.green),
                const SizedBox(width: 10),
                _StatCard(label: 'Wrong', value: '$actualWrong', color: Colors.red),
                const SizedBox(width: 10),
                _StatCard(label: 'Skipped', value: '$unansweredCount', color: Colors.orange),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.insights_rounded, color: scheme.primary),
                      const SizedBox(width: 8),
                      const Text('Performance Analysis', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(_analysis, style: const TextStyle(height: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                icon: const Icon(Icons.rate_review_rounded),
                label: const Text('Review Answers'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ReviewScreen(questions: questions, selectedAnswers: selectedAnswers)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Retake Exam'),
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => ExamInstructionsScreen(subject: subject, questions: questions)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton.icon(
                icon: const Icon(Icons.home_rounded),
                label: const Text('Back to Home'),
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

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
/// REVIEW SCREEN
/// =========================================================================

class ReviewScreen extends StatelessWidget {
  final List<Question> questions;
  final List<int?> selectedAnswers;
  const ReviewScreen({super.key, required this.questions, required this.selectedAnswers});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Review Answers')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: questions.length,
        itemBuilder: (context, index) {
          final question = questions[index];
          final selected = selectedAnswers[index];
          final isCorrect = selected == question.correctIndex;
          final wasAnswered = selected != null;

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: !wasAnswered ? scheme.outlineVariant : (isCorrect ? Colors.green : Colors.red), width: 1.4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                      child: Text('Q${index + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
                    ),
                    const Spacer(),
                    Icon(
                      !wasAnswered ? Icons.remove_circle_outline_rounded : (isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded),
                      color: !wasAnswered ? Colors.orange : (isCorrect ? Colors.green : Colors.red),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      !wasAnswered ? 'Skipped' : (isCorrect ? 'Correct' : 'Wrong'),
                      style: TextStyle(fontWeight: FontWeight.w600, color: !wasAnswered ? Colors.orange : (isCorrect ? Colors.green : Colors.red)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(question.questionText, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
                const SizedBox(height: 10),
                ...List.generate(question.options.length, (i) {
                  final isCorrectOption = i == question.correctIndex;
                  final isSelectedOption = i == selected;
                  Color? bg;
                  if (isCorrectOption) {
                    bg = Colors.green.withOpacity(0.15);
                  } else if (isSelectedOption && !isCorrectOption) {
                    bg = Colors.red.withOpacity(0.15);
                  }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isCorrectOption ? Colors.green : (isSelectedOption ? Colors.red : scheme.outlineVariant)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 12, backgroundColor: scheme.surface, child: Text(String.fromCharCode(65 + i), style: const TextStyle(fontSize: 12))),
                        const SizedBox(width: 10),
                        Expanded(child: Text(question.options[i], style: const TextStyle(fontSize: 13.5))),
                        if (isCorrectOption) const Icon(Icons.check_rounded, color: Colors.green, size: 18),
                        if (isSelectedOption && !isCorrectOption) const Icon(Icons.close_rounded, color: Colors.red, size: 18),
                      ],
                    ),
                  );
                }),
                if (question.explanation.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: scheme.primaryContainer.withOpacity(0.4), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, size: 18, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(question.explanation, style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
