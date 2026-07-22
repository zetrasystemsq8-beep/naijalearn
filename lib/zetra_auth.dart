import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// MODEL
// ============================================================

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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'zetramail': zetramail,
      'auth_email': authEmail,
      'username': username,
      'verified': verified,
      'avatar_url': avatarUrl,
    };
  }
}

// ============================================================
// SERVICE
// ============================================================

class ZetraAuthException implements Exception {
  final String message;
  ZetraAuthException(this.message);

  @override
  String toString() => message;
}

class ZetraAuthService {
  final SupabaseClient _client = Supabase.instance.client;

  static const String noAccountMessage = 'This ZetraMail account does not exist.';
  static const String invalidOtpMessage = 'Invalid verification code.';

  String? _pendingAuthEmail;
  String? _pendingZetramail;

  String? get pendingZetramail => _pendingZetramail;

  bool get isSignedIn => _client.auth.currentSession != null;

  /// Step 1: resolve the entered ZetraMail (or other identifier) to the
  /// internal auth_email via the resolve_login_email(p_identifier) RPC.
  /// This is the ONLY approved way to resolve an identifier pre-login —
  /// a direct `.from('profiles').select(...).eq('zetramail', ...)` here
  /// would be subject to RLS and silently return null for unauthenticated
  /// callers even when a matching row exists, which was the actual bug
  /// in the previous version of this file.
  ///
  /// Step 2: if the RPC returns null/empty, throw before calling
  /// signInWithOtp.
  /// Step 3: otherwise call signInWithOtp() using ONLY the resolved
  /// auth_email. Returns that auth_email, which the OTP screen needs
  /// to verify against.
  Future<String> requestOtpForZetraMail(String zetramail) async {
    final normalized = zetramail.trim().toLowerCase();

    if (normalized.isEmpty) {
      throw ZetraAuthException(noAccountMessage);
    }

    dynamic result;
    try {
      result = await _client.rpc(
        'resolve_login_email',
        params: {'p_identifier': normalized},
      );
    } on PostgrestException catch (_) {
      throw ZetraAuthException(noAccountMessage);
    }

    // The RPC may return a plain string, or (depending on how it's
    // declared) a single-row/single-column result — handle both shapes
    // defensively without guessing at schema details.
    String? authEmail;
    if (result is String && result.isNotEmpty) {
      authEmail = result;
    } else if (result is Map && result.values.isNotEmpty) {
      final first = result.values.first;
      if (first is String && first.isNotEmpty) authEmail = first;
    } else if (result is List && result.isNotEmpty) {
      final row = result.first;
      if (row is String && row.isNotEmpty) {
        authEmail = row;
      } else if (row is Map && row.values.isNotEmpty) {
        final first = row.values.first;
        if (first is String && first.isNotEmpty) authEmail = first;
      }
    }

    if (authEmail == null || authEmail.isEmpty) {
      throw ZetraAuthException(noAccountMessage);
    }

    try {
      await _client.auth.signInWithOtp(
        email: authEmail,
        shouldCreateUser: false,
      );
    } on AuthException catch (_) {
      throw ZetraAuthException(noAccountMessage);
    }

    _pendingAuthEmail = authEmail;
    _pendingZetramail = normalized;

    return authEmail;
  }

  /// Step 4: Verify the OTP against auth_email (never zetramail).
  /// Step 5: Load the profile once verified.
  Future<ZetraProfile> verifyOtp({
    required String token,
    String? authEmailOverride,
  }) async {
    final authEmail = authEmailOverride ?? _pendingAuthEmail;

    if (authEmail == null) {
      throw ZetraAuthException('No pending sign-in request. Please start again.');
    }

    try {
      final AuthResponse res = await _client.auth.verifyOTP(
        type: OtpType.email,
        email: authEmail,
        token: token.trim(),
      );

      if (res.session == null || res.user == null) {
        throw ZetraAuthException(invalidOtpMessage);
      }
    } on AuthException catch (_) {
      throw ZetraAuthException(invalidOtpMessage);
    }

    final profile = await loadCurrentProfile();

    _pendingAuthEmail = null;
    _pendingZetramail = null;

    return profile;
  }

