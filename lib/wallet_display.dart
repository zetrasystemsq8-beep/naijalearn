// lib/wallet_display.dart
//
// NaijaLearn's wallet screen. Read-only display of the app-specific
// balance (backed by app_currency_balances via ZetraPay). Funding is
// NOT done here — users open ZTC, tap "Send to Apps" > NaijaLearn, and
// the balance updates server-side. This screen just shows the result.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'zetra_pay.dart';

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
        final row = await Supabase.instance.client
            .from('profiles')
            .select('zetra_id')
            .eq('id', userId)
            .maybeSingle();
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Zetra ID copied'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Wallet')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            colors: [scheme.primary, scheme.primary.withOpacity(0.75)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('NaijaLearn Balance',
                                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
                            const SizedBox(height: 8),
                            Text(
                              _rawBalance != null ? '${_formatCp(_cp)} CP' : '—',
                              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            if (_rawBalance != null && _cent > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                '+ $_cent Cent',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.85),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.badge_outlined, size: 16, color: Colors.white70),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _zetraId ?? 'Loading...',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  if (_zetraId != null)
                                    GestureDetector(
                                      onTap: _copyZetraId,
                                      child: const Icon(Icons.copy_rounded, size: 16, color: Colors.white70),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.verified_rounded, size: 14, color: Colors.white70),
                                const SizedBox(width: 4),
                                Text('Powered by ZTC', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.account_balance_wallet_rounded, color: scheme.onPrimaryContainer),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Fund this wallet', style: TextStyle(fontWeight: FontWeight.w600)),
                                  Text(
                                    'Open ZTC → Send to Apps → NaijaLearn, using the Zetra ID above',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your balance updates automatically once a transfer from ZTC completes. '
                        'Pull down to refresh if you don\'t see it right away.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
            Icon(Icons.error_outline_rounded, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
