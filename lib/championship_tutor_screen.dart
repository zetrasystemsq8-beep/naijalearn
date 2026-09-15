// lib/championship_tutor_screen.dart
// REPLACES the earlier version.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'championship_tutor_provider.dart';
import 'championship_models.dart';
import 'championship_bracket.dart';

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
      appBar: AppBar(
        title: const Text('Championship — Coach Dashboard'),
        actions: [
          if (provider.season != null)
            IconButton(
              icon: const Icon(Icons.account_tree_rounded),
              tooltip: 'Tournament Bracket',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ChampionshipBracketScreen(seasonId: provider.season!.id)),
              ),
            ),
        ],
      ),
      backgroundColor: scheme.surface,
      body: RefreshIndicator(onRefresh: provider.refresh, child: _buildBody(context, provider)),
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
        Padding(padding: EdgeInsets.all(24), child: Text('Your tutor account is not yet approved, so you cannot register a Championship team.')),
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
                  : 'Entry fee: $entryFeeCent Cent  •  Your balance: $balanceCent Cent${affordable ? '' : ' — not enough Cent to register'}',
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
        _EntryFeeBanner(entryFeeCent: widget.provider.season!.entryFeeCent, balanceCent: widget.provider.myCentBalance),
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
                  items: classrooms.map((c) => DropdownMenuItem<int>(value: c['id'] as int, child: Text(c['name'] as String))).toList(),
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
              TextFormField(controller: _categoryCtrl, decoration: const InputDecoration(labelText: 'Category (e.g. JAMB, WAEC)', border: OutlineInputBorder())),
              const SizedBox(height: 14),
              TextFormField(controller: _descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Short description', border: OutlineInputBorder())),
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
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withOpacity(0.4), borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              CircleAvatar(radius: 26, backgroundColor: scheme.primaryContainer, child: Icon(Icons.shield_moon_rounded, color: scheme.onPrimaryContainer)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text('Status: ${team.status}${team.rosterLocked ? ' • Roster locked' : ''}', style: Theme.of(context).textTheme.bodySmall),
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

class _RosterSection extends StatefulWidget {
  final TutorChampionshipProvider provider;
  const _RosterSection({required this.provider});

  @override
  State<_RosterSection> createState() => _RosterSectionState();
}

class _RosterSectionState extends State<_RosterSection> {
  final _usernameCtrl = TextEditingController();
  bool _adding = false;

  Future<void> _addPlayer() async {
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) return;
    setState(() => _adding = true);
    final ok = await widget.provider.addToRoster(username);
    setState(() => _adding = false);
    if (ok) _usernameCtrl.clear();
  }

  Future<void> _confirmLockRoster() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lock roster?'),
        content: const Text('Once locked, you cannot add or remove players for the rest of the season. This cannot be undone by you — only admin can unlock it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lock Roster')),
        ],
      ),
    );
    if (confirmed == true) widget.provider.lockRoster();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = widget.provider;
    final locked = provider.team!.rosterLocked;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withOpacity(0.4), borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Roster (${provider.roster.length}/${provider.season!.rosterLimit})', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (!locked)
                TextButton.icon(onPressed: _confirmLockRoster, icon: const Icon(Icons.lock_rounded, size: 16), label: const Text('Lock')),
            ],
          ),
          if (provider.actionError != null)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(provider.actionError!, style: TextStyle(color: scheme.error, fontSize: 12))),
          if (provider.roster.isEmpty)
            const Text('No players added yet.')
          else
            ...provider.roster.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
                  title: Text(p.username),
                  trailing: locked
                      ? null
                      : IconButton(
                          icon: Icon(Icons.remove_circle_outline_rounded, color: scheme.error),
                          onPressed: () => provider.removeFromRoster(p.studentId),
                        ),
                )),
          if (!locked) ...[
            const Divider(height: 24),
            Text('Add by username (must be in this team\'s classroom)', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(hintText: 'username', border: OutlineInputBorder(), isDense: true),
                    onSubmitted: (_) => _addPlayer(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _adding ? null : _addPlayer,
                  child: _adding ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundSelectionSection extends StatefulWidget {
  final TutorChampionshipProvider provider;
  const _RoundSelectionSection({required this.provider});

  @override
  State<_RoundSelectionSection> createState() => _RoundSelectionSectionState();
}

class _RoundSelectionSectionState extends State<_RoundSelectionSection> {
  late Set<String> _pending;

  @override
  void initState() {
    super.initState();
    _pending = widget.provider.currentSelectionStudentIds.toSet();
  }

  @override
  void didUpdateWidget(covariant _RoundSelectionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider.selectedMatch?.matchId != widget.provider.selectedMatch?.matchId) {
      _pending = widget.provider.currentSelectionStudentIds.toSet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = widget.provider;
    if (provider.myMatches.isEmpty) return const Text('No matches scheduled yet.');

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
            children: provider.myMatches
                .map((m) => ChoiceChip(
                      label: Text(m.roundName),
                      selected: provider.selectedMatch?.matchId == m.matchId,
                      onSelected: (_) async {
                        await provider.selectMatch(m);
                        setState(() => _pending = provider.currentSelectionStudentIds.toSet());
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          Text(
            provider.canEditSelection
                ? 'Pick up to ${provider.season!.playersPerRound} players (locks once the round opens):'
                : 'Selection is locked for this round.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (provider.actionError != null) Text(provider.actionError!, style: TextStyle(color: scheme.error, fontSize: 12)),
          ...provider.roster.map((p) {
            final checked = _pending.contains(p.studentId);
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: checked,
              onChanged: !provider.canEditSelection
                  ? null
                  : (v) => setState(() {
                        if (v == true) {
                          _pending.add(p.studentId);
                        } else {
                          _pending.remove(p.studentId);
                        }
                      }),
              title: Text(p.username),
            );
          }),
          if (provider.canEditSelection) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => provider.saveSelection(_pending.toList()),
                child: const Text('Save Selection'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
