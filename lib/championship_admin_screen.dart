// lib/championship_admin_screen.dart
//
// Admin dashboard (spec sections 22-23, 29). Every write here goes
// through the same championship_teams/rounds/matches/question_sets
// tables the tutor/student screens read — admin just has an RLS policy
// (championship_is_admin()) granting full access, so no special RPCs
// are needed for these actions.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'championship_admin_provider.dart';
import 'championship_models.dart';
import 'championship_service.dart';

class AdminChampionshipScreen extends StatelessWidget {
  const AdminChampionshipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminChampionshipProvider()..load(),
      child: const _AdminChampionshipView(),
    );
  }
}

class _AdminChampionshipView extends StatelessWidget {
  const _AdminChampionshipView();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminChampionshipProvider>();

    if (provider.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!provider.isAdmin) {
      return const Scaffold(body: Center(child: Text('Admin access required.')));
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: _SeasonPicker(provider: provider),
          bottom: const TabBar(tabs: [
            Tab(text: 'Teams'),
            Tab(text: 'Rounds'),
            Tab(text: 'Matches'),
            Tab(text: 'Question Sets'),
          ]),
        ),
        floatingActionButton: provider.seasons.isEmpty
            ? FloatingActionButton.extended(
                onPressed: () => _showCreateSeasonSheet(context, provider),
                icon: const Icon(Icons.add),
                label: const Text('New Season'),
              )
            : null,
        body: provider.selectedSeason == null
            ? Center(
                child: FilledButton(
                  onPressed: () => _showCreateSeasonSheet(context, provider),
                  child: const Text('Create your first season'),
                ),
              )
            : TabBarView(
                children: [
                  _TeamsTab(provider: provider),
                  _RoundsTab(provider: provider),
                  _MatchesTab(provider: provider),
                  _QuestionSetsTab(provider: provider),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// SEASON PICKER + CREATE
// ---------------------------------------------------------------------

class _SeasonPicker extends StatelessWidget {
  final AdminChampionshipProvider provider;
  const _SeasonPicker({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.seasons.isEmpty) return const Text('Academic Championship — Admin');
    return Row(
      children: [
        Expanded(
          child: DropdownButton<ChampionshipSeason>(
            value: provider.selectedSeason,
            isExpanded: true,
            dropdownColor: Theme.of(context).colorScheme.surface,
            underline: const SizedBox(),
            style: const TextStyle(color: Colors.white),
            items: provider.seasons
                .map((s) => DropdownMenuItem(value: s, child: Text('${s.name} (${s.status})')))
                .toList(),
            onChanged: (s) {
              if (s != null) provider.selectSeason(s);
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white),
          onPressed: () => _showCreateSeasonSheet(context, provider),
        ),
        PopupMenuButton<String>(
          onSelected: (status) => provider.setSeasonStatus(status),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'draft', child: Text('Set: draft')),
            PopupMenuItem(value: 'registration_open', child: Text('Set: registration_open')),
            PopupMenuItem(value: 'registration_closed', child: Text('Set: registration_closed')),
            PopupMenuItem(value: 'in_progress', child: Text('Set: in_progress')),
            PopupMenuItem(value: 'completed', child: Text('Set: completed')),
            PopupMenuItem(value: 'cancelled', child: Text('Set: cancelled')),
          ],
          icon: const Icon(Icons.more_vert, color: Colors.white),
        ),
      ],
    );
  }
}

void _showCreateSeasonSheet(BuildContext context, AdminChampionshipProvider provider) {
  final formKey = GlobalKey<FormState>();
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final teamLimitCtrl = TextEditingController(text: '32');
  final rosterLimitCtrl = TextEditingController(text: '10');
  final playersPerRoundCtrl = TextEditingController(text: '5');
  DateTime? regStart;
  DateTime? regEnd;
  bool submitting = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New Championship Season', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 14),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Season name', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          initialDate: DateTime.now(),
                        );
                        if (d != null) setState(() => regStart = d);
                      },
                      child: Text(regStart == null ? 'Registration start' : '${regStart!.year}-${regStart!.month}-${regStart!.day}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 400)),
                          initialDate: DateTime.now().add(const Duration(days: 7)),
                        );
                        if (d != null) setState(() => regEnd = d);
                      },
                      child: Text(regEnd == null ? 'Registration end' : '${regEnd!.year}-${regEnd!.month}-${regEnd!.day}'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: teamLimitCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Team limit', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: rosterLimitCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Roster size', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: playersPerRoundCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Per round', border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                if (provider.actionError != null) ...[
                  const SizedBox(height: 10),
                  Text(provider.actionError!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate() || regStart == null || regEnd == null) return;
                          setState(() => submitting = true);
                          final ok = await provider.createSeason(
                            name: nameCtrl.text.trim(),
                            description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                            registrationStart: regStart!,
                            registrationEnd: regEnd!,
                            teamLimit: int.tryParse(teamLimitCtrl.text) ?? 32,
                            rosterLimit: int.tryParse(rosterLimitCtrl.text) ?? 10,
                            playersPerRound: int.tryParse(playersPerRoundCtrl.text) ?? 5,
                          );
                          setState(() => submitting = false);
                          if (ok && ctx.mounted) Navigator.pop(ctx);
                        },
                  child: submitting ? const CircularProgressIndicator() : const Text('Create Season'),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------
