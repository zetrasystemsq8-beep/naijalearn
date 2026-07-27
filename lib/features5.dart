// lib/features5.dart
//
// Five new features bundled together so main.dart only needs one import:
// 1. Flashcards + Spaced Repetition
// 2. Coin Shop
// 3. Spin Wheel Rewards (spends into Coin Shop, awards XP via AppProvider)
// 4. Exam Countdown
// 5. Topic Mastery Tracker
//
// Each feature has its own lightweight ChangeNotifier service so state is
// shared and reactive across screens. Register CoinService, FlashcardService
// and MasteryService as providers in main() alongside AppProvider.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  FlashcardService._();
  static final FlashcardService instance = FlashcardService._();

  final List<Flashcard> _cards = [];
  int _nextId = 1;

  List<Flashcard> get all => List.unmodifiable(_cards);

  List<Flashcard> forSubject(String subject) =>
      _cards.where((c) => c.subject == subject).toList();

  List<Flashcard> dueForSubject(String subject) =>
      _cards.where((c) => c.subject == subject && c.isDue).toList();

  List<String> get subjectsWithCards =>
      _cards.map((c) => c.subject).toSet().toList()..sort();

  void addCard({required String subject, required String front, required String back}) {
    _cards.add(Flashcard(id: 'fc${_nextId++}', subject: subject, front: front, back: back));
    notifyListeners();
  }

  void deleteCard(String id) {
    _cards.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  void recordResult(Flashcard card, bool correct) {
    if (correct) {
      card.markCorrect();
    } else {
      card.markWrong();
    }
    notifyListeners();
  }
}

class FlashcardsScreen extends StatelessWidget {
  const FlashcardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<FlashcardService>();
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
/// 2. COIN SHOP
/// =========================================================================

class ShopItem {
  final String id;
  final String name;
  final String emoji;
  final int cost;
  const ShopItem({required this.id, required this.name, required this.emoji, required this.cost});
}

class CoinService extends ChangeNotifier {
  CoinService._();
  static final CoinService instance = CoinService._();

  int _coins = 0;
  final Set<String> _ownedItemIds = {};

  int get coins => _coins;
  Set<String> get ownedItemIds => Set.unmodifiable(_ownedItemIds);

  static const List<ShopItem> shopItems = [
    ShopItem(id: 'frame_gold', name: 'Gold Avatar Frame', emoji: '🖼️', cost: 100),
    ShopItem(id: 'frame_fire', name: 'Fire Avatar Frame', emoji: '🔥', cost: 150),
    ShopItem(id: 'title_scholar', name: 'Scholar Title', emoji: '🎓', cost: 80),
    ShopItem(id: 'title_genius', name: 'Genius Title', emoji: '🧠', cost: 200),
    ShopItem(id: 'theme_ocean', name: 'Ocean Theme Pack', emoji: '🌊', cost: 250),
    ShopItem(id: 'streak_freeze', name: 'Streak Freeze', emoji: '🧊', cost: 50),
  ];

  void addCoins(int amount) {
    _coins += amount;
    notifyListeners();
  }

  bool purchase(ShopItem item) {
    if (_ownedItemIds.contains(item.id)) return false;
    if (_coins < item.cost) return false;
    _coins -= item.cost;
    _ownedItemIds.add(item.id);
    notifyListeners();
    return true;
  }

  bool owns(String id) => _ownedItemIds.contains(id);
}

class CoinShopScreen extends StatelessWidget {
  const CoinShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final coinService = context.watch<CoinService>();
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
          final owned = coinService.owns(item.id);
          return Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Text(item.emoji, style: const TextStyle(fontSize: 28)),
              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(owned ? 'Owned' : '${item.cost} coins'),
              trailing: owned
                  ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                  : FilledButton(
                      onPressed: coinService.coins >= item.cost
                          ? () {
                              final success = coinService.purchase(item);
                              if (success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('${item.name} purchased!')),
                                );
                              }
                            }
                          : null,
                      child: const Text('Buy'),
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
  static DateTime? _lastSpinDate;

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

  bool get _alreadySpunToday {
    if (_lastSpinDate == null) return false;
    final now = DateTime.now();
    return _lastSpinDate!.year == now.year &&
        _lastSpinDate!.month == now.month &&
        _lastSpinDate!.day == now.day;
  }

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
    if (_alreadySpunToday || _spinning) return;
    setState(() {
      _spinning = true;
      _result = null;
    });

    final segment = _segments[Random().nextInt(_segments.length)];
    _controller.forward(from: 0).whenComplete(() {
      _lastSpinDate = DateTime.now();
      if (segment.coins != null) {
        CoinService.instance.addCoins(segment.coins!);
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
                  onPressed: (_alreadySpunToday || _spinning) ? null : _spin,
                  child: Text(_alreadySpunToday
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
/// 4. EXAM COUNTDOWN
/// =========================================================================

class ExamCountdownService extends ChangeNotifier {
  ExamCountdownService._();
  static final ExamCountdownService instance = ExamCountdownService._();

  String examName = 'WAEC/WASSCE';
  DateTime? examDate;

  void setExam({required String name, required DateTime date}) {
    examName = name;
    examDate = date;
    notifyListeners();
  }

  Duration? get timeRemaining =>
      examDate == null ? null : examDate!.difference(DateTime.now());
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

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      ExamCountdownService.instance.setExam(name: ExamCountdownService.instance.examName, date: picked);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ExamCountdownService.instance;
    final remaining = service.timeRemaining;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Exam Countdown')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(service.examName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (remaining == null || remaining.isNegative)
              Column(
                children: [
                  const Text('No exam date set yet.', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _pickDate(context),
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: const Text('Set Exam Date'),
                  ),
                ],
              )
            else
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CountdownUnit(value: remaining.inDays, label: 'Days'),
                        _CountdownUnit(value: remaining.inHours % 24, label: 'Hours'),
                        _CountdownUnit(value: remaining.inMinutes % 60, label: 'Min'),
                        _CountdownUnit(value: remaining.inSeconds % 60, label: 'Sec'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(onPressed: () => _pickDate(context), child: const Text('Change Date')),
                ],
              ),
          ],
        ),
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
/// 5. TOPIC MASTERY TRACKER
/// =========================================================================

class _MasteryTally {
  int correct = 0;
  int total = 0;
}

class MasteryService extends ChangeNotifier {
  MasteryService._();
  static final MasteryService instance = MasteryService._();

  final Map<String, _MasteryTally> _bySubject = {};

  void recordSession({required String subject, required int correct, required int total}) {
    final tally = _bySubject.putIfAbsent(subject, () => _MasteryTally());
    tally.correct += correct;
    tally.total += total;
    notifyListeners();
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
