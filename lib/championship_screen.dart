// lib/championship_screen.dart
//
// REPLACES the earlier version. Visual language unchanged (matches
// LoginScreen's gradient-header/white-card style), but every data
// access now goes through the new bracket-row shape instead of
// separate round/match models.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'championship_provider.dart';
import 'championship_models.dart';
import 'championship_quiz_screen.dart';
import 'championship_bracket.dart';

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
              actions: [
                if (provider.season != null)
                  IconButton(
                    icon: const Icon(Icons.account_tree_rounded, color: Colors.white),
                    tooltip: 'Tournament Bracket',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChampionshipBracketScreen(seasonId: provider.season!.id)),
                    ),
                  ),
              ],
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
      return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
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
    if (!provider.onTeam) {
      return const _MessageCard(
        icon: Icons.groups_outlined,
        message: "You're not on a Championship roster this season. Ask your tutor to add you if your classroom is registered.",
      );
    }

    final scheme = Theme.of(context).colorScheme;
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
                  backgroundImage: provider.myTeam?.logoUrl != null ? NetworkImage(provider.myTeam!.logoUrl!) : null,
                  child: provider.myTeam?.logoUrl == null
                      ? Icon(Icons.shield_moon_rounded, color: scheme.onPrimaryContainer)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(provider.teamName ?? 'Team', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      if (provider.coachName != null)
                        Text('Coach: ${provider.coachName}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (provider.myTeam != null) _StatusPill(status: provider.myTeam!.status),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (match == null)
            const _MessageCard(icon: Icons.hourglass_empty_rounded, message: 'No matches scheduled yet.')
          else ...[
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flag_rounded, color: scheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(match.roundName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      _StatusPill(status: match.roundStatus),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(match.teamAName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text('VS', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
                      Expanded(child: Text(match.teamBName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
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
                  ] else if (match.matchStatus == 'active' || match.roundStatus == 'open') ...[
                    const SizedBox(height: 10),
                    const Center(child: Text("Your team's match is currently active.", style: TextStyle(fontStyle: FontStyle.italic))),
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
    final match = provider.currentMatch!;
    final scheme = Theme.of(context).colorScheme;

    if (!provider.isSelectedForCurrentMatch) {
      return const _MessageCard(
        icon: Icons.info_outline_rounded,
        message: 'You are on the team roster but were not selected for this round.',
      );
    }

    final attempt = provider.myAttempt;
    if (attempt != null && attempt['status'] != null) {
      final status = attempt['status'] as String;
      if (status != 'not_started') {
        final label = switch (status) {
          'submitted' => 'Submitted — score available after the round closes.',
          'expired' => 'Time expired before you submitted.',
          'in_progress' => 'Attempt in progress.',
          _ => status,
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
    }

    return _Card(
      color: scheme.errorContainer.withOpacity(0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🔴 YOU HAVE BEEN SELECTED', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onErrorContainer)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final started = await ChampionshipQuizScreen.startAndOpen(context, match.matchId);
                if (started) provider.refresh();
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start Attempt'),
            ),
          ),
        ],
      ),
    );
  }
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
      child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
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
          if (roster.isEmpty) const Text('No players yet.'),
          ...roster.map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const CircleAvatar(radius: 14, child: Icon(Icons.person, size: 14)),
                    const SizedBox(width: 10),
                    Text(p.username),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
