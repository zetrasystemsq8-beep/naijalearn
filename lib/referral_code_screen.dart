// lib/referral_code_screen.dart
//
// Mandatory referral code entry — shown once, on a user's very first
// login, before they reach Home.
//
// HARDENED VERSION v2: every operation is wrapped so it can NEVER
// throw past this screen, AND every Supabase call has a hard timeout
// so it can NEVER hang forever either. If anything fails or times
// out, the user is let through anyway after a brief message.
// Referral tracking is a nice-to-have; it must never lock a real
// student out of the app.
//
// What changed vs the old version:
//   1. Every `.rpc(...)` call now has `.timeout(...)` — no more
//      infinite spinners if the network stalls or a request never
//      gets a response.
//   2. submitCode() now returns a small result object (not just a
//      bool) so the UI can show the user a clear, honest notice:
//      "Saved!" / "Already saved" / "Continuing without saving" —
//      instead of silently proceeding with no feedback.
//   3. The success/notice message is shown for a brief moment
//      before navigating away, so the user actually sees it instead
//      of it flashing and disappearing behind a page transition.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How long we'll wait on any single Supabase call from this screen
/// before giving up and treating it as failed (fail-open).
const _kRpcTimeout = Duration(seconds: 8);

/// How long a success/notice message stays on screen before we
/// navigate away, so the user actually gets to read it.
const _kNoticeDisplayDuration = Duration(milliseconds: 900);

/// =========================================================================
/// DEVICE ID — every step wrapped; returns a fallback id instead of
/// ever throwing, even if SharedPreferences itself is unavailable.
/// =========================================================================

class DeviceIdService {
  DeviceIdService._();
  static final DeviceIdService instance = DeviceIdService._();

  static const String _prefsKey = 'nl_device_id';
  String? _cached;

  Future<String> getDeviceId() async {
    if (_cached != null) return _cached!;
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(_kRpcTimeout);
      var id = prefs.getString(_prefsKey);
      if (id == null || id.isEmpty) {
        id = _generateId();
        await prefs.setString(_prefsKey, id);
      }
      _cached = id;
      return id;
    } catch (e) {
      debugPrint('[DeviceId] Failed to read/write SharedPreferences (non-fatal): $e');
      // Fallback: a fresh random id for this session only. Fine — this
      // is only used for a soft fraud-signal on the server, never for
      // anything that blocks the user.
      final fallback = _generateId();
      _cached = fallback;
      return fallback;
    }
  }

  String _generateId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// =========================================================================
/// RESULT TYPE — lets the UI show a specific, honest notice instead of
/// a generic success/fail boolean.
/// =========================================================================

enum SubmitReferralOutcome {
  /// Saved for the first time just now.
  savedNow,

  /// This user already had a code on file (e.g. re-entered the screen
  /// after already submitting) — not an error, just informational.
  alreadySaved,

  /// The code doesn't exist / isn't active. Only meaningful for a
  /// typed code — DIRECT always exists, so this shouldn't happen for it.
  invalidCode,

  /// Anything else — network issue, timeout, Supabase error. We still
  /// let the user through; this is just so the UI can be honest about
  /// what happened instead of pretending it succeeded.
  failedNonFatal,
}

class SubmitReferralResult {
  final SubmitReferralOutcome outcome;
  const SubmitReferralResult(this.outcome);

  String get noticeMessage {
    switch (outcome) {
      case SubmitReferralOutcome.savedNow:
        return 'Saved! Welcome to NaijaLearn.';
      case SubmitReferralOutcome.alreadySaved:
        return "You're all set — continuing.";
      case SubmitReferralOutcome.invalidCode:
        return "That code wasn't recognized — continuing anyway.";
      case SubmitReferralOutcome.failedNonFatal:
        return 'Could not save your referral code — continuing anyway.';
    }
  }

  bool get isNotice =>
      outcome == SubmitReferralOutcome.savedNow ||
      outcome == SubmitReferralOutcome.alreadySaved;
}

/// =========================================================================
/// SERVICE — every method catches internally and has a timeout;
/// nothing here ever throws to its caller, and nothing here can hang
/// forever.
/// =========================================================================

