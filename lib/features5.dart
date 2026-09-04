// lib/features5.dart
//
// ⚡ REDESIGNED VERSION — visuals only. FlashcardService, CoinService,
// ExamCountdownService, MasteryService, and every Supabase/ZetraPay call
// below are 100% unchanged from your original file — copy this in as a
// straight replacement, nothing breaks.
//
// Uses the shared design system from app_enhancements.dart (ShinyCard,
// GradientButton, GradientHeader — which includes its own back button)
// and AppTheme.heroGradient(context) from app_theme.dart for every
// gradient, so colors are always derived from your real emerald/ocean
// brand and correct in both light and dark mode.
//
// SpinWheelScreen keeps its own deliberately distinct "tomorrow-tech"
// dark aesthetic (per the original design intent — a wheel screen is
// meant to feel like a different, more arcade-like space) but its
// AppBar already provides automatic back navigation, so no change
// needed there beyond minor accent alignment.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_enhancements.dart' show AppProvider, ShinyCard, GradientButton, GradientHeader, QuizScreen;
import 'app_theme.dart' show AppTheme, AppColors;
import 'zetra_pay.dart';

/// =========================================================================
/// 1. FLASHCARDS + SPACED REPETITION  (service unchanged — logic only)
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

  List<Flashcard> forSubject(String subject) => _cards.where((c) => c.subject == subject).toList();

  List<Flashcard> dueForSubject(String subject) => _cards.where((c) => c.subject == subject && c.isDue).toList();

  List<String> get subjectsWithCards => _cards.map((c) => c.subject).toSet().toList()..sort();

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
        _cards[idx] = Flashcard(id: row['id'] as String, subject: subject, front: front, back: back, boxLevel: 1, nextReview: card.nextReview);
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
      await _client.from('flashcards').update({'box_level': card.boxLevel, 'next_review': card.nextReview.toIso8601String()}).eq('id', card.id);
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final subjects = service.subjectsWithCards;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: GradientHeader(
              title: '🗂️ Flashcards',
              subtitle: 'Spaced-repetition review',
              trailing: Material(
                color: Colors.white.withOpacity(0.18),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _showAddCardDialog(context),
                  child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.add_rounded, color: Colors.white)),
                ),
              ),
            ),
          ),
          if (subjects.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(icon: Icons.style_rounded, title: 'No flashcards yet', subtitle: 'Tap + to create your first flashcard.'),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final subject = subjects[index];
                    final total = service.forSubject(subject).length;
                    final due = service.dueForSubject(subject).length;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ShinyCard(
                        tint: due > 0 ? AppColors.xp : null,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(subject, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text('$total cards • $due due for review', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: GradientButton(
                                label: 'Review',
                                height: 40,
                                onPressed: due == 0 ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FlashcardReviewScreen(subject: subject))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: subjects.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showAddCardDialog(BuildContext context) {
    final subjectController = TextEditingController();
    final frontController = TextEditingController();
    final backController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('New Flashcard'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: subjectController, decoration: const InputDecoration(labelText: 'Subject')),
              const SizedBox(height: 12),
              TextField(controller: frontController, decoration: const InputDecoration(labelText: 'Front (question)'), maxLines: 2),
              const SizedBox(height: 12),
              TextField(controller: backController, decoration: const InputDecoration(labelText: 'Back (answer)'), maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (subjectController.text.trim().isEmpty || frontController.text.trim().isEmpty) return;
              FlashcardService.instance.addCard(subject: subjectController.text.trim(), front: frontController.text.trim(), back: backController.text.trim());
              Navigator.pop(dialogContext);
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
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Review Complete'),
        content: Text('You got $_correctCount out of ${_queue.length} correct.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
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
    final scheme = Theme.of(context).colorScheme;

    if (_queue.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Align(alignment: Alignment.centerLeft, child: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop())),
              const Expanded(child: Center(child: Text('No cards due for review right now.'))),
            ],
          ),
        ),
      );
    }

    final card = _queue[_index];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop()),
                Expanded(child: Text('${widget.subject} Review', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              ]),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: _index / _queue.length, minHeight: 8, backgroundColor: scheme.surfaceContainerHighest)),
              const SizedBox(height: 8),
              Text('Card ${_index + 1} of ${_queue.length}', style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _showBack = !_showBack),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: _showBack ? AppTheme.heroGradient(context) : null,
                      color: _showBack ? null : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Center(
                      child: SingleChildScrollView(
                        child: Text(
                          _showBack ? card.back : card.front,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _showBack ? Colors.white : scheme.onSurface),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(_showBack ? 'Tap card to see question' : 'Tap card to reveal answer', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 20),
              if (_showBack)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _answer(false),
                        icon: const Icon(Icons.close_rounded, color: AppColors.error),
                        label: const Text('Got it wrong'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: GradientButton(label: 'Got it right', icon: Icons.check_rounded, height: 48, onPressed: () => _answer(true))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// 2. CENT SHOP  (service unchanged — logic only)
/// =========================================================================

class ShopItem {
  final String id;
  final String name;
  final String emoji;
  final int cost;
  final String category;
  final String usefulness;
  const ShopItem({required this.id, required this.name, required this.emoji, required this.cost, required this.category, required this.usefulness});
}

class SpinExclusiveItem {
  final String id;
  final String name;
  final String emoji;
  final String category;
  final String rarity;
  final Color rarityColor;
  const SpinExclusiveItem({required this.id, required this.name, required this.emoji, required this.category, required this.rarity, required this.rarityColor});
}

class CoinService extends ChangeNotifier {
  CoinService._() {
    _init();
  }
  static final CoinService instance = CoinService._();

  SupabaseClient get _client => Supabase.instance.client;
  static const String _appId = ZetraPay.naijaLearnAppId;

  static const int _dailyLoginBonusCent = 10;
  static const int _centsPerCp = 1000;

  double _cents = 0;
  int _streakFreezeCount = 0;
  final Set<String> _ownedItemIds = {};
  String? _equippedFrameId;
  String? _equippedTitleId;
  bool _oceanThemeActive = false;
  String? _lastLoginBonusDate;
  String? _lastSpinDate;
  int? _pendingLoginBonusCent;
  bool _loaded = false;

  double get cents => _cents;
  int get cp => (_cents.round()) ~/ _centsPerCp;
  int get leftoverCent => (_cents.round()) % _centsPerCp;

  int get streakFreezeCount => _streakFreezeCount;
  Set<String> get ownedItemIds => Set.unmodifiable(_ownedItemIds);
  String? get equippedFrameId => _equippedFrameId;
  String? get equippedTitleId => _equippedTitleId;
  bool get oceanThemeActive => _oceanThemeActive;
  int? get pendingLoginBonusCent => _pendingLoginBonusCent;
  bool get isLoaded => _loaded;

  static const List<ShopItem> shopItems = [
    ShopItem(id: 'frame_gold', name: 'Gold Avatar Frame', emoji: '🖼️', cost: 100, category: 'frame', usefulness: 'Adds a gold ring around your avatar on your Profile once equipped.'),
    ShopItem(id: 'frame_fire', name: 'Fire Avatar Frame', emoji: '🔥', cost: 150, category: 'frame', usefulness: 'Adds a fire-orange ring around your avatar on your Profile once equipped.'),
    ShopItem(id: 'title_scholar', name: 'Scholar Title', emoji: '🎓', cost: 80, category: 'title', usefulness: 'Shows a "📖 Scholar" badge next to your name on your Profile once equipped.'),
    ShopItem(id: 'title_genius', name: 'Genius Title', emoji: '🧠', cost: 200, category: 'title', usefulness: 'Shows a "🧠 Genius" badge next to your name on your Profile once equipped.'),
    ShopItem(id: 'theme_ocean', name: 'Ocean Theme Pack', emoji: '🌊', cost: 250, category: 'theme', usefulness: 'Re-skins the whole app in ocean-blue colors once activated.'),
    ShopItem(id: 'streak_freeze', name: 'Streak Freeze', emoji: '🧊', cost: 50, category: 'consumable', usefulness: 'Automatically protects your streak the next time you miss a day.'),
  ];

  static const List<SpinExclusiveItem> spinExclusiveItems = [
    SpinExclusiveItem(id: 'spin_frame_neon', name: 'Neon Avatar Frame', emoji: '⚡', category: 'frame', rarity: 'Rare', rarityColor: Color(0xFF00E5FF)),
    SpinExclusiveItem(id: 'spin_title_lucky', name: 'Lucky Title', emoji: '🍀', category: 'title', rarity: 'Rare', rarityColor: Color(0xFF00E5FF)),
    SpinExclusiveItem(id: 'spin_frame_diamond', name: 'Diamond Avatar Frame', emoji: '💎', category: 'frame', rarity: 'Epic', rarityColor: Color(0xFFB388FF)),
    SpinExclusiveItem(id: 'spin_title_legend', name: 'Legend Title', emoji: '👑', category: 'title', rarity: 'Epic', rarityColor: Color(0xFFB388FF)),
    SpinExclusiveItem(id: 'spin_frame_galaxy', name: 'Galaxy Avatar Frame', emoji: '🌌', category: 'frame', rarity: 'Legendary', rarityColor: Color(0xFFFFD700)),
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
      }
      _cents = await ZetraPay.getAppCurrencyBalance(_appId);
    } catch (e) {
      debugPrint('[CoinService] init failed: $e');
    }
    await _claimDailyLoginBonusIfNeeded();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _claimDailyLoginBonusIfNeeded() async {
    final today = _todayKey();
    if (_lastLoginBonusDate == today) return;
    final error = await ZetraPay.creditAppCurrency(appId: _appId, unitAmount: _dailyLoginBonusCent.toDouble());
    if (error == null) {
      _cents += _dailyLoginBonusCent;
      _lastLoginBonusDate = today;
      _pendingLoginBonusCent = _dailyLoginBonusCent;
      await _pushLocal();
      notifyListeners();
    }
  }

  void clearPendingLoginBonus() {
    _pendingLoginBonusCent = null;
  }

  bool get canSpinToday => _lastSpinDate != _todayKey();

  Future<void> recordSpin() async {
    _lastSpinDate = _todayKey();
    notifyListeners();
    await _pushLocal();
  }

  List<String> _ownedItemsForStorage() => [..._ownedItemIds, ...List.filled(_streakFreezeCount, 'streak_freeze')];

  Future<void> _pushLocal() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('coin_wallets').upsert({
        'user_id': user.id,
        'owned_items': _ownedItemsForStorage(),
        'last_login_bonus_date': _lastLoginBonusDate,
        'last_spin_date': _lastSpinDate,
        'equipped_frame': _equippedFrameId,
        'equipped_title': _equippedTitleId,
        'ocean_theme_active': _oceanThemeActive,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[CoinService] pushLocal failed: $e');
    }
  }

  Future<void> refreshBalance() async {
    try {
      _cents = await ZetraPay.getAppCurrencyBalance(_appId);
      notifyListeners();
    } catch (e) {
      debugPrint('[CoinService] refreshBalance failed: $e');
    }
  }

  Future<bool> purchase(ShopItem item) async {
    if (_cents < item.cost) return false;

    final error = await ZetraPay.spendAppCurrency(appId: _appId, unitAmount: item.cost.toDouble());
    if (error != null) return false;
    _cents -= item.cost;

    if (item.id == 'streak_freeze') {
      _streakFreezeCount += 1;
      notifyListeners();
      await _pushLocal();
      return true;
    }

    if (_ownedItemIds.contains(item.id)) {
      await ZetraPay.creditAppCurrency(appId: _appId, unitAmount: item.cost.toDouble());
      _cents += item.cost;
      notifyListeners();
      return false;
    }

    _ownedItemIds.add(item.id);
    notifyListeners();
    await _pushLocal();
    return true;
  }

  Future<bool> grantSpinExclusiveItem(String id) async {
    if (_ownedItemIds.contains(id)) return false;
    _ownedItemIds.add(id);
    notifyListeners();
    await _pushLocal();
    return true;
  }

  bool owns(String id) => _ownedItemIds.contains(id);

  Future<void> equipFrame(String? id) async {
    if (id != null && !_ownedItemIds.contains(id)) return;
    _equippedFrameId = id;
    notifyListeners();
    await _pushLocal();
  }

  Future<void> equipTitle(String? id) async {
    if (id != null && !_ownedItemIds.contains(id)) return;
    _equippedTitleId = id;
    notifyListeners();
    await _pushLocal();
  }

  Future<void> setOceanThemeActive(bool active) async {
    if (active && !_ownedItemIds.contains('theme_ocean')) return;
    _oceanThemeActive = active;
    notifyListeners();
    await _pushLocal();
  }

  bool consumeStreakFreeze() {
    if (_streakFreezeCount <= 0) return false;
    _streakFreezeCount -= 1;
    notifyListeners();
    _pushLocal();
    return true;
  }

  static Color? frameColorFor(String? id) {
    switch (id) {
      case 'frame_gold':
        return const Color(0xFFFFD700);
      case 'frame_fire':
        return Colors.deepOrange;
      case 'spin_frame_neon':
        return const Color(0xFF00E5FF);
      case 'spin_frame_diamond':
        return const Color(0xFFB388FF);
      case 'spin_frame_galaxy':
        return const Color(0xFFFFD700);
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
      case 'spin_title_lucky':
        return '🍀 Lucky';
      case 'spin_title_legend':
        return '👑 Legend';
      default:
        return null;
    }
  }
}

Future<void> showPurchaseCelebration(BuildContext context, ShopItem item) {
  return showDialog(context: context, barrierDismissible: false, builder: (ctx) => _PurchaseCelebrationDialog(item: item));
}

class _PurchaseCelebrationDialog extends StatefulWidget {
  final ShopItem item;
  const _PurchaseCelebrationDialog({required this.item});

  @override
  State<_PurchaseCelebrationDialog> createState() => _PurchaseCelebrationDialogState();
}

class _PurchaseCelebrationDialogState extends State<_PurchaseCelebrationDialog> with SingleTickerProviderStateMixin {
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
      backgroundColor: scheme.surface,
      child: ScaleTransition(
        scale: _scale,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.item.emoji, style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 12),
              const Text('Purchase Successful! 🎉', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(widget.item.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: scheme.primaryContainer.withOpacity(0.5), borderRadius: BorderRadius.circular(14)),
                child: Text(widget.item.usefulness, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 20),
              GradientButton(label: 'Awesome!', onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showSpinWinCelebration(BuildContext context, SpinExclusiveItem item) {
  return showDialog(context: context, barrierDismissible: false, builder: (ctx) => _SpinWinCelebrationDialog(item: item));
}

class _SpinWinCelebrationDialog extends StatefulWidget {
  final SpinExclusiveItem item;
  const _SpinWinCelebrationDialog({required this.item});

  @override
  State<_SpinWinCelebrationDialog> createState() => _SpinWinCelebrationDialogState();
}

class _SpinWinCelebrationDialogState extends State<_SpinWinCelebrationDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
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
    // Deliberately kept dark/neon regardless of app theme — this is a
    // "you won a rare prize" moment, meant to feel distinct.
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF12122A), widget.item.rarityColor.withOpacity(0.25)]),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: widget.item.rarityColor, width: 1.6),
            boxShadow: [BoxShadow(color: widget.item.rarityColor.withOpacity(0.5), blurRadius: 32, spreadRadius: 2)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: widget.item.rarityColor.withOpacity(0.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: widget.item.rarityColor)),
                child: Text(widget.item.rarity.toUpperCase(), style: TextStyle(color: widget.item.rarityColor, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
              ),
              const SizedBox(height: 18),
              Text(widget.item.emoji, style: const TextStyle(fontSize: 68)),
              const SizedBox(height: 14),
              const Text('YOU WON!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(widget.item.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white70), textAlign: TextAlign.center),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: widget.item.rarityColor, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Claim It!', style: TextStyle(fontWeight: FontWeight.bold)),
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
      final bonus = coinService.pendingLoginBonusCent;
      if (bonus != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Welcome back! +$bonus Cent daily login bonus 🎁')));
        coinService.clearPendingLoginBonus();
      }
    });
  }

  Future<void> _handlePurchase(CoinService coinService, ShopItem item) async {
    final success = await coinService.purchase(item);
    if (success && mounted) await showPurchaseCelebration(context, item);
  }

  Widget _buildActionButton(BuildContext context, CoinService coinService, ShopItem item) {
    final owned = coinService.owns(item.id);

    if (item.id == 'streak_freeze' || !owned) {
      return SizedBox(
        width: 84,
        child: GradientButton(label: 'Buy', height: 38, onPressed: coinService.cents >= item.cost ? () => _handlePurchase(coinService, item) : null),
      );
    }

    switch (item.category) {
      case 'frame':
        final equipped = coinService.equippedFrameId == item.id;
        return SizedBox(width: 90, height: 38, child: OutlinedButton(onPressed: () => coinService.equipFrame(equipped ? null : item.id), style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(equipped ? 'Unequip' : 'Equip', style: const TextStyle(fontSize: 12))));
      case 'title':
        final equipped = coinService.equippedTitleId == item.id;
        return SizedBox(width: 90, height: 38, child: OutlinedButton(onPressed: () => coinService.equipTitle(equipped ? null : item.id), style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(equipped ? 'Unequip' : 'Equip', style: const TextStyle(fontSize: 12))));
      case 'theme':
        final active = coinService.oceanThemeActive;
        return SizedBox(width: 90, height: 38, child: OutlinedButton(onPressed: () => coinService.setOceanThemeActive(!active), style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(active ? 'Deactivate' : 'Activate', style: const TextStyle(fontSize: 11))));
      default:
        return const Icon(Icons.check_circle_rounded, color: AppColors.success);
    }
  }

  String _statusSubtitle(CoinService coinService, ShopItem item) {
    if (item.id == 'streak_freeze') return '${coinService.streakFreezeCount} owned • ${item.cost} Cent each';
    if (!coinService.owns(item.id)) return '${item.cost} Cent';
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

  Widget _spinExclusiveTile(BuildContext context, CoinService coinService, SpinExclusiveItem item) {
    final owned = coinService.owns(item.id);
    final scheme = Theme.of(context).colorScheme;

    Widget action;
    if (!owned) {
      action = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: scheme.outlineVariant)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock_rounded, size: 14, color: scheme.onSurfaceVariant), const SizedBox(width: 4), Text('Spin only', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))]),
      );
    } else if (item.category == 'frame') {
      final equipped = coinService.equippedFrameId == item.id;
      action = OutlinedButton(onPressed: () => coinService.equipFrame(equipped ? null : item.id), child: Text(equipped ? 'Unequip' : 'Equip'));
    } else {
      final equipped = coinService.equippedTitleId == item.id;
      action = OutlinedButton(onPressed: () => coinService.equipTitle(equipped ? null : item.id), child: Text(equipped ? 'Unequip' : 'Equip'));
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: owned ? [item.rarityColor.withOpacity(0.16), Colors.transparent] : [scheme.surfaceContainerHighest, scheme.surfaceContainerHighest]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: owned ? item.rarityColor.withOpacity(0.6) : scheme.outlineVariant.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Opacity(opacity: owned ? 1 : 0.35, child: Text(item.emoji, style: const TextStyle(fontSize: 28))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text(item.name, style: TextStyle(fontWeight: FontWeight.w600, color: owned ? null : scheme.onSurfaceVariant))),
                  const SizedBox(width: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: item.rarityColor.withOpacity(0.18), borderRadius: BorderRadius.circular(6)), child: Text(item.rarity, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: item.rarityColor))),
                ]),
                const SizedBox(height: 2),
                Text(owned ? 'Won from Daily Spin 🎉' : 'Only from Daily Spin', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          action,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coinService = context.watch<CoinService>();
    final scheme = Theme.of(context).colorScheme;

    if (!coinService.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: coinService.refreshBalance,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: GradientHeader(
                title: '💰 Cent Shop',
                subtitle: 'Spend Cent, chase Spin-Exclusives',
                trailing: GestureDetector(
                  onTap: coinService.refreshBalance,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${coinService.cp} CP', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        if (coinService.leftoverCent > 0) Text('+${coinService.leftoverCent} Cent', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text('Cent Store', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ...CoinService.shopItems.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ShinyCard(
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
                                    Text(_statusSubtitle(coinService, item), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildActionButton(context, coinService, item),
                            ],
                          ),
                        ),
                      )),
                  const SizedBox(height: 24),
                  Row(children: [Icon(Icons.casino_rounded, color: scheme.primary, size: 20), const SizedBox(width: 8), Text('Spin-Exclusive Collection', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 4),
                  Text('These can never be bought — only won from the Daily Spin.', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  ...CoinService.spinExclusiveItems.map((item) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _spinExclusiveTile(context, coinService, item))),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// 3. SPIN WHEEL REWARDS  (logic unchanged; keeps its own distinct
/// dark/neon aesthetic on purpose — AppBar already gives automatic back
/// navigation, so no structural change needed there)
/// =========================================================================

class _WheelSegment {
  final String label;
  final Color color;
  final IconData icon;
  final int? xp;
  final String? spinItemId;
  final double weight;
  const _WheelSegment({required this.label, required this.color, required this.icon, this.xp, this.spinItemId, required this.weight});
}

class SpinWheelScreen extends StatefulWidget {
  const SpinWheelScreen({super.key});

  @override
  State<SpinWheelScreen> createState() => _SpinWheelScreenState();
}

class _SpinWheelScreenState extends State<SpinWheelScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _spinning = false;
  String? _resultLabel;
  Color? _resultColor;

  static final List<_WheelSegment> _segments = [
    const _WheelSegment(label: '10 XP', color: Color(0xFF00E5FF), icon: Icons.bolt_rounded, xp: 10, weight: 22),
    const _WheelSegment(label: '15 XP', color: Color(0xFF7C4DFF), icon: Icons.bolt_rounded, xp: 15, weight: 20),
    const _WheelSegment(label: 'Try Again', color: Color(0xFF546E7A), icon: Icons.replay_rounded, weight: 16),
    const _WheelSegment(label: '25 XP', color: Color(0xFF00BFA5), icon: Icons.bolt_rounded, xp: 25, weight: 14),
    _WheelSegment(label: 'Neon Frame', color: const Color(0xFF00E5FF), icon: Icons.auto_awesome_rounded, spinItemId: 'spin_frame_neon', weight: 8),
    const _WheelSegment(label: '40 XP', color: Color(0xFFFF6E40), icon: Icons.bolt_rounded, xp: 40, weight: 8),
    _WheelSegment(label: 'Lucky Title', color: const Color(0xFF00E5FF), icon: Icons.auto_awesome_rounded, spinItemId: 'spin_title_lucky', weight: 5),
    const _WheelSegment(label: '60 XP', color: Color(0xFFFFD740), icon: Icons.bolt_rounded, xp: 60, weight: 4),
    _WheelSegment(label: 'Diamond Frame', color: const Color(0xFFB388FF), icon: Icons.diamond_rounded, spinItemId: 'spin_frame_diamond', weight: 2),
    _WheelSegment(label: 'JACKPOT — Galaxy Frame', color: const Color(0xFFFFD700), icon: Icons.stars_rounded, spinItemId: 'spin_frame_galaxy', weight: 1),
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

  _WheelSegment _pickWeighted() {
    final totalWeight = _segments.fold<double>(0, (sum, s) => sum + s.weight);
    final roll = Random().nextDouble() * totalWeight;
    double cumulative = 0;
    for (final s in _segments) {
      cumulative += s.weight;
      if (roll <= cumulative) return s;
    }
    return _segments.first;
  }

  void _spin() {
    final coinService = context.read<CoinService>();
    if (!coinService.canSpinToday || _spinning) return;
    setState(() {
      _spinning = true;
      _resultLabel = null;
      _resultColor = null;
    });

    final segment = _pickWeighted();
    _controller.forward(from: 0).whenComplete(() async {
      await coinService.recordSpin();

      if (segment.xp != null) {
        context.read<AppProvider>().addXP(segment.xp!);
      }

      SpinExclusiveItem? wonItem;
      bool duplicateFallback = false;
      if (segment.spinItemId != null) {
        final granted = await coinService.grantSpinExclusiveItem(segment.spinItemId!);
        if (granted) {
          wonItem = CoinService.spinExclusiveItems.firstWhere((i) => i.id == segment.spinItemId);
        } else {
          duplicateFallback = true;
          context.read<AppProvider>().addXP(30);
        }
      }

      if (!mounted) return;
      setState(() {
        _spinning = false;
        _resultLabel = duplicateFallback ? 'Already owned — +30 XP bonus!' : segment.label;
        _resultColor = segment.color;
      });

      if (wonItem != null && mounted) {
        await showSpinWinCelebration(context, wonItem);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final coinService = context.watch<CoinService>();
    final alreadySpunToday = !coinService.canSpinToday;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E1A),
      appBar: AppBar(title: const Text('Daily Spin'), backgroundColor: const Color(0xFF0B0E1A), foregroundColor: Colors.white, elevation: 0),
      body: Stack(
        children: [
          Positioned(top: -80, left: -60, child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7C4DFF).withOpacity(0.18)))),
          Positioned(bottom: -100, right: -60, child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF00E5FF).withOpacity(0.12)))),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Spin for XP — and a shot at a Spin-Exclusive prize', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13)),
                    const SizedBox(height: 28),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.35), blurRadius: 50, spreadRadius: 4)])),
                        RotationTransition(
                          turns: Tween(begin: 0.0, end: 8.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic)),
                          child: Container(
                            width: 240,
                            height: 240,
                            decoration: BoxDecoration(shape: BoxShape.circle, gradient: SweepGradient(colors: _segments.map((s) => s.color).toList()), border: Border.all(color: Colors.white.withOpacity(0.15), width: 3)),
                            child: Center(
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(color: const Color(0xFF0B0E1A), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.3), width: 2)),
                                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
                              ),
                            ),
                          ),
                        ),
                        Positioned(top: -6, child: Icon(Icons.arrow_drop_down_rounded, size: 48, color: Colors.white.withOpacity(0.9))),
                      ],
                    ),
                    const SizedBox(height: 36),
                    if (_resultLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(color: (_resultColor ?? Colors.white).withOpacity(0.15), borderRadius: BorderRadius.circular(16), border: Border.all(color: (_resultColor ?? Colors.white).withOpacity(0.6))),
                        child: Text('You won: $_resultLabel!', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: (alreadySpunToday || _spinning) ? Colors.white24 : const Color(0xFF00E5FF), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 0),
                        onPressed: (alreadySpunToday || _spinning) ? null : _spin,
                        child: Text(alreadySpunToday ? 'Come back tomorrow' : (_spinning ? 'Spinning...' : 'Spin Now'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =========================================================================
/// 4. MULTI-EXAM COUNTDOWN  (service unchanged — logic only)
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
          return ExamCountdownEntry(id: row['id'] as String, examName: row['exam_name'] as String, examDate: DateTime.parse(row['exam_date'] as String));
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
      final row = await _client.from('exam_countdowns').insert({'user_id': user.id, 'exam_name': name, 'exam_date': date.toIso8601String().split('T').first}).select().single();
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
      await _client.from('exam_countdowns').update({'exam_date': newDate.toIso8601String().split('T').first}).eq('id', id);
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Add Exam'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Exam name (e.g. WAEC, JAMB)')),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text(pickedDate == null ? 'Choose date' : '${pickedDate!.year}-${pickedDate!.month.toString().padLeft(2, '0')}-${pickedDate!.day.toString().padLeft(2, '0')}'),
                    onPressed: () async {
                      final picked = await showDatePicker(context: dialogContext, initialDate: DateTime.now().add(const Duration(days: 90)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365 * 2)));
                      if (picked != null) setDialogState(() => pickedDate = picked);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                FilledButton(onPressed: (nameController.text.trim().isEmpty || pickedDate == null) ? null : () => Navigator.pop(dialogContext, true), child: const Text('Add')),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final exams = service.exams;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: GradientHeader(title: '⏳ Exam Countdown', subtitle: 'Days left to WAEC, JAMB, NECO...')),
          if (exams.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: _EmptyState(icon: Icons.hourglass_bottom_rounded, title: 'No exams added yet', subtitle: "Tap + to add WAEC, JAMB, NECO, or any exam you're preparing for."))
          else
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final exam = exams[index];
                    final remaining = exam.examDate.difference(DateTime.now());
                    final isPast = remaining.isNegative;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: isPast ? null : AppTheme.heroGradient(context),
                          color: isPast ? AppColors.error.withOpacity(0.12) : null,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: isPast ? null : [BoxShadow(color: scheme.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              Expanded(child: Text(exam.examName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isPast ? scheme.onSurface : Colors.white))),
                              IconButton(icon: Icon(Icons.delete_outline_rounded, color: isPast ? scheme.onSurface : Colors.white), onPressed: () => ExamCountdownService.instance.removeExam(exam.id)),
                            ]),
                            const SizedBox(height: 8),
                            if (isPast)
                              Text('This exam date has passed.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurface))
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
                      ),
                    );
                  },
                  childCount: exams.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _addExamDialog(context), child: const Icon(Icons.add_rounded)),
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
        Text('$value', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}

