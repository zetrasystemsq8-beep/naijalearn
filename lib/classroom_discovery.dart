// lib/classroom_discovery.dart
//
// "Discover Classes" — embeddable widget (no own Scaffold/AppBar), lives
// inside classes_home.dart. Default view is sectioned (Popular / New /
// Browse by Exam / Browse by Subject) per the polish-pass spec; searching
// or picking a filter switches to a flat filtered list.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'classroom_detail.dart';
import 'classroom_shared.dart' show kExamCategories, loadSubjects, formatCpCent, formatStudentCount, isNewClassroom, isPopularClassroom;

class ClassroomDiscoveryTab extends StatefulWidget {
  const ClassroomDiscoveryTab({super.key});

  @override
  State<ClassroomDiscoveryTab> createState() => _ClassroomDiscoveryTabState();
}

class _ClassroomDiscoveryTabState extends State<ClassroomDiscoveryTab> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _popular = [];
  List<Map<String, dynamic>> _newest = [];
  List<Map<String, dynamic>> _filtered = [];
  List<String> _subjects = [];

  String? _activeExam;
  String? _activeSubject;
  bool get _filterActive => _searchController.text.trim().isNotEmpty || _activeExam != null || _activeSubject != null;

  @override
  void initState() {
    super.initState();
    loadSubjects().then((s) {
      if (mounted) setState(() => _subjects = s);
    });
    _loadHome();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHome() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final popular = await _client.from('classrooms').select().eq('status', 'active').order('student_count', ascending: false).limit(10);
      final newest = await _client.from('classrooms').select().eq('status', 'active').order('created_at', ascending: false).limit(10);
      setState(() {
        _popular = List<Map<String, dynamic>>.from(popular);
        _newest = List<Map<String, dynamic>>.from(newest);
      });
    } catch (_) {
      setState(() => _error = 'Could not load classes right now.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runFilter() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = _client.from('classrooms').select().eq('status', 'active');
      if (_activeExam != null) query = query.eq('exam_category', _activeExam!);
      if (_activeSubject != null) query = query.eq('subject', _activeSubject!);
      final search = _searchController.text.trim();
      if (search.isNotEmpty) query = query.ilike('name', '%$search%');

      final rows = await query.order('student_count', ascending: false).limit(50);
      setState(() => _filtered = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      setState(() => _error = 'Could not load classes right now.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectExam(String? exam) {
    setState(() {
      _activeExam = exam;
      _activeSubject = null;
    });
    if (exam != null) _runFilter();
  }

  void _selectSubject(String? subject) {
    setState(() {
      _activeSubject = subject;
      _activeExam = null;
    });
    if (subject != null) _runFilter();
  }

  void _clearFilters() {
    setState(() {
      _activeExam = null;
      _activeSubject = null;
      _searchController.clear();
    });
  }

  Future<void> _enterInviteCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Invite Code'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. NLCLASS-7X92K', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Find Class')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    await _lookupInviteCode(code);
  }

  Future<void> _lookupInviteCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    try {
      final row = await _client.from('classrooms').select('id').eq('invite_code', code).maybeSingle();
      if (!mounted) return;
      if (row == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No classroom found with that code. Double-check it and try again.")));
        return;
      }
      // Opens the classroom PREVIEW only — the student still has to go
      // through the normal Join button and Cent-wallet debit from there.
      // The code never grants access on its own.
      Navigator.push(context, MaterialPageRoute(builder: (_) => ClassroomDetailScreen(classroomId: row['id'] as int)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not look up that code right now.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search classes or paste an invite code',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _filterActive ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: _clearFilters) : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (value) {
                    if (value.trim().toUpperCase().startsWith('NLCLASS-')) {
                      _lookupInviteCode(value);
                    } else {
                      _runFilter();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _enterInviteCode,
                icon: const Icon(Icons.qr_code_rounded),
                tooltip: 'Enter Invite Code',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : RefreshIndicator(
                      onRefresh: _filterActive ? _runFilter : _loadHome,
                      child: _filterActive ? _buildFilteredList() : _buildSectionedHome(),
                    ),
        ),
      ],
    );
  }

  Widget _buildFilteredList() {
    if (_filtered.isEmpty) {
      return ListView(children: const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No classes match that search')),
        ),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _filtered.length,
      itemBuilder: (context, index) => _ClassroomCard(classroom: _filtered[index]),
    );
  }

  Widget _buildSectionedHome() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_popular.isNotEmpty) ...[
          _SectionHeader('Popular Classes'),
          _HorizontalClassroomList(classrooms: _popular),
        ],
        if (_newest.isNotEmpty) ...[
          _SectionHeader('New Classes'),
          _HorizontalClassroomList(classrooms: _newest),
        ],
        _SectionHeader('Browse by Exam'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kExamCategories.map((e) => ChoiceChip(label: Text(e), selected: false, onSelected: (_) => _selectExam(e))).toList(),
          ),
        ),
        const SizedBox(height: 20),
        _SectionHeader('Browse by Subject'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _subjects.map((s) => ChoiceChip(label: Text(s), selected: false, onSelected: (_) => _selectSubject(s))).toList(),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}

class _HorizontalClassroomList extends StatelessWidget {
  final List<Map<String, dynamic>> classrooms;
  const _HorizontalClassroomList({required this.classrooms});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: classrooms.length,
        itemBuilder: (context, index) => SizedBox(
          width: 230,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ClassroomCard(classroom: classrooms[index]),
          ),
        ),
      ),
    );
  }
}

class _ClassroomCard extends StatelessWidget {
  final Map<String, dynamic> classroom;
  const _ClassroomCard({required this.classroom});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = classroom['name'] as String;
    final subject = classroom['subject'] as String;
    final examCategory = classroom['exam_category'] as String;
    final studentCount = classroom['student_count'] as int;
    final capacity = classroom['capacity'] as int?;
    final isPaid = classroom['is_paid'] as bool;
    final priceCent = classroom['price_cent'] as int;
    final coverUrl = classroom['cover_image_url'] as String?;
    final durationDays = classroom['duration_days'] as int?;
    final createdAt = DateTime.tryParse(classroom['created_at'] as String? ?? '');

    final isNew = createdAt != null && isNewClassroom(createdAt);
    final isPopular = isPopularClassroom(studentCount, capacity);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ClassroomDetailScreen(classroomId: classroom['id'] as int)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: coverUrl != null
                      ? Image.network(coverUrl, fit: BoxFit.cover)
                      : Container(
                          color: scheme.primaryContainer,
                          alignment: Alignment.center,
                          child: Icon(Icons.school_rounded, color: scheme.onPrimaryContainer, size: 32),
                        ),
                ),
                if (isPopular || isNew)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: isPopular ? Colors.orange : Colors.green, borderRadius: BorderRadius.circular(6)),
                      child: Text(isPopular ? 'POPULAR' : 'NEW', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.verified_rounded, size: 12, color: scheme.primary),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          '$subject • $examCategory',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${formatStudentCount(studentCount, capacity)}${durationDays != null ? ' • $durationDays-day access' : ''}',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isPaid ? formatCpCent(priceCent) : 'Free',
                    style: TextStyle(fontWeight: FontWeight.bold, color: isPaid ? scheme.primary : Colors.green, fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
