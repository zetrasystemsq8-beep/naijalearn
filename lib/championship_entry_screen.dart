// lib/championship_entry_screen.dart
// Unchanged from before — only depends on isCurrentUserApprovedTutor(),
// which still works the same way against tutor_profiles regardless of
// the championship schema rebuild.

import 'package:flutter/material.dart';
import 'championship_service.dart';
import 'championship_screen.dart';
import 'championship_tutor_screen.dart';

class ChampionshipEntryScreen extends StatefulWidget {
  const ChampionshipEntryScreen({super.key});

  @override
  State<ChampionshipEntryScreen> createState() => _ChampionshipEntryScreenState();
}

class _ChampionshipEntryScreenState extends State<ChampionshipEntryScreen> {
  bool _loading = true;
  bool _isTutor = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final isTutor = await ChampionshipService.instance.isCurrentUserApprovedTutor();
    if (!mounted) return;
    setState(() {
      _isTutor = isTutor;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _isTutor ? const TutorChampionshipScreen() : const StudentChampionshipScreen();
  }
}
