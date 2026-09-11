// lib/admin_panel.dart
//
// Admin screen for verifying Cent purchase orders.
// Access is enforced server-side by RLS + is_admin() in Postgres — this
// screen should still only be *shown* to users where profiles.is_admin
// is true, same as before.
//
// No admin password dialog: authorization comes from the signed-in
// Supabase session plus the is_admin() check inside each RPC, not from a
// password typed into a text field.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const List<String> _rejectionReasons = [
  'Payment not found',
  'Wrong amount',
  'Invalid receipt',
  'Reference does not match',
  'Duplicate transaction',
  'Other',
];

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  final Map<String, bool> _actionInProgress = {};

  @override
  void initState() {
    super.initState();
    _loadPendingOrders();
  }

  Future<void> _loadPendingOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _client
          .from('payment_orders')
          .select()
          .eq('status', 'pending_verification')
          .order('receipt_submitted_at', ascending: true);

      setState(() => _orders = List<Map<String, dynamic>>.from(response));
    } catch (e) {
      setState(() => _error = 'Failed to load orders: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      return DateFormat('MMM d, yyyy • h:mm a').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _viewReceipt(String? receiptPath) async {
    if (receiptPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No receipt on this order.')),
      );
      return;
    }

    try {
      final signedUrl = await _client.storage
          .from('payment-receipts')
          .createSignedUrl(receiptPath, 300); // 5 minutes

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('Payment receipt'),
                automaticallyImplyLeading: false,
                actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))],
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    signedUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Could not load receipt image.'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open receipt: $e')),
        );
      }
    }
  }

  Future<bool> _confirmAction({required String title, required String message, required Color color}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _approve(String reference, int centAmount) async {
    final confirmed = await _confirmAction(
      title: 'Approve payment',
      message: 'Confirm that you have checked the actual OPay transaction for '
          '$reference and it matches this order. $centAmount Cent will be credited.',
      color: Colors.green,
    );
    if (!confirmed) return;

    setState(() => _actionInProgress[reference] = true);
    try {
      await _client.rpc('admin_approve_payment', params: {'p_order_reference': reference});
      _showSnack('Approved — $centAmount Cent credited.', Colors.green);
      await _loadPendingOrders();
    } on PostgrestException catch (e) {
      _showSnack(e.message, Colors.red);
    } catch (e) {
      _showSnack('Something went wrong: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _actionInProgress[reference] = false);
    }
  }

  Future<void> _reject(String reference) async {
    final reason = await _showRejectDialog();
    if (reason == null) return;

    setState(() => _actionInProgress[reference] = true);
    try {
      await _client.rpc('admin_reject_payment', params: {
        'p_order_reference': reference,
        'p_reason': reason,
      });
      _showSnack('Order rejected.', Colors.orange);
      await _loadPendingOrders();
    } on PostgrestException catch (e) {
      _showSnack(e.message, Colors.red);
    } catch (e) {
      _showSnack('Something went wrong: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _actionInProgress[reference] = false);
    }
  }

  Future<void> _requestNewReceipt(String reference) async {
    final confirmed = await _confirmAction(
      title: 'Request a new receipt',
      message: 'The user will be asked to upload a clearer receipt for $reference. '
          'No Cent will be credited or denied yet.',
      color: Colors.blue,
    );
    if (!confirmed) return;

    setState(() => _actionInProgress[reference] = true);
    try {
      await _client.rpc('admin_request_new_receipt', params: {'p_order_reference': reference});
      _showSnack('New receipt requested.', Colors.blue);
      await _loadPendingOrders();
    } on PostgrestException catch (e) {
      _showSnack(e.message, Colors.red);
    } catch (e) {
      _showSnack('Something went wrong: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _actionInProgress[reference] = false);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 3)),
    );
  }

  Future<String?> _showRejectDialog() async {
    String selectedReason = _rejectionReasons.first;
    final otherController = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reject payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select a reason:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ..._rejectionReasons.map(
                (reason) => RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(reason),
                  value: reason,
                  groupValue: selectedReason,
                  onChanged: (value) => setDialogState(() => selectedReason = value!),
                ),
              ),
              if (selectedReason == 'Other') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: otherController,
                  decoration: const InputDecoration(
                    hintText: 'Describe the reason',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                final reason = selectedReason == 'Other' ? otherController.text.trim() : selectedReason;
                Navigator.pop(context, reason.isEmpty ? 'Other' : reason);
              },
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment verification'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadPendingOrders, tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState(scheme)
              : _orders.isEmpty
                  ? _buildEmptyState(scheme)
                  : RefreshIndicator(
                      onRefresh: _loadPendingOrders,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _orders.length,
                        itemBuilder: (context, index) => _buildOrderCard(context, _orders[index]),
                      ),
                    ),
    );
  }

  Widget _buildErrorState(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadPendingOrders, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            const Text('No pending payments', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('All Cent purchases have been reviewed.', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, Map<String, dynamic> order) {
    final scheme = Theme.of(context).colorScheme;
    final reference = order['order_reference'] as String;
    final centAmount = order['cent_amount'] as int;
    final naira = order['amount_naira'] as int;
    final receiptPath = order['receipt_path'] as String?;
    final createdAt = order['created_at'] as String?;
    final submittedAt = order['receipt_submitted_at'] as String?;
    final userId = order['user_id'] as String? ?? '';
    final isProcessing = _actionInProgress[reference] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    reference,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                  child: Text('$centAmount Cent',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MetaRow(icon: Icons.person_outline_rounded, label: 'User', value: userId),
                  const SizedBox(height: 6),
                  _MetaRow(icon: Icons.payments_outlined, label: 'Expected amount', value: '₦$naira'),
                  const SizedBox(height: 6),
                  _MetaRow(icon: Icons.event_outlined, label: 'Order created', value: _formatDate(createdAt)),
                  const SizedBox(height: 6),
                  _MetaRow(icon: Icons.upload_file_outlined, label: 'Receipt submitted', value: _formatDate(submittedAt)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _viewReceipt(receiptPath),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('View receipt'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: isProcessing ? null : () => _approve(reference, centAmount),
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    child: isProcessing
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                        : const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: isProcessing ? null : () => _reject(reference),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1), foregroundColor: Colors.red),
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: isProcessing ? null : () => _requestNewReceipt(reference),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('Request a new receipt'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text('$label: ', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.labelSmall, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
