// lib/wallet_display.dart
//
// Balance-fetching logic, Zetra ID lookup, and every Supabase/ZetraPay
// call are unchanged from before.
//
// What's new here isn't visual — it's that this screen now knows about
// the rest of the Cent-purchase economy instead of living in isolation:
//   1. Returning from BuyCentScreen always triggers a fresh balance pull,
//      so an approved purchase shows up without the user having to
//      remember to pull-to-refresh.
//   2. If the user has an order sitting in awaiting_payment,
//      awaiting_receipt, or pending_verification, that's surfaced right
//      on the wallet — so "where did my money go" never has to be a
//      WhatsApp message. Tapping it drops them back into BuyCentScreen
//      at the right step (BuyCentScreen already resumes from the saved
//      order_reference on its own).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'app_enhancements.dart' show ShinyCard, GradientButton, GradientHeader;
import 'app_theme.dart' show AppTheme, AppColors;
import 'zetra_pay.dart';
import 'buy_cent.dart';

class WalletDisplayScreen extends StatefulWidget {
  const WalletDisplayScreen({super.key});

  @override
  State<WalletDisplayScreen> createState() => _WalletDisplayScreenState();
}

class _WalletDisplayScreenState extends State<WalletDisplayScreen> {
  int? _rawBalance; // raw Cent, source of truth
  String? _zetraId;
  bool _loading = true;
  String? _error;

  // Most recent non-final order for this user, if any (awaiting_payment,
  // awaiting_receipt, or pending_verification). Null once verified/rejected
  // or if the user has never started a purchase.
  Map<String, dynamic>? _openOrder;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final balance = await ZetraPay.getAppCurrencyBalance(ZetraPay.naijaLearnAppId);

      final userId = Supabase.instance.client.auth.currentUser?.id;
      String? zetraId;
      Map<String, dynamic>? openOrder;

      if (userId != null) {
        final profileRow =
            await Supabase.instance.client.from('profiles').select('zetra_id').eq('id', userId).maybeSingle();
        zetraId = profileRow?['zetra_id'] as String?;

        final orderRows = await Supabase.instance.client
            .from('payment_orders')
            .select()
            .inFilter('status', ['awaiting_payment', 'awaiting_receipt', 'pending_verification'])
            .order('created_at', ascending: false)
            .limit(1);

        if (orderRows is List && orderRows.isNotEmpty) {
          openOrder = Map<String, dynamic>.from(orderRows.first as Map);
        }
      }

      setState(() {
        _rawBalance = balance.round();
        _zetraId = zetraId;
        _openOrder = openOrder;
      });
    } catch (e) {
      setState(() => _error = 'Could not load your wallet. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _cp => (_rawBalance ?? 0) ~/ 1000;
  int get _cent => (_rawBalance ?? 0) % 1000;

  String _formatCp(int cp) {
    return cp.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  }

  void _copyZetraId() {
    if (_zetraId == null) return;
    Clipboard.setData(ClipboardData(text: _zetraId!));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zetra ID copied'), duration: Duration(seconds: 2)));
  }

  Future<void> _openBuyCent() async {
    // Awaiting the push means we reload the instant the user comes back —
    // whether they finished a purchase, cancelled it, or just backed out.
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BuyCentScreen()));
    if (mounted) _load();
  }

  ({String label, String detail, IconData icon}) _openOrderCopy(String status) {
    switch (status) {
      case 'awaiting_payment':
        return (label: 'Payment pending', detail: 'You started a purchase — tap to finish transferring and upload your receipt.', icon: Icons.hourglass_empty_rounded);
      case 'awaiting_receipt':
        return (label: 'Receipt needed', detail: 'An admin asked for a clearer receipt on your last upload — tap to resubmit.', icon: Icons.replay_rounded);
      case 'pending_verification':
      default:
        return (label: 'Verification pending', detail: 'Your receipt is with an admin — Cent will appear here once it\'s confirmed.', icon: Icons.hourglass_top_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Column(
                  children: [
                    const GradientHeader(title: '💳 My Wallet'),
                    Expanded(child: _ErrorState(message: _error!, onRetry: _load)),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      const SliverToBoxAdapter(child: GradientHeader(title: '💳 My Wallet', subtitle: 'Your NaijaLearn balance')),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            // ================================================
                            // BALANCE CARD
                            // ================================================
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(26),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                gradient: AppTheme.heroGradient(context),
                                boxShadow: [BoxShadow(color: scheme.primary.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 12))],
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    right: -20,
                                    top: -30,
                                    child: Container(width: 120, height: 120, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.07))),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                                            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 18),
                                          ),
                                          const SizedBox(width: 10),
                                          Text('NaijaLearn Balance', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _rawBalance != null ? '${_formatCp(_cp)} CP' : '—',
                                        style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                                      ),
                                      if (_rawBalance != null && _cent > 0) ...[
                                        const SizedBox(height: 2),
                                        Text('+ $_cent Cent', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.85))),
                                      ],
                                      const SizedBox(height: 18),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.badge_outlined, size: 16, color: Colors.white70),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _zetraId ?? 'Loading...',
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (_zetraId != null)
                                              GestureDetector(onTap: _copyZetraId, child: const Icon(Icons.copy_rounded, size: 16, color: Colors.white70)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          const Icon(Icons.verified_rounded, size: 14, color: Colors.white70),
                                          const SizedBox(width: 4),
                                          Text('Powered by ZTC', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // ================================================
                            // OPEN ORDER BANNER — new. Only shown if there's
                            // an in-flight purchase somewhere in the pipeline.
                            // ================================================
                            if (_openOrder != null) ...[
                              const SizedBox(height: 16),
                              _buildOpenOrderBanner(context, _openOrder!),
                            ],

                            const SizedBox(height: 20),

                            // ================================================
                            // BUY CENT/CP
                            // ================================================
                            Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _openBuyCent,
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    gradient: AppTheme.heroGradient(context),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [BoxShadow(color: scheme.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(14)),
                                        child: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 26),
                                      ),
                                      const SizedBox(width: 16),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Buy Cent or CP', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                                            SizedBox(height: 4),
                                            Text('Transfer directly to our account', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_rounded, color: Colors.white70),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // ================================================
                            // FUND VIA ZTC
                            // ================================================
                            ShinyCard(
                              tint: AppColors.info,
                              padding: const EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: AppColors.info.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                                    child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.info),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Fund via ZTC', style: TextStyle(fontWeight: FontWeight.w600)),
                                        Text('Open ZTC → Send to Apps → NaijaLearn', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),
                            Text(
                              "Your balance updates automatically once a transfer completes. Pull down to refresh if you don't see it right away.",
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildOpenOrderBanner(BuildContext context, Map<String, dynamic> order) {
    final scheme = Theme.of(context).colorScheme;
    final status = order['status'] as String;
    final cent = order['cent_amount'] as int;
    final copy = _openOrderCopy(status);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openBuyCent,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.10),
            border: Border.all(color: Colors.amber.withOpacity(0.45), width: 1.4),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(copy.icon, color: Colors.amber.shade900, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${copy.label} · $cent Cent', style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 13.5)),
                    const SizedBox(height: 4),
                    Text(copy.detail, style: TextStyle(color: Colors.amber.shade900.withOpacity(0.9), fontSize: 12.5, height: 1.4)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.amber.shade900),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.error.withOpacity(0.12), shape: BoxShape.circle),
              child: const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.error),
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            GradientButton(label: 'Retry', icon: Icons.refresh_rounded, onPressed: onRetry, height: 46),
          ],
        ),
      ),
    );
  }
}
