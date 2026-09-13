// lib/championship_entry_screen.dart
//
// Single entry point for "Academic Championship" in the nav — decides
// whether to show the tutor dashboard or the student view based on
// whether the signed-in user is an approved tutor, so the app doesn't
// need two separate menu entries or ask the user which role they are.

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
