// lib/championship_screen.dart
//
// Student view of the Academic Championship (spec section 20).
// Visual language matches LoginScreen: gradient header using the theme's
// colorScheme, white rounded content cards, soft shadows — no hardcoded
// colors, so it stays in sync with app_theme.dart automatically.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'championship_provider.dart';
import 'championship_models.dart';
import 'championship_quiz_screen.dart';

class StudentChampionshipScreen extends StatelessWidget {
  const StudentChampionshipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => StudentChampionshipProvider()..load(),
      child: const _StudentChampionshipView(),
    );
  }
}

class _StudentChampionshipView extends StatelessWidget {
  const _StudentChampionshipView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.watch<StudentChampionshipProvider>();

    return Scaffold(
      backgroundColor: scheme.surface,
      body: RefreshIndicator(
        onRefresh: provider.refresh,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 140,
              pinned: true,
              backgroundColor: scheme.primary,
              flexibleSpace: FlexibleSpaceBar(
                title: const Text('Academic Championship', style: TextStyle(color: Colors.white)),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [scheme.primary, scheme.tertiary.withOpacity(0.85)],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -30,
                        right: -20,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildBody(context, provider)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, StudentChampionshipProvider provider) {
    if (provider.loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (provider.error != null) {
      return _MessageCard(icon: Icons.error_outline_rounded, message: provider.error!);
    }
    if (provider.season == null) {
      return const _MessageCard(
        icon: Icons.emoji_events_outlined,
        message: 'No championship season is running right now. Check back soon!',
      );
    }
    if (provider.team == null) {
      return const _MessageCard(
        icon: Icons.groups_outlined,
        message: "You're not on a Championship roster this season. Ask your tutor to add you if your classroom is registered.",
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final team = provider.team!;
    final round = provider.currentRound;
    final match = provider.currentMatch;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primaryContainer,
                  backgroundImage: team.logoUrl != null ? NetworkImage(team.logoUrl!) : null,
                  child: team.logoUrl == null
                      ? Icon(Icons.shield_moon_rounded, color: scheme.onPrimaryContainer)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(team.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      if (provider.coachName != null)
                        Text('Coach: ${provider.coachName}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                _StatusPill(status: team.status),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (round == null)
            const _MessageCard(icon: Icons.hourglass_empty_rounded, message: 'Rounds have not been scheduled yet.')
          else ...[
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flag_rounded, color: scheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(round.name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      _StatusPill(status: round.status),
                    ],
                  ),
                  if (match != null) ...[
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(team.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text('VS', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Text(
                            provider.opponentTeam?.name ?? 'TBD',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    if (match.scoresVisible) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text('${match.teamAScore}', textAlign: TextAlign.center)),
                          const Text('RESULTS AVAILABLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          Expanded(child: Text('${match.teamBScore}', textAlign: TextAlign.center)),
                        ],
                      ),
                    ] else if (round.status == 'open') ...[
                      const SizedBox(height: 10),
                      const Center(child: Text("Your team's match is currently active.", style: TextStyle(fontStyle: FontStyle.italic))),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSelectionCard(context, provider),
          ],
          const SizedBox(height: 14),
          _RosterCard(roster: provider.roster),
        ],
      ),
    );
  }

  Widget _buildSelectionCard(BuildContext context, StudentChampionshipProvider provider) {
    final round = provider.currentRound!;
    final match = provider.currentMatch;
    final scheme = Theme.of(context).colorScheme;

    if (match == null) {
      return const _MessageCard(icon: Icons.event_busy_rounded, message: 'No match scheduled for this round yet.');
    }
    if (!provider.isSelectedForCurrentMatch) {
      return const _MessageCard(
        icon: Icons.info_outline_rounded,
        message: 'You are on the team roster but were not selected for this round.',
      );
    }

    final attempt = provider.myAttempt;
    if (attempt != null && attempt.status != 'not_started') {
      final label = switch (attempt.status) {
        'submitted' => 'Submitted — score available after the round closes.',
        'forfeited' => 'Time expired before you submitted.',
        'in_progress' => 'Attempt in progress.',
        _ => attempt.status,
      };
      return _Card(
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
          ],
        ),
      );
    }

    final canStart = round.status == 'open';
    return _Card(
      color: scheme.errorContainer.withOpacity(canStart ? 0.5 : 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🔴 YOU HAVE BEEN SELECTED', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onErrorContainer)),
          const SizedBox(height: 6),
          Text('Opens: ${_formatDateTime(round.opensAt)}\nCloses: ${_formatDateTime(round.closesAt)}'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canStart
                  ? () async {
                      final started = await ChampionshipQuizScreen.startAndOpen(context, match.id);
                      if (started) provider.refresh();
                    }
                  : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(canStart ? 'Start Attempt' : 'Round not open yet'),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour >= 12 ? 'PM' : 'AM';
  final min = local.minute.toString().padLeft(2, '0');
  return '${local.day}/${local.month} $h:$min $ampm';
}

class _Card extends StatelessWidget {
  final Widget child;
  final Color? color;
  const _Card({required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _MessageCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer),
      ),
    );
  }
}

class _RosterCard extends StatelessWidget {
  final List<ChampionshipPlayer> roster;
  const _RosterCard({required this.roster});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Team Roster', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...roster.map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundImage: p.studentAvatarUrl != null ? NetworkImage(p.studentAvatarUrl!) : null,
                      child: p.studentAvatarUrl == null ? const Icon(Icons.person, size: 14) : null,
                    ),
                    const SizedBox(width: 10),
                    Text(p.studentName ?? 'Player'),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
