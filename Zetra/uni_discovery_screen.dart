import 'package:flutter/material.dart';
import 'uni_controller.dart';
import 'uni_models.dart';

class UniDiscoveryScreen extends StatefulWidget {
  const UniDiscoveryScreen({super.key, required this.ctrl});
  final UniversityController ctrl;
  @override
  State<UniDiscoveryScreen> createState() => _UniDiscoveryScreenState();
}

class _UniDiscoveryScreenState extends State<UniDiscoveryScreen> {
  static const levels = ['100 Level', '200 Level', '300 Level', '400 Level', '500 Level'];
  static const semesters = ['First Semester', 'Second Semester'];
  final _q = TextEditingController();
  String? level, semester;
  late Future<List<UniListing>> _f = _run();

  Future<List<UniListing>> _run() =>
      widget.ctrl.repo.search(query: _q.text, level: level, semester: semester);
  void _load() => setState(() => _f = _run());

  @override
  void dispose() { _q.dispose(); super.dispose(); }

  Future<void> _enroll(UniListing l) async {
    final free = l.price == 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enroll in ${l.course.code}?'),
        content: Text(free
            ? 'This course is free.'
            : 'Price: ${l.price} Cent, charged from your NaijaLearn wallet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(free ? 'Enroll' : 'Pay & enroll')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.ctrl.enroll(l.course.id);
      if (mounted) _load();
    } on UniException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  DropdownButtonFormField<String?> _drop(String hint, List<String> items, String? value, void Function(String?) on) =>
      DropdownButtonFormField<String?>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: hint, isDense: true),
        items: [
          DropdownMenuItem<String?>(value: null, child: Text('Any')),
          for (final i in items) DropdownMenuItem<String?>(value: i, child: Text(i)),
        ],
        onChanged: (v) { on(v); _load(); },
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find courses')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _q,
            onChanged: (_) => _load(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Course code, name, tutor or university',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: _drop('Level', levels, level, (v) => level = v)),
            const SizedBox(width: 12),
            Expanded(child: _drop('Semester', semesters, semester, (v) => semester = v)),
          ]),
        ),
        Expanded(child: FutureBuilder<List<UniListing>>(
          future: _f,
          builder: (c, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return Center(child: Text('${s.error}'));
            final list = s.data ?? [];
            if (list.isEmpty) return const Center(child: Text('No courses found.'));
            return ListView(padding: const EdgeInsets.all(12), children: [
              for (final l in list)
                Card(child: ListTile(
                  title: Text('${l.course.code} — ${l.course.title}'),
                  subtitle: Text('${l.university} • ${l.department}\n${l.course.level} • ${l.tutor} • ${l.price == 0 ? 'Free' : '${l.price} Cent'}'),
                  isThreeLine: true,
                  trailing: l.enrolled
                      ? const Chip(label: Text('Enrolled'))
                      : FilledButton.tonal(onPressed: () => _enroll(l), child: const Text('Enroll')),
                )),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Courses are created by tutors on NaijaLearn and are not official university material.', style: TextStyle(fontSize: 12)),
              ),
            ]);
          },
        )),
      ]),
    );
  }
}
