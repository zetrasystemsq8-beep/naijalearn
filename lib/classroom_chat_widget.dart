// lib/classroom_chat_widget.dart
//
// Shared chat UI for a classroom. Polls on open + pull-to-refresh —
// no Supabase Realtime subscription yet (see QUESTIONS_FOR_TEAM.md #5).
// isTutor controls moderation controls (remove message).
//
// v2: reply-to quoting, image sharing (private per-classroom bucket),
// lightweight read receipts ("Seen by N" on your own latest message
// only — not per message, to stay cheap at any volume), and grouped
// bubble styling (name shown only when the sender changes).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  final _scrollController = ScrollController();
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _messages = [];
  Map<String, String> _usernames = {};
  Map<int, int> _seenCounts = {}; // message_id -> count of others who've read up to here
  bool _loading = true;
  bool _sending = false;
  Map<String, dynamic>? _replyingTo;
  XFile? _pendingImage;

  String? get _myId => _client.auth.currentUser?.id;

  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
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
      });

      await _markRead();
      await _loadSeenCounts();
      _scrollToBottom();
    } catch (_) {
      // Silent — pull to refresh again.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead() async {
    final myId = _myId;
    if (myId == null || _messages.isEmpty) return;
    try {
      await _client.from('classroom_chat_read_state').upsert({
        'classroom_id': widget.classroomId,
        'user_id': myId,
        'last_read_message_id': _messages.last['id'],
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Non-fatal — read receipts just won't be perfectly accurate.
    }
  }

  Future<void> _loadSeenCounts() async {
    final myId = _myId;
    if (myId == null) return;
    // Only my own most recent message needs a seen count.
    final myMessages = _messages.where((m) => m['sender_id'] == myId).toList();
    if (myMessages.isEmpty) return;
    final latestMineId = myMessages.last['id'] as int;

    try {
      final rows = await _client
          .from('classroom_chat_read_state')
          .select('user_id, last_read_message_id')
          .eq('classroom_id', widget.classroomId);
      final count = (rows as List).where((r) => r['user_id'] != myId && (r['last_read_message_id'] as int?) != null && (r['last_read_message_id'] as int) >= latestMineId).length;
      if (mounted) setState(() => _seenCounts = {latestMineId: count});
    } catch (_) {
      // Non-fatal.
    }
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 70);
    if (file != null && mounted) setState(() => _pendingImage = file);
  }

  Future<String?> _uploadImageIfNeeded() async {
    if (_pendingImage == null) return null;
    final myId = _myId!;
    final ext = _pendingImage!.path.split('.').last.toLowerCase();
    final safeExt = ['jpg', 'jpeg', 'png'].contains(ext) ? ext : 'jpg';
    final path = '${widget.classroomId}/$myId/${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final bytes = await _pendingImage!.readAsBytes();

    await _client.storage.from('classroom-chat-media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: safeExt == 'png' ? 'image/png' : 'image/jpeg'),
        );
    return path;
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _pendingImage == null) return;

    setState(() => _sending = true);
    try {
      final imagePath = await _uploadImageIfNeeded();

      await _client.from('classroom_messages').insert({
        'classroom_id': widget.classroomId,
        'sender_id': _myId,
        'message': text.isEmpty ? '📷 Photo' : text,
        'reply_to_id': _replyingTo?['id'],
        'image_path': imagePath,
      });

      _messageController.clear();
      setState(() {
        _replyingTo = null;
        _pendingImage = null;
      });
      await _load();
      _scrollToBottom(animated: true);
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
        'removed_by': _myId,
      }).eq('id', messageId);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove message.')));
      }
    }
  }

  Map<String, dynamic>? _findMessageById(int? id) {
    if (id == null) return null;
    for (final m in _messages) {
      if (m['id'] == id) return m;
    }
    return null;
  }

  void _startReply(Map<String, dynamic> message) {
    setState(() => _replyingTo = message);
  }

  Future<String?> _signedImageUrl(String path) async {
    try {
      return await _client.storage.from('classroom-chat-media').createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isMe = msg['sender_id'] == _myId;
                            final removed = msg['is_removed'] as bool;
                            final senderName = _usernames[msg['sender_id']] ?? 'Student';

                            // Group: only show the name label when the sender
                            // changes from the previous message.
                            final prev = index > 0 ? _messages[index - 1] : null;
                            final showName = !isMe && (prev == null || prev['sender_id'] != msg['sender_id']);
                            final tightTop = prev != null && prev['sender_id'] == msg['sender_id'];

                            final replyTarget = _findMessageById(msg['reply_to_id'] as int?);
                            final imagePath = msg['image_path'] as String?;
                            final isMyLatest = isMe && msg['id'] == (_messages.where((m) => m['sender_id'] == _myId).isNotEmpty ? _messages.where((m) => m['sender_id'] == _myId).last['id'] : null);
                            final seenCount = _seenCounts[msg['id']] ?? 0;

                            return GestureDetector(
                              onLongPress: removed ? null : () => _startReply(msg),
                              child: Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Column(
                                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    if (showName)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4, bottom: 2, top: 6),
                                        child: Text(senderName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                                      ),
                                    Container(
                                      margin: EdgeInsets.only(top: tightTop ? 2 : 8, bottom: 2),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                      decoration: BoxDecoration(
                                        color: isMe ? scheme.primary : scheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (replyTarget != null)
                                            Container(
                                              margin: const EdgeInsets.only(bottom: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: (isMe ? Colors.white : scheme.primary).withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border(left: BorderSide(color: isMe ? Colors.white70 : scheme.primary, width: 3)),
                                              ),
                                              child: Text(
                                                (replyTarget['is_removed'] as bool) ? '[Message removed]' : replyTarget['message'] as String,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(fontSize: 12, color: isMe ? Colors.white70 : scheme.onSurfaceVariant),
                                              ),
                                            )
                                          else if (msg['reply_to_id'] != null)
                                            Container(
                                              margin: const EdgeInsets.only(bottom: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              decoration: BoxDecoration(color: (isMe ? Colors.white : scheme.primary).withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                                              child: Text('Original message unavailable', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: isMe ? Colors.white70 : scheme.onSurfaceVariant)),
                                            ),
                                          if (imagePath != null && !removed)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 6),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(10),
                                                child: FutureBuilder<String?>(
                                                  future: _signedImageUrl(imagePath),
                                                  builder: (context, snap) {
                                                    if (!snap.hasData) {
                                                      return Container(width: 180, height: 140, color: Colors.black12, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
                                                    }
                                                    return Image.network(snap.data!, width: 200, fit: BoxFit.cover);
                                                  },
                                                ),
                                              ),
                                            ),
                                          if (removed || (msg['message'] as String).isNotEmpty && (msg['message'] != '📷 Photo' || imagePath == null))
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
                                    if (isMyLatest && seenCount > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 4, bottom: 4),
                                        child: Text('Seen by $seenCount', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
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
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Container(width: 3, height: 28, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Replying to: ${(_replyingTo!['is_removed'] as bool) ? '[Message removed]' : _replyingTo!['message']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                GestureDetector(onTap: () => setState(() => _replyingTo = null), child: const Icon(Icons.close_rounded, size: 16)),
              ],
            ),
          ),

        if (_pendingImage != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_pendingImage!.path), width: 44, height: 44, fit: BoxFit.cover)),
                const SizedBox(width: 8),
                const Expanded(child: Text('Photo attached', style: TextStyle(fontSize: 12))),
                GestureDetector(onTap: () => setState(() => _pendingImage = null), child: const Icon(Icons.close_rounded, size: 16)),
              ],
            ),
          ),

        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(onPressed: _sending ? null : _pickImage, icon: const Icon(Icons.image_outlined)),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Message the class...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
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