// TEAMS TAB
// ---------------------------------------------------------------------

class _TeamsTab extends StatelessWidget {
  final AdminChampionshipProvider provider;
  const _TeamsTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.teams.isEmpty) return const Center(child: Text('No teams registered yet.'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: provider.teams.length,
      itemBuilder: (context, i) {
        final t = provider.teams[i];
        return Card(
          child: ListTile(
            title: Text(t.name),
            subtitle: Text('Status: ${t.status}${t.category != null ? ' • ${t.category}' : ''}'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'disqualify') {
                  _showDisqualifyDialog(context, provider, t.id);
                } else {
                  provider.setTeamStatus(t.id, v);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'approved', child: Text('Approve')),
                PopupMenuItem(value: 'rejected', child: Text('Reject')),
                PopupMenuItem(value: 'withdrawn', child: Text('Mark withdrawn')),
                PopupMenuItem(value: 'disqualify', child: Text('Disqualify…')),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDisqualifyDialog(BuildContext context, AdminChampionshipProvider provider, String teamId) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disqualify team'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Reason')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              provider.disqualifyTeam(teamId, ctrl.text.trim().isEmpty ? 'No reason given' : ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Disqualify'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// ROUNDS TAB
// ---------------------------------------------------------------------

class _RoundsTab extends StatelessWidget {
  final AdminChampionshipProvider provider;
  const _RoundsTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: provider.rounds.isEmpty
              ? const Center(child: Text('No rounds yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: provider.rounds.length,
                  itemBuilder: (context, i) {
                    final r = provider.rounds[i];
                    return Card(
                      child: ListTile(
                        title: Text('${r.roundNumber}. ${r.name}'),
                        subtitle: Text('${r.status} • opens ${_fmt(r.opensAt)} • closes ${_fmt(r.closesAt)}'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) => provider.setRoundStatus(r.id, v),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'scheduled', child: Text('Set: scheduled')),
                            PopupMenuItem(value: 'open', child: Text('Open round')),
                            PopupMenuItem(value: 'closed', child: Text('Close round')),
                            PopupMenuItem(value: 'cancelled', child: Text('Cancel round')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () => _showCreateRoundSheet(context, provider),
            icon: const Icon(Icons.add),
            label: const Text('New Round'),
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime d) => '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _showCreateRoundSheet(BuildContext context, AdminChampionshipProvider provider) {
    final nameCtrl = TextEditingController();
    final numberCtrl = TextEditingController(text: '${provider.rounds.length + 1}');
    DateTime? opensAt;
    DateTime? closesAt;
    String? questionSetId;
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New Round', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 14),
                TextField(controller: numberCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Round number', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Round name (e.g. Quarterfinal)', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Question set', border: OutlineInputBorder()),
                  items: provider.questionSets
                      .map((q) => DropdownMenuItem(value: q.id, child: Text('${q.name} (${q.questionCount}q)')))
                      .toList(),
                  onChanged: (v) => questionSetId = v,
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final dt = await _pickDateTime(ctx);
                        if (dt != null) setState(() => opensAt = dt);
                      },
                      child: Text(opensAt == null ? 'Opens at' : _fmt(opensAt!)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final dt = await _pickDateTime(ctx);
                        if (dt != null) setState(() => closesAt = dt);
                      },
                      child: Text(closesAt == null ? 'Closes at' : _fmt(closesAt!)),
                    ),
                  ),
                ]),
                if (provider.actionError != null) ...[
                  const SizedBox(height: 10),
                  Text(provider.actionError!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (nameCtrl.text.trim().isEmpty || opensAt == null || closesAt == null) return;
                          setState(() => submitting = true);
                          final ok = await provider.createRound(
                            roundNumber: int.tryParse(numberCtrl.text) ?? (provider.rounds.length + 1),
                            name: nameCtrl.text.trim(),
                            opensAt: opensAt!,
                            closesAt: closesAt!,
                            questionSetId: questionSetId,
                          );
                          setState(() => submitting = false);
                          if (ok && ctx.mounted) Navigator.pop(ctx);
                        },
                  child: submitting ? const CircularProgressIndicator() : const Text('Create Round'),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<DateTime?> _pickDateTime(BuildContext context) async {
  final date = await showDatePicker(
    context: context,
    firstDate: DateTime.now().subtract(const Duration(days: 1)),
    lastDate: DateTime.now().add(const Duration(days: 400)),
    initialDate: DateTime.now(),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

// ---------------------------------------------------------------------
// MATCHES TAB
// ---------------------------------------------------------------------

class _MatchesTab extends StatelessWidget {
  final AdminChampionshipProvider provider;
  const _MatchesTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.rounds.isEmpty) return const Center(child: Text('Create a round first.'));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: provider.rounds.map((r) {
        final matches = provider.matchesByRound[r.id] ?? [];
        return Card(
          child: ExpansionTile(
            title: Text('${r.name} (${matches.length} matches)'),
            children: [
              ...matches.map((m) => ListTile(
                    dense: true,
                    title: Text('${provider.teamNames[m.teamAId] ?? '?'}  vs  ${provider.teamNames[m.teamBId] ?? '?'}'),
                    subtitle: Text(m.scoresVisible ? 'Score: ${m.teamAScore} — ${m.teamBScore} (${m.status})' : m.status),
                  )),
              Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed: () => _showCreateMatchSheet(context, provider, r),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Match'),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _showCreateMatchSheet(BuildContext context, AdminChampionshipProvider provider, ChampionshipRound round) {
    String? teamA;
    String? teamB;
    bool submitting = false;
    final approvedTeams = provider.teams.where((t) => t.status == 'approved').toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New Match — ${round.name}', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Team A', border: OutlineInputBorder()),
                items: approvedTeams.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                onChanged: (v) => teamA = v,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Team B', border: OutlineInputBorder()),
                items: approvedTeams.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                onChanged: (v) => teamB = v,
              ),
              if (provider.actionError != null) ...[
                const SizedBox(height: 10),
                Text(provider.actionError!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        if (teamA == null || teamB == null || teamA == teamB) return;
                        setState(() => submitting = true);
                        final ok = await provider.createMatch(roundId: round.id, teamAId: teamA!, teamBId: teamB!);
                        setState(() => submitting = false);
                        if (ok && ctx.mounted) Navigator.pop(ctx);
                      },
                child: submitting ? const CircularProgressIndicator() : const Text('Create Match'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// QUESTION SETS TAB
// ---------------------------------------------------------------------

class _QuestionSetsTab extends StatelessWidget {
  final AdminChampionshipProvider provider;
  const _QuestionSetsTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: provider.questionSets.isEmpty
              ? const Center(child: Text('No question sets yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: provider.questionSets.length,
                  itemBuilder: (context, i) {
                    final q = provider.questionSets[i];
                    return Card(
                      child: ListTile(
                        title: Text(q.name),
                        subtitle: Text('${q.subject} • ${q.questionCount} questions • ${q.durationSeconds ~/ 60} min'),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () => _showCreateQuestionSetSheet(context, provider),
            icon: const Icon(Icons.add),
            label: const Text('New Question Set'),
          ),
        ),
      ],
    );
  }

  void _showCreateQuestionSetSheet(BuildContext context, AdminChampionshipProvider provider) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _QuestionSetBuilderScreen(provider: provider)));
  }
}

/// Full-screen builder rather than a bottom sheet — picking dozens of
/// questions needs real scroll space, not a cramped sheet.
class _QuestionSetBuilderScreen extends StatefulWidget {
  final AdminChampionshipProvider provider;
  const _QuestionSetBuilderScreen({required this.provider});

  @override
  State<_QuestionSetBuilderScreen> createState() => _QuestionSetBuilderScreenState();
}

class _QuestionSetBuilderScreenState extends State<_QuestionSetBuilderScreen> {
  final _nameCtrl = TextEditingController();
  final _durationCtrl = TextEditingController(text: '1800');
  final _service = ChampionshipService.instance;

  List<String> _subjects = [];
  String? _subject;
  List<Map<String, dynamic>> _questions = [];
  final Set<String> _selected = {};
  bool _loadingSubjects = true;
  bool _loadingQuestions = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    final subjects = await _service.fetchDistinctSubjects();
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _loadingSubjects = false;
    });
  }

  Future<void> _onSubjectChanged(String? subject) async {
    if (subject == null) return;
    setState(() {
      _subject = subject;
      _loadingQuestions = true;
      _selected.clear();
    });
    final questions = await _service.fetchQuestionsBySubject(subject);
    if (!mounted) return;
    setState(() {
      _questions = questions;
      _loadingQuestions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Question Set')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Set name', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
              controller: _durationCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Duration (seconds)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            _loadingSubjects
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
                    value: _subject,
                    items: _subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: _onSubjectChanged,
                  ),
            const SizedBox(height: 8),
            Text('Selected: ${_selected.length}', style: Theme.of(context).textTheme.bodySmall),
            const Divider(),
            Expanded(
              child: _loadingQuestions
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _questions.length,
                      itemBuilder: (context, i) {
                        final q = _questions[i];
                        final id = q['id'] as String;
                        return CheckboxListTile(
                          value: _selected.contains(id),
                          title: Text(q['question_text'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
                        );
                      },
                    ),
            ),
            if (widget.provider.actionError != null)
              Text(widget.provider.actionError!, style: const TextStyle(color: Colors.red)),
            FilledButton(
              onPressed: _submitting || _selected.isEmpty || _subject == null
                  ? null
                  : () async {
                      setState(() => _submitting = true);
                      final ok = await widget.provider.createQuestionSet(
                        name: _nameCtrl.text.trim().isEmpty ? '$_subject Set' : _nameCtrl.text.trim(),
                        subject: _subject!,
                        durationSeconds: int.tryParse(_durationCtrl.text) ?? 1800,
                        questionIds: _selected.toList(),
                      );
                      setState(() => _submitting = false);
                      if (ok && mounted) Navigator.pop(context);
                    },
              child: _submitting
                  ? const CircularProgressIndicator()
                  : Text('Create Set (${_selected.length} questions)'),
            ),
          ],
        ),
      ),
    );
  }
}