class ReferralService {
  ReferralService._();
  static final ReferralService instance = ReferralService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Null if this user has no attribution yet OR if the check itself
  /// failed/timed out for any reason — both cases are treated the same
  /// by the caller, which fails open regardless.
  Future<Map<String, dynamic>?> getMyAttribution() async {
    try {
      final result = await _client
          .rpc('get_my_referral_attribution')
          .timeout(_kRpcTimeout);
      if (result == null) return null;
      if (result is! Map) return null;
      return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint('[Referral] getMyAttribution failed (non-fatal): $e');
      return null;
    }
  }

  /// Never throws, never hangs. Always returns within _kRpcTimeout.
  Future<SubmitReferralResult> submitCode(String code) async {
    try {
      final deviceId = await DeviceIdService.instance.getDeviceId();
      final result = await _client.rpc('submit_referral_code', params: {
        'p_code': code.trim(),
        'p_device_id': deviceId,
      }).timeout(_kRpcTimeout);

      debugPrint('[Referral] submitCode succeeded: $result');

      final alreadyAttributed =
          result is Map && result['already_attributed'] == true;

      return SubmitReferralResult(
        alreadyAttributed
            ? SubmitReferralOutcome.alreadySaved
            : SubmitReferralOutcome.savedNow,
      );
    } on PostgrestException catch (e) {
      debugPrint('[Referral] submitCode Postgrest error (non-fatal): ${e.message}');
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid referral code')) {
        return const SubmitReferralResult(SubmitReferralOutcome.invalidCode);
      }
      return const SubmitReferralResult(SubmitReferralOutcome.failedNonFatal);
    } on TimeoutException catch (e) {
      debugPrint('[Referral] submitCode timed out (non-fatal): $e');
      return const SubmitReferralResult(SubmitReferralOutcome.failedNonFatal);
    } catch (e) {
      debugPrint('[Referral] submitCode failed (non-fatal): $e');
      return const SubmitReferralResult(SubmitReferralOutcome.failedNonFatal);
    }
  }

  Future<List<Map<String, dynamic>>> adminGetStats() async {
    try {
      final rows = await _client
          .rpc('admin_get_referral_stats')
          .timeout(_kRpcTimeout);
      if (rows is! List) return [];
      return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } catch (e) {
      debugPrint('[Referral] adminGetStats failed: $e');
      return [];
    }
  }

  /// Returns null on success, an error message string on failure —
  /// used by the admin approve/deactivate toggle.
  Future<String?> adminSetCodeActive(String code, bool active) async {
    try {
      await _client.rpc('admin_set_referral_code_active', params: {
        'p_code': code,
        'p_active': active,
      }).timeout(_kRpcTimeout);
      return null;
    } on TimeoutException {
      return 'Request timed out — please try again.';
    } catch (e) {
      return e.toString();
    }
  }
}

/// =========================================================================
/// MANDATORY ENTRY SCREEN
/// =========================================================================
///
/// Usage (in VerifyOtpScreen._verifyCode, after OTP succeeds):
///
///   final attribution = await ReferralService.instance.getMyAttribution();
///   if (attribution == null) {
///     // first login OR the check failed — either way, show this screen
///     Navigator.of(context).pushAndRemoveUntil(
///       MaterialPageRoute(builder: (_) => ReferralCodeEntryScreen(
///         onDone: () => Navigator.of(context).pushAndRemoveUntil(
///           MaterialPageRoute(builder: (_) => NaiOnboardingGate(profile: profile)),
///           (route) => false,
///         ),
///       )),
///       (route) => false,
///     );
///   } else {
///     Navigator.of(context).pushAndRemoveUntil(
///       MaterialPageRoute(builder: (_) => NaiOnboardingGate(profile: profile)),
///       (route) => false,
///     );
///   }

class ReferralCodeEntryScreen extends StatefulWidget {
  final VoidCallback onDone;
  const ReferralCodeEntryScreen({super.key, required this.onDone});

  @override
  State<ReferralCodeEntryScreen> createState() => _ReferralCodeEntryScreenState();
}

