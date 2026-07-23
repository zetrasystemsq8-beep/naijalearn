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
// Authentication: NaijaLearn is a client of the existing Zetra ecosystem.
// Users are NOT created here — they must already have a Zetra account.
// The user types their ZetraMail address (e.g. user@zetramail.ng). We
// resolve that to the internal auth_email via the resolve_login_email(...)
// Supabase RPC, and Supabase Auth OTP is sent/verified using ONLY that
// internal auth_email — the user never sees or types it. If the RPC
// returns null/empty, we show "This ZetraMail account does not exist."
// and never call signInWithOtp.
//
// Note on backgrounding: Flutter does NOT reload the app or reset widget
// state when the user switches to another app (ZetraMail) and returns,
// as long as the OS hasn't killed the process. The entered email, the
// OTP digits, and the resend-timer all persist automatically. The
// WidgetsBindingObserver on VerifyOtpScreen below simply logs lifecycle
// transitions and deliberately does NOT touch any state on resume —
// it exists so future changes don't accidentally introduce a reset.

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
/// AUTHENTICATION (Zetra ecosystem client — RPC-backed OTP login)
/// =========================================================================

class ZetraProfile {
  final String id;
  final String zetramail;
  final String authEmail;
  final String username;
  final bool verified;
  final String? avatarUrl;

  ZetraProfile({
    required this.id,
    required this.zetramail,
    required this.authEmail,
    required this.username,
    required this.verified,
    this.avatarUrl,
  });

