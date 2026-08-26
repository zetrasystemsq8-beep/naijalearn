// lib/admin_panel.dart
//
// Admin screen for approving/rejecting Cent purchase requests.
// Only visible if user.is_admin = true.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _pendingRequests = [];
  bool _loading = true;
  String? _error;

  Map<int, bool> _actionInProgress = {};

  @override
  void initState() {
    super.initState();
    _loadPendingRequests();
  }

  Future<void> _loadPendingRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _client
          .from('cent_purchase_requests')
          .select()
          .eq('status', 'pending')
          .order('requested_at', ascending: false);

      setState(() {
        _pendingRequests = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      setState(() => _error = 'Failed to load requests: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _promptForAdminPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Admin Password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Enter admin password'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Unlock')),
        ],
      ),
    );
    return result;
  }

  Future<void> _approveRequest(int requestId, int centAmount) async {
    final adminPassword = await _promptForAdminPassword();
    if (adminPassword == null || adminPassword.isEmpty) return;

    setState(() => _actionInProgress[requestId] = true);

    try {
      final result = await _client.rpc('admin_approve_cent_purchase', params: {
        'request_id': requestId,
        'p_admin_password': adminPassword,
      });

      if (result is Map && result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Request approved. $centAmount Cent credited.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          await _loadPendingRequests();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result?['message'] ?? 'Unknown error'}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionInProgress[requestId] = false);
    }
  }

  Future<void> _rejectRequest(int requestId) async {
    final reason = await _showRejectDialog();
    if (reason == null) return;

    final adminPassword = await _promptForAdminPassword();
    if (adminPassword == null || adminPassword.isEmpty) return;

    setState(() => _actionInProgress[requestId] = true);

    try {
      final result = await _client.rpc('admin_reject_cent_purchase', params: {
        'request_id': requestId,
        'rejection_reason': reason,
        'p_admin_password': adminPassword,
      });

      if (result is Map && result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Request rejected.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
          await _loadPendingRequests();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result?['message'] ?? 'Unknown error'}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionInProgress[requestId] = false);
    }
  }

  Future<String?> _showRejectDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Request'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Enter reason (optional)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM d, yyyy • h:mm a').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadPendingRequests,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _loadPendingRequests, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _pendingRequests.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 48, color: scheme.primary),
                            const SizedBox(height: 12),
                            const Text('No pending requests', textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            Text(
                              'All Cent purchases have been processed',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadPendingRequests,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _pendingRequests.length,
                        itemBuilder: (context, index) {
                          final req = _pendingRequests[index];
                          final requestId = req['id'] as int;
                          final reference = req['reference'] as String? ?? '';
                          final centAmount = req['cent_amount'] as int? ?? 0;
                          final requestedAt = req['requested_at'] as String? ?? '';
                          final isProcessing = _actionInProgress[requestId] ?? false;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
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
                                  // Header: Reference & Amount
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          reference,
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: scheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '$centAmount Cent',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: scheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 12),

                                  // Request ID & Date
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerLowest,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.fingerprint_rounded, size: 14, color: scheme.onSurfaceVariant),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Request #$requestId',
                                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                  color: scheme.onSurfaceVariant,
                                                  fontFamily: 'monospace',
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(Icons.access_time_rounded, size: 14, color: scheme.onSurfaceVariant),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                _formatDate(requestedAt),
                                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                  color: scheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 14),

                                  // Action Buttons
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: isProcessing ? null : () => _approveRequest(requestId, centAmount),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.green,
                                          ),
                                          child: isProcessing
                                              ? const SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                                                )
                                              : const Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.check_rounded, size: 18),
                                                    SizedBox(width: 6),
                                                    Text('Approve'),
                                                  ],
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton.tonal(
                                          onPressed: isProcessing ? null : () => _rejectRequest(requestId),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.red.withOpacity(0.1),
                                            foregroundColor: Colors.red,
                                          ),
                                          child: isProcessing
                                              ? const SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.red)),
                                                )
                                              : const Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.close_rounded, size: 18),
                                                    SizedBox(width: 6),
                                                    Text('Reject'),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
