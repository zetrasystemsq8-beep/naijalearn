// lib/championship_tutor_screen.dart
//
// Tutor dashboard (spec sections 4-10, 21). Enforces in the UI what RLS
// also enforces server-side, so tutors get a clear message instead of a
// raw Postgres error: classroom-only roster picks, roster size cap,
// players-per-round cap, and a hard lock once a round opens.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'championship_tutor_provider.dart';
import 'championship_models.dart';

class TutorChampionshipScreen extends StatelessWidget {
  const TutorChampionshipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TutorChampionshipProvider()..load(),
      child: const _TutorChampionshipView(),
    );
  }
}

class _TutorChampionshipView extends StatelessWidget {
  const _TutorChampionshipView();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TutorChampionshipProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Championship — Coach Dashboard')),
      backgroundColor: scheme.surface,
      body: RefreshIndicator(
        onRefresh: provider.refresh,
        child: _buildBody(context, provider),
      ),
    );
  }

  Widget _buildBody(BuildContext context, TutorChampionshipProvider provider) {
    if (provider.loading) {
      return ListView(children: const [Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))]);
    }
    if (provider.error != null) {
      return ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(provider.error!))]);
    }
    if (!provider.isApprovedTutor) {
      return ListView(children: const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Text('Your tutor account is not yet approved, so you cannot register a Championship team.'),
        ),
      ]);
    }
    if (provider.season == null) {
      return ListView(children: const [
        Padding(padding: EdgeInsets.all(24), child: Text('No championship season is open for registration right now.')),
      ]);
    }
    if (provider.team == null) {
      return _RegisterTeamForm(provider: provider);
    }
    return _TeamDashboard(provider: provider);
  }
}

