// lib/buy_cent.dart
//
// Cent purchase flow — order first, then payment, then receipt upload.
//
// Flow:
//   1. User enters amount             -> Screen: amount entry
//   2. Server creates a payment order -> RPC create_payment_order
//   3. User transfers money, uploads
//      a receipt of the transfer      -> Screen: payment + receipt upload
//   4. Order goes to pending_verification. Nothing is credited yet.
//   5. Admin verifies against the real OPay transaction and approves.
//
// Cent is only ever credited by the backend, from the admin-approval RPC.
// This screen never adds Cent locally under any circumstance.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Same admin WhatsApp line used elsewhere in the app (e.g. ContactSupportScreen).
const String _adminWhatsAppNumber = '2348056604409';

const String _kPrefsReferenceKey = 'nl_buycent_order_reference';

class BuyCentScreen extends StatefulWidget {
  const BuyCentScreen({super.key});

  @override
  State<BuyCentScreen> createState() => _BuyCentScreenState();
}

class _BuyCentScreenState extends State<BuyCentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _picker = ImagePicker();

  static const int _centPerCp = 1000;

  bool _isCent = true; // true = Cent, false = CP
  bool _loadingConfig = true;
  bool _creatingOrder = false;
  bool _uploadingReceipt = false;
  bool _restoringOrder = true;

  String? _formError;
  String? _actionError;

  Map<String, dynamic>? _paymentSettings;
  Map<String, dynamic>? _order; // current payment_orders row, or null
  XFile? _pickedReceipt;

  @override
  void initState() {
    super.initState();
    _loadPaymentSettings();
    _restoreOrderIfAny();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------

  Future<void> _loadPaymentSettings() async {
    try {
      final config = await Supabase.instance.client
          .from('app_config')
          .select('payment_account_number, payment_bank_name, payment_account_owner')
          .eq('app_id', 'naijalearn')
          .single();

      if (!mounted) return;
      setState(() {
        _paymentSettings = {
          'account_number': config['payment_account_number'] as String?,
          'bank_name': config['payment_bank_name'] as String?,
          'account_name': config['payment_account_owner'] as String?,
        };
        _loadingConfig = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _formError = 'Could not load payment details. Please try again.';
        _loadingConfig = false;
      });
    }
  }

  Future<void> _restoreOrderIfAny() async {
    final prefs = await SharedPreferences.getInstance();
    final reference = prefs.getString(_kPrefsReferenceKey);

    if (reference == null) {
      if (mounted) setState(() => _restoringOrder = false);
      return;
    }

    try {
      final row = await Supabase.instance.client
          .from('payment_orders')
          .select()
          .eq('order_reference', reference)
          .maybeSingle();

      if (!mounted) return;

      if (row == null) {
        await prefs.remove(_kPrefsReferenceKey);
        setState(() => _restoringOrder = false);
        return;
      }

      setState(() {
        _order = row;
        _restoringOrder = false;
      });
    } catch (_) {
      if (mounted) setState(() => _restoringOrder = false);
    }
  }

  Future<void> _refreshOrder() async {
    final reference = _order?['order_reference'] as String?;
    if (reference == null) return;

    try {
      final row = await Supabase.instance.client
          .from('payment_orders')
          .select()
          .eq('order_reference', reference)
          .maybeSingle();
      if (mounted && row != null) setState(() => _order = row);
    } catch (_) {
      // Silent — user can pull to refresh again.
    }
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  int get _centAmount {
    final raw = int.tryParse(_amountController.text) ?? 0;
    return _isCent ? raw : raw * _centPerCp;
  }

  int get _nairaAmount => _centAmount; // 1 Naira per Cent, matches server rate

  String _formatNaira(int amount) =>
      '₦${amount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

  Future<void> _createOrder() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _creatingOrder = true;
      _formError = null;
    });

    try {
      final result = await Supabase.instance.client
          .rpc('create_payment_order', params: {'p_cent_amount': _centAmount});

      final order = Map<String, dynamic>.from(result as Map);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsReferenceKey, order['order_reference'] as String);

      if (mounted) setState(() => _order = order);
    } on PostgrestException catch (e) {
      setState(() => _formError = e.message);
    } catch (e) {
      setState(() => _formError = 'Could not start this order. Please try again.');
    } finally {
      if (mounted) setState(() => _creatingOrder = false);
    }
  }

  Future<void> _pickReceipt({required bool fromCamera}) async {
    final file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      // Downscale + compress on the way in — keeps this data-friendly.
      maxWidth: 1600,
      imageQuality: 70,
    );
    if (file != null && mounted) {
      setState(() {
        _pickedReceipt = file;
        _actionError = null;
      });
    }
  }

  Future<void> _submitReceipt() async {
    final order = _order;
    final receipt = _pickedReceipt;
    if (order == null || receipt == null) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _actionError = 'Your session expired. Please sign in again.');
      return;
    }

    setState(() {
      _uploadingReceipt = true;
      _actionError = null;
    });

    try {
      final reference = order['order_reference'] as String;
      final ext = receipt.path.split('.').last.toLowerCase();
      final safeExt = ['jpg', 'jpeg', 'png'].contains(ext) ? ext : 'jpg';
      final path = '$userId/${reference}_${DateTime.now().millisecondsSinceEpoch}.$safeExt';

      final bytes = await receipt.readAsBytes();

      await Supabase.instance.client.storage.from('payment-receipts').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: safeExt == 'png' ? 'image/png' : 'image/jpeg',
              upsert: false,
            ),
          );

      final result = await Supabase.instance.client.rpc('submit_payment_receipt', params: {
        'p_order_reference': reference,
        'p_receipt_path': path,
      });

      if (mounted) {
        setState(() {
          _order = Map<String, dynamic>.from(result as Map);
          _pickedReceipt = null;
        });
      }
    } on PostgrestException catch (e) {
      setState(() => _actionError = e.message);
    } catch (e) {
      setState(() => _actionError = 'Upload failed. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _uploadingReceipt = false);
    }
  }

  Future<void> _startNewPurchase() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsReferenceKey);
    if (!mounted) return;
    setState(() {
      _order = null;
      _pickedReceipt = null;
      _amountController.clear();
      _formError = null;
      _actionError = null;
    });
  }

  Future<void> _contactAdminOnWhatsApp() async {
    final reference = _order?['order_reference'] as String?;
    final message = reference == null
        ? 'Hi, I need help with a Cent purchase on NaijaLearn.'
        : 'Hi, I need help with my Cent purchase on NaijaLearn.\n\n'
            'Reference: $reference';
    final uri = Uri.parse('https://wa.me/$_adminWhatsAppNumber?text=${Uri.encodeComponent(message)}');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp. Please contact support directly.')),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loadingConfig || _restoringOrder) {
      return Scaffold(
        appBar: AppBar(title: const Text('Buy Cent')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_paymentSettings == null) {
      return _buildUnavailableScreen(context);
    }

    final status = _order?['status'] as String?;

    return Scaffold(
      appBar: AppBar(title: const Text('Buy Cent')),
      body: SafeArea(
        child: switch (status) {
          null => _buildAmountEntry(context),
          'awaiting_payment' || 'awaiting_receipt' => _buildPaymentAndUpload(context),
          'pending_verification' => _buildPendingReview(context),
          'rejected' => _buildRejected(context),
          'verified' => _buildVerified(context),
          _ => _buildPendingReview(context),
        },
      ),
    );
  }

  Widget _buildUnavailableScreen(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              const Text('Payment details are unavailable right now',
                  textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Please contact support for assistance.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 20),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Go back')),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _contactAdminOnWhatsApp,
                icon: const Icon(Icons.chat_rounded),
                label: const Text('Message support on WhatsApp'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Screen 1: amount entry --------------------------------------------

  Widget _buildAmountEntry(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoBanner(
              icon: Icons.shield_outlined,
              tone: _InfoTone.warning,
              title: 'Only pay into the account we show you',
              message: 'We will display one designated account on the next screen. '
                  'Do not transfer to any other account, and do not share your '
                  'payment reference with anyone.',
            ),
            const SizedBox(height: 24),
            Text('How much would you like to buy?',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline, width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(child: _CurrencyToggleButton(
                    label: 'Cent', selected: _isCent, onTap: () => setState(() => _isCent = true))),
                  Container(width: 1, color: scheme.outline),
                  Expanded(child: _CurrencyToggleButton(
                    label: 'CP (1,000 Cent)', selected: !_isCent, onTap: () => setState(() => _isCent = false))),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value == null || value.isEmpty) return 'Enter an amount';
                final amount = int.tryParse(value);
                if (amount == null || amount <= 0) return 'Enter a valid amount';
                if (amount > 1000000) return 'Maximum is 1,000,000 ${_isCent ? 'Cent' : 'CP'}';
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
            if (_centAmount > 0)
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
                    Text('You will pay', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer)),
                    Text(_formatNaira(_nairaAmount),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer, fontSize: 16)),
                  ],
                ),
              ),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              _ErrorBox(message: _formError!),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: (_centAmount > 0 && !_creatingOrder) ? _createOrder : null,
                child: _creatingOrder
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Continue to payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Screen 2: payment instructions + receipt upload -------------------

  Widget _buildPaymentAndUpload(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final order = _order!;
    final reference = order['order_reference'] as String;
    final naira = order['amount_naira'] as int;
    final cent = order['cent_amount'] as int;
    final isAwaitingNewReceipt = order['status'] == 'awaiting_receipt';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isAwaitingNewReceipt)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _InfoBanner(
                icon: Icons.replay_rounded,
                tone: _InfoTone.info,
                title: 'Please upload a clearer receipt',
                message: 'An admin reviewed your last upload and could not confirm the details. '
                    'Upload a new, clear screenshot of the same transaction below.',
              ),
            ),

          Text('Order summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow('You are buying', '$cent Cent'),
                const SizedBox(height: 12),
                Container(height: 1, color: Colors.white.withOpacity(0.25)),
                const SizedBox(height: 12),
                _DetailRow('Amount to transfer', _formatNaira(naira)),
              ],
            ),
          ),

          const SizedBox(height: 22),
          Text('Step 1 — Transfer to this account',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final number = _paymentSettings?['account_number'] as String? ?? '';
              await Clipboard.setData(ClipboardData(text: number));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account number copied.')));
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border.all(color: scheme.primary, width: 1.5),
                borderRadius: BorderRadius.circular(16),
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
                        Text(_paymentSettings?['bank_name'] as String? ?? 'Not set',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text(_paymentSettings?['account_number'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 1)),
                        const SizedBox(height: 2),
                        Text(_paymentSettings?['account_name'] as String? ?? '',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                      ],
                    ),
                  ),
                  Icon(Icons.copy_rounded, size: 20, color: scheme.primary),
                ],
              ),
            ),
          ),

          const SizedBox(height: 22),
          Text('Step 2 — Include this reference',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
                Text(
                  'Enter this exactly in the transfer narration/description. '
                  'Without it, we cannot match your payment to this order.',
                  style: TextStyle(color: Colors.orange.shade900, fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600),
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
                        child: Text(reference,
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 19, fontFamily: 'monospace',
                                letterSpacing: 0.5, color: Colors.orange.shade800)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Colors.orange),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: reference));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Reference copied.')));
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),
          Text('Step 3 — Upload your OPay receipt',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'Your receipt should clearly show the amount, date and time, '
            'transaction status, and reference number.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          if (_pickedReceipt != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outline),
              ),
              child: Image.file(File(_pickedReceipt!.path), height: 180, width: double.infinity, fit: BoxFit.cover),
            ),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploadingReceipt ? null : () => _pickReceipt(fromCamera: false),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose from gallery'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploadingReceipt ? null : () => _pickReceipt(fromCamera: true),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Take a photo'),
                ),
              ),
            ],
          ),

          if (_actionError != null) ...[
            const SizedBox(height: 12),
            _ErrorBox(message: _actionError!),
          ],

          const SizedBox(height: 20),
          _InfoBanner(
            icon: Icons.info_outline_rounded,
            tone: _InfoTone.neutral,
            title: 'What happens after you submit',
            message: 'Uploading a receipt does not credit Cent automatically. '
                'An admin checks the actual transaction and approves it — this '
                'is usually quick, but can occasionally take longer.',
          ),

          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: (_pickedReceipt != null && !_uploadingReceipt) ? _submitReceipt : null,
              icon: _uploadingReceipt
                  ? null
                  : const Icon(Icons.upload_rounded),
              label: _uploadingReceipt
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Submit Payment for Verification', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: _uploadingReceipt ? null : _startNewPurchase,
              child: const Text('Cancel this order'),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Pending verification -----------------------------------------------

  Widget _buildPendingReview(BuildContext context) {
    final order = _order!;
    final reference = order['order_reference'] as String;
    final cent = order['cent_amount'] as int;
    final naira = order['amount_naira'] as int;

    return RefreshIndicator(
      onRefresh: _refreshOrder,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _InfoBanner(
            icon: Icons.hourglass_top_rounded,
            tone: _InfoTone.pending,
            title: 'Payment verification pending',
            message: "We've received your payment receipt. Your Cent will be "
                'credited once the payment is confirmed.',
          ),
          const SizedBox(height: 20),
          _OrderSummaryCard(reference: reference, naira: naira, cent: cent, formatNaira: _formatNaira),
          const SizedBox(height: 20),
          Text(
            'Pull down to check for an update, or reach out if this has been '
            'pending for a while.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _contactAdminOnWhatsApp,
            icon: const Icon(Icons.chat_rounded, size: 18, color: Color(0xFF25D366)),
            label: const Text('Message support on WhatsApp'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF25D366)),
              foregroundColor: const Color(0xFF25D366),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Rejected -------------------------------------------------------------

  Widget _buildRejected(BuildContext context) {
    final order = _order!;
    final reference = order['order_reference'] as String;
    final cent = order['cent_amount'] as int;
    final naira = order['amount_naira'] as int;
    final reason = order['rejection_reason'] as String? ?? 'Not specified';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _InfoBanner(
          icon: Icons.cancel_outlined,
          tone: _InfoTone.error,
          title: 'Payment could not be verified',
          message: 'Reason: $reason',
        ),
        const SizedBox(height: 20),
        _OrderSummaryCard(reference: reference, naira: naira, cent: cent, formatNaira: _formatNaira),
        const SizedBox(height: 24),
        SizedBox(
          height: 54,
          child: FilledButton(onPressed: _startNewPurchase, child: const Text('Start a new purchase')),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _contactAdminOnWhatsApp,
          icon: const Icon(Icons.chat_rounded, size: 18, color: Color(0xFF25D366)),
          label: const Text('Message support on WhatsApp'),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFF25D366)),
            foregroundColor: const Color(0xFF25D366),
          ),
        ),
      ],
    );
  }

  // ---- Verified -------------------------------------------------------------

  Widget _buildVerified(BuildContext context) {
    final order = _order!;
    final cent = order['cent_amount'] as int;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 56),
            const SizedBox(height: 16),
            Text('Payment verified', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('$cent Cent has been added to your wallet.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: _startNewPurchase, child: const Text('Buy more Cent')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared widgets
// ---------------------------------------------------------------------------

class _CurrencyToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CurrencyToggleButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: selected ? scheme.primary : Colors.transparent),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: selected ? Colors.white : scheme.onSurface),
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

