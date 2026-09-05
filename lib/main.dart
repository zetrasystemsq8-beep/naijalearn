// lib/main.dart
//
// NaijaLearn — CBT Practice App
// Material 3.
//
// Question content lives in per-subject files (questions_*.dart).
// Gamification (XP, streak, badges, leaderboard, daily challenge, mock
// exams, analytics) lives in app_enhancements.dart and plugs in via
// AppProvider, without replacing any of the CBT screens below.
// Certification eligibility tracking lives in certification.dart.
// AI Study Coach, Score Predictor, Career Mode, Hall of Fame, Live Quiz
// Battles, Mistakes Vault, Bookmarks, Report Card, and small shared
// widgets (StreakSaverBanner, PaceMeter, dailyGoalStatusText) live in
// career_features.dart.
// Textbooks (multi-subject lesson shelf) live in textbooks.dart.
// Flashcards, Coin Shop, Spin Wheel, Multi-Exam Countdown, Topic
// Mastery, and Focus Mode live in features5.dart.
// Force-update / version gate lives in app_update.dart.
//
// THEME: the app's seed color is Nigerian green by default, but switches
// to an ocean-blue seed whenever CoinService.oceanThemeActive is true —
// making the Coin Shop's Ocean Theme Pack purchase actually visible
// across the whole app, not just a cosmetic flag sitting unused.
//
// Authentication: NaijaLearn is a client of the existing Zetra ecosystem
// for ZetraMail accounts, AND supports NaijaLearn-only self-signup
// accounts (username + password, no email, no OTP) — see signup_screen.dart
// and AuthService.signUpWithUsername/loginWithUsername below. LoginScreen
// routes based on whether the typed identifier contains '@': with '@' it's
// treated as a ZetraMail login (full flow, mandatory OTP); without '@' it's
// treated as a NaijaLearn username login (no OTP, straight to HomeScreen).
//
// Login is email+password (signInWithPassword), matching how the rest of
// the Zetra ecosystem (NAI) authenticates. The user types their ZetraMail
// address; it's resolved to the internal auth_email via the
// resolve_login_email(...) Supabase RPC, and Supabase Auth's password
// sign-in is called using ONLY that internal auth_email — the user never
// sees or types it. If the RPC returns null/empty, or the password is
// wrong, we show "Invalid ZetraMail or password."
//
// Verification code step: a code is ALWAYS required after ZetraMail
// password login, on every single login attempt — not just for unverified
// profiles. This is a deliberate second factor: knowing the ZetraMail +
// password alone is not enough to get in, since the code only shows up in
// the account owner's ZetraMail inbox (via the Zetra ID app). request_otp
// is called exactly once, right after signInWithPassword succeeds.
// Self-signup username accounts skip this step entirely (see above).
//
// Session-vs-verified tracking: Supabase creates a valid session the
// instant signInWithPassword succeeds — BEFORE the OTP step runs. So a
// bare "is there a session?" check is not enough to know someone has
// fully logged in; if the app process is killed while the user is
// fetching their code from the ZetraMail app, a naive check would send
// them straight into HomeScreen on relaunch, skipping the code entirely.
// To prevent that, AuthService stores a `nl_otp_verified` flag in
// Supabase Auth's own per-user metadata: reset to false at the start of
// every login(), set to true only once verifyCode() succeeds (or
// immediately for self-signup username accounts, which have no OTP step).
// SplashScreen checks this flag (not just session presence) to decide
// whether to route to HomeScreen or back to VerifyOtpScreen — and does
// NOT re-request a code in that second case, since the one already sent
// is still valid.
//
// This does NOT use Supabase's built-in signInWithOtp/verifyOTP (which
// rejects the .internal auth email domain with "Email address is
// invalid") — it uses the backend's own request_otp/verify_otp RPCs,
// the same ones NAI uses.
//
// FORCE UPDATE: before deciding where to route (Login vs Home vs
// VerifyOtp), SplashScreen asks AppUpdateService whether this build is
// too old to keep running. If so, it's replaced entirely by
// ForceUpdateScreen — a non-dismissible wall — instead of continuing on
// to auth/session routing. See app_update.dart for the Supabase-backed
// version check itself.
//
// REFERRAL ATTRIBUTION: immediately after the mandatory OTP step
// succeeds (and before the user ever reaches NaiOnboardingGate/HomeScreen),
// VerifyOtpScreen checks ReferralService.instance.getMyAttribution(). If
// the account has no referral code on file yet, the user is routed
// through ReferralCodeEntryScreen exactly once; if a code is already on
// file, the flow is unchanged. See referral_code_screen.dart.
//
// LOGIN SCREEN VISUAL STYLE: bright gradient backdrop (primary → tertiary
// → surface) with soft decorative glow circles, a glassy white input
// card, and a solid white elevated primary button — matching the same
// treatment as SignUpScreen (see signup_screen.dart) for a consistent,
// vibrant look across both auth screens.
//
// DEEP LINKS (Challenge a Friend): naijalearn://challenge/<id> links are
// caught by ChallengeDeepLinkListener (challenge_feature.dart) and pushed
// onto the top-level `navigatorKey` below, which is also handed to
// MaterialApp so pushes work from outside the widget tree.

