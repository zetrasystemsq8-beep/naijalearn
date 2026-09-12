// lib/classroom_discovery.dart
//
// "Tutor Classes" — replaces the old open Groups browse screen.
// Deliberately simple per spec: Popular / New / category filter chips,
// no recommendation engine.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'classroom_detail.dart';
import 'create_classroom.dart' show kClassroomCategories;

enum _SortMode { popular, newest }

class ClassroomDiscoveryScreen extends StatefulWidget {
  const ClassroomDiscoveryScreen({super.key});

  @override
  State<ClassroomDiscoveryScreen> createState() => _ClassroomDiscoveryScreenState();
}

class _ClassroomDiscoveryScreenState extends State<ClassroomDiscoveryScreen> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _classrooms = [];
  bool _loading = true;
  String? _error;
  _SortMode _sort = _SortMode.popular;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = _client.from('classrooms').select().eq('status', 'active');

      if (_selectedCategory != null) {
        query = query.contains('categories', [_selectedCategory!]);
      }
      final search = _searchController.text.trim();
      if (search.isNotEmpty) {
        query = query.ilike('name', '%$search%');
      }

      final ordered = _sort == _SortMode.popular
          ? query.order('student_count', ascending: false)
          : query.order('created_at', ascending: false);

      final rows = await ordered.limit(50);
      setState(() => _classrooms = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      setState(() => _error = 'Could not load classes right now.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Tutor Classes')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search classes',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                isDense: true,
              ),
              onSubmitted: (_) => _load(),
            ),
          ),

          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ChoiceChip(
                  label: const Text('Popular'),
                  selected: _sort == _SortMode.popular && _selectedCategory == null,
                  onSelected: (_) {
                    setState(() {
                      _sort = _SortMode.popular;
                      _selectedCategory = null;
                    });
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('New'),
                  selected: _sort == _SortMode.newest && _selectedCategory == null,
                  onSelected: (_) {
                    setState(() {
                      _sort = _SortMode.newest;
                      _selectedCategory = null;
                    });
                    _load();
                  },
                ),
                const SizedBox(width: 12),
                Container(width: 1, color: scheme.outline),
                const SizedBox(width: 12),
                ...kClassroomCategories.map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: _selectedCategory == c,
                        onSelected: (v) {
                          setState(() => _selectedCategory = v ? c : null);
                          _load();
                        },
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _classrooms.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.school_outlined, size: 48, color: scheme.onSurfaceVariant),
                                const SizedBox(height: 12),
                                const Text('No classes found'),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: _classrooms.length,
                              itemBuilder: (context, index) => _ClassroomCard(classroom: _classrooms[index]),
                            ),
                          ),
          ),
        ],
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
    final studentCount = classroom['student_count'] as int;
    final capacity = classroom['capacity'] as int;
    final isPaid = classroom['is_paid'] as bool;
    final priceCent = classroom['price_cent'] as int;
    final coverUrl = classroom['cover_image_url'] as String?;

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
            if (coverUrl != null)
              Image.network(coverUrl, height: 120, width: double.infinity, fit: BoxFit.cover)
            else
              Container(
                height: 90,
                color: scheme.primaryContainer,
                alignment: Alignment.center,
                child: Icon(Icons.school_rounded, color: scheme.onPrimaryContainer, size: 32),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(subject, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.people_outline_rounded, size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('$studentCount/$capacity students', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      const Spacer(),
                      Text(
                        isPaid ? '₦$priceCent' : 'Free',
                        style: TextStyle(fontWeight: FontWeight.bold, color: isPaid ? scheme.primary : Colors.green),
                      ),
                    ],
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
