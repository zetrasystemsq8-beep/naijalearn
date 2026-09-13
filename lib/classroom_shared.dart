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