  factory ZetraProfile.fromMap(Map<String, dynamic> map) {
    return ZetraProfile(
      id: map['id'] as String,
      zetramail: map['zetramail'] as String,
      authEmail: map['auth_email'] as String,
      username: map['username'] as String? ?? '',
      verified: map['verified'] as bool? ?? false,
      avatarUrl: map['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'zetramail': zetramail,
        'auth_email': authEmail,
        'username': username,
        'verified': verified,
        'avatar_url': avatarUrl,
      };
}

class ZetraAuthException implements Exception {
  final String message;
  ZetraAuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const String noAccountMessage = 'This ZetraMail account does not exist.';
  static const String invalidOtpMessage = 'Invalid verification code.';

  SupabaseClient get _client => Supabase.instance.client;

  String? _pendingAuthEmail;
  String? _pendingZetramail;

  String? get pendingZetramail => _pendingZetramail;

  bool get isSignedIn => _client.auth.currentSession != null;

  Future<String> requestOtpForZetraMail(String zetramail) async {
    final normalized = zetramail.trim().toLowerCase();

    debugPrint('[ZetraAuth] Entered ZetraMail: "$normalized"');

    if (normalized.isEmpty) {
      debugPrint('[ZetraAuth] Empty ZetraMail after trim — aborting before any RPC/Auth call.');
      throw ZetraAuthException(noAccountMessage);
    }

    dynamic result;
    try {
      result = await _client.rpc(
        'resolve_login_email',
        params: {'p_identifier': normalized},
      );
    } on PostgrestException catch (e) {
      debugPrint('[ZetraAuth] resolve_login_email RPC FAILED (PostgrestException): '
          'code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      throw ZetraAuthException(noAccountMessage);
    }

    debugPrint('[ZetraAuth] resolve_login_email RPC result: $result (type: ${result.runtimeType})');

    // Robust extraction: recursively search the RPC result for the first non-empty String.
    String? extractAuthEmail(dynamic res) {
      if (res == null) return null;
      if (res is String) {
        final trimmed = res.trim();
        if (trimmed.isNotEmpty) return trimmed;
      }
      if (res is Map) {
        for (final v in res.values) {
          final found = extractAuthEmail(v);
          if (found != null && found.isNotEmpty) return found;
        }
      }
      if (res is List && res.isNotEmpty) {
        for (final item in res) {
          final found = extractAuthEmail(item);
          if (found != null && found.isNotEmpty) return found;
        }
      }
      return null;
    }

    final authEmail = extractAuthEmail(result);

    if (authEmail == null || authEmail.isEmpty) {
      debugPrint('[ZetraAuth] resolve_login_email returned null/empty for '
          'identifier="$normalized" — no matching Zetra account. RPC result: $result');
      throw ZetraAuthException(noAccountMessage);
    }

    debugPrint('[ZetraAuth] auth_email resolved via RPC: "$authEmail"');
    debugPrint('[ZetraAuth] About to call signInWithOtp('
        'email: "$authEmail", shouldCreateUser: false) '
        '— entered zetramail was "$normalized".');

    try {
      await _client.auth.signInWithOtp(
        email: authEmail,
        shouldCreateUser: false, // NaijaLearn never creates new accounts
      );
      debugPrint('[ZetraAuth] signInWithOtp() SUCCEEDED for "$authEmail".');
    } on AuthException catch (e) {
      debugPrint('[ZetraAuth] signInWithOtp() FAILED (AuthException): '
          'message="${e.message}", statusCode=${e.statusCode}');
      throw ZetraAuthException(noAccountMessage);
    } catch (e, st) {
      debugPrint('[ZetraAuth] signInWithOtp() FAILED (non-AuthException, e.g. network): $e');
      debugPrint('[ZetraAuth] Stack trace: $st');
      rethrow;
    }

    // STEP 5 setup: save the resolved internal email so OTP verification
    // (and resend) reuse it — the user's typed zetramail is never used
    // for any Supabase Auth call.
    _pendingAuthEmail = authEmail;
    _pendingZetramail = normalized;

    return authEmail;
  }

  Future<ZetraProfile> verifyOtpAndLoadProfile({
    required String token,
    String? authEmailOverride,
  }) async {
    final authEmail = authEmailOverride ?? _pendingAuthEmail;

    debugPrint('[ZetraAuth] verifyOTP() called with authEmail="$authEmail", '
        'token="${token.trim()}"');

    if (authEmail == null) {
      debugPrint('[ZetraAuth] verifyOTP() aborted — no pending authEmail set.');
      throw ZetraAuthException('No pending sign-in request. Please start again.');
    }

    try {
      final res = await _client.auth.verifyOTP(
        type: OtpType.email,
        email: authEmail,
        token: token.trim(),
      );
      debugPrint('[ZetraAuth] verifyOTP() response: '
          'session=${res.session != null}, user=${res.user != null}, '
          'userId=${res.user?.id}');
      if (res.session == null || res.user == null) {
        debugPrint('[ZetraAuth] verifyOTP() returned null session/user with no thrown '
            'exception — treating as invalid OTP.');
        throw ZetraAuthException(invalidOtpMessage);
      }
    } on AuthException catch (e) {
      debugPrint('[ZetraAuth] verifyOTP() FAILED (AuthException): '
          'message="${e.message}", statusCode=${e.statusCode}');
      throw ZetraAuthException(invalidOtpMessage);
    } catch (e, st) {
      debugPrint('[ZetraAuth] verifyOTP() FAILED (non-AuthException): $e');
      debugPrint('[ZetraAuth] Stack trace: $st');
      rethrow;
    }

    final profile = await loadCurrentProfile();

    _pendingAuthEmail = null;
    _pendingZetramail = null;

    return profile;
  }

  Future<ZetraProfile> loadCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw ZetraAuthException('Not signed in.');
    }

    Map<String, dynamic>? row;
    try {
      row = await _client.from('profiles').select().eq('id', user.id).maybeSingle();
    } on PostgrestException catch (e) {
      debugPrint('[ZetraAuth] loadCurrentProfile() lookup FAILED (PostgrestException): '
          'code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      throw ZetraAuthException(noAccountMessage);
    }

    if (row == null) {
      debugPrint('[ZetraAuth] loadCurrentProfile(): no profile row for user.id="${user.id}".');
      throw ZetraAuthException(noAccountMessage);
    }

    return ZetraProfile.fromMap(row);
  }

  Future<void> resendOtp() async {
    if (_pendingAuthEmail == null) {
      throw ZetraAuthException('No pending sign-in request. Please start again.');
    }
    debugPrint('[ZetraAuth] resendOtp() called for authEmail="$_pendingAuthEmail" '
        '(shouldCreateUser: false)');
    try {
      await _client.auth.signInWithOtp(
        email: _pendingAuthEmail!,
        shouldCreateUser: false,
      );
      debugPrint('[ZetraAuth] resendOtp() SUCCEEDED for "$_pendingAuthEmail".');
    } on AuthException catch (e) {
      debugPrint('[ZetraAuth] resendOtp() FAILED (AuthException): '
          'message="${e.message}", statusCode=${e.statusCode}');
      throw ZetraAuthException('Could not resend code. Please try again.');
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _pendingAuthEmail = null;
    _pendingZetramail = null;
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _zetramailController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _zetramailController.dispose();
    super.dispose();
  }

  String? _validateZetraMail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Please enter your ZetraMail address';
    final emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
    if (!emailRegex.hasMatch(email)) return 'Please enter a valid email';
    return null;
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final zetramail = _zetramailController.text.trim();

    try {
      final authEmail = await AuthService.instance.requestOtpForZetraMail(zetramail);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyOtpScreen(zetramail: zetramail, authEmail: authEmail),
        ),
      );
    } on ZetraAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not send code. Please check your connection and try again.');
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
                    'Sign in with your ZetraMail address',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _zetramailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.done,
                    validator: _validateZetraMail,
                    onFieldSubmitted: (_) => _continue(),
                    decoration: InputDecoration(
                      labelText: 'ZetraMail address',
                      hintText: 'you@zetramail.ng',
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
                      onPressed: _loading ? null : _continue,
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
  final String zetramail;
  final String authEmail;

  const VerifyOtpScreen({super.key, required this.zetramail, required this.authEmail});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      final profile = await AuthService.instance.verifyOtpAndLoadProfile(
        token: _codeController.text.trim(),
        authEmailOverride: widget.authEmail,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeScreen(profile: profile)),
        (route) => false,
      );
    } on ZetraAuthException catch (e) {
      setState(() => _errorMessage = e.message);
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
      await AuthService.instance.resendOtp();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent to your ZetraMail inbox.')),
      );
    } on ZetraAuthException catch (e) {
      setState(() => _errorMessage = e.message);
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
                    'Enter the 6-digit code sent to your ZetraMail inbox for',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.zetramail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Open the ZetraMail app, copy the code, then come back here — this screen stays exactly as you left it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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
    Timer(const Duration(milliseconds: 2000), () async {
      if (!mounted) return;

      final hasSession = Supabase.instance.client.auth.currentSession != null;
      Widget destination;

      if (hasSession) {
        try {
          final profile = await AuthService.instance.loadCurrentProfile();
          destination = HomeScreen(profile: profile);
        } catch (_) {
          destination = const LoginScreen();
        }
      } else {
        destination = const LoginScreen();
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, animation, __) => FadeTransition(opacity: animation, child: destination),
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
  final ZetraProfile? profile;

  const HomeScreen({super.key, this.profile});

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
                          Text(
                            profile != null ? 'Welcome, ${profile!.username}' : 'Choose a subject to practice',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                        child: Icon(Icons.book_rounded, color: Colors.white.withOpacity(0.7)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildListDelegate(
                  kSubjects.map((subject) {
                    return GestureDetector(
                      onTap: () => _pickCountAndStart(context, subject),
                      child: Container(
                        decoration: BoxDecoration(color: subject.color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(subject.icon, size: 44, color: subject.color),
                            const SizedBox(height: 8),
                            Text(
                              subject.name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: subject.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
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

  const _StatPill({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

/// =========================================================================
/// REMAINING SCREENS (stub import from app_enhancements.dart)
/// =========================================================================
