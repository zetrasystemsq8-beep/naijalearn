// lib/features5.dart
//
// Five new features bundled together so main.dart only needs one import:
// 1. Flashcards + Spaced Repetition (Supabase-backed)
// 2. Coin Shop (Supabase-backed): Daily Login Bonus, Streak Freeze,
//    equippable Avatar Frames, equippable Titles, and an activatable
//    Ocean Theme — all now actually functional, not just cosmetic
//    placeholders.
// 3. Spin Wheel Rewards (spends into Coin Shop, awards XP via AppProvider)
//    — "already spun today" is now persisted via CoinService instead of
//    a static in-memory variable, so it survives app restarts.
// 4. Multi-Exam Countdown (Supabase-backed, tracks several exams at once)
// 5. Topic Mastery Tracker (Supabase-backed) + Focus Mode
//
// Each feature has its own lightweight ChangeNotifier service so state is
// shared and reactive across screens. Register CoinService, FlashcardService,
// MasteryService, and ExamCountdownService as providers in main() alongside
// AppProvider.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_enhancements.dart';

/// =========================================================================
/// 1. FLASHCARDS + SPACED REPETITION
/// =========================================================================

class Flashcard {
  final String id;
  final String subject;
  final String front;
  final String back;
  int boxLevel; // 1 (new/hard) through 5 (mastered) — Leitner system
  DateTime nextReview;

  Flashcard({
    required this.id,
    required this.subject,
    required this.front,
    required this.back,
    this.boxLevel = 1,
    DateTime? nextReview,
  }) : nextReview = nextReview ?? DateTime.now();

  static const Map<int, int> _intervalDays = {1: 0, 2: 1, 3: 3, 4: 7, 5: 14};

  void markCorrect() {
    boxLevel = (boxLevel + 1).clamp(1, 5);
    nextReview = DateTime.now().add(Duration(days: _intervalDays[boxLevel] ?? 0));
  }

  void markWrong() {
    boxLevel = 1;
    nextReview = DateTime.now();
  }

  bool get isDue => !nextReview.isAfter(DateTime.now());
}

class FlashcardService extends ChangeNotifier {
  FlashcardService._() {
    _init();
  }
  static final FlashcardService instance = FlashcardService._();

  SupabaseClient get _client => Supabase.instance.client;

  final List<Flashcard> _cards = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<Flashcard> get all => List.unmodifiable(_cards);

  List<Flashcard> forSubject(String subject) =>
      _cards.where((c) => c.subject == subject).toList();

  List<Flashcard> dueForSubject(String subject) =>
      _cards.where((c) => c.subject == subject && c.isDue).toList();

  List<String> get subjectsWithCards =>
      _cards.map((c) => c.subject).toSet().toList()..sort();

