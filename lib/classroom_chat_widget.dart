// lib/classroom_chat_widget.dart
//
// Shared chat UI for a classroom. Polls on open + pull-to-refresh —
// no Supabase Realtime subscription yet (see QUESTIONS_FOR_TEAM.md #5).
// isTutor controls moderation controls (remove message).
//
// Adds: reply-to-message (long-press a bubble to reply, shows a quoted
// preview) and lightweight @mention highlighting (text only — no
// autocomplete/notify yet, that's a separate feature needing a mentions
// table + push).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'classroom_shared.dart' show loadUsernames;

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
  Map<String, String> _usernames = {};
  Map<int, dynamic> _messagesById = {};
  bool _loading = true;
  bool _sending = false;
  Map<String, dynamic>? _replyingTo;

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
      final messages = List<Map<String, dynamic>>.from(rows);
      final usernames = await loadUsernames(messages.map((m) => m['sender_id'] as String).toList());
      setState(() {
        _messages = messages;
        _usernames = usernames;
        _messagesById = {for (final m in messages) m['id'] as int: m};
      });
    } catch (_) {
      // Silent — pull to refresh again.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startReply(Map<String, dynamic> msg) {
    setState(() => _replyingTo = msg);
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
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
        if (_replyingTo != null) 'reply_to_id': _replyingTo!['id'],
      });
      _messageController.clear();
      _replyingTo = null;
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

  // Splits message text into plain-text and @mention spans for rendering.
  List<InlineSpan> _buildMessageSpans(String text, {required Color baseColor, required Color mentionColor}) {
    final regex = RegExp(r'(@[a-zA-Z0-9_]+)');
    final spans = <InlineSpan>[];
    int last = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(color: mentionColor, fontWeight: FontWeight.w700),
      ));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return spans;
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
                            final senderName = _usernames[msg['sender_id']] ?? 'Student';

                            final replyToId = msg['reply_to_id'] as int?;
                            final parent = replyToId != null ? _messagesById[replyToId] : null;
                            final parentSenderName = parent != null ? (_usernames[parent['sender_id']] ?? 'Student') : null;
                            final parentText = parent != null
                                ? ((parent['is_removed'] as bool) ? '[Message removed]' : (parent['message'] as String))
                                : null;

                            final bubbleColor = isMe ? scheme.primary : scheme.surfaceContainerHighest;
                            final textColor = isMe ? Colors.white : scheme.onSurface;
                            final mentionColor = isMe ? Colors.amber.shade100 : scheme.primary;

                            return GestureDetector(
                              onLongPress: removed ? null : () => _startReply(msg),
                              child: Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Column(
                                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    if (!isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                                        child: Text(senderName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                                      ),
                                    Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                      decoration: BoxDecoration(
                                        color: bubbleColor,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (parentText != null)
                                            Container(
                                              margin: const EdgeInsets.only(bottom: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: (isMe ? Colors.white : scheme.primary).withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border(left: BorderSide(color: isMe ? Colors.white70 : scheme.primary, width: 3)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(parentSenderName ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor.withOpacity(0.85))),
                                                  const SizedBox(height: 2),
                                                  Text(parentText, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.75))),
                                                ],
                                              ),
                                            ),
                                          removed
                                              ? Text('[Message removed]', style: TextStyle(color: textColor, fontStyle: FontStyle.italic))
                                              : RichText(
                                                  text: TextSpan(
                                                    style: TextStyle(color: textColor, fontSize: 14.5),
                                                    children: _buildMessageSpans(msg['message'] as String, baseColor: textColor, mentionColor: mentionColor),
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
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
        if (_replyingTo != null)
          Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: scheme.primary, width: 3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Replying to ${_usernames[_replyingTo!['sender_id']] ?? 'Student'}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (_replyingTo!['is_removed'] as bool) ? '[Message removed]' : (_replyingTo!['message'] as String),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: _cancelReply, visualDensity: VisualDensity.compact),
              ],
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
