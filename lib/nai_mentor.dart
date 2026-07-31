// lib/nai_mentor.dart
//
// NAI Mentor — the interview/Blueprint chat screen inside NaijaLearn.
// Talks to the 'nai-interview' Supabase Edge Function. Only reachable by
// signed-in Zetra users (guests never see this entry point).
//
// NaiOnboardingGate is a one-time interstitial shown right after a NEW
// account verifies (accounts created after _naiRolloutCutoff only —
// existing users are never shown this). It checks for an existing
// Academic Blueprint first, and marks itself "seen" via Supabase Auth
// user metadata so it never reappears once dismissed.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show ZetraProfile, HomeScreen;

class NaiBlueprintService {
  NaiBlueprintService._();
  static final NaiBlueprintService instance = NaiBlueprintService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<Map<String, dynamic>?> getActiveBlueprint(String type) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return await _client
        .from('blueprints')
        .select()
        .eq('user_id', user.id)
        .eq('blueprint_type', type)
        .eq('status', 'active')
        .maybeSingle();
  }

  Future<Map<String, dynamic>> sendInterviewMessage({
    String? interviewId,
    required String blueprintType,
    String? message,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in.');
    }
    final res = await _client.functions.invoke('nai-interview', body: {
      'user_id': user.id,
      'blueprint_type': blueprintType,
      'requesting_app': 'naijalearn',
      'interview_id': interviewId,
      'message': message,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  ChatMessage({required this.role, required this.content});
}

class NaiMentorScreen extends StatefulWidget {
  final String blueprintType; // 'academic', 'career', etc.
  final VoidCallback? onDone; // if set, shows a "Continue" button (onboarding mode)
  const NaiMentorScreen({super.key, this.blueprintType = 'academic', this.onDone});

  @override
  State<NaiMentorScreen> createState() => _NaiMentorScreenState();
}

class _NaiMentorScreenState extends State<NaiMentorScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  String? _interviewId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _send(null);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String? userText) async {
    if (userText != null && userText.trim().isEmpty) return;

    setState(() {
      _sending = true;
      if (userText != null) {
        _messages.add(ChatMessage(role: 'user', content: userText));
      }
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final result = await NaiBlueprintService.instance.sendInterviewMessage(
        interviewId: _interviewId,
        blueprintType: widget.blueprintType,
        message: userText,
      );
      if (!mounted) return;
      setState(() {
        _interviewId = result['interview_id']?.toString();
        _messages.add(ChatMessage(role: 'assistant', content: result['reply'] as String? ?? '...'));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(role: 'assistant', content: 'Sorry, something went wrong. Please try again.'));
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NAI Mentor'),
        actions: [
          if (widget.onDone != null)
            TextButton(
              onPressed: widget.onDone,
              child: const Text('Continue to NaijaLearn'),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final msg = _messages[index];
                final isUser = msg.role == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      msg.content,
                      style: TextStyle(color: isUser ? scheme.onPrimary : scheme.onSurface, height: 1.4),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) => _send(v),
                      decoration: InputDecoration(
                        hintText: 'Type your answer...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(_controller.text),
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One-time onboarding gate shown right after signup verification.
/// Only shown to accounts created AFTER _naiRolloutCutoff — existing
/// users never see this, per product decision. Also skipped if the
/// user already has an Academic Blueprint, or already dismissed this
/// once before (tracked via Supabase Auth user metadata).
class NaiOnboardingGate extends StatefulWidget {
  final ZetraProfile profile;
  const NaiOnboardingGate({super.key, required this.profile});

  @override
  State<NaiOnboardingGate> createState() => _NaiOnboardingGateState();
}

class _NaiOnboardingGateState extends State<NaiOnboardingGate> {
  static final DateTime _naiRolloutCutoff = DateTime.parse('2026-07-31T00:00:00Z');
  static const String _onboardingSeenKey = 'nl_nai_onboarding_seen';

  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final user = Supabase.instance.client.auth.currentUser;
    final createdAtStr = user?.createdAt;
    final isNewAccount = createdAtStr != null &&
        (DateTime.tryParse(createdAtStr)?.isAfter(_naiRolloutCutoff) ?? false);
    final alreadySeen = user?.userMetadata?[_onboardingSeenKey] == true;

    if (!isNewAccount || alreadySeen) {
      _goHome();
      return;
    }

    final blueprint = await NaiBlueprintService.instance.getActiveBlueprint('academic');
    if (blueprint != null) {
      _goHome();
      return;
    }

    if (mounted) setState(() => _checking = false);
  }

  Future<void> _markSeenAndContinue() async {
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {_onboardingSeenKey: true}),
      );
    } catch (_) {}
    _goHome();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(profile: widget.profile)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return NaiMentorScreen(blueprintType: 'academic', onDone: _markSeenAndContinue);
  }
}
