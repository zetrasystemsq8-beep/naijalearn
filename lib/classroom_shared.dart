// lib/classroom_shared.dart
//
// Single source for subject/category lists used across the Tutor
// Classroom feature — nothing else should hardcode its own copy.
//
// TODO(team): kTutorSubjects below is a placeholder. Per the final
// decisions doc ("do not maintain a duplicate subject list"), this
// should be replaced with whatever your existing NaijaLearn subject
// source already is (a Supabase table, a shared Dart constant used by
// the quiz feature, etc.). I don't have visibility into that source, so
// I couldn't safely wire it in without guessing a table/constant name
// that might not exist. Swap the body of loadSubjects() below for the
// real source — every screen that calls it will pick up the change
// automatically.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Exam/category tag for a classroom — fixed set per the final decisions
/// doc. Deliberately NOT the same list as subjects.
const List<String> kExamCategories = ['JAMB', 'WAEC', 'NECO', 'General/Other'];

/// Placeholder subject list — replace loadSubjects()'s body with a call
/// into your actual subject source once identified.
const List<String> _placeholderSubjects = [
  'Mathematics', 'English', 'Biology', 'Chemistry', 'Physics', 'Economics',
  'Government', 'Literature', 'Geography', 'Agricultural Science', 'Further Mathematics',
];

/// Returns the authoritative subject list. Currently returns the
/// placeholder above synchronously wrapped in a Future so call sites
/// don't need to change when this becomes a real async fetch (e.g. a
/// Supabase table read).
Future<List<String>> loadSubjects() async {
  // TODO(team): replace with e.g.
  //   final rows = await Supabase.instance.client.from('subjects').select('name');
  //   return rows.map((r) => r['name'] as String).toList();
  return _placeholderSubjects;
}

// ---------------------------------------------------------------------------
// Currency display — NaijaLearn's economy is 1000 Cent = 1 CP, CP is the
// larger denomination shown to users. Every screen that shows a Cent
// amount (classroom price, wallet balance, revenue) should go through
// this, not print raw "Cent" numbers for large amounts.
//
// TODO(team): if wallet_display.dart or another file already has an
// equivalent formatter, use that one instead and delete this — I built
// this because I couldn't find an existing shared one to import, not
// because one shouldn't exist.
// ---------------------------------------------------------------------------
const int kCentPerCp = 1000;

/// Formats a raw Cent amount as "X CP", "X CP Y Cent", or "Y Cent" —
/// never a bare four-digit Cent number once it crosses 1 CP.
String formatCpCent(int totalCent) {
  final cp = totalCent ~/ kCentPerCp;
  final cent = totalCent % kCentPerCp;
  if (cp > 0 && cent > 0) return '$cp CP $cent Cent';
  if (cp > 0) return '$cp CP';
  return '$cent Cent';
}

/// A classroom created within the last 7 days — simple, honest "new"
/// signal, not a fabricated badge.
bool isNewClassroom(DateTime createdAt) => DateTime.now().difference(createdAt).inDays <= 7;

/// A classroom in the top slice of enrollment among what's currently
/// loaded — computed from real student_count, not a fake number.
bool isPopularClassroom(int studentCount, int capacity) {
  if (studentCount < 5) return false; // avoid calling a 1-student class "popular"
  return capacity > 0 && (studentCount / capacity) >= 0.5;
}

// ---------------------------------------------------------------------------
// Display names — never show a raw UUID to a tutor or in chat. profiles
// has a `username` column (see ZetraProfile in main.dart); this batches
// the lookup so a screen with N students makes 1 query, not N.
// ---------------------------------------------------------------------------
Future<Map<String, String>> loadUsernames(List<String> userIds) async {
  if (userIds.isEmpty) return {};
  try {
    final rows = await Supabase.instance.client
        .from('profiles')
        .select('id, username')
        .inFilter('id', userIds.toSet().toList());
    return {for (final r in (rows as List)) r['id'] as String: (r['username'] as String?)?.trim().isNotEmpty == true ? r['username'] as String : 'Student'};
  } catch (_) {
    return {for (final id in userIds) id: 'Student'};
  }
}
