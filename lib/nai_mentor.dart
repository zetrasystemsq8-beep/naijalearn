// lib/nai_mentor.dart
//
// NAI Mentor — the interview/Blueprint chat screen inside NaijaLearn.
// Talks to the 'nai-interview' Supabase Edge Function. Only reachable by
// signed-in Zetra users (guests never see this entry point).
//
// Pricing (paid in NaijaLearn's app currency — Cent, via ZetraPay):
//   - 1 message  = 1 Cent
//   - 15 messages = 10 Cent
//   - Unlimited for 24 hours = 1000 Cent (= 1 CP)
// Credits/day-pass are tracked server-side in nai_message_wallet via
// security-definer RPCs, so the client can never grant itself free
// messages — only nai_grant_message_credits/nai_grant_day_pass can add
// them, and those only run after a real ZetraPay.spendAppCurrency call.
//
// NaiOnboardingGate is a one-time interstitial shown right after a NEW
// account verifies (accounts created after _naiRolloutCutoff only —
// existing users are never shown this). The first onboarding interview
// is free — it does NOT consume a credit — since it happens before the
// user has had any chance to buy any.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show ZetraProfile, HomeScreen;
import 'zetra_pay.dart';

class NaiBlueprintService {
  NaiBlueprintService._();
  static final NaiBlueprintService instance = NaiBlueprintService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<Map<String, dynamic>?> getActiveBlueprint(String type) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return await _client
        .from('blueprints')
        .select()
        .eq('user_id', user.id)
        .eq('blueprint_type', type)
        .eq('status', 'active')
        .maybeSingle();
  }

  Future<Map<String, dynamic>> sendInterviewMessage({
    String? interviewId,
    required String blueprintType,
    String? message,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in.');
    }
    final res = await _client.functions.invoke('nai-interview', body: {
      'user_id': user.id,
      'blueprint_type': blueprintType,
      'requesting_app': 'naijalearn',
      'interview_id': interviewId,
      'message': message,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}

/// Handles the paid side: consuming a credit before each message, and
/// purchasing more (single message / 15-pack / day pass).
class NaiWallet {
  NaiWallet._();
  static SupabaseClient get _client => Supabase.instance.client;

  static const int singleMessagePriceCent = 1;
  static const int packOf15PriceCent = 10;
  static const int packOf15Credits = 15;
  static const int dayPassPriceCent = 1000; // = 1 CP

  /// Tries to consume one message credit (or use an active day pass).
  /// Returns true if the message may proceed.
  static Future<bool> tryConsumeCredit() async {
    final result = await _client.rpc('nai_consume_message_credit');
    return result == true;
  }

  /// Buys a single message: spends Cent, then grants exactly 1 credit.
  /// Returns null on success, or an error message.
  static Future<String?> buySingleMessage() async {
    final err = await ZetraPay.spendAppCurrency(
      appId: ZetraPay.naijaLearnAppId,
      unitAmount: singleMessagePriceCent.toDouble(),
    );
    if (err != null) return err;
    await _client.rpc('nai_grant_message_credits', params: {'p_credits': 1});
    return null;
  }

  static Future<String?> buyFifteenPack() async {
    final err = await ZetraPay.spendAppCurrency(
      appId: ZetraPay.naijaLearnAppId,
      unitAmount: packOf15PriceCent.toDouble(),
    );
    if (err != null) return err;
    await _client.rpc('nai_grant_message_credits', params: {'p_credits': packOf15Credits});
    return null;
  }

  static Future<String?> buyDayPass() async {
    final err = await ZetraPay.spendAppCurrency(
      appId: ZetraPay.naijaLearnAppId,
      unitAmount: dayPassPriceCent.toDouble(),
    );
    if (err != null) return err;
    await _client.rpc('nai_grant_day_pass');
    return null;
  }
}

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  ChatMessage({required this.role, required this.content});
}

class NaiMentorScreen extends StatefulWidget {
  final String blueprintType; // 'academic', 'career', etc.
  final VoidCallback? onDone; // if set, shows a "Continue" button (onboarding mode)
  final bool freeMode; // true during the one-time onboarding interview — no charge
  const NaiMentorScreen({
    super.key,
    this.blueprintType = 'academic',
    this.onDone,
    this.freeMode = false,
  });

  @override
  State<NaiMentorScreen> createState() => _NaiMentorScreenState();
}

class _NaiMentorScreenState extends State<NaiMentorScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  String? _interviewId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // The opening message never costs a credit — only messages the user
    // actually types and sends do.
    _send(null, chargeable: false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showPaywall() async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Keep chatting with NAI',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                "You're out of messages. Top up to continue.",
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              _PaywallOption(
                title: '1 Message',
                price: '1¢',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final err = await NaiWallet.buySingleMessage();
                  if (err != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                },
              ),
              const SizedBox(height: 10),
              _PaywallOption(
                title: '15 Messages',
                price: '10¢',
                subtitle: 'Best value',
                highlight: true,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final err = await NaiWallet.buyFifteenPack();
                  if (err != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                },
              ),
              const SizedBox(height: 10),
              _PaywallOption(
                title: 'Unlimited Today',
                price: '1 CP',
                subtitle: '24 hours, no limits',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final err = await NaiWallet.buyDayPass();
                  if (err != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _send(String? userText, {bool chargeable = true}) async {
    if (userText != null && userText.trim().isEmpty) return;

    if (chargeable && !widget.freeMode) {
      final allowed = await NaiWallet.tryConsumeCredit();
      if (!allowed) {
        await _showPaywall();
        return;
      }
    }

    setState(() {
      _sending = true;
      if (userText != null) {
        _messages.add(ChatMessage(role: 'user', content: userText));
      }
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final result = await NaiBlueprintService.instance.sendInterviewMessage(
        interviewId: _interviewId,
        blueprintType: widget.blueprintType,
        message: userText,
      );
      if (!mounted) return;
      setState(() {
        _interviewId = result['interview_id']?.toString();
        _messages.add(ChatMessage(role: 'assistant', content: result['reply'] as String? ?? '...'));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(role: 'assistant', content: 'Sorry, something went wrong. Please try again.'));
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NAI Mentor'),
        actions: [
          if (widget.onDone != null)
            TextButton(
              onPressed: widget.onDone,
              child: const Text('Continue to NaijaLearn'),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final msg = _messages[index];
                final isUser = msg.role == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      msg.content,
                      style: TextStyle(color: isUser ? scheme.onPrimary : scheme.onSurface, height: 1.4),
                    ),
                  ),
                );
              },
            ),
          ),
          if (!widget.freeMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '1¢ per message · 15 for 10¢ · 1 CP for unlimited today',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) => _send(v),
                      decoration: InputDecoration(
                        hintText: 'Type your answer...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(_controller.text),
                    icon: const Icon(Icons.send_rounded),
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

class _PaywallOption extends StatelessWidget {
  final String title;
  final String price;
  final String? subtitle;
  final bool highlight;
  final VoidCallback onTap;
  const _PaywallOption({
    required this.title,
    required this.price,
    this.subtitle,
    this.highlight = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: highlight ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    if (subtitle != null)
                      Text(subtitle!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Text(price, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One-time onboarding gate shown right after signup verification.
/// Only shown to accounts created AFTER _naiRolloutCutoff — existing
/// users never see this, per product decision. Also skipped if the
/// user already has an Academic Blueprint, or already dismissed this
/// once before (tracked via Supabase Auth user metadata). The interview
/// here runs in freeMode — it never charges Cent.
class NaiOnboardingGate extends StatefulWidget {
  final ZetraProfile profile;
  const NaiOnboardingGate({super.key, required this.profile});

  @override
  State<NaiOnboardingGate> createState() => _NaiOnboardingGateState();
}

class _NaiOnboardingGateState extends State<NaiOnboardingGate> {
  static final DateTime _naiRolloutCutoff = DateTime.parse('2026-07-31T00:00:00Z');
  static const String _onboardingSeenKey = 'nl_nai_onboarding_seen';

  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final user = Supabase.instance.client.auth.currentUser;
    final createdAtStr = user?.createdAt;
    final isNewAccount = createdAtStr != null &&
        (DateTime.tryParse(createdAtStr)?.isAfter(_naiRolloutCutoff) ?? false);
    final alreadySeen = user?.userMetadata?[_onboardingSeenKey] == true;

    if (!isNewAccount || alreadySeen) {
      _goHome();
      return;
    }

    final blueprint = await NaiBlueprintService.instance.getActiveBlueprint('academic');
    if (blueprint != null) {
      _goHome();
      return;
    }

    if (mounted) setState(() => _checking = false);
  }

  Future<void> _markSeenAndContinue() async {
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {_onboardingSeenKey: true}),
      );
    } catch (_) {}
    _goHome();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(profile: widget.profile)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return NaiMentorScreen(blueprintType: 'academic', onDone: _markSeenAndContinue, freeMode: true);
  }
}
