// lib/buy_cent.dart
//
// Two-screen payment flow for buying Cent/CP
// Screen 1: Amount entry
// Screen 2: Payment confirmation with tappable account details
//
// Layout order on Screen 2 (reorganized for clarity):
//   1. Bank account (primary action — tap to copy)
//   2. Reference code (critical — must be included in transfer)
//   3. Amount summary (high-contrast, readable)
//   4. Numbered payment steps
//   5. Processing-time notice (sets honest expectations)
//   6. Security warning (compact, red)
//   7. WhatsApp escalation button (for scams / stuck payments)
//   8. Action buttons

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Same admin WhatsApp line used in ContactSupportScreen (main.dart).
const String _adminWhatsAppNumber = '2348056604409';

class BuyCentScreen extends StatefulWidget {
  const BuyCentScreen({super.key});

  @override
  State<BuyCentScreen> createState() => _BuyCentScreenState();
}

class _BuyCentScreenState extends State<BuyCentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();

  bool _isCent = true; // true = Cent, false = CP
  bool _loading = false;
  bool _loadingConfig = true;
  String? _error;

  String? _currentReference;
  bool _paymentConfirmed = false;

  // Payment settings from Supabase
  Map<String, dynamic>? _paymentSettings;

  static const int _nairaPerCent = 1;
  static const int _centPerCp = 1000;

  @override
  void initState() {
    super.initState();
    _loadPaymentSettings();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentSettings() async {
    try {
      final config = await Supabase.instance.client
          .from('app_config')
          .select('payment_account_number, payment_bank_name, payment_account_owner')
          .eq('app_id', 'naijalearn')
          .single();

      setState(() {
        _paymentSettings = {
          'account_number': config['payment_account_number'] as String?,
          'bank_name': config['payment_bank_name'] as String?,
          'account_name': config['payment_account_owner'] as String?,
        };
        _loadingConfig = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load payment details. Please refresh and try again.';
        _loadingConfig = false;
      });
    }
  }

  String _generateReference() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    return 'NL${timestamp.toString().substring(5, 11)}$random';
  }

  int get _amountInNaira {
    if (_amountController.text.isEmpty) return 0;
    final amount = int.tryParse(_amountController.text) ?? 0;
    return _isCent ? amount : amount * _centPerCp;
  }

  String _formatNaira(int amount) =>
      '₦${amount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}.00';

  void _goToPaymentScreen() {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _currentReference = _generateReference();
      _paymentConfirmed = false;
      _error = null;
    });
  }

  Future<void> _confirmPayment() async {
    if (_currentReference == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final amount = _isCent
          ? int.parse(_amountController.text)
          : int.parse(_amountController.text) * _centPerCp;

      final result = await Supabase.instance.client.rpc('confirm_currency_purchase', params: {
        'p_reference': _currentReference,
        'p_amount_cent': amount,
        'p_app_id': 'naijalearn',
      });

      if (result is Map && result['success'] == true) {
        if (mounted) {
          setState(() {
            _paymentConfirmed = true;
            _currentReference = null;
            _amountController.clear();
            _error = null;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '✓ Submitted! Your payment is pending review — this usually '
                'takes a few minutes, but can occasionally take longer. '
                "You'll be credited once an admin confirms it.",
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 6),
            ),
          );

          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context);
          });
        }
      } else {
        setState(() => _error = result?['message'] ?? 'Payment verification failed. Contact admin for assistance.');
      }
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Contact admin if payment was made.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _contactAdminOnWhatsApp() async {
    final ref = _currentReference ?? '';
    final message = ref.isEmpty
        ? "Hi, I need help with a Cent purchase on NaijaLearn."
        : "Hi, I need help with my Cent purchase on NaijaLearn.\n\nReference: $ref\nAmount: ${_formatNaira(_amountInNaira)}";
    final uri = Uri.parse('https://wa.me/$_adminWhatsAppNumber?text=${Uri.encodeComponent(message)}');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp. Please contact admin manually.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loadingConfig) {
      return Scaffold(
        appBar: AppBar(title: const Text('Buy Cent')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_paymentSettings == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Buy Cent')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
                const SizedBox(height: 12),
                const Text('Payment details unavailable'),
                const SizedBox(height: 8),
                Text('Please contact admin for assistance', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _contactAdminOnWhatsApp,
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('Message Admin on WhatsApp'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Buy Cent')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===================================================
              // SCREEN 1: Amount Entry
              // ===================================================
              if (_currentReference == null) ...[
                _WarningBanner(
                  icon: Icons.warning_rounded,
                  title: 'SECURITY WARNING',
                  message: 'NEVER send money to any account except the ONE shown '
                      'in the next screen. Do NOT share your reference code. '
                      'Any suspicious activity = SCAM. Report to Admin immediately.',
                ),

                const SizedBox(height: 24),

                Text(
                  'How much do you want to buy?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Currency Toggle
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outline, width: 1.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isCent = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _isCent ? scheme.primary : Colors.transparent,
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(13)),
                            ),
                            child: Text(
                              'Cent',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: _isCent ? Colors.white : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(width: 1, color: scheme.outline),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isCent = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: !_isCent ? scheme.primary : Colors.transparent,
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(13)),
                            ),
                            child: Text(
                              'CP (1,000 Cent)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: !_isCent ? Colors.white : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Amount Input
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Enter amount';
                    final amount = int.tryParse(value);
                    if (amount == null || amount <= 0) return 'Enter a valid amount';
                    if (amount > 1000000) return 'Maximum 1,000,000 ${_isCent ? 'Cent' : 'CP'}';
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'Amount (${_isCent ? 'Cent' : 'CP'})',
                    prefixIcon: const Icon(Icons.currency_exchange_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),

                // Naira Equivalent
                if (_amountInNaira > 0)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: scheme.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Amount in Naira',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        Text(
                          _formatNaira(_amountInNaira),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimaryContainer,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _ErrorBox(message: _error!),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  height: 54,
                  child: FilledButton.tonal(
                    onPressed: _amountInNaira > 0 ? _goToPaymentScreen : null,
                    child: const Text('Continue to Payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]
              // ===================================================
              // SCREEN 2: Payment Confirmation
              // ===================================================
              else ...[
                if (_error != null) ...[
                  _ErrorBox(message: _error!),
                  const SizedBox(height: 16),
                ],

                // ---- 1. Bank account (primary action) ----
                Text(
                  'Step 1 — Transfer to this account',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    final number = _paymentSettings?['account_number'] as String? ?? '';
                    await Clipboard.setData(ClipboardData(text: number));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Account number copied.')),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border.all(color: scheme.primary, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: scheme.primary.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.account_balance_rounded, color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _paymentSettings?['bank_name'] as String? ?? 'Not set — contact support',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _paymentSettings?['account_number'] as String? ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 1),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _paymentSettings?['account_name'] as String? ?? '',
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.copy_rounded, size: 20, color: scheme.primary),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                // ---- 2. Reference code (critical) ----
                Text(
                  'Step 2 — Use this reference code',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange, width: 2),
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.orange.withOpacity(0.06),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.security_rounded, color: Colors.orange, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You MUST include this in the transfer description, or we cannot match your payment to your account.',
                              style: TextStyle(color: Colors.orange.shade900, fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _currentReference ?? '',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 19,
                                  fontFamily: 'monospace',
                                  letterSpacing: 0.5,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, color: Colors.orange),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _currentReference ?? ''));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Reference code copied.')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // ---- 3. Amount summary (fixed contrast) ----
                Text(
                  'Order Summary',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailRow('Amount to Transfer', _formatNaira(_amountInNaira)),
                      const SizedBox(height: 12),
                      Container(height: 1, color: Colors.white.withOpacity(0.25)),
                      const SizedBox(height: 12),
                      _DetailRow(
                        'You Will Receive',
                        '${_isCent ? _amountController.text : (int.tryParse(_amountController.text) ?? 0) * _centPerCp} Cent',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // ---- 4. Payment steps ----
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('How it works', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const _PaymentStep(1, 'Copy the account above', 'Tap the account box to copy'),
                      const SizedBox(height: 8),
                      const _PaymentStep(2, 'Make the transfer', 'Use your bank app to send the amount'),
                      const SizedBox(height: 8),
                      const _PaymentStep(3, 'Add the reference', 'Paste the code above in the transfer description'),
                      const SizedBox(height: 8),
                      const _PaymentStep(4, 'Tap "I Have Paid"', 'Come back here and confirm below'),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ---- 5. Processing-time notice ----
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.07),
                    border: Border.all(color: Colors.green.withOpacity(0.35)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.schedule_rounded, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'After you confirm, your payment is reviewed by an admin. '
                          'This usually takes a few minutes but can occasionally take '
                          'longer — no need to submit twice.',
                          style: TextStyle(color: Colors.green.shade900, fontSize: 12.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ---- 6. Security warning (compact) ----
                _WarningBanner(
                  icon: Icons.warning_rounded,
                  title: 'Only send to the account above',
                  message: 'Never transfer to any other account. Never share your '
                      'reference code with anyone claiming to be admin or support.',
                  compact: true,
                ),

                const SizedBox(height: 16),

                // ---- 7. WhatsApp escalation ----
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Issue or suspect a scam?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                            Text('Message admin directly on WhatsApp', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _contactAdminOnWhatsApp,
                        icon: const Icon(Icons.chat_rounded, size: 18, color: Color(0xFF25D366)),
                        label: const Text('WhatsApp'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF25D366)),
                          foregroundColor: const Color(0xFF25D366),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ---- 8. Action buttons ----
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _confirmPayment,
                    icon: _loading ? null : const Icon(Icons.check_circle_rounded),
                    label: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Text('I Have Paid', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton.tonal(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _currentReference = null;
                              _amountController.clear();
                              _error = null;
                            }),
                    child: const Text('Back', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
      ],
    );
  }
}

class _PaymentStep extends StatelessWidget {
  final int number;
  final String title;
  final String description;

  const _PaymentStep(this.number, this.title, this.description);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text('$number', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(description, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool compact;

  const _WarningBanner({
    required this.icon,
    required this.title,
    required this.message,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        border: Border.all(color: Colors.red, width: compact ? 1.5 : 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.red, size: compact ? 20 : 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 12.5 : 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_rounded, color: scheme.error, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: scheme.error, fontSize: 13))),
        ],
      ),
    );
  }
}
