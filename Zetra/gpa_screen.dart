import 'package:flutter/material.dart';
import 'models.dart';
import 'university_controller.dart';

class GpaScreen extends StatefulWidget {
  const GpaScreen({super.key, required this.ctrl});
  final UniversityController ctrl;
  @override
  State<GpaScreen> createState() => _GpaScreenState();
}

class _GpaScreenState extends State<GpaScreen> {
  static const sems = ['1st Semester', '2nd Semester'];
  final code = TextEditingController();
  final units = TextEditingController(text: '3');
  String? grade;
  String sem = sems.first;

  Future<void> _add() async {
    final u = int.tryParse(units.text);
    if (code.text.trim().isEmpty || u == null || u <= 0 || grade == null) return;
    await widget.ctrl.addResult(ResultEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        code: code.text.trim().toUpperCase(), units: u, grade: grade!, semester: sem));
    code.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (grade != null && !c.scale.points.containsKey(grade)) grade = null;
        String f(double? v) => v == null ? '—' : v.toStringAsFixed(2);
        return Scaffold(
          appBar: AppBar(title: const Text('GPA / CGPA')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            SegmentedButton<GradeScale>(
              segments: [for (final s in GradeScale.values) ButtonSegment(value: s, label: Text(s.label))],
              selected: {c.scale},
              onSelectionChanged: (s) => c.setScale(s.first),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _Stat('$sem GPA', f(c.gpa(semester: sem)))),
              const SizedBox(width: 12),
              Expanded(child: _Stat('CGPA', f(c.gpa()))),
            ]),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: sem, decoration: const InputDecoration(labelText: 'Semester'),
              items: [for (final s in sems) DropdownMenuItem(value: s, child: Text(s))],
              onChanged: (v) => setState(() => sem = v ?? sem),
            ),
            TextField(controller: code, decoration: const InputDecoration(labelText: 'Course code')),
            Row(children: [
              Expanded(child: TextField(
                controller: units, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Units'))),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<String>(
                value: grade, decoration: const InputDecoration(labelText: 'Grade'),
                items: [for (final g in c.scale.points.keys) DropdownMenuItem(value: g, child: Text(g))],
                onChanged: (v) => setState(() => grade = v),
              )),
            ]),
            const SizedBox(height: 12),
            FilledButton(onPressed: _add, child: const Text('Add result')),
            const SizedBox(height: 16),
            for (final r in c.results.where((r) => r.semester == sem))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${r.code} — ${r.grade}'),
                subtitle: Text('${r.units} units'),
                trailing: IconButton(
                    icon: const Icon(Icons.delete_outline), onPressed: () => c.removeResult(r.id)),
              ),
            const SizedBox(height: 8),
            const Text('Calculator only. Not an official or verified university record.',
                style: TextStyle(fontSize: 12)),
          ]),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ));
}
