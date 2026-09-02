// lib/signup_screen.dart
//
// Self-serve NaijaLearn-only account creation. No pre-existing Zetra
// account required, no OTP step. Under the hood this still creates a
// real Supabase Auth user (via a generated internal alias email) and a
// matching `profiles` row, so everything built on top of auth.uid() —
// Buy Cent, Admin Panel, app_currency_balances — keeps working
// unchanged. It does NOT create a `wallets` row, so "Fund via ZTC" on
// the Wallet screen won't work for these accounts (they're not part of
// the wider Zetra ecosystem) — Buy Cent bank transfer works fine.
//
// REFERRAL ATTRIBUTION: immediately after account creation succeeds,
// checks ReferralService.instance.getMyAttribution(). Since this is
// always a brand-new signup, attribution will always be null here — so
// every self-signup user is routed through ReferralCodeEntryScreen once,
// exactly like the ZetraMail/OTP signup path in main.dart. Existing
// users never hit this screen again (it's signup-only), so there's no
// risk of re-prompting anyone who already has a code on file.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart' show AuthService, ZetraProfile, ZetraAuthException, HomeScreen;
import 'referral_code_screen.dart';

// Must match the domain used in AuthService.loginWithUsername (main.dart).
const String kNaijaLearnAliasDomain = 'nlstudent.internal';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateUsername(String? value) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) return 'Please choose a username';
    if (username.contains('@')) return "Username can't contain @";
    final validPattern = RegExp(r'^[a-zA-Z0-9_]{3,20}$');
    if (!validPattern.hasMatch(username)) {
      return '3-20 characters — letters, numbers, underscore only';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Please enter a password';
    if (password.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final profile = await AuthService.instance.signUpWithUsername(
        username: username,
        password: password,
      );
      if (!mounted) return;

      // New account — check referral attribution once, before ever
      // landing in HomeScreen. This mirrors the ZetraMail/OTP signup
      // flow in main.dart (VerifyOtpScreen), so username-only signups
      // get the exact same one-time referral prompt.
      final attribution = await ReferralService.instance.getMyAttribution();
      if (!mounted) return;

      if (attribution == null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ReferralCodeEntryScreen(
              onDone: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => HomeScreen(profile: profile)),
                (route) => false,
              ),
            ),
          ),
          (route) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomeScreen(profile: profile)),
          (route) => false,
        );
      }
    } on ZetraAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not create your account. Please try again.');
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
          // Vibrant multi-color gradient backdrop — "shiny lovable" look.
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
            top: 120,
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
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
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
                              child: Icon(Icons.person_add_alt_1_rounded, size: 50, color: scheme.primary),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Create your NaijaLearn account',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Just a username and password — no email needed',
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
                                  controller: _usernameController,
                                  textInputAction: TextInputAction.next,
                                  validator: _validateUsername,
                                  decoration: InputDecoration(
                                    labelText: 'Username',
                                    filled: true,
                                    fillColor: scheme.surfaceContainerHighest.withOpacity(0.5),
                                    prefixIcon: Icon(Icons.person_outline_rounded, color: scheme.primary),
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
                                  textInputAction: TextInputAction.done,
                                  validator: _validatePassword,
                                  onFieldSubmitted: (_) => _createAccount(),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          backgroundColor: Colors.white,
                          foregroundColor: scheme.primary,
                          elevation: 6,
                          shadowColor: Colors.black.withOpacity(0.3),
                        ),
                        onPressed: _loading ? null : _createAccount,
                        child: _loading
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: scheme.primary),
                              )
                            : const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
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
