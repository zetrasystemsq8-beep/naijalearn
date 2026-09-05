// lib/wallet_display.dart
//
// ⚡ REDESIGNED VERSION — visuals only. Balance-fetching logic, Zetra ID
// lookup, and every Supabase/ZetraPay call below are 100% unchanged —
// copy this in as a straight replacement, nothing breaks.
//
// Uses the shared design system from app_enhancements.dart (ShinyCard,
// GradientButton, GradientHeader — which includes its own back button)
// and AppTheme.heroGradient(context) from app_theme.dart, so the
// balance card always matches your real brand color in both light and
// dark mode instead of a generic scheme.primary flat fill.

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
      if (userId != null) {
        final row = await Supabase.instance.client.from('profiles').select('zetra_id').eq('id', userId).maybeSingle();
        zetraId = row?['zetra_id'] as String?;
      }

      setState(() {
        _rawBalance = balance.round();
        _zetraId = zetraId;
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
                            // BALANCE CARD — hero treatment, brand gradient,
                            // layered depth to match the rest of the app.
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

                            const SizedBox(height: 20),

                            // ================================================
                            // BUY CENT/CP — primary CTA, gradient button
                            // ================================================
                            Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BuyCentScreen())),
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
                            // FUND VIA ZTC — secondary option, ShinyCard
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