  /// Loads the profile row for the currently authenticated user. This
  /// runs AFTER sign-in, so it's a client-side select against the
  /// user's own row keyed by `id` — RLS permits `auth.uid() == id`
  /// reads here, which is a different context from pre-login lookup
  /// (which now goes through the RPC instead). This never reads or
  /// filters by `email`.
  Future<ZetraProfile> loadCurrentProfile() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw ZetraAuthException('Not signed in.');
    }

    Map<String, dynamic>? response;
    try {
      response = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
    } on PostgrestException catch (_) {
      throw ZetraAuthException(noAccountMessage);
    }

    if (response == null) {
      throw ZetraAuthException(noAccountMessage);
    }

    return ZetraProfile.fromMap(response);
  }

  Future<void> resendOtp() async {
    if (_pendingAuthEmail == null) {
      throw ZetraAuthException('No pending sign-in request. Please start again.');
    }
    try {
      await _client.auth.signInWithOtp(
        email: _pendingAuthEmail!,
        shouldCreateUser: false,
      );
    } on AuthException catch (_) {
      throw ZetraAuthException('Could not resend code. Please try again.');
    }
  }

  void cancelPendingSignIn() {
    _pendingAuthEmail = null;
    _pendingZetramail = null;
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _pendingAuthEmail = null;
    _pendingZetramail = null;
  }
}

// ============================================================
// LOGIN SCREEN
// ============================================================

class ZetraLoginScreen extends StatefulWidget {
  const ZetraLoginScreen({super.key});

  @override
  State<ZetraLoginScreen> createState() => _ZetraLoginScreenState();
}

class _ZetraLoginScreenState extends State<ZetraLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _zetramailController = TextEditingController();
  final _authService = ZetraAuthService();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _zetramailController.dispose();
    super.dispose();
  }

  String? _validateZetraMail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Enter your ZetraMail address.';
    }
    final emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
    if (!emailRegex.hasMatch(trimmed)) {
      return 'Enter a valid ZetraMail address.';
    }
    return null;
  }

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final zetramail = _zetramailController.text.trim();

    try {
      final authEmail = await _authService.requestOtpForZetraMail(zetramail);

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ZetraOtpScreen(
            authService: _authService,
            zetramail: zetramail,
            authEmail: authEmail,
          ),
        ),
      );
    } on ZetraAuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.school_rounded,
                    size: 64,
                    color: Color(0xFF00843D),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Sign in to NaijaLearn',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use your ZetraMail address to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _zetramailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      labelText: 'ZetraMail address',
                      hintText: 'yourname@zetramail.ng',
                      prefixIcon: const Icon(Icons.alternate_email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: _validateZetraMail,
                    onFieldSubmitted: (_) => _handleContinue(),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00843D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Continue',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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

// ============================================================
// OTP SCREEN
// ============================================================

class ZetraOtpScreen extends StatefulWidget {
  final ZetraAuthService authService;
  final String zetramail;
  final String authEmail;

  const ZetraOtpScreen({
    super.key,
    required this.authService,
    required this.zetramail,
    required this.authEmail,
  });

  @override
  State<ZetraOtpScreen> createState() => _ZetraOtpScreenState();
}

class _ZetraOtpScreenState extends State<ZetraOtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  String? _validateOtp(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Enter the code we sent you.';
    }
    if (trimmed.length < 6) {
      return 'Enter the 6-digit code.';
    }
    return null;
  }

  Future<void> _handleVerify() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final ZetraProfile profile = await widget.authService.verifyOtp(
        token: _otpController.text.trim(),
        authEmailOverride: widget.authEmail,
      );

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ZetraProfileHomeScreen(profile: profile),
        ),
        (route) => false,
      );
    } on ZetraAuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _handleResend() async {
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      await widget.authService.resendOtp();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent.')),
      );
    } on ZetraAuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not resend code. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.mark_email_read_rounded,
                    size: 64,
                    color: Color(0xFF00843D),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Enter verification code',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a code to ${widget.zetramail}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    enabled: !_isVerifying,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, letterSpacing: 8),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '------',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: _validateOtp,
                    onFieldSubmitted: (_) => _handleVerify(),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isVerifying ? null : _handleVerify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00843D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isVerifying
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Verify',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _isResending ? null : _handleResend,
                    child: _isResending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Resend code'),
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

// ============================================================
// PROFILE / HOME SCREEN
// ============================================================

class ZetraProfileHomeScreen extends StatelessWidget {
  final ZetraProfile profile;

  const ZetraProfileHomeScreen({super.key, required this.profile});

  Future<void> _handleSignOut(BuildContext context) async {
    await ZetraAuthService().signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ZetraLoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      appBar: AppBar(
        title: const Text('NaijaLearn'),
        backgroundColor: const Color(0xFF00843D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _handleSignOut(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: const Color(0xFF00843D).withOpacity(0.1),
                backgroundImage: profile.avatarUrl != null
                    ? NetworkImage(profile.avatarUrl!)
                    : null,
                child: profile.avatarUrl == null
                    ? Text(
                        profile.username.isNotEmpty
                            ? profile.username[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00843D),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                profile.username,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    profile.zetramail,
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  if (profile.verified) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified, size: 16, color: Color(0xFF00843D)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
