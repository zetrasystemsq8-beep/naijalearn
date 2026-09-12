// lib/classroom_chat_widget.dart
//
// Shared chat UI for a classroom. Polls on open + pull-to-refresh —
// no Supabase Realtime subscription yet (see QUESTIONS_FOR_TEAM.md #5).
// isTutor controls moderation controls (remove message).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClassroomChatWidget extends StatefulWidget {
  final int classroomId;
  final bool isTutor;
  const ClassroomChatWidget({super.key, required this.classroomId, required this.isTutor});

  @override
  State<ClassroomChatWidget> createState() => _ClassroomChatWidgetState();
}

class _ClassroomChatWidgetState extends State<ClassroomChatWidget> {
  final _client = Supabase.instance.client;
  final _messageController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _client
          .from('classroom_messages')
          .select()
          .eq('classroom_id', widget.classroomId)
          .order('created_at', ascending: true)
          .limit(200);
      setState(() => _messages = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Silent — pull to refresh again.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      await _client.from('classroom_messages').insert({
        'classroom_id': widget.classroomId,
        'sender_id': _client.auth.currentUser!.id,
        'message': text,
      });
      _messageController.clear();
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _removeMessage(int messageId) async {
    try {
      await _client.from('classroom_messages').update({
        'is_removed': true,
        'removed_by': _client.auth.currentUser!.id,
      }).eq('id', messageId);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove message.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final myId = _client.auth.currentUser?.id;

    return Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _messages.isEmpty
                      ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No messages yet')))])
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isMe = msg['sender_id'] == myId;
                            final removed = msg['is_removed'] as bool;

                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                decoration: BoxDecoration(
                                  color: isMe ? scheme.primary : scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      removed ? '[Message removed]' : msg['message'] as String,
                                      style: TextStyle(
                                        color: isMe ? Colors.white : scheme.onSurface,
                                        fontStyle: removed ? FontStyle.italic : FontStyle.normal,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          DateFormat('h:mm a').format(DateTime.parse(msg['created_at'])),
                                          style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : scheme.onSurfaceVariant),
                                        ),
                                        if (widget.isTutor && !removed) ...[
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => _removeMessage(msg['id'] as int),
                                            child: Icon(Icons.delete_outline_rounded, size: 14, color: isMe ? Colors.white70 : scheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Message the class...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
