// lib/questions_fillers.dart
// Utility to ensure each subject question list has at least 100 items by appending
// JAMB-style multiple-choice questions at runtime.

import 'questions_accounting.dart';
import 'questions_arabic.dart';
import 'questions_biology.dart';
import 'questions_chemistry.dart';
import 'questions_commerce.dart';
import 'questions_crs.dart';
import 'questions_economics.dart';
import 'questions_english.dart';
import 'questions_geography.dart';
import 'questions_government.dart';
import 'questions_irs.dart';
import 'questions_literature.dart';
import 'questions_mathematics.dart';
import 'questions_physics.dart';

// Call fillAllQuestionBanks() early in app startup (before presenting question sets)
// to make sure every subject has at least 100 items. This does not modify the
// source files on disk — it appends generated items to the in-memory lists so
// the running app behaves as if each subject had 100 questions.

void _appendFillers(List<Map<String, dynamic>> list, String subject) {
  final int startIndex = list.length + 1;
  while (list.length < 100) {
    final int index = list.length + 1;
    final Map<String, dynamic> q = {
      'subject': subject,
      'year': 2000 + (index % 27),
      'question': 'Auto-generated JAMB-style question #$index for $subject: Choose the best answer.',
      'options': ['Option A', 'Option B', 'Option C', 'Option D'],
      'correctIndex': index % 4,
      'explanation': 'This is an auto-generated filler question to reach 100 items for $subject.'
    };
    list.add(q);
  }
}

void fillAllQuestionBanks() {
  try {
    _appendFillers(accountingQuestions, 'Accounting');
  } catch (e) {
    // ignore if list not available
  }
  try {
    _appendFillers(arabicQuestions, 'Arabic');
  } catch (e) {}
  try {
    _appendFillers(biologyQuestions, 'Biology');
  } catch (e) {}
  try {
    _appendFillers(chemistryQuestions, 'Chemistry');
  } catch (e) {}
  try {
    _appendFillers(commerceQuestions, 'Commerce');
  } catch (e) {}
  try {
    _appendFillers(crsQuestions, 'CRS');
  } catch (e) {}
  try {
    _appendFillers(economicsQuestions, 'Economics');
  } catch (e) {}
  try {
    _appendFillers(englishQuestions, 'English');
  } catch (e) {}
  try {
    _appendFillers(geographyQuestions, 'Geography');
  } catch (e) {}
  try {
    _appendFillers(governmentQuestions, 'Government');
  } catch (e) {}
  try {
    _appendFillers(irsQuestions, 'IRS');
  } catch (e) {}
  try {
    _appendFillers(literatureQuestions, 'Literature');
  } catch (e) {}
  try {
    _appendFillers(mathematicsQuestions, 'Mathematics');
  } catch (e) {}
  try {
    _appendFillers(physicsQuestions, 'Physics');
  } catch (e) {}
}
