// lib/buy_currency.dart
//
// Direct payment flow for students to buy CP/Cent
// No external app required — simple form, auto-generated reference,
// manual payment confirmation. Bank details fetched from Supabase config.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BuyCurrencyScreen extends StatefulWidget {
  const BuyCurrencyScreen({super.key});

  @override
  State<BuyCurrencyScreen> createState() => _BuyCurrencyScreenState();
}

class _BuyCurrencyScreenState extends State<BuyCurrencyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  
  bool _isCent = true; // true = Cent, false = CP
  bool _loading = false;
  bool _loadingBankDetails = true;
  String? _error;
  
  String? _currentReference;
  bool _paymentConfirmed = false;
  
  // Bank details (fetched from backend)
  String? _bankAccount;
  String? _bankName;
  
  static const int _nairaPerCent = 1; // 1 Naira = 1 Cent
  static const int _centPerCp = 1000;

  @override
  void initState() {
    super.initState();
    _fetchBankDetails();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchBankDetails() async {
    try {
      final config = await Supabase.instance.client
          .from('app_config')
          .select('payment_account_number, payment_bank_name')
          .eq('app_id', 'naijalearn')
          .single();

      setState(() {
        _bankAccount = config['payment_account_number'] as String?;
        _bankName = config['payment_bank_name'] as String?;
        _loadingBankDetails = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load payment details. Please refresh and try again.';
        _loadingBankDetails = false;
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

  void _startPurchase() {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _currentReference = _generateReference();
      _paymentConfirmed = false;
      _error = null;
    });
  }

  void _copyAccountDetails() {
    if (_bankAccount == null || _bankName == null) return;
    final details = '$_bankName - $_bankAccount';
    Clipboard.setData(ClipboardData(text: details));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account details copied'), duration: Duration(seconds: 2)),
    );
  }

  void _copyReference() {
    if (_currentReference == null) return;
    Clipboard.setData(ClipboardData(text: _currentReference!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reference copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _confirmPayment() async {
    if (_currentReference == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Call backend to credit the account with reference verification
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
            SnackBar(
              content: const Text('✓ Successfully credited! Your wallet has been updated.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );

          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context);
          });
        }
      } else {
        setState(() => _error = result?['message'] ?? 'Payment verification failed. Contact admin if this persists.');
      }
    } on PostgrestException catch (e) {
      setState(() => _error = e.message ?? 'Server error. Contact admin for assistance.');
    } catch (e) {
      setState(() => _error = 'Something went wrong. Contact admin if payment was made.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loadingBankDetails) {
      return Scaffold(
        appBar: AppBar(title: const Text('Buy CP or Cent')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_bankAccount == null || _bankName == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Buy CP or Cent')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
                const SizedBox(height: 12),
                Text('Payment details unavailable', textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Please contact admin for assistance',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Buy CP or Cent')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Critical Security Warning
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
                            'NEVER send money to any account except the ONE shown below. Do NOT share your reference code with anyone. If you have ANY issues with payment, contact Admin ONLY through your Profile settings.',
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

              const SizedBox(height: 20),

              // Step 1: Enter Amount
              if (_currentReference == null) ...[
                Text(
                  'How much do you want to buy?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                
                // Currency Type Toggle
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

                // Show Naira Equivalent
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
                    onPressed: _amountInNaira > 0 ? _startPurchase : null,
                    child: const Text('Continue to Payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ] else ...[
                // Step 2: Payment Instructions
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.account_balance_outlined, color: scheme.onPrimaryContainer, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Transfer Details',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.onPrimaryContainer,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _PaymentDetail(
                        label: 'Amount to Pay',
                        value: '₦${_amountInNaira.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}.00',
                        scheme: scheme,
                      ),
                      const SizedBox(height: 12),
                      Container(height: 1, color: Colors.white.withOpacity(0.1)),
                      const SizedBox(height: 12),
                      _PaymentDetail(
                        label: 'Bank Name',
                        value: _bankName ?? '—',
                        scheme: scheme,
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Account Number',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Colors.white.withOpacity(0.65),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _bankAccount ?? '—',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onPrimaryContainer,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(Icons.copy_rounded, color: scheme.onPrimaryContainer, size: 24),
                              onPressed: _copyAccountDetails,
                              tooltip: 'Copy account details',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Reference Code Section (PROMINENT)
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
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'You MUST use this reference code in the transfer description. Without it, we cannot link your payment to your wallet.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange.shade900,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reference Code',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _currentReference ?? '',
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    color: Colors.orange.shade700,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            FilledButton.icon(
                              onPressed: _copyReference,
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              label: const Text('Copy'),
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
                      Row(
                        children: [
                          Icon(Icons.list_alt_rounded, color: scheme.primary, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Payment Steps',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _PaymentStep(
                        number: 1,
                        title: 'Copy Account Details',
                        description: 'Tap the button above to copy bank account number',
                      ),
                      const SizedBox(height: 12),
                      _PaymentStep(
                        number: 2,
                        title: 'Bank Transfer',
                        description: 'Go to your bank app and transfer the amount above',
                      ),
                      const SizedBox(height: 12),
                      _PaymentStep(
                        number: 3,
                        title: 'Add Reference',
                        description: 'Paste the reference code above in the transfer description',
                      ),
                      const SizedBox(height: 12),
                      _PaymentStep(
                        number: 4,
                        title: 'Confirm Here',
                        description: 'Come back and click "I Have Paid" below',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Need Help Section
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.help_outline_rounded, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Need Help?',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Go to your Profile > Contact Admin',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
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
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                        : const Text('I Have Paid', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton.tonal(
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _currentReference = null;
                              _amountController.clear();
                              _error = null;
                            });
                          },
                    child: const Text('Back', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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

class _PaymentDetail extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme scheme;

  const _PaymentDetail({
    required this.label,
    required this.value,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white.withOpacity(0.65),
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _PaymentStep extends StatelessWidget {
  final int number;
  final String title;
  final String description;

  const _PaymentStep({
    required this.number,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              '$number',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