/// =========================================================================
/// 5. TOPIC MASTERY + FOCUS MODE  (service unchanged — logic only)
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
      await _client.from('subject_mastery').upsert({'user_id': user.id, 'subject': subject, 'correct': tally.correct, 'total': tally.total});
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
    if (mastery >= 0.75) return AppColors.success;
    if (mastery >= 0.5) return AppColors.xp;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<MasteryService>();

    if (!service.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final subjects = service.trackedSubjects;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: GradientHeader(title: '🎯 Topic Mastery', subtitle: 'Your accuracy by subject')),
          if (subjects.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: _EmptyState(icon: Icons.track_changes_rounded, title: 'No mastery data yet', subtitle: 'Complete a few practice exams to see your mastery by subject.'))
          else
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final subject = subjects[index];
                    final mastery = service.masteryFor(subject);
                    final color = _colorFor(mastery);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ShinyCard(
                        tint: color,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text(subject, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${(mastery * 100).toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                            ]),
                            const SizedBox(height: 8),
                            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: mastery, minHeight: 10, backgroundColor: Theme.of(context).colorScheme.surface, valueColor: AlwaysStoppedAnimation(color))),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: subjects.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FocusModeScreen extends StatelessWidget {
  const FocusModeScreen({super.key});

  static const int _minAttemptsToRank = 5;
  static const int _questionsPerSubject = 15;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final scheme = Theme.of(context).colorScheme;

    final ranked = provider.getAvailableSubjects().where((s) => (provider.stats.subjectAttempts[s] ?? 0) >= _minAttemptsToRank).map((s) => MapEntry(s, provider.getSubjectScore(s))).toList()..sort((a, b) => a.value.compareTo(b.value));
    final weakest = ranked.take(3).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: GradientHeader(title: '🎯 Focus Mode', subtitle: 'Target your weakest subjects')),
          if (weakest.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _EmptyState(icon: Icons.track_changes_rounded, title: 'Not enough data yet', subtitle: 'Practice at least $_minAttemptsToRank questions in a subject to see your weakest areas here.'))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text('Your weakest subjects right now — a focused mock exam targeting these will help the most.', style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  ...weakest.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ShinyCard(
                          tint: AppColors.warning,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: (e.value / 100).clamp(0.0, 1.0), minHeight: 8, backgroundColor: scheme.surface, valueColor: const AlwaysStoppedAnimation(AppColors.warning))),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text('${e.value.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      )),
                  const SizedBox(height: 20),
                  GradientButton(
                    label: 'Start Focus Practice',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () {
                      final subjects = weakest.map((e) => e.key).toList();
                      final questions = provider.generateMockExamMulti(subjects, _questionsPerSubject);
                      Navigator.of(context).push(MaterialPageRoute(
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
                      ));
                    },
                  ),
                ]),
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
