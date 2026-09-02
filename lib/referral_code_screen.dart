// lib/referral_code_screen.dart
//
// Mandatory referral code entry — shown once, on a user's very first
// login, before they reach Home. Every signup gets attributed to a
// code: either a real ad creator's code, or the always-active 'DIRECT'
// fallback for organic users who weren't referred by anyone.
//
// Attribution is permanent once set — the RPC is idempotent, so this
// screen is always safe to re-invoke; it just returns the existing
// attribution instead of overwriting it.
//
// Device identification: rather than adding a new plugin dependency,
// this generates a random UUID once and persists it in
// SharedPreferences — stable across app restarts on the same device,
// which is enough for the fraud-flagging signal server-side.
//
// DEBUG INSTRUMENTATION (temporary): _submit() now logs the full
// exception type and stack trace via debugPrint whenever submitCode()
// throws, so the "Null check operator used on a null value" crash can
// be traced to its exact origin (client-side Dart vs. the Supabase RPC
// response itself). Remove the debugPrint block once the root cause is
// found and fixed.

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// =========================================================================
/// DEVICE ID — lightweight, persisted, no new plugin required.
/// =========================================================================

class DeviceIdService {
  DeviceIdService._();
  static final DeviceIdService instance = DeviceIdService._();

  static const String _prefsKey = 'nl_device_id';
  String? _cached;

  Future<String> getDeviceId() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKey);
    if (id == null) {
      id = _generateId();
      await prefs.setString(_prefsKey, id);
    }
    _cached = id;
    return id;
  }

  String _generateId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// =========================================================================
/// SERVICE
/// =========================================================================

class ReferralService {
  ReferralService._();
  static final ReferralService instance = ReferralService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Null if this user has no attribution yet (first login) — used to
  /// decide whether to show the mandatory screen at all.
  Future<Map<String, dynamic>?> getMyAttribution() async {
    final result = await _client.rpc('get_my_referral_attribution');
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> submitCode(String code) async {
    final deviceId = await DeviceIdService.instance.getDeviceId();
    debugPrint('[Referral] submitCode() calling RPC with p_code="${code.trim()}", p_device_id="$deviceId"');
    final result = await _client.rpc('submit_referral_code', params: {
      'p_code': code.trim(),
      'p_device_id': deviceId,
    });
    debugPrint('[Referral] submit_referral_code RPC raw result: $result (type: ${result.runtimeType})');
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> adminGetStats() async {
    final rows = await _client.rpc('admin_get_referral_stats');
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }
}

/// =========================================================================
/// MANDATORY ENTRY SCREEN
/// =========================================================================
///
/// Usage: after OTP verification succeeds, before navigating to the
/// normal onboarding/home destination, call:
///
///   final attribution = await ReferralService.instance.getMyAttribution();
///   final destination = attribution == null
///       ? ReferralCodeEntryScreen(onDone: () => /* navigate to your normal destination */)
///       : /* your normal destination directly */;
///
/// See the integration note at the bottom of this file for the exact
/// main.dart wiring.

class ReferralCodeEntryScreen extends StatefulWidget {
  /// Called once a code has been successfully submitted (or was already
  /// on file) — the caller decides where to navigate next.
  final VoidCallback onDone;
  const ReferralCodeEntryScreen({super.key, required this.onDone});

  @override
  State<ReferralCodeEntryScreen> createState() => _ReferralCodeEntryScreenState();
}

class _ReferralCodeEntryScreenState extends State<ReferralCodeEntryScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_codeController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a code — use DIRECT if no one referred you.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ReferralService.instance.submitCode(_codeController.text);
      if (!mounted) return;
      widget.onDone();
    } catch (e, stackTrace) {
      // DEBUG: full type + stack trace so the exact throwing line can be
      // identified. Check `flutter logs` / your device's logcat output
      // for a block starting with "[Referral] EXCEPTION".
      debugPrint('[Referral] EXCEPTION during submitCode(): '
          'runtimeType=${e.runtimeType}, toString="$e"');
      debugPrint('[Referral] STACK TRACE:\n$stackTrace');

      if (!mounted) return;
      final message = e.toString().replaceFirst('PostgrestException(message: ', '').split(',').first;
      setState(() => _error = message.isNotEmpty ? message : 'Invalid code. Please check and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _useDirect() {
    _codeController.text = 'DIRECT';
    _submit();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // No back button — this is a mandatory, one-time step.
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
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
                  decoration: InputDecoration(
                    hintText: 'ENTER CODE',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Continue'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _useDirect,
                  child: const Text("I found this on my own — no referral"),
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
/// ADMIN — REFERRAL STATS (read-only)
/// =========================================================================

class AdminReferralStatsScreen extends StatefulWidget {
  const AdminReferralStatsScreen({super.key});

  @override
  State<AdminReferralStatsScreen> createState() => _AdminReferralStatsScreenState();
}

class _AdminReferralStatsScreenState extends State<AdminReferralStatsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

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
            if (snapshot.hasError) {
              return ListView(children: [
                const SizedBox(height: 60),
                Center(child: Text('Could not load stats.', style: TextStyle(color: scheme.error))),
              ]);
            }
            final rows = snapshot.data ?? [];
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = rows[i];
                final active = r['active'] as bool? ?? true;
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
                              Text(r['code'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              if (!active) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(6)),
                                  child: Text('inactive', style: TextStyle(fontSize: 10, color: scheme.error)),
                                ),
                              ],
                            ]),
                            Text(
                              [r['creator_name'], r['country']].where((e) => e != null && e != '').join(' · '),
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Text('${r['total_referrals']}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: scheme.primary)),
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
