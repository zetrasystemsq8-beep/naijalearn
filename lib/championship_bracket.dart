// lib/championship_bracket.dart
//
// Visual tournament bracket (spec section 19). Draws real connector
// lines between a round's matches and the following round, using the
// standard single-elimination layout formula: match i in round r sits
// at y = unit * 2^r * (i + 0.5), which is why it lines up with the
// midpoint of the two matches feeding into it.
//
// ASSUMPTION this widget documents rather than hides: it assumes each
// round has exactly half as many matches as the previous one, ordered
// so match `2i`/`2i+1` in round r feed match `i` in round r+1 — i.e. a
// clean bracket, which is how the admin dashboard creates matches if
// used round-by-round in order. If a season's matches don't fit that
// shape (byes, irregular pairings), it falls back to a plain stacked
// list per round with no connector lines instead of drawing something
// misleading.

import 'package:flutter/material.dart';
import 'championship_service.dart';
import 'championship_models.dart';

class BracketMatchDisplay {
  final String matchId;
  final String teamAName;
  final String teamBName;
  final num? teamAScore;
  final num? teamBScore;
  final String? winnerName;
  final String status;

  BracketMatchDisplay({
    required this.matchId,
    required this.teamAName,
    required this.teamBName,
    this.teamAScore,
    this.teamBScore,
    this.winnerName,
    required this.status,
  });
}

class ChampionshipBracketScreen extends StatefulWidget {
  final String seasonId;
  const ChampionshipBracketScreen({super.key, required this.seasonId});

  @override
  State<ChampionshipBracketScreen> createState() => _ChampionshipBracketScreenState();
}

class _ChampionshipBracketScreenState extends State<ChampionshipBracketScreen> {
  final _service = ChampionshipService.instance;
  bool _loading = true;
  String? _error;
  List<String> _roundNames = [];
  List<List<BracketMatchDisplay>> _bracket = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rounds = await _service.fetchRounds(widget.seasonId);
      final matches = await _service.fetchAllMatchesForSeason(widget.seasonId);
      final teamNames = await _service.fetchTeamNamesBySeason(widget.seasonId);

      rounds.sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
      final grouped = <List<ChampionshipMatch>>[];
      for (final r in rounds) {
        grouped.add(matches.where((m) => m.roundId == r.id).toList());
      }

      setState(() {
        _roundNames = rounds.map((r) => r.name).toList();
        _bracket = grouped
            .map((roundMatches) => roundMatches
                .map((m) => BracketMatchDisplay(
                      matchId: m.id,
                      teamAName: teamNames[m.teamAId] ?? 'TBD',
                      teamBName: teamNames[m.teamBId] ?? 'TBD',
                      teamAScore: m.teamAScore,
                      teamBScore: m.teamBScore,
                      winnerName: m.winnerTeamId != null ? teamNames[m.winnerTeamId] : null,
                      status: m.status,
                    ))
                .toList())
            .toList();
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

/// Pure/presentational — takes already-resolved display data so it can
/// be reused from student/tutor/admin screens without duplicating
/// fetch logic.
class ChampionshipBracket extends StatelessWidget {
  final List<String> roundNames;
  final List<List<BracketMatchDisplay>> rounds;
  static const double cardWidth = 170;
  static const double cardHeight = 64;
  static const double columnGap = 56;
  static const double unit = 96; // vertical slot height for round-0 matches

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
  final BracketMatchDisplay match;
  final double width;
  final double height;
  const _BracketMatchCard({required this.match, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolved = match.winnerName != null;
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
          _TeamRow(
            name: match.teamAName,
            score: match.teamAScore,
            isWinner: resolved && match.winnerName == match.teamAName,
          ),
          const Divider(height: 6),
          _TeamRow(
            name: match.teamBName,
            score: match.teamBScore,
            isWinner: resolved && match.winnerName == match.teamBName,
          ),
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

  _BracketConnectorPainter({
    required this.roundCounts,
    required this.cardWidth,
    required this.columnGap,
    required this.unit,
    required this.color,
  });

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
          // draw the vertical connector once per pair
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

/// Used when match counts don't halve cleanly round-to-round (byes,
/// irregular admin-created pairings) — no connector lines drawn, since
/// a wrong line is worse than no line.
class _FallbackStackedBracket extends StatelessWidget {
  final List<String> roundNames;
  final List<List<BracketMatchDisplay>> rounds;
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
                  Text(roundNames.length > r ? roundNames[r] : 'Round ${r + 1}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...rounds[r].map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _BracketMatchCard(match: m, width: 190, height: 64),
                      )),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