  Future<void> _init() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      final rows = await _client.from('flashcards').select().eq('user_id', user.id);
      _cards
        ..clear()
        ..addAll((rows as List<dynamic>).map((r) {
          final row = r as Map<String, dynamic>;
          return Flashcard(
            id: row['id'] as String,
            subject: row['subject'] as String,
            front: row['front'] as String,
            back: row['back'] as String,
            boxLevel: (row['box_level'] as num?)?.toInt() ?? 1,
            nextReview: DateTime.tryParse(row['next_review'] as String? ?? '') ?? DateTime.now(),
          );
        }));
    } catch (e) {
      debugPrint('[FlashcardService] init failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> addCard({required String subject, required String front, required String back}) async {
    final user = _client.auth.currentUser;
    final tempId = 'fc_local_${DateTime.now().microsecondsSinceEpoch}';
    final card = Flashcard(id: tempId, subject: subject, front: front, back: back);
    _cards.add(card);
    notifyListeners();

    if (user == null) return;
    try {
      final row = await _client.from('flashcards').insert({
        'user_id': user.id,
        'subject': subject,
        'front': front,
        'back': back,
        'box_level': 1,
        'next_review': DateTime.now().toIso8601String(),
      }).select().single();

      final idx = _cards.indexWhere((c) => c.id == tempId);
      if (idx != -1) {
        _cards[idx] = Flashcard(
          id: row['id'] as String,
          subject: subject,
          front: front,
          back: back,
          boxLevel: 1,
          nextReview: card.nextReview,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[FlashcardService] addCard failed: $e');
    }
  }

  Future<void> deleteCard(String id) async {
    _cards.removeWhere((c) => c.id == id);
    notifyListeners();
    try {
      await _client.from('flashcards').delete().eq('id', id);
    } catch (e) {
      debugPrint('[FlashcardService] deleteCard failed: $e');
    }
  }

  Future<void> recordResult(Flashcard card, bool correct) async {
    if (correct) {
      card.markCorrect();
    } else {
      card.markWrong();
    }
    notifyListeners();
    try {
      await _client.from('flashcards').update({
        'box_level': card.boxLevel,
        'next_review': card.nextReview.toIso8601String(),
      }).eq('id', card.id);
    } catch (e) {
      debugPrint('[FlashcardService] recordResult push failed: $e');
    }
  }
}

class FlashcardsScreen extends StatelessWidget {
  const FlashcardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<FlashcardService>();

    if (!service.isLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Flashcards')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final subjects = service.subjectsWithCards;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flashcards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add flashcard',
            onPressed: () => _showAddCardDialog(context),
          ),
        ],
      ),
      body: subjects.isEmpty
          ? const _EmptyState(
              icon: Icons.style_rounded,
              title: 'No flashcards yet',
              subtitle: 'Tap + to create your first flashcard.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: subjects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final subject = subjects[index];
                final total = service.forSubject(subject).length;
                final due = service.dueForSubject(subject).length;
                return Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    title: Text(subject, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('$total cards • $due due for review'),
                    trailing: FilledButton(
                      onPressed: due == 0
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => FlashcardReviewScreen(subject: subject),
                                ),
                              ),
                      child: const Text('Review'),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showAddCardDialog(BuildContext context) {
    final subjectController = TextEditingController();
    final frontController = TextEditingController();
    final backController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Flashcard'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: frontController,
                decoration: const InputDecoration(labelText: 'Front (question)'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: backController,
                decoration: const InputDecoration(labelText: 'Back (answer)'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (subjectController.text.trim().isEmpty || frontController.text.trim().isEmpty) return;
              FlashcardService.instance.addCard(
                subject: subjectController.text.trim(),
                front: frontController.text.trim(),
                back: backController.text.trim(),
              );
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class FlashcardReviewScreen extends StatefulWidget {
  final String subject;
  const FlashcardReviewScreen({super.key, required this.subject});

  @override
  State<FlashcardReviewScreen> createState() => _FlashcardReviewScreenState();
}

class _FlashcardReviewScreenState extends State<FlashcardReviewScreen> {
  late List<Flashcard> _queue;
  int _index = 0;
  bool _showBack = false;
  int _correctCount = 0;

  @override
  void initState() {
    super.initState();
    _queue = FlashcardService.instance.dueForSubject(widget.subject);
  }

  void _answer(bool correct) {
    FlashcardService.instance.recordResult(_queue[_index], correct);
    if (correct) _correctCount++;
    if (_index < _queue.length - 1) {
      setState(() {
        _index++;
        _showBack = false;
      });
    } else {
      _finish();
    }
  }

  void _finish() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review Complete'),
        content: Text('You got $_correctCount out of ${_queue.length} correct.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('${widget.subject} Review')),
        body: const Center(child: Text('No cards due for review right now.')),
      );
    }

    final card = _queue[_index];
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.subject} Review')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            LinearProgressIndicator(value: _index / _queue.length),
            const SizedBox(height: 8),
            Text('Card ${_index + 1} of ${_queue.length}'),
            const SizedBox(height: 24),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showBack = !_showBack),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Center(
                    child: SingleChildScrollView(
                      child: Text(
                        _showBack ? card.back : card.front,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(_showBack ? 'Tap card to see question' : 'Tap card to reveal answer',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            if (_showBack)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _answer(false),
                      icon: const Icon(Icons.close_rounded, color: Colors.red),
                      label: const Text('Got it wrong'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _answer(true),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Got it right'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// 2. COIN SHOP + DAILY LOGIN BONUS + STREAK FREEZE + EQUIPPABLE ITEMS
/// =========================================================================

class ShopItem {
  final String id;
  final String name;
  final String emoji;
  final int cost;
  final String category; // 'frame' | 'title' | 'theme' | 'consumable'
  final String usefulness;
  const ShopItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.cost,
    required this.category,
    required this.usefulness,
  });
}

class CoinService extends ChangeNotifier {
  CoinService._() {
    _init();
  }
  static final CoinService instance = CoinService._();

  SupabaseClient get _client => Supabase.instance.client;

  static const int _dailyLoginBonusCoins = 15;

  int _coins = 0;
  int _streakFreezeCount = 0;
  final Set<String> _ownedItemIds = {};
  String? _equippedFrameId;
  String? _equippedTitleId;
  bool _oceanThemeActive = false;
  String? _lastLoginBonusDate;
  String? _lastSpinDate;
  int? _pendingLoginBonusCoins;
  bool _loaded = false;

  int get coins => _coins;
  int get streakFreezeCount => _streakFreezeCount;
  Set<String> get ownedItemIds => Set.unmodifiable(_ownedItemIds);
  String? get equippedFrameId => _equippedFrameId;
  String? get equippedTitleId => _equippedTitleId;
  bool get oceanThemeActive => _oceanThemeActive;
  int? get pendingLoginBonusCoins => _pendingLoginBonusCoins;
  bool get isLoaded => _loaded;

  static const List<ShopItem> shopItems = [
    ShopItem(
      id: 'frame_gold',
      name: 'Gold Avatar Frame',
      emoji: '🖼️',
      cost: 100,
      category: 'frame',
      usefulness: 'Adds a gold ring around your avatar on your Profile once equipped.',
    ),
    ShopItem(
      id: 'frame_fire',
      name: 'Fire Avatar Frame',
      emoji: '🔥',
      cost: 150,
      category: 'frame',
      usefulness: 'Adds a fire-orange ring around your avatar on your Profile once equipped.',
    ),
    ShopItem(
      id: 'title_scholar',
      name: 'Scholar Title',
      emoji: '🎓',
      cost: 80,
      category: 'title',
      usefulness: 'Shows a "📖 Scholar" badge next to your name on your Profile once equipped.',
    ),
    ShopItem(
      id: 'title_genius',
      name: 'Genius Title',
      emoji: '🧠',
      cost: 200,
      category: 'title',
      usefulness: 'Shows a "🧠 Genius" badge next to your name on your Profile once equipped.',
    ),
    ShopItem(
      id: 'theme_ocean',
      name: 'Ocean Theme Pack',
      emoji: '🌊',
      cost: 250,
      category: 'theme',
      usefulness: 'Re-skins the whole app in ocean-blue colors once activated.',
    ),
    ShopItem(
      id: 'streak_freeze',
      name: 'Streak Freeze',
      emoji: '🧊',
      cost: 50,
      category: 'consumable',
      usefulness: 'Automatically protects your streak the next time you miss a day.',
    ),
  ];

  String _todayKey() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _init() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      final row = await _client.from('coin_wallets').select().eq('user_id', user.id).maybeSingle();
      if (row != null) {
        _coins = (row['coins'] as num?)?.toInt() ?? 0;
        final owned = ((row['owned_items'] as List?) ?? []).cast<String>();
        _ownedItemIds
          ..clear()
          ..addAll(owned.where((id) => id != 'streak_freeze'));
        _streakFreezeCount = owned.where((id) => id == 'streak_freeze').length;
        _lastLoginBonusDate = row['last_login_bonus_date'] as String?;
        _lastSpinDate = row['last_spin_date'] as String?;
        _equippedFrameId = row['equipped_frame'] as String?;
        _equippedTitleId = row['equipped_title'] as String?;
        _oceanThemeActive = row['ocean_theme_active'] as bool? ?? false;
      } else {
        await _push();
      }
    } catch (e) {
      debugPrint('[CoinService] init failed: $e');
    }
    _claimDailyLoginBonusIfNeeded();
    _loaded = true;
    notifyListeners();
  }

  void _claimDailyLoginBonusIfNeeded() {
    final today = _todayKey();
    if (_lastLoginBonusDate == today) return;
    _coins += _dailyLoginBonusCoins;
    _lastLoginBonusDate = today;
    _pendingLoginBonusCoins = _dailyLoginBonusCoins;
    _push();
  }

  /// Call once the bonus banner has been shown so it doesn't reappear
  /// for the rest of the day.
  void clearPendingLoginBonus() {
    _pendingLoginBonusCoins = null;
  }

  /// Whether the user still has their daily spin available. Persisted
  /// server-side so reloading/restarting the app can't be used to spin
  /// more than once per day.
  bool get canSpinToday => _lastSpinDate != _todayKey();

  void recordSpin() {
    _lastSpinDate = _todayKey();
    notifyListeners();
    _push();
  }

  List<String> _ownedItemsForStorage() => [
        ..._ownedItemIds,
        ...List.filled(_streakFreezeCount, 'streak_freeze'),
      ];

  Future<void> _push() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('coin_wallets').upsert({
        'user_id': user.id,
        'coins': _coins,
        'owned_items': _ownedItemsForStorage(),
        'last_login_bonus_date': _lastLoginBonusDate,
        'last_spin_date': _lastSpinDate,
        'equipped_frame': _equippedFrameId,
        'equipped_title': _equippedTitleId,
        'ocean_theme_active': _oceanThemeActive,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[CoinService] push failed: $e');
    }
  }

  void addCoins(int amount) {
    _coins += amount;
    notifyListeners();
    _push();
  }

  /// Streak Freeze is consumable and stackable — buying it repeatedly
  /// increases the count instead of being a one-time unlock like the
  /// other shop items.
  bool purchase(ShopItem item) {
    if (_coins < item.cost) return false;

    if (item.id == 'streak_freeze') {
      _coins -= item.cost;
      _streakFreezeCount += 1;
      notifyListeners();
      _push();
      return true;
    }

    if (_ownedItemIds.contains(item.id)) return false;
    _coins -= item.cost;
    _ownedItemIds.add(item.id);
    notifyListeners();
    _push();
    return true;
  }

  bool owns(String id) => _ownedItemIds.contains(id);

  /// Equips (or unequips, by passing null) an owned Avatar Frame. Only
  /// one frame can be equipped at a time.
  void equipFrame(String? id) {
    if (id != null && !_ownedItemIds.contains(id)) return;
    _equippedFrameId = id;
    notifyListeners();
    _push();
  }

  /// Equips (or unequips, by passing null) an owned Title. Only one
  /// title can be equipped at a time.
  void equipTitle(String? id) {
    if (id != null && !_ownedItemIds.contains(id)) return;
    _equippedTitleId = id;
    notifyListeners();
    _push();
  }

  /// Activates or deactivates the Ocean Theme pack, re-skinning the
  /// whole app's color scheme. Only works if the pack is owned.
  void setOceanThemeActive(bool active) {
    if (active && !_ownedItemIds.contains('theme_ocean')) return;
    _oceanThemeActive = active;
    notifyListeners();
    _push();
  }

  /// Consumes one Streak Freeze to protect the current streak from
  /// resetting after a missed day. Called from AppProvider's StreakService
  /// when it detects a gap. Returns true if a freeze was available and
  /// consumed.
  bool consumeStreakFreeze() {
    if (_streakFreezeCount <= 0) return false;
    _streakFreezeCount -= 1;
    notifyListeners();
    _push();
    return true;
  }

  static Color? frameColorFor(String? id) {
    switch (id) {
      case 'frame_gold':
        return const Color(0xFFFFD700);
      case 'frame_fire':
        return Colors.deepOrange;
      default:
        return null;
    }
  }

  static String? titleLabelFor(String? id) {
    switch (id) {
      case 'title_scholar':
        return '📖 Scholar';
      case 'title_genius':
        return '🧠 Genius';
      default:
        return null;
    }
  }
}

/// Big, celebratory confirmation shown right after a successful purchase —
/// replaces the old tiny SnackBar, which felt underwhelming for spending
/// hard-earned coins.
Future<void> showPurchaseCelebration(BuildContext context, ShopItem item) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PurchaseCelebrationDialog(item: item),
  );
}

class _PurchaseCelebrationDialog extends StatefulWidget {
  final ShopItem item;
  const _PurchaseCelebrationDialog({required this.item});

  @override
  State<_PurchaseCelebrationDialog> createState() => _PurchaseCelebrationDialogState();
}

class _PurchaseCelebrationDialogState extends State<_PurchaseCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ScaleTransition(
        scale: _scale,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.item.emoji, style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 12),
              const Text('Purchase Successful! 🎉',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(widget.item.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(widget.item.usefulness,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Awesome!'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CoinShopScreen extends StatefulWidget {
  const CoinShopScreen({super.key});

  @override
  State<CoinShopScreen> createState() => _CoinShopScreenState();
}

class _CoinShopScreenState extends State<CoinShopScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final coinService = context.read<CoinService>();
      final bonus = coinService.pendingLoginBonusCoins;
      if (bonus != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Welcome back! +$bonus coins daily login bonus 🎁')),
        );
        coinService.clearPendingLoginBonus();
      }
    });
  }

  Widget _buildActionButton(BuildContext context, CoinService coinService, ShopItem item) {
    final owned = coinService.owns(item.id);

    if (item.id == 'streak_freeze') {
      return FilledButton(
        onPressed: coinService.coins >= item.cost
            ? () async {
                final success = coinService.purchase(item);
                if (success) await showPurchaseCelebration(context, item);
              }
            : null,
        child: const Text('Buy'),
      );
    }

    if (!owned) {
      return FilledButton(
        onPressed: coinService.coins >= item.cost
            ? () async {
                final success = coinService.purchase(item);
                if (success) await showPurchaseCelebration(context, item);
              }
            : null,
        child: const Text('Buy'),
      );
    }

    switch (item.category) {
      case 'frame':
        final equipped = coinService.equippedFrameId == item.id;
        return OutlinedButton(
          onPressed: () => coinService.equipFrame(equipped ? null : item.id),
          child: Text(equipped ? 'Unequip' : 'Equip'),
        );
      case 'title':
        final equipped = coinService.equippedTitleId == item.id;
        return OutlinedButton(
          onPressed: () => coinService.equipTitle(equipped ? null : item.id),
          child: Text(equipped ? 'Unequip' : 'Equip'),
        );
      case 'theme':
        final active = coinService.oceanThemeActive;
        return OutlinedButton(
          onPressed: () => coinService.setOceanThemeActive(!active),
          child: Text(active ? 'Deactivate' : 'Activate'),
        );
      default:
        return const Icon(Icons.check_circle_rounded, color: Colors.green);
    }
  }

  String _statusSubtitle(CoinService coinService, ShopItem item) {
    if (item.id == 'streak_freeze') {
      return '${coinService.streakFreezeCount} owned • ${item.cost} coins each';
    }
    if (!coinService.owns(item.id)) {
      return '${item.cost} coins';
    }
    switch (item.category) {
      case 'frame':
        return coinService.equippedFrameId == item.id ? 'Owned • Equipped ✓' : 'Owned • Not equipped';
      case 'title':
        return coinService.equippedTitleId == item.id ? 'Owned • Equipped ✓' : 'Owned • Not equipped';
      case 'theme':
        return coinService.oceanThemeActive ? 'Owned • Active ✓' : 'Owned • Not active';
      default:
        return 'Owned';
    }
  }

  @override
  Widget build(BuildContext context) {
    final coinService = context.watch<CoinService>();

    if (!coinService.isLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Coin Shop')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coin Shop'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Row(
                children: [
                  const Icon(Icons.monetization_on_rounded, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text('${coinService.coins}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: CoinService.shopItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = CoinService.shopItems[index];
          return Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Text(item.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(_statusSubtitle(coinService, item),
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(context, coinService, item),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// =========================================================================
/// 3. SPIN WHEEL REWARDS
/// =========================================================================

class _WheelSegment {
  final String label;
  final Color color;
  final int? coins;
  final int? xp;
  const _WheelSegment(this.label, this.color, {this.coins, this.xp});
}

class SpinWheelScreen extends StatefulWidget {
  const SpinWheelScreen({super.key});

  @override
  State<SpinWheelScreen> createState() => _SpinWheelScreenState();
}

class _SpinWheelScreenState extends State<SpinWheelScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _spinning = false;
  String? _result;

  static const List<_WheelSegment> _segments = [
    _WheelSegment('10 coins', Colors.amber, coins: 10),
    _WheelSegment('20 XP', Colors.deepPurple, xp: 20),
    _WheelSegment('25 coins', Colors.orange, coins: 25),
    _WheelSegment('Try again', Colors.grey),
    _WheelSegment('50 coins', Colors.green, coins: 50),
    _WheelSegment('40 XP', Colors.indigo, xp: 40),
    _WheelSegment('100 coins', Colors.redAccent, coins: 100),
    _WheelSegment('10 XP', Colors.teal, xp: 10),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _spin() {
    final coinService = context.read<CoinService>();
    if (!coinService.canSpinToday || _spinning) return;
    setState(() {
      _spinning = true;
      _result = null;
    });

    final segment = _segments[Random().nextInt(_segments.length)];
    _controller.forward(from: 0).whenComplete(() {
      coinService.recordSpin();
      if (segment.coins != null) {
        coinService.addCoins(segment.coins!);
      }
      if (segment.xp != null) {
        context.read<AppProvider>().addXP(segment.xp!);
      }
      if (mounted) {
        setState(() {
          _spinning = false;
          _result = segment.label;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coinService = context.watch<CoinService>();
    final alreadySpunToday = !coinService.canSpinToday;

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Spin')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotationTransition(
                turns: Tween(begin: 0.0, end: 6.0).animate(
                  CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
                ),
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(colors: _segments.map((s) => s.color).toList()),
                    border: Border.all(color: scheme.outline, width: 4),
                  ),
                  child: const Center(
                    child: Icon(Icons.star_rounded, color: Colors.white, size: 32),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              if (_result != null)
                Text('You won: $_result!',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: (alreadySpunToday || _spinning) ? null : _spin,
                  child: Text(alreadySpunToday
                      ? 'Come back tomorrow'
                      : (_spinning ? 'Spinning...' : 'Spin Now')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// 4. MULTI-EXAM COUNTDOWN
/// =========================================================================

class ExamCountdownEntry {
  final String id;
  String examName;
  DateTime examDate;
  ExamCountdownEntry({required this.id, required this.examName, required this.examDate});
}

class ExamCountdownService extends ChangeNotifier {
  ExamCountdownService._() {
    _init();
  }
  static final ExamCountdownService instance = ExamCountdownService._();

  SupabaseClient get _client => Supabase.instance.client;

  final List<ExamCountdownEntry> _exams = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;

  List<ExamCountdownEntry> get exams {
    final sorted = List<ExamCountdownEntry>.from(_exams);
    sorted.sort((a, b) => a.examDate.compareTo(b.examDate));
    return sorted;
  }

  Future<void> _init() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      final rows = await _client.from('exam_countdowns').select().eq('user_id', user.id);
      _exams
        ..clear()
        ..addAll((rows as List<dynamic>).map((r) {
          final row = r as Map<String, dynamic>;
          return ExamCountdownEntry(
            id: row['id'] as String,
            examName: row['exam_name'] as String,
            examDate: DateTime.parse(row['exam_date'] as String),
          );
        }));
    } catch (e) {
      debugPrint('[ExamCountdownService] init failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> addExam({required String name, required DateTime date}) async {
    final user = _client.auth.currentUser;
    final tempId = 'exam_local_${DateTime.now().microsecondsSinceEpoch}';
    final entry = ExamCountdownEntry(id: tempId, examName: name, examDate: date);
    _exams.add(entry);
    notifyListeners();

    if (user == null) return;
    try {
      final row = await _client.from('exam_countdowns').insert({
        'user_id': user.id,
        'exam_name': name,
        'exam_date': date.toIso8601String().split('T').first,
      }).select().single();

      final idx = _exams.indexWhere((e) => e.id == tempId);
      if (idx != -1) {
        _exams[idx] = ExamCountdownEntry(id: row['id'] as String, examName: name, examDate: date);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ExamCountdownService] addExam failed: $e');
    }
  }

  Future<void> removeExam(String id) async {
    _exams.removeWhere((e) => e.id == id);
    notifyListeners();
    try {
      await _client.from('exam_countdowns').delete().eq('id', id);
    } catch (e) {
      debugPrint('[ExamCountdownService] removeExam failed: $e');
    }
  }

  Future<void> updateExamDate(String id, DateTime newDate) async {
    final idx = _exams.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    _exams[idx].examDate = newDate;
    notifyListeners();
    try {
      await _client.from('exam_countdowns').update({
        'exam_date': newDate.toIso8601String().split('T').first,
      }).eq('id', id);
    } catch (e) {
      debugPrint('[ExamCountdownService] updateExamDate failed: $e');
    }
  }
}

class ExamCountdownScreen extends StatefulWidget {
  const ExamCountdownScreen({super.key});

  @override
  State<ExamCountdownScreen> createState() => _ExamCountdownScreenState();
}

class _ExamCountdownScreenState extends State<ExamCountdownScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _addExamDialog(BuildContext context) async {
    final nameController = TextEditingController();
    DateTime? pickedDate;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Add Exam'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Exam name (e.g. WAEC, JAMB)'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text(pickedDate == null
                        ? 'Choose date'
                        : '${pickedDate!.year}-${pickedDate!.month.toString().padLeft(2, '0')}-${pickedDate!.day.toString().padLeft(2, '0')}'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: DateTime.now().add(const Duration(days: 90)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                      );
                      if (picked != null) {
                        setDialogState(() => pickedDate = picked);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                FilledButton(
                  onPressed: (nameController.text.trim().isEmpty || pickedDate == null)
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && pickedDate != null) {
      await ExamCountdownService.instance.addExam(name: nameController.text.trim(), date: pickedDate!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ExamCountdownService>();
    final scheme = Theme.of(context).colorScheme;

    if (!service.isLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Exam Countdown')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final exams = service.exams;

    return Scaffold(
      appBar: AppBar(title: const Text('Exam Countdown')),
      body: exams.isEmpty
          ? const _EmptyState(
              icon: Icons.hourglass_bottom_rounded,
              title: 'No exams added yet',
              subtitle: 'Tap + to add WAEC, JAMB, NECO, or any exam you\'re preparing for.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: exams.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final exam = exams[index];
                final remaining = exam.examDate.difference(DateTime.now());
                final isPast = remaining.isNegative;

                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isPast ? scheme.errorContainer.withOpacity(0.4) : scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(exam.examName,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => ExamCountdownService.instance.removeExam(exam.id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (isPast)
                        const Text('This exam date has passed.', textAlign: TextAlign.center)
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _CountdownUnit(value: remaining.inDays, label: 'Days'),
                            _CountdownUnit(value: remaining.inHours % 24, label: 'Hours'),
                            _CountdownUnit(value: remaining.inMinutes % 60, label: 'Min'),
                            _CountdownUnit(value: remaining.inSeconds % 60, label: 'Sec'),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addExamDialog(context),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _CountdownUnit extends StatelessWidget {
  final int value;
  final String label;
  const _CountdownUnit({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// =========================================================================
/// 5. TOPIC MASTERY TRACKER + FOCUS MODE
/// =========================================================================

class _MasteryTally {
  int correct = 0;
  int total = 0;
}

class MasteryService extends ChangeNotifier {
  MasteryService._() {
    _init();
  }
  static final MasteryService instance = MasteryService._();

  SupabaseClient get _client => Supabase.instance.client;

  final Map<String, _MasteryTally> _bySubject = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> _init() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      final rows = await _client.from('subject_mastery').select().eq('user_id', user.id);
      _bySubject.clear();
      for (final r in (rows as List<dynamic>)) {
        final row = r as Map<String, dynamic>;
        final tally = _MasteryTally();
        tally.correct = (row['correct'] as num?)?.toInt() ?? 0;
        tally.total = (row['total'] as num?)?.toInt() ?? 0;
        _bySubject[row['subject'] as String] = tally;
      }
    } catch (e) {
      debugPrint('[MasteryService] init failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  void recordSession({required String subject, required int correct, required int total}) {
    final tally = _bySubject.putIfAbsent(subject, () => _MasteryTally());
    tally.correct += correct;
    tally.total += total;
    notifyListeners();
    _push(subject, tally);
  }

  Future<void> _push(String subject, _MasteryTally tally) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('subject_mastery').upsert({
        'user_id': user.id,
        'subject': subject,
        'correct': tally.correct,
        'total': tally.total,
      });
    } catch (e) {
      debugPrint('[MasteryService] push failed: $e');
    }
  }

  double masteryFor(String subject) {
    final tally = _bySubject[subject];
    if (tally == null || tally.total == 0) return 0;
    return tally.correct / tally.total;
  }

  List<String> get trackedSubjects => _bySubject.keys.toList()..sort();
}

class TopicMasteryScreen extends StatelessWidget {
  const TopicMasteryScreen({super.key});

  Color _colorFor(double mastery) {
    if (mastery >= 0.75) return Colors.green;
    if (mastery >= 0.5) return Colors.amber;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<MasteryService>();

    if (!service.isLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Topic Mastery')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final subjects = service.trackedSubjects;

    return Scaffold(
      appBar: AppBar(title: const Text('Topic Mastery')),
      body: subjects.isEmpty
          ? const _EmptyState(
              icon: Icons.track_changes_rounded,
              title: 'No mastery data yet',
              subtitle: 'Complete a few practice exams to see your mastery by subject.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: subjects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final subject = subjects[index];
                final mastery = service.masteryFor(subject);
                final color = _colorFor(mastery);
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(subject, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${(mastery * 100).toStringAsFixed(0)}%',
                              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: mastery,
                          minHeight: 10,
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Ranks the user's weakest subjects (from AppProvider's already-synced
/// subjectScores/subjectAttempts) and offers a single tap into a mock
/// exam targeting exactly those subjects.
class FocusModeScreen extends StatelessWidget {
  const FocusModeScreen({super.key});

  static const int _minAttemptsToRank = 5;
  static const int _questionsPerSubject = 15;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final scheme = Theme.of(context).colorScheme;

    final ranked = provider
        .getAvailableSubjects()
        .where((s) => (provider.stats.subjectAttempts[s] ?? 0) >= _minAttemptsToRank)
        .map((s) => MapEntry(s, provider.getSubjectScore(s)))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final weakest = ranked.take(3).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('🎯 Focus Mode')),
      body: weakest.isEmpty
          ? _EmptyState(
              icon: Icons.track_changes_rounded,
              title: 'Not enough data yet',
              subtitle: 'Practice at least $_minAttemptsToRank questions in a subject to see your weakest areas here.',
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Your weakest subjects right now — a focused mock exam targeting these will help the most.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                ...weakest.map((e) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: (e.value / 100).clamp(0.0, 1.0),
                                    minHeight: 8,
                                    backgroundColor: scheme.surface,
                                    valueColor: const AlwaysStoppedAnimation(Colors.orange),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('${e.value.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start Focus Practice'),
                    onPressed: () {
                      final subjects = weakest.map((e) => e.key).toList();
                      final questions = provider.generateMockExamMulti(subjects, _questionsPerSubject);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => QuizScreen(
                            questions: questions,
                            title: 'Focus Practice',
                            onComplete: (score) => Navigator.pop(context),
                            onCompleteDetailed: (graded) {
                              final Map<String, int> correctBySubject = {};
                              final Map<String, int> totalBySubject = {};
                              int overall = 0;
                              for (final gq in graded) {
                                final subject = gq['subject'] as String? ?? 'Unknown';
                                final wasCorrect = gq['__correct'] as bool? ?? false;
                                totalBySubject[subject] = (totalBySubject[subject] ?? 0) + 1;
                                if (wasCorrect) {
                                  correctBySubject[subject] = (correctBySubject[subject] ?? 0) + 1;
                                  overall++;
                                }
                              }
                              for (final subject in subjects) {
                                provider.recordAnswer(subject, correctBySubject[subject] ?? 0, totalBySubject[subject] ?? 0);
                              }
                              provider.addXP(overall * 2);
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// =========================================================================
/// SHARED WIDGET
/// =========================================================================

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