class _EntryFeeBanner extends StatelessWidget {
  final num entryFeeCent;
  final num balanceCent;
  const _EntryFeeBanner({required this.entryFeeCent, required this.balanceCent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final free = entryFeeCent <= 0;
    final affordable = balanceCent >= entryFeeCent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: free || affordable ? scheme.primaryContainer.withOpacity(0.4) : scheme.errorContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(free ? Icons.celebration_rounded : Icons.toll_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              free
                  ? 'This season is free to enter.'
                  : 'Entry fee: $entryFeeCent Cent  •  Your balance: $balanceCent Cent'
                      '${affordable ? '' : ' — not enough Cent to register'}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterTeamForm extends StatefulWidget {
  final TutorChampionshipProvider provider;
  const _RegisterTeamForm({required this.provider});

  @override
  State<_RegisterTeamForm> createState() => _RegisterTeamFormState();
}

class _RegisterTeamFormState extends State<_RegisterTeamForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  int? _classroomId;
  bool _submitting = false;

  bool get _canAfford => widget.provider.myCentBalance >= widget.provider.season!.entryFeeCent;

  @override
  Widget build(BuildContext context) {
    final classrooms = widget.provider.myClassrooms;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Register Your Team', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Season: ${widget.provider.season!.name}', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        _EntryFeeBanner(
          entryFeeCent: widget.provider.season!.entryFeeCent,
          balanceCent: widget.provider.myCentBalance,
        ),
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (classrooms.isEmpty)
                const Text('You have no classrooms yet — create one before registering a Championship team.')
              else
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Classroom to represent', border: OutlineInputBorder()),
                  items: classrooms
                      .map((c) => DropdownMenuItem<int>(value: c['id'] as int, child: Text(c['name'] as String)))
                      .toList(),
                  onChanged: (v) => setState(() => _classroomId = v),
                  validator: (v) => v == null ? 'Choose a classroom' : null,
                ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Team name', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a team name' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _categoryCtrl,
                decoration: const InputDecoration(labelText: 'Category (e.g. JAMB, WAEC)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Short description', border: OutlineInputBorder()),
              ),
              if (widget.provider.actionError != null) ...[
                const SizedBox(height: 12),
                Text(widget.provider.actionError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: (_submitting || classrooms.isEmpty || !_canAfford) ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Register Team'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    await widget.provider.registerTeam(
      classroomId: _classroomId!,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      category: _categoryCtrl.text.trim().isEmpty ? null : _categoryCtrl.text.trim(),
    );
    if (mounted) setState(() => _submitting = false);
  }
}

class _TeamDashboard extends StatelessWidget {
  final TutorChampionshipProvider provider;
  const _TeamDashboard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final team = provider.team!;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              CircleAvatar(radius: 26, backgroundColor: scheme.primaryContainer, child: Icon(Icons.shield_moon_rounded, color: scheme.onPrimaryContainer)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text('Status: ${team.status}', style: Theme.of(context).textTheme.bodySmall),
                    if (team.status == 'disqualified' && team.disqualifiedReason != null)
                      Text('Reason: ${team.disqualifiedReason}', style: TextStyle(color: scheme.error, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _RosterSection(provider: provider),
        const SizedBox(height: 16),
        _RoundSelectionSection(provider: provider),
      ],
    );
  }
}

class _RosterSection extends StatelessWidget {
  final TutorChampionshipProvider provider;
  const _RosterSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withOpacity(0.4), borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Roster (${provider.roster.length}/${provider.season!.rosterLimit})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showAddPlayerSheet(context, provider),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          if (provider.actionError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(provider.actionError!, style: TextStyle(color: scheme.error, fontSize: 12)),
            ),
          if (provider.roster.isEmpty)
            const Text('No players added yet.')
          else
            ...provider.roster.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundImage: p.studentAvatarUrl != null ? NetworkImage(p.studentAvatarUrl!) : null,
                    child: p.studentAvatarUrl == null ? const Icon(Icons.person, size: 16) : null,
                  ),
                  title: Text(p.studentName ?? 'Player'),
                  trailing: IconButton(
                    icon: Icon(Icons.remove_circle_outline_rounded, color: scheme.error),
                    onPressed: () => provider.removeFromRoster(p.id),
                  ),
                )),
        ],
      ),
    );
  }

  void _showAddPlayerSheet(BuildContext context, TutorChampionshipProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) {
          final rosterIds = provider.roster.map((p) => p.studentId).toSet();
          final available = provider.eligibleStudents.where((s) => !rosterIds.contains(s['student_id'])).toList();
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Text('Add from your classroom', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (available.isEmpty) const Text('No more eligible students in this classroom.'),
              ...available.map((s) {
                final studentId = s['student_id'] as String;
                final taken = provider.rosteredElsewhere.contains(studentId);
                final name = s['profiles']?['username'] as String? ?? 'Student';
                return ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text(name),
                  subtitle: taken ? const Text('Already on another Championship team this season') : null,
                  trailing: taken
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          onPressed: () async {
                            final ok = await provider.addToRoster(studentId);
                            if (ok && context.mounted) Navigator.pop(context);
                          },
                        ),
                  enabled: !taken,
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _RoundSelectionSection extends StatelessWidget {
  final TutorChampionshipProvider provider;
  const _RoundSelectionSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (provider.rounds.isEmpty) {
      return const Text('Rounds have not been scheduled yet.');
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withOpacity(0.4), borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Round Selection', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: provider.rounds
                .map((r) => ChoiceChip(
                      label: Text(r.name),
                      selected: provider.selectedRound?.id == r.id,
                      onSelected: (_) => provider.selectRound(r),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          if (provider.matchForSelectedRound == null)
            const Text('No match scheduled for your team in this round.')
          else ...[
            Text(
              provider.canEditSelectionForCurrentRound
                  ? 'Pick ${provider.season!.playersPerRound} players for this round (locks once the round opens):'
                  : 'Selections are locked for this round.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (provider.actionError != null)
              Text(provider.actionError!, style: TextStyle(color: scheme.error, fontSize: 12)),
            ...provider.roster.map((p) {
              final selected = provider.currentSelections.any((s) => s.studentId == p.studentId);
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: selected,
                onChanged: provider.canEditSelectionForCurrentRound ? (_) => provider.toggleSelection(p.studentId) : null,
                title: Text(p.studentName ?? 'Player'),
              );
            }),
          ],
        ],
      ),
    );
  }
}