import 'dart:async';
import 'dart:convert';
import 'study_plan.dart';
import 'models.dart';
export 'models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:passkeys/authenticator.dart';
import 'notification_service.dart';
import 'app_enhancements.dart';
import 'certification.dart';
import 'career_features.dart';
import 'textbooks.dart';
import 'features5.dart';
import 'zetra_pay.dart';
import 'wallet_display.dart';
import 'admin_panel.dart';
import 'academic_arena.dart';
import 'world_challenge.dart';
import 'study_squads.dart';
import 'nai_mentor.dart';
import 'guest_mode.dart';
import 'signup_screen.dart';
import 'app_update.dart';
import 'referral_code_screen.dart';
import 'challenge_feature.dart';
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

/// Top-level navigator key — lets code outside the widget tree (namely
/// ChallengeDeepLinkListener) push routes onto the app's Navigator.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  
 await NotificationService.instance.init();
  
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider.value(value: CoinService.instance),
        ChangeNotifierProvider.value(value: FlashcardService.instance),
        ChangeNotifierProvider.value(value: MasteryService.instance),
        ChangeNotifierProvider.value(value: ExamCountdownService.instance),
      ],
      child: const NaijaLearnApp(),
    ),
  );
  ChallengeDeepLinkListener.init(navigatorKey);
}

Future<void> signInWithZetraFingerprint(BuildContext context) async {
  final authenticator = PasskeyAuthenticator();
  try {
    final response = await Supabase.instance.client.auth.signInWithPasskey(authenticator);
    if (response.session != null) {
      // Signed in — same account as ZetraMail. Caller should navigate
      // to HomeScreen the same way the existing password login does
      // after AuthService.instance.login(...) succeeds.
    }
  } catch (e) {
    // No passkey set up on this device yet, or it was cancelled.
    // Fall back to the existing password login screen — do nothing
    // here except let the calling button show an error/snackbar.
    rethrow;
  }
}

/// =========================================================================
/// AUTHENTICATION (Zetra ecosystem client — email+password + mandatory OTP)
/// =========================================================================

class ZetraProfile {
  final String id;
  final String zetramail;
  final String username;
  final bool verified;
  final String? avatarUrl;

  ZetraProfile({
    required this.id,
    required this.zetramail,
    required this.username,
    required this.verified,
    this.avatarUrl,
  });

