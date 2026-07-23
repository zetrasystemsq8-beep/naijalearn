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
///
/// This is the ONLY login flow in this file. There is exactly one
/// AuthService, one place that calls resolve_login_email, one place
/// that calls signInWithOtp for the initial code send, and one place
/// that calls signInWithOtp for resend. There is no signUp call
/// anywhere in this file. profiles.email is never read or compared —
/// the only `.from('profiles')` query in this file is the post-login
/// `loadCurrentProfile()`, which selects by `id`, not by `email`.

/// Minimal read model of a `profiles` row, used to populate the app after
/// sign-in (username, zetramail, avatar, verified badge, etc).
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

  /// STEP 1 of the ONLY login flow: call the resolve_login_email
  /// RPC with the entered ZetraMail address (or username / Zetra ID /
  /// phone number). The Postgres function's named parameter is
  /// `p_identifier` — PostgREST matches RPC parameters by name, so this
  /// key must match the function signature exactly.
  ///
  /// STEP 2: if the RPC returns null/empty, throw noAccountMessage
  /// BEFORE ever calling signInWithOtp.
  ///
  /// STEP 3: otherwise call signInWithOtp() using ONLY the resolved
  /// auth_email, with shouldCreateUser: false. profiles.email is never
  /// queried or compared anywhere in this method.
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

    // Robust extraction: handle String, Map, List and nested shapes
    String? extractAuthEmail(dynamic res) {
      if (res == null) return null;
      if (res is String && res.isNotEmpty) return res;
      if (res is Map) {
        // Common shapes include: { 'resolve_login_email': '...'}
        // or { 'data': '...' } or { 'data': [ { 'resolve_login_email': '...' } ] }
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

  /// STEP 5 (verification): uses the SAME resolved auth_email saved in
  /// step 3 above — never the zetramail, never a fresh profiles.email
  /// lookup. Then loads the profile row so the UI can display it.
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

  /// Loads the `profiles` row for the currently authenticated user.
  /// This runs AFTER sign-in, so it's a client-side select against the
  /// user's own row, keyed by `id` — this is the only `.from('profiles')`
  /// call in the file, and it never reads or compares `email`.
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

  /// Resend: reuses the SAME _pendingAuthEmail saved during step 3 — not
  /// a fresh resolve_login_email call, and not the zetramail.
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
  /// The ZetraMail address the user typed — shown on screen.
  final String zetramail;
  /// The internal auth_email resolved from resolve_login_email() — used
  /// for the actual Supabase Auth call. Never shown to the user.
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
    // Observes app lifecycle (e.g. backgrounding to check ZetraMail and
    // returning). Deliberately does NOT clear the entered code, reset the
    // form, or navigate away on resume — Flutter keeps this State object
    // alive in memory the whole time, so nothing here needs to "restore"
    // anything. This observer exists purely so future edits don't
    // accidentally add a reset-on-resume bug.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Intentionally left as a no-op for our state. The widget tree and
    // this State object are not recreated when switching to ZetraMail
    // and back, so _codeController's text and _errorMessage survive
    // automatically without any code here.
  }

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