class _OrderSummaryCard extends StatelessWidget {
  final String reference;
  final int naira;
  final int cent;
  final String Function(int) formatNaira;

  const _OrderSummaryCard({
    required this.reference,
    required this.naira,
    required this.cent,
    required this.formatNaira,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$cent Cent', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(formatNaira(naira), style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          Text(reference, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ],
      ),
    );
  }
}

enum _InfoTone { warning, info, neutral, pending, error }

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final _InfoTone tone;
  final String title;
  final String message;

  const _InfoBanner({required this.icon, required this.tone, required this.title, required this.message});

  ({Color fg, Color bg, Color border}) _colors() {
    switch (tone) {
      case _InfoTone.warning:
        return (fg: Colors.red.shade800, bg: Colors.red.withOpacity(0.07), border: Colors.red.withOpacity(0.4));
      case _InfoTone.info:
        return (fg: Colors.blue.shade800, bg: Colors.blue.withOpacity(0.06), border: Colors.blue.withOpacity(0.35));
      case _InfoTone.pending:
        return (fg: Colors.amber.shade900, bg: Colors.amber.withOpacity(0.10), border: Colors.amber.withOpacity(0.45));
      case _InfoTone.error:
        return (fg: Colors.red.shade800, bg: Colors.red.withOpacity(0.07), border: Colors.red.withOpacity(0.4));
      case _InfoTone.neutral:
        return (fg: Colors.grey.shade800, bg: Colors.grey.withOpacity(0.08), border: Colors.grey.withOpacity(0.3));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.border, width: 1.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.fg, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: c.fg, fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 4),
                Text(message, style: TextStyle(color: c.fg.withOpacity(0.9), fontSize: 12.5, height: 1.4)),
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
