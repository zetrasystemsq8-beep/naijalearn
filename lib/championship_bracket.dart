// lib/championship_bracket.dart
// REPLACES the earlier version. get_championship_bracket returns one
// flat list of rows (round+match+team names+scores already joined) —
// this groups them by round_number client-side instead of the earlier
// version's separate rounds/matches/teamNames fetches.

import 'package:flutter/material.dart';
import 'championship_service.dart';
import 'championship_models.dart';

class ChampionshipBracketScreen extends StatefulWidget {
  final int seasonId;
  const ChampionshipBracketScreen({super.key, required this.seasonId});

  @override
  State<ChampionshipBracketScreen> createState() => _ChampionshipBracketScreenState();
}

class _ChampionshipBracketScreenState extends State<ChampionshipBracketScreen> {
  final _service = ChampionshipService.instance;
  bool _loading = true;
  String? _error;
  List<String> _roundNames = [];
  List<List<ChampionshipBracketRow>> _bracket = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _service.fetchBracket(widget.seasonId);
      final byRound = <int, List<ChampionshipBracketRow>>{};
      for (final r in rows) {
        byRound.putIfAbsent(r.roundNumber, () => []).add(r);
      }
      final sortedRoundNumbers = byRound.keys.toList()..sort();
      setState(() {
        _roundNames = sortedRoundNumbers.map((n) => byRound[n]!.first.roundName).toList();
        _bracket = sortedRoundNumbers.map((n) => byRound[n]!).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load bracket: $e';
        _loading = false;
      });
    }
  }

  bool get _isCleanBracket {
    for (int r = 0; r < _bracket.length - 1; r++) {
      if (_bracket[r].length != _bracket[r + 1].length * 2) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tournament Bracket')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _bracket.isEmpty
                  ? const Center(child: Text('No matches scheduled yet.'))
                  : _isCleanBracket
                      ? ChampionshipBracket(roundNames: _roundNames, rounds: _bracket)
                      : _FallbackStackedBracket(roundNames: _roundNames, rounds: _bracket),
    );
  }
}

class ChampionshipBracket extends StatelessWidget {
  final List<String> roundNames;
  final List<List<ChampionshipBracketRow>> rounds;
  static const double cardWidth = 170;
  static const double cardHeight = 64;
  static const double columnGap = 56;
  static const double unit = 96;

  const ChampionshipBracket({super.key, required this.roundNames, required this.rounds});

  @override
  Widget build(BuildContext context) {
    final round0Count = rounds.isNotEmpty ? rounds.first.length : 0;
    final totalHeight = unit * round0Count + 40;
    final totalWidth = rounds.length * (cardWidth + columnGap) + columnGap;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: totalWidth,
        height: totalHeight,
        child: Stack(
          children: [
            CustomPaint(
              size: Size(totalWidth, totalHeight),
              painter: _BracketConnectorPainter(
                roundCounts: rounds.map((r) => r.length).toList(),
                cardWidth: cardWidth,
                columnGap: columnGap,
                unit: unit,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            for (int r = 0; r < rounds.length; r++) ...[
              Positioned(
                left: r * (cardWidth + columnGap) + columnGap,
                top: 4,
                child: SizedBox(
                  width: cardWidth,
                  child: Text(
                    roundNames.length > r ? roundNames[r] : 'Round ${r + 1}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              for (int i = 0; i < rounds[r].length; i++)
                Positioned(
                  left: r * (cardWidth + columnGap) + columnGap,
                  top: unit * (1 << r) * (i + 0.5) - cardHeight / 2 + 24,
                  child: _BracketMatchCard(match: rounds[r][i], width: cardWidth, height: cardHeight),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BracketMatchCard extends StatelessWidget {
  final ChampionshipBracketRow match;
  final double width;
  final double height;
  const _BracketMatchCard({required this.match, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TeamRow(name: match.teamAName, score: match.teamAScore, isWinner: match.winnerTeamId == match.teamAId),
          const Divider(height: 6),
          _TeamRow(name: match.teamBName, score: match.teamBScore, isWinner: match.winnerTeamId == match.teamBId),
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  final String name;
  final num? score;
  final bool isWinner;
  const _TeamRow({required this.name, this.score, required this.isWinner});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12,
      fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
      color: isWinner ? Theme.of(context).colorScheme.primary : null,
    );
    return Row(
      children: [
        Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
        if (score != null) Text('$score', style: style),
      ],
    );
  }
}

class _BracketConnectorPainter extends CustomPainter {
  final List<int> roundCounts;
  final double cardWidth;
  final double columnGap;
  final double unit;
  final Color color;

  _BracketConnectorPainter({required this.roundCounts, required this.cardWidth, required this.columnGap, required this.unit, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;

    for (int r = 0; r < roundCounts.length - 1; r++) {
      final thisColX = r * (cardWidth + columnGap) + columnGap + cardWidth;
      final nextColX = (r + 1) * (cardWidth + columnGap) + columnGap;
      final midX = (thisColX + nextColX) / 2;

      for (int i = 0; i < roundCounts[r]; i++) {
        final y = unit * (1 << r) * (i + 0.5) + 24;
        canvas.drawLine(Offset(thisColX, y), Offset(midX, y), paint);

        final nextY = unit * (1 << (r + 1)) * ((i ~/ 2) + 0.5) + 24;
        if (i.isEven) {
          final partnerY = unit * (1 << r) * (i + 1 + 0.5) + 24;
          canvas.drawLine(Offset(midX, y), Offset(midX, partnerY), paint);
        }
        canvas.drawLine(Offset(midX, nextY), Offset(nextColX, nextY), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BracketConnectorPainter oldDelegate) => false;
}

class _FallbackStackedBracket extends StatelessWidget {
  final List<String> roundNames;
  final List<List<ChampionshipBracketRow>> rounds;
  const _FallbackStackedBracket({required this.roundNames, required this.rounds});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(rounds.length, (r) {
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: 190,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(roundNames.length > r ? roundNames[r] : 'Round ${r + 1}', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...rounds[r].map((m) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _BracketMatchCard(match: m, width: 190, height: 64))),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
