// lib/nai_mentor.dart
//
// NAI — NaijaLearn's persistent AI study companion.
//
// Two conversation modes exist:
//   1. Blueprint interview (legacy, unchanged) — the one-time onboarding
//      interview via NaiOnboardingGate, still uses nai_interviews.
//   2. Persistent chat (new) — NaiChatScreen, backed by nai_chat_messages,
//      reachable anytime, remembers everything via nai_student_memory +
//      nai_timetable_items + nai_study_sessions, all injected server-side
//      as STUDENT CONTEXT on every message.
//
// SECURITY NOTE: no function here ever sends a user_id to the Edge
// Function. The server derives the caller's identity from their actual
// Supabase Auth session (the JWT the Supabase client attaches to every
// functions.invoke call automatically) — this matches the Edge Function
// rewrite that scopes every database call to auth.uid() via RLS, so
// nothing here can act on another student's data even in theory.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show ZetraProfile, HomeScreen;
import 'zetra_pay.dart';

/// =========================================================================
/// BLUEPRINT SERVICE (legacy interview mode — unchanged)
/// =========================================================================

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
    if (_client.auth.currentUser == null) {
      throw Exception('Not signed in.');
    }
    final res = await _client.functions.invoke('nai-interview', body: {
      'blueprint_type': blueprintType,
      'requesting_app': 'naijalearn',
      'interview_id': interviewId,
      'message': message,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}

/// =========================================================================
/// PERSISTENT CHAT SERVICE (new)
/// =========================================================================

class NaiChatService {
  NaiChatService._();
  static final NaiChatService instance = NaiChatService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Loads recent chat history directly from the table (fast, no AI
  /// call) — used to restore the conversation when the screen opens.
  Future<List<ChatMessage>> loadHistory({int limit = 40}) async {
    final rows = await _client.rpc('nai_get_chat_history', params: {'p_limit': limit});
    return (rows as List)
        .map((r) => ChatMessage(role: r['role'] as String, content: r['content'] as String))
        .toList()
        .reversed
        .toList();
  }

  /// Sends a message in persistent chat mode. The server saves both the
  /// user's message and NAI's reply to nai_chat_messages automatically,
  /// injects the full STUDENT CONTEXT dashboard, and may silently run an
  /// action (save a timetable, log a session, etc.) before replying.
  Future<String> sendMessage(String message) async {
    final res = await _client.functions.invoke('nai-interview', body: {
      'mode': 'chat',
      'message': message,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return data['reply'] as String? ?? '...';
  }
}

/// =========================================================================
/// DASHBOARD (goal, exam countdown, streak, today's plan, timetable)
/// =========================================================================

class NaiDashboard {
  final String? goal;
  final String? targetScore;
  final String? examType;
  final DateTime? examDate;
  final int? daysToExam;
  final String? strongestSubject;
  final String? weakestSubject;
  final int dailyStudyMinutesTarget;
  final int todayScheduledMinutes;
  final int todayRemainingCapacityMinutes;
  final int currentStreakDays;
  final List<TimetableItem> todayItems;
  final List<TimetableItem> missedItems;
  final List<TimetableItem> upcomingItems;

  NaiDashboard({
    required this.goal,
    required this.targetScore,
    required this.examType,
    required this.examDate,
    required this.daysToExam,
    required this.strongestSubject,
    required this.weakestSubject,
    required this.dailyStudyMinutesTarget,
    required this.todayScheduledMinutes,
    required this.todayRemainingCapacityMinutes,
    required this.currentStreakDays,
    required this.todayItems,
    required this.missedItems,
    required this.upcomingItems,
  });

  factory NaiDashboard.fromMap(Map<String, dynamic> m) {
    List<TimetableItem> parseItems(dynamic raw) {
      if (raw == null) return [];
      return (raw as List).map((r) => TimetableItem.fromMap(Map<String, dynamic>.from(r as Map))).toList();
    }

    return NaiDashboard(
      goal: m['goal'] as String?,
      targetScore: m['target_score'] as String?,
      examType: m['exam_type'] as String?,
      examDate: m['exam_date'] != null ? DateTime.tryParse(m['exam_date'] as String) : null,
      daysToExam: (m['days_to_exam'] as num?)?.toInt(),
      strongestSubject: m['strongest_subject'] as String?,
      weakestSubject: m['weakest_subject'] as String?,
      dailyStudyMinutesTarget: (m['daily_study_minutes_target'] as num?)?.toInt() ?? 90,
      todayScheduledMinutes: (m['today_scheduled_minutes'] as num?)?.toInt() ?? 0,
      todayRemainingCapacityMinutes: (m['today_remaining_capacity_minutes'] as num?)?.toInt() ?? 0,
      currentStreakDays: (m['current_streak_days'] as num?)?.toInt() ?? 0,
      todayItems: parseItems(m['today_items']),
      missedItems: parseItems(m['missed_items']),
      upcomingItems: parseItems(m['upcoming_timetable']),
    );
  }
}

class TimetableItem {
  final int id;
  final DateTime? date;
  final String subject;
  final String topic;
  final int durationMinutes;
  final bool completed;

  TimetableItem({
    required this.id,
    required this.date,
    required this.subject,
    required this.topic,
    required this.durationMinutes,
    required this.completed,
  });

  factory TimetableItem.fromMap(Map<String, dynamic> m) => TimetableItem(
        id: (m['id'] as num).toInt(),
        date: m['item_date'] != null ? DateTime.tryParse(m['item_date'] as String) : null,
        subject: m['subject'] as String? ?? '',
        topic: m['topic'] as String? ?? '',
        durationMinutes: (m['duration_minutes'] as num?)?.toInt() ?? 30,
        completed: m['completed'] as bool? ?? false,
      );
}

class NaiDashboardService {
  NaiDashboardService._();
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<NaiDashboard?> load() async {
    if (_client.auth.currentUser == null) return null;
    final result = await _client.rpc('nai_get_dashboard');
    return NaiDashboard.fromMap(Map<String, dynamic>.from(result as Map));
  }

  static Future<void> markComplete(int itemId, bool completed) async {
    await _client.rpc('nai_mark_timetable_item', params: {'p_id': itemId, 'p_completed': completed});
  }

  static Future<void> moveItem(int itemId, DateTime newDate) async {
    await _client.rpc('nai_move_timetable_item', params: {
      'p_id': itemId,
      'p_new_date': newDate.toIso8601String().split('T').first,
    });
  }

  static Future<void> deleteItem(int itemId) async {
    await _client.rpc('nai_delete_timetable_item', params: {'p_id': itemId});
  }
}

/// =========================================================================
/// PAYWALL (unchanged pricing — applies to both chat and interview modes)
/// =========================================================================

class NaiWallet {
  NaiWallet._();
  static SupabaseClient get _client => Supabase.instance.client;

  static const int singleMessagePriceCent = 1;
  static const int packOf15PriceCent = 10;
  static const int packOf15Credits = 15;
  static const int dayPassPriceCent = 1000;

  static Future<bool> tryConsumeCredit() async {
    final result = await _client.rpc('nai_consume_message_credit');
    return result == true;
  }

  static Future<String?> buySingleMessage() async {
    final err = await ZetraPay.spendAppCurrency(appId: ZetraPay.naijaLearnAppId, unitAmount: singleMessagePriceCent.toDouble());
    if (err != null) return err;
    await _client.rpc('nai_grant_message_credits', params: {'p_credits': 1});
    return null;
  }

  static Future<String?> buyFifteenPack() async {
    final err = await ZetraPay.spendAppCurrency(appId: ZetraPay.naijaLearnAppId, unitAmount: packOf15PriceCent.toDouble());
    if (err != null) return err;
    await _client.rpc('nai_grant_message_credits', params: {'p_credits': packOf15Credits});
    return null;
  }

  static Future<String?> buyDayPass() async {
    final err = await ZetraPay.spendAppCurrency(appId: ZetraPay.naijaLearnAppId, unitAmount: dayPassPriceCent.toDouble());
    if (err != null) return err;
    await _client.rpc('nai_grant_day_pass');
    return null;
  }
}

class ChatMessage {
  final String role;
  final String content;
  ChatMessage({required this.role, required this.content});
}

Future<void> _showNaiPaywall(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: BoxDecoration(
          color: Theme.of(sheetContext).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Keep chatting with NAI', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text("You're out of messages. Top up to continue."),
            const SizedBox(height: 20),
            _PaywallOption(
              title: '1 Message',
              price: '1¢',
              onTap: () async {
                Navigator.pop(sheetContext);
                final err = await NaiWallet.buySingleMessage();
                if (err != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              },
            ),
            const SizedBox(height: 10),
            _PaywallOption(
              title: '15 Messages',
              price: '10¢',
              subtitle: 'Best value',
              highlight: true,
              onTap: () async {
                Navigator.pop(sheetContext);
                final err = await NaiWallet.buyFifteenPack();
                if (err != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              },
            ),
            const SizedBox(height: 10),
            _PaywallOption(
              title: 'Unlimited Today',
              price: '1 CP',
              subtitle: '24 hours, no limits',
              onTap: () async {
                Navigator.pop(sheetContext);
                final err = await NaiWallet.buyDayPass();
                if (err != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              },
            ),
          ],
        ),
      );
    },
  );
}

class _PaywallOption extends StatelessWidget {
  final String title;
  final String price;
  final String? subtitle;
  final bool highlight;
  final VoidCallback onTap;
  const _PaywallOption({required this.title, required this.price, this.subtitle, this.highlight = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: highlight ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Text(price, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// PERSISTENT CHAT SCREEN (the main NAI Mentor experience)
/// =========================================================================

class NaiChatScreen extends StatefulWidget {
  const NaiChatScreen({super.key});

  @override
  State<NaiChatScreen> createState() => _NaiChatScreenState();
}

class _NaiChatScreenState extends State<NaiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loadingHistory = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await NaiChatService.instance.loadHistory();
      if (!mounted) return;
      setState(() {
        _messages.addAll(history);
        _loadingHistory = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
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

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;

    final allowed = await NaiWallet.tryConsumeCredit();
    if (!allowed) {
      await _showNaiPaywall(context);
      return;
    }

    setState(() {
      _sending = true;
      _messages.add(ChatMessage(role: 'user', content: text));
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final reply = await NaiChatService.instance.sendMessage(text);
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(role: 'assistant', content: reply)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage(role: 'assistant', content: 'Sorry, something went wrong. Please try again.')));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NAI Mentor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: 'My Timetable',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NaiTimetableScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadingHistory
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            "Hi! I'm NAI, your study companion. Tell me your goal, ask what to study today, or just say hello.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_sending ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
                              child: Text(msg.content, style: TextStyle(color: isUser ? scheme.onPrimary : scheme.onSurface, height: 1.4)),
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('1¢ per message · 15 for 10¢ · 1 CP for unlimited today',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
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
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: 'Ask NAI anything...',
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

/// =========================================================================
/// DASHBOARD CARD — embed on Home tab
/// =========================================================================

class NaiDashboardCard extends StatefulWidget {
  const NaiDashboardCard({super.key});

  @override
  State<NaiDashboardCard> createState() => _NaiDashboardCardState();
}

class _NaiDashboardCardState extends State<NaiDashboardCard> {
  NaiDashboard? _dashboard;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await NaiDashboardService.load();
      if (mounted) setState(() {
        _dashboard = d;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final d = _dashboard;
    if (d == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    final hasAnything = d.goal != null || d.todayItems.isNotEmpty || d.currentStreakDays > 0;
    if (!hasAnything) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NaiChatScreen())),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 6),
                    const Text('NAI Mentor', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (d.currentStreakDays > 0)
                      Row(children: [
                        const Icon(Icons.local_fire_department_rounded, size: 16, color: Colors.deepOrange),
                        Text(' ${d.currentStreakDays}d', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                  ],
                ),
                if (d.daysToExam != null) ...[
                  const SizedBox(height: 6),
                  Text('${d.examType ?? 'Exam'} in ${d.daysToExam} days', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 10),
                if (d.todayItems.isEmpty)
                  Text("No plan for today yet — ask NAI what to study.", style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))
                else
                  ...d.todayItems.take(3).map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(item.completed ? Icons.check_circle_rounded : Icons.circle_outlined,
                                size: 16, color: item.completed ? Colors.green : scheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('${item.subject}${item.topic.isNotEmpty ? ' — ${item.topic}' : ''} (${item.durationMinutes}m)',
                                  style: const TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// TIMETABLE SCREEN
/// =========================================================================

class NaiTimetableScreen extends StatefulWidget {
  const NaiTimetableScreen({super.key});

  @override
  State<NaiTimetableScreen> createState() => _NaiTimetableScreenState();
}

class _NaiTimetableScreenState extends State<NaiTimetableScreen> {
  NaiDashboard? _dashboard;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await NaiDashboardService.load();
    if (mounted) setState(() {
      _dashboard = d;
      _loading = false;
    });
  }

  Future<void> _toggle(TimetableItem item) async {
    await NaiDashboardService.markComplete(item.id, !item.completed);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Timetable')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dashboard == null
              ? const Center(child: Text('Could not load your timetable.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_dashboard!.missedItems.isNotEmpty) ...[
                        _SectionHeader(title: 'Missed', color: Colors.red),
                        ..._dashboard!.missedItems.map((i) => _TimetableTile(item: i, onToggle: () => _toggle(i))),
                        const SizedBox(height: 16),
                      ],
                      _SectionHeader(title: 'Today', color: Theme.of(context).colorScheme.primary),
                      if (_dashboard!.todayItems.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nothing scheduled — ask NAI to plan your day.')),
                      ..._dashboard!.todayItems.map((i) => _TimetableTile(item: i, onToggle: () => _toggle(i))),
                      const SizedBox(height: 16),
                      _SectionHeader(title: 'Upcoming', color: Colors.grey),
                      if (_dashboard!.upcomingItems.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nothing scheduled yet.')),
                      ..._dashboard!.upcomingItems.map((i) => _TimetableTile(item: i, onToggle: () => _toggle(i), showDate: true)),
                    ],
                  ),
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
    );
  }
}

class _TimetableTile extends StatelessWidget {
  final TimetableItem item;
  final VoidCallback onToggle;
  final bool showDate;
  const _TimetableTile({required this.item, required this.onToggle, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: item.completed,
        onChanged: (_) => onToggle(),
        title: Text('${item.subject}${item.topic.isNotEmpty ? ' — ${item.topic}' : ''}'),
        subtitle: Text(
          showDate && item.date != null
              ? '${item.date!.day}/${item.date!.month} · ${item.durationMinutes} min'
              : '${item.durationMinutes} min',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// =========================================================================
/// LEGACY: NAI Mentor onboarding interview screen (Blueprint mode)
/// =========================================================================

class NaiMentorScreen extends StatefulWidget {
  final String blueprintType;
  final VoidCallback? onDone;
  final bool freeMode;
  const NaiMentorScreen({super.key, this.blueprintType = 'academic', this.onDone, this.freeMode = false});

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
    _send(null, chargeable: false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String? userText, {bool chargeable = true}) async {
    if (userText != null && userText.trim().isEmpty) return;

    if (chargeable && !widget.freeMode) {
      final allowed = await NaiWallet.tryConsumeCredit();
      if (!allowed) {
        await _showNaiPaywall(context);
        return;
      }
    }

    setState(() {
      _sending = true;
      if (userText != null) _messages.add(ChatMessage(role: 'user', content: userText));
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
      setState(() => _messages.add(ChatMessage(role: 'assistant', content: 'Sorry, something went wrong. Please try again.')));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NAI Mentor'),
        actions: [if (widget.onDone != null) TextButton(onPressed: widget.onDone, child: const Text('Continue to NaijaLearn'))],
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
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
                    child: Text(msg.content, style: TextStyle(color: isUser ? scheme.onPrimary : scheme.onSurface, height: 1.4)),
                  ),
                );
              },
            ),
          ),
          if (!widget.freeMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('1¢ per message · 15 for 10¢ · 1 CP for unlimited today', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
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
                  IconButton.filled(onPressed: _sending ? null : () => _send(_controller.text), icon: const Icon(Icons.send_rounded)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =========================================================================
/// ONBOARDING GATE (unchanged from before)
/// =========================================================================

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
    final isNewAccount = createdAtStr != null && (DateTime.tryParse(createdAtStr)?.isAfter(_naiRolloutCutoff) ?? false);
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
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {_onboardingSeenKey: true}));
    } catch (_) {}
    _goHome();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(profile: widget.profile)));
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return NaiMentorScreen(blueprintType: 'academic', onDone: _markSeenAndContinue, freeMode: true);
  }
}
