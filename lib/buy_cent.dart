// lib/buy_cent.dart
//
// Two-screen payment flow for buying Cent/CP
// Screen 1: Amount entry
// Screen 2: Payment confirmation with tappable account details

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
              content: Text('✓ Payment confirmed! Your wallet will be credited shortly.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
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
      setState(() => _error = e.message ?? 'Server error. Contact admin.');
    } catch (e) {
      setState(() => _error = 'Something went wrong. Contact admin if payment was made.');
    } finally {
      if (mounted) setState(() => _loading = false);
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
              // SCREEN 1: Amount Entry
              if (_currentReference == null) ...[
                // Security Warning
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    border: Border.all(color: Colors.red, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_rounded, color: Colors.red, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⚠️ SECURITY WARNING',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'NEVER send money to any account except the ONE shown in the next screen. Do NOT share your reference code. Any suspicious activity = SCAM. Report to Admin immediately.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.red.shade700,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
                          '₦${_amountInNaira.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}.00',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
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
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: scheme.error, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
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
              // SCREEN 2: Payment Confirmation
              else ...[
                Text(
                  'Transfer to this account',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Tappable Account Details (matching User ID copy style)
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
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border.all(color: scheme.outline),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _paymentSettings?['bank_name'] as String? ?? 'Not set — contact support',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _paymentSettings?['account_number'] as String? ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18, letterSpacing: 1),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _paymentSettings?['account_name'] as String? ?? '',
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.copy_rounded, size: 18),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Amount & Reference
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.primary, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailRow('Amount to Transfer', '₦${_amountInNaira.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}.00'),
                      const SizedBox(height: 12),
                      Container(height: 1, color: Colors.white.withOpacity(0.1)),
                      const SizedBox(height: 12),
                      _DetailRow('You Will Receive', '${_isCent ? _amountController.text : (int.tryParse(_amountController.text) ?? 0) * _centPerCp} Cent'),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Reference Code (ORANGE WARNING)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange, width: 2),
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.orange.withOpacity(0.05),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.security_rounded, color: Colors.orange, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'IMPORTANT: Reference Code',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'You MUST use this reference in the transfer description. Without it, we cannot link your payment to your account.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange.shade900,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _currentReference ?? '',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: Colors.orange.shade700,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.copy_rounded, color: Colors.orange),
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

                const SizedBox(height: 20),

                // Payment Steps
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
                      Text('Payment Steps', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _PaymentStep(1, 'Copy account above', 'Tap the account box to copy'),
                      const SizedBox(height: 8),
                      _PaymentStep(2, 'Make transfer', 'Use your bank app to send the amount'),
                      const SizedBox(height: 8),
                      _PaymentStep(3, 'Add reference', 'Paste the reference code above in description'),
                      const SizedBox(height: 8),
                      _PaymentStep(4, 'Click below', 'Come back here and confirm payment'),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Help Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_rounded, color: scheme.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Any issues or scams?', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                            Text('Contact Admin immediately via Profile settings', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Action Buttons
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
                    onPressed: _loading ? null : () => setState(() {
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
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withOpacity(0.7))),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
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