class _ReferralCodeEntryScreenState extends State<ReferralCodeEntryScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  bool _proceeded = false; // guards against double-navigation

  /// The ONLY exit from this screen. Guaranteed to fire exactly once,
  /// no matter what happened — success, failure, timeout, anything.
  void _proceed() {
    if (_proceeded) return;
    _proceeded = true;
    if (!mounted) return;
    widget.onDone();
  }

  Future<void> _submit([String? forcedCode]) async {
    if (_busy || _proceeded) return;

    final code = (forcedCode ?? _codeController.text).trim();
    if (code.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a code — or tap "I found this on my own".')),
        );
      }
      return;
    }

    setState(() => _busy = true);

    // submitCode() internally catches everything, has a hard timeout,
    // and always returns within _kRpcTimeout — there is nothing left
    // here that can hang or throw. Even so, wrapped one more time as
    // a final safety net.
    SubmitReferralResult result =
        const SubmitReferralResult(SubmitReferralOutcome.failedNonFatal);
    try {
      result = await ReferralService.instance.submitCode(code);
    } catch (e) {
      debugPrint('[Referral] Unexpected error in _submit (non-fatal): $e');
    }

    if (!mounted) return;

    // Always show the user exactly what happened — success, "already
    // done", or a soft failure — so they're never left guessing why
    // the screen moved on.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.noticeMessage),
        backgroundColor: result.isNotice ? Colors.green.shade700 : null,
        duration: _kNoticeDisplayDuration + const Duration(milliseconds: 600),
      ),
    );

    // Give the user a beat to actually read the notice before we
    // navigate away — otherwise it flashes and vanishes behind the
    // page transition.
    await Future.delayed(_kNoticeDisplayDuration);

    if (!mounted) return;

    // Proceed regardless of outcome — this screen's only job is a
    // best-effort attempt, never a hard gate.
    _proceed();
  }

  void _useDirect() => _submit('DIRECT');

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(22)),
                  child: Icon(Icons.card_giftcard_rounded, size: 40, color: scheme.primary),
                ),
                const SizedBox(height: 24),
                Text(
                  'Who told you about NaijaLearn?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter a referral code to continue. If no one referred you, tap "I found this on my own" below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _codeController,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
                  decoration: InputDecoration(
                    hintText: 'ENTER CODE',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy ? null : () => _submit(),
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Continue'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _useDirect,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("I found this on my own — no referral"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// ADMIN — REFERRAL STATS with Approve/Deactivate toggle
/// =========================================================================

class AdminReferralStatsScreen extends StatefulWidget {
  const AdminReferralStatsScreen({super.key});

  @override
  State<AdminReferralStatsScreen> createState() => _AdminReferralStatsScreenState();
}

class _AdminReferralStatsScreenState extends State<AdminReferralStatsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  final Set<String> _busyCodes = {};

  @override
  void initState() {
    super.initState();
    _future = ReferralService.instance.adminGetStats();
  }

  Future<void> _refresh() async {
    final next = ReferralService.instance.adminGetStats();
    setState(() => _future = next);
    await next;
  }

  Future<void> _toggleActive(String code, bool currentlyActive) async {
    setState(() => _busyCodes.add(code));
    final error = await ReferralService.instance.adminSetCodeActive(code, !currentlyActive);
    if (!mounted) return;
    setState(() => _busyCodes.remove(code));
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Referral Stats')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 60),
                Center(child: Text('No referral codes yet.', style: TextStyle(color: scheme.onSurfaceVariant))),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = rows[i];
                final code = r['code'] as String? ?? '';
                final active = r['active'] as bool? ?? true;
                final busy = _busyCodes.contains(code);
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: !active ? Border.all(color: scheme.outlineVariant) : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(code, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: active ? Colors.green.withOpacity(0.15) : scheme.errorContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  active ? 'active' : 'pending',
                                  style: TextStyle(fontSize: 10, color: active ? Colors.green.shade800 : scheme.error),
                                ),
                              ),
                            ]),
                            Text(
                              [r['creator_name'], r['country']].where((e) => e != null && e != '').join(' · '),
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Text('${r['total_referrals'] ?? 0}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: scheme.primary)),
                      const SizedBox(width: 10),
                      if (code != 'DIRECT')
                        busy
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : IconButton(
                                icon: Icon(
                                  active ? Icons.pause_circle_outline_rounded : Icons.check_circle_outline_rounded,
                                  color: active ? Colors.orange : Colors.green,
                                ),
                                tooltip: active ? 'Deactivate' : 'Approve',
                                onPressed: () => _toggleActive(code, active),
                              ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
