// lib/buy_currency.dart
//
// Direct payment flow for students to buy CP/Cent
// No external app required — simple form, auto-generated reference,
// manual payment confirmation.

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
  String? _error;
  
  String? _currentReference;
  bool _paymentConfirmed = false;
  
  // Constants
  static const String _bankAccount = '1234567890'; // Replace with actual account
  static const String _bankName = 'NaijaBank';
  static const int _nairaPerCent = 1; // 1 Naira = 1 Cent
  static const int _centPerCp = 1000;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
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
      const SnackBar(content: Text('Reference copied'), duration: Duration(seconds: 2)),
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
        setState(() {
          _paymentConfirmed = true;
          _currentReference = null;
          _amountController.clear();
          _error = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Successfully credited! ${_isCent ? _amountController.text : int.parse(_amountController.text) * _centPerCp} Cent added.',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        setState(() => _error = result?['message'] ?? 'Payment verification failed');
      }
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Buy CP or Cent')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isCent = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _isCent ? scheme.primary : Colors.transparent,
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(11)),
                            ),
                            child: Text(
                              'Cent',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _isCent ? Colors.white : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isCent = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !_isCent ? scheme.primary : Colors.transparent,
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(11)),
                            ),
                            child: Text(
                              'CP',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: !_isCent ? Colors.white : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Amount Input
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Enter amount';
                    final amount = int.tryParse(value);
                    if (amount == null || amount <= 0) return 'Enter a valid amount';
                    if (amount > 1000000) return 'Maximum 1,000,000';
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'Amount (${_isCent ? 'Cent' : 'CP'})',
                    prefixIcon: const Icon(Icons.currency_exchange_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),

                // Show Naira Equivalent
                if (_amountInNaira > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Amount in Naira',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          '₦${_amountInNaira.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}.00',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimaryContainer,
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
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: scheme.error, fontSize: 13),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton.tonal(
                    onPressed: _amountInNaira > 0 ? _startPurchase : null,
                    child: const Text('Proceed to Payment', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ] else ...[
                // Step 2: Payment Instructions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Details',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _PaymentDetail(
                        label: 'Amount to Pay',
                        value: '₦${_amountInNaira.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}.00',
                        scheme: scheme,
                      ),
                      const SizedBox(height: 12),
                      _PaymentDetail(
                        label: 'Bank Name',
                        value: _bankName,
                        scheme: scheme,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
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
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _bankAccount,
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(Icons.copy_rounded, color: scheme.onPrimaryContainer),
                              onPressed: _copyAccountDetails,
                              tooltip: 'Copy account details',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Reference Code Section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚠️ Important: Reference Code',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You MUST include this reference when making the transfer. Without it, we cannot link your payment to this purchase.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: scheme.outlineVariant),
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
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _currentReference ?? '',
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(Icons.copy_rounded, color: scheme.primary),
                              onPressed: _copyReference,
                              tooltip: 'Copy reference',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Confirmation Section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.yellow.withOpacity(0.1),
                    border: Border.all(color: Colors.yellow.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Steps',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _PaymentStep(
                        number: 1,
                        title: 'Copy Account & Amount',
                        description: 'Use the account number and amount above',
                      ),
                      const SizedBox(height: 8),
                      _PaymentStep(
                        number: 2,
                        title: 'Make Bank Transfer',
                        description: 'Transfer to the account with reference code as description',
                      ),
                      const SizedBox(height: 8),
                      _PaymentStep(
                        number: 3,
                        title: 'Click "I Have Paid"',
                        description: 'Come back here and confirm payment to credit your wallet',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Action Buttons
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _confirmPayment,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                        : const Text('I Have Paid', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 8),
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
                    child: const Text('Cancel', style: TextStyle(fontSize: 16)),
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
            color: Colors.white.withOpacity(0.7),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: scheme.onPrimaryContainer,
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.yellow.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              '$number',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