  factory ZetraProfile.fromMap(Map<String, dynamic> map) {
    return ZetraProfile(
      id: map['id'] as String,
      zetramail: map['zetramail'] as String? ?? '',
      username: map['username'] as String? ?? '',
      verified: map['verified'] as bool? ?? false,
      avatarUrl: map['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'zetramail': zetramail,
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

  static const String invalidCredentialsMessage = 'Invalid ZetraMail or password.';
  static const String invalidOtpMessage = 'Invalid or expired code. Please try again.';
  static const String profileLoadErrorMessage = 'Could not load your profile. Please try again.';

  static const String _otpVerifiedMetaKey = 'nl_otp_verified';

  SupabaseClient get _client => Supabase.instance.client;

  bool get isSignedIn => _client.auth.currentSession != null;

  /// True only once the CURRENT session has completed the mandatory
  /// verification-code step. Backed by Supabase Auth's own per-user
  /// metadata so it survives the app process being killed and relaunched.
  bool get isOtpVerifiedForCurrentSession =>
      _client.auth.currentUser?.userMetadata?[_otpVerifiedMetaKey] == true;

  /// Resolves the typed ZetraMail to the internal auth_email via RPC, then
  /// signs in with email+password against Supabase Auth. Immediately
  /// invalidates any stale "verified" flag from a previous login, then
  /// requests a fresh code exactly once. The caller (LoginScreen) is
  /// expected to always route to VerifyOtpScreen next.
  Future<ZetraProfile> login({
    required String zetramail,
    required String password,
  }) async {
    final normalized = zetramail.trim().toLowerCase();

    debugPrint('[ZetraAuth] Entered ZetraMail: "$normalized"');

    if (normalized.isEmpty) {
      debugPrint('[ZetraAuth] Empty ZetraMail after trim — aborting before any RPC/Auth call.');
      throw ZetraAuthException(invalidCredentialsMessage);
    }

    String? resolvedEmail;
    try {
      final result = await _client.rpc(
        'resolve_login_email',
        params: {'p_identifier': normalized},
      );
      resolvedEmail = result is String ? result : null;
      debugPrint('[ZetraAuth] resolve_login_email RPC result: $result (type: ${result.runtimeType})');
    } on PostgrestException catch (e) {
      debugPrint('[ZetraAuth] resolve_login_email RPC FAILED (PostgrestException): '
          'code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      throw ZetraAuthException(invalidCredentialsMessage);
    }

    if (resolvedEmail == null || resolvedEmail.isEmpty) {
      debugPrint('[ZetraAuth] resolve_login_email returned null/empty for '
          'identifier="$normalized" — no matching Zetra account.');
      throw ZetraAuthException(invalidCredentialsMessage);
    }

    debugPrint('[ZetraAuth] auth_email resolved via RPC: "$resolvedEmail"');
    debugPrint('[ZetraAuth] About to call signInWithPassword() for resolved auth_email.');

    AuthResponse response;
    try {
      response = await _client.auth.signInWithPassword(
        email: resolvedEmail,
        password: password,
      );
      debugPrint('[ZetraAuth] signInWithPassword() SUCCEEDED.');
    } on AuthException catch (e) {
      debugPrint('[ZetraAuth] signInWithPassword() FAILED (AuthException): '
          'message="${e.message}", statusCode=${e.statusCode}');
      throw ZetraAuthException(invalidCredentialsMessage);
    }

    final user = response.user;
    if (user == null) {
      debugPrint('[ZetraAuth] signInWithPassword() returned null user with no thrown exception.');
      throw ZetraAuthException(invalidCredentialsMessage);
    }

    // Every login must redo the OTP step — clear any leftover "verified"
    // flag from a previous session before requesting the new code.
    try {
      await _client.auth.updateUser(UserAttributes(data: {_otpVerifiedMetaKey: false}));
    } catch (e) {
      debugPrint('[ZetraAuth] Could not reset otp-verified flag (non-fatal): $e');
    }

    final profile = await loadCurrentProfile();

    debugPrint('[ZetraAuth] Requesting mandatory login OTP via request_otp RPC.');
    try {
      await _client.rpc('request_otp');
      debugPrint('[ZetraAuth] request_otp SUCCEEDED.');
    } on PostgrestException catch (e) {
      debugPrint('[ZetraAuth] request_otp FAILED (PostgrestException): '
          'code=${e.code}, message=${e.message}');
      throw ZetraAuthException('Could not send your verification code. Please try again.');
    }

    return profile;
  }

  /// Self-serve NaijaLearn-only signup. Creates a real Supabase Auth user
  /// under a generated internal alias email (username@nlstudent.internal),
  /// then a matching profiles row via the complete_naijalearn_signup RPC.
  /// No OTP step — the caller is logged in immediately after this returns.
  Future<ZetraProfile> signUpWithUsername({
    required String username,
    required String password,
  }) async {
    final aliasEmail = '$username@nlstudent.internal';

    AuthResponse response;
    try {
      response = await _client.auth.signUp(
        email: aliasEmail,
        password: password,
        data: {'username': username},
      );
    } on AuthException catch (e) {
      throw ZetraAuthException(e.message);
    }

    if (response.user == null || response.session == null) {
      throw ZetraAuthException('Could not create account. Please try again.');
    }

    try {
      await _client.rpc('complete_naijalearn_signup', params: {
        'p_username': username,
        'p_alias_email': aliasEmail,
      });
    } on PostgrestException catch (e) {
      throw ZetraAuthException(e.message);
    }

    // No OTP for self-signup accounts — mark verified immediately.
    try {
      await _client.auth.updateUser(UserAttributes(data: {_otpVerifiedMetaKey: true}));
    } catch (e) {
      debugPrint('[ZetraAuth] Could not set otp-verified flag after signup (non-fatal): $e');
    }

    return loadCurrentProfile();
  }

  /// Login for NaijaLearn-only username accounts (identifier typed with no
  /// @ symbol). Skips resolve_login_email and the OTP step entirely.
  Future<ZetraProfile> loginWithUsername({
    required String username,
    required String password,
  }) async {
    final aliasEmail = '$username@nlstudent.internal';

    try {
      final response = await _client.auth.signInWithPassword(email: aliasEmail, password: password);
      if (response.user == null) throw ZetraAuthException(invalidCredentialsMessage);
    } on AuthException {
      throw ZetraAuthException(invalidCredentialsMessage);
    }

    try {
      await _client.auth.updateUser(UserAttributes(data: {_otpVerifiedMetaKey: true}));
    } catch (e) {
      debugPrint('[ZetraAuth] Could not set otp-verified flag on username login (non-fatal): $e');
    }

    return loadCurrentProfile();
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
      throw ZetraAuthException(profileLoadErrorMessage);
    }

    if (row == null) {
      debugPrint('[ZetraAuth] loadCurrentProfile(): no profile row for user.id="${user.id}".');
      throw ZetraAuthException(profileLoadErrorMessage);
    }

    return ZetraProfile.fromMap(row);
  }

  /// Verifies the code the user copied from their ZetraMail inbox against
  /// the backend's own verify_otp RPC (NOT Supabase's verifyOTP — that
  /// requires the .internal auth email, which Supabase Auth itself rejects
  /// as an invalid email format). On success, marks this session verified
  /// via Supabase Auth user metadata so a killed-and-relaunched app knows
  /// this step is already done.
  Future<ZetraProfile> verifyCode({required String code}) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      debugPrint('[ZetraAuth] verifyCode() aborted — no active session.');
      throw ZetraAuthException("You're not signed in. Please log in again.");
    }

    debugPrint('[ZetraAuth] verify_otp() called with code="${code.trim()}"');

    dynamic result;
    try {
      result = await _client.rpc('verify_otp', params: {'p_code': code.trim()});
      debugPrint('[ZetraAuth] verify_otp RPC result: $result');
    } on PostgrestException catch (e) {
      debugPrint('[ZetraAuth] verify_otp FAILED (PostgrestException): '
          'code=${e.code}, message=${e.message}');
      throw ZetraAuthException(invalidOtpMessage);
    }

    if (result != true) {
      debugPrint('[ZetraAuth] verify_otp returned falsy result — treating as invalid code.');
      throw ZetraAuthException(invalidOtpMessage);
    }

    try {
      await _client.auth.updateUser(UserAttributes(data: {_otpVerifiedMetaKey: true}));
      debugPrint('[ZetraAuth] otp-verified flag persisted for this session.');
    } catch (e) {
      debugPrint('[ZetraAuth] Could not persist otp-verified flag (non-fatal): $e');
    }

    return loadCurrentProfile();
  }

  Future<void> resendCode() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw ZetraAuthException("You're not signed in. Please log in again.");
    }
    debugPrint('[ZetraAuth] resendCode() called via request_otp RPC.');
    try {
      await _client.rpc('request_otp');
      debugPrint('[ZetraAuth] resendCode() SUCCEEDED.');
    } on PostgrestException catch (e) {
      debugPrint('[ZetraAuth] resendCode() FAILED (PostgrestException): '
          'code=${e.code}, message=${e.message}');
      throw ZetraAuthException('Could not resend code. Please try again.');
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.updateUser(UserAttributes(data: {_otpVerifiedMetaKey: false}));
    } catch (_) {
      // non-fatal — signing out below still clears the session either way
    }
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
  final _zetramailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _zetramailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateZetraMail(String? value) {
    final identifier = value?.trim() ?? '';
    if (identifier.isEmpty) return 'Please enter your ZetraMail or username';
    // If it contains '@', validate as an email. Otherwise it's treated
    // as a NaijaLearn username login — no format restriction beyond
    // "not empty" here (signup already enforces the real format).
    if (identifier.contains('@')) {
      final emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
      if (!emailRegex.hasMatch(identifier)) return 'Please enter a valid email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Please enter your password';
    if (password.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final zetramail = _zetramailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      if (zetramail.contains('@')) {
        // Full ZetraMail login — always requests a fresh OTP, so every
        // successful login lands on VerifyOtpScreen, never straight into
        // HomeScreen. Password alone is never enough.
        await AuthService.instance.login(zetramail: zetramail, password: password);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const VerifyOtpScreen()),
          (route) => false,
        );
      } else {
        // No @ symbol typed — treat as a NaijaLearn-only username login.
        // No OTP step; straight into HomeScreen on success.
        final profile = await AuthService.instance.loginWithUsername(
          username: zetramail,
          password: password,
        );
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomeScreen(profile: profile)),
          (route) => false,
        );
      }
    } on ZetraAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not sign in. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // Vibrant multi-color gradient backdrop — "shiny lovable" look,
          // matching SignUpScreen for a consistent bright auth experience.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withOpacity(0.85),
                  scheme.tertiary.withOpacity(0.65),
                  scheme.surface,
                ],
                stops: const [0.0, 0.28, 0.55],
              ),
            ),
          ),
          // Soft decorative glow blobs for depth.
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.12),
              ),
            ),
          ),
          Positioned(
            top: 140,
            left: -50,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.tertiary.withOpacity(0.18),
              ),
            ),
          ),
          SafeArea(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Scrollable content up top — grows/shrinks with keyboard,
                  // but the primary action stays docked at the bottom below.
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 100,
                              height: 100,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Colors.white, Color(0xFFEFEFFF)],
                                ),
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25),
                                    blurRadius: 24,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Icon(Icons.school_rounded, size: 52, color: scheme.primary),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Welcome to NaijaLearn',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sign in with your ZetraMail — or your NaijaLearn username',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withOpacity(0.9),
                                ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.96),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 30,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _zetramailController,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.username],
                                  textInputAction: TextInputAction.next,
                                  validator: _validateZetraMail,
                                  decoration: InputDecoration(
                                    labelText: 'ZetraMail or username',
                                    hintText: 'you@zetramail.ng or username',
                                    filled: true,
                                    fillColor: scheme.surfaceContainerHighest.withOpacity(0.5),
                                    prefixIcon: Icon(Icons.email_outlined, color: scheme.primary),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  autofillHints: const [AutofillHints.password],
                                  textInputAction: TextInputAction.done,
                                  validator: _validatePassword,
                                  onFieldSubmitted: (_) => _continue(),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    filled: true,
                                    fillColor: scheme.surfaceContainerHighest.withOpacity(0.5),
                                    prefixIcon: Icon(Icons.lock_outline_rounded, color: scheme.primary),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_errorMessage!, style: TextStyle(color: scheme.error, fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Primary action pinned to the bottom of the screen.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 56,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              backgroundColor: Colors.white,
                              foregroundColor: scheme.primary,
                              elevation: 6,
                              shadowColor: Colors.black.withOpacity(0.3),
                            ),
                            onPressed: _loading ? null : _continue,
                            child: _loading
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.4, color: scheme.primary),
                                  )
                                : const Text('Log In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 56,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              backgroundColor: Colors.white,
                              foregroundColor: scheme.primary,
                              elevation: 6,
                              shadowColor: Colors.black.withOpacity(0.3),
                            ),
                            onPressed: _loading
                                ? null
                                : () async {
                                    try {
                                      await signInWithZetraFingerprint(context);
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Fingerprint sign-in failed. Please use password login.')),
                                      );
                                    }
                                  },
                            child: _loading
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.4, color: scheme.primary),
                                  )
                                : const Text('Sign in with Fingerprint', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const SignUpScreen()),
                                  ),
                          child: Text(
                            "Don't have an account? Sign up",
                            style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const GuestHomeScreen()),
                                  ),
                          child: Text(
                            'Continue as Guest',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
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

class VerifyOtpScreen extends StatefulWidget {
  const VerifyOtpScreen({super.key});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  String? _errorMessage;

  static const int _resendCooldownSeconds = 30;
  int _resendSecondsLeft = _resendCooldownSeconds;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startResendCooldown();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsLeft <= 1) {
        timer.cancel();
        setState(() => _resendSecondsLeft = 0);
      } else {
        setState(() => _resendSecondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resendTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  String? _validateCode(String? value) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) return 'Please enter the code';
    if (code.length < 4) return 'Enter the code from your ZetraMail';
    return null;
  }

  Future<void> _verifyCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final profile = await AuthService.instance.verifyCode(code: _codeController.text.trim());
      if (!mounted) return;

      // Check referral attribution once, right after OTP success, before
      // ever landing in the app. Existing users with a code already on
      // file skip this entirely and go straight to NaiOnboardingGate.
      final attribution = await ReferralService.instance.getMyAttribution();
      if (!mounted) return;

      if (attribution == null) {
        // First login, no code on file yet — collect it once. Using
        // push() (not pushAndRemoveUntil) here keeps this screen mounted
        // so `context` below stays valid when onDone eventually fires.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReferralCodeEntryScreen(
              onDone: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => NaiOnboardingGate(profile: profile)),
                (route) => false,
              ),
            ),
          ),
        );
      } else {
        // Already has a code on file — unchanged flow.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => NaiOnboardingGate(profile: profile)),
          (route) => false,
        );
      }
    } on ZetraAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Invalid or expired code. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_resendSecondsLeft > 0) return;

    setState(() {
      _resending = true;
      _errorMessage = null;
    });

    try {
      await AuthService.instance.resendCode();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent to your ZetraMail inbox.')),
      );
      _startResendCooldown();
    } on ZetraAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not resend code. Please try again.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _useDifferentAccount() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Your Zetra ID')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.mark_email_read_rounded, size: 56, color: scheme.primary),
                      const SizedBox(height: 20),
                      Text(
                        'Open your ZetraMail in the Zetra ID app, copy the code, and paste it below.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
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
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: _loading ? null : _verifyCode,
                        child: _loading ? const CircularProgressIndicator() : const Text('Verify'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _resending ? null : _resendCode,
                      child: Text(_resendSecondsLeft > 0 ? 'Resend ($_resendSecondsLeft)' : 'Resend code'),
                    ),
                    TextButton(
                      onPressed: _loading ? null : _useDifferentAccount,
                      child: const Text('Use a different account'),
                    ),
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
