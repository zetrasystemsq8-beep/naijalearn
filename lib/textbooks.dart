// lib/textbooks.dart
//
// Central registry for all subject lesson files. Add a new import and a
// new Textbook entry here whenever a new lessons_<subject>.dart file is
// created — main.dart never needs to know about individual subjects,
// it only imports this one file and uses `allTextbooks`.

import 'package:flutter/material.dart';
import 'main.dart';
import 'lessons_english.dart';
import 'lessons_biology.dart';
import 'lessons_physics.dart';
import 'lessons_government.dart';
import 'lessons_literature.dart';
import 'lessons_chemistry.dart';
import 'lessons_math.dart';
/// Represents one subject's textbook: its display info plus its list
/// of lesson maps (each map has chapterTitle, body, etc.).
class Textbook {
  final String subject;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> lessons;

  const Textbook({
    required this.subject,
    required this.icon,
    required this.color,
    required this.lessons,
  });
}

/// The full shelf of textbooks currently available in the app.
/// Add one line here for every new lessons_<subject>.dart file.
final List<Textbook> allTextbooks = [
  Textbook(
    subject: 'English',
    icon: Icons.menu_book_rounded,
    color: const Color(0xFF3F51B5),
    lessons: englishLessons,
  ),
  Textbook(
    subject: 'Biology',
    icon: Icons.eco_rounded,
    color: Colors.green,
    lessons: biologyLessons,
  ),
  Textbook(
    subject: 'Physics',
    icon: Icons.science_rounded,
    color: Colors.deepPurple,
    lessons: physicsLessons,
  ),
  Textbook(
    subject: 'Government',
    icon: Icons.account_balance_rounded,
    color: Colors.indigo,
    lessons: governmentLessons,
  ),
  Textbook(
    subject: 'Literature',
    icon: Icons.auto_stories_rounded,
    color: Colors.purple,
    lessons: literatureLessons,
  ),
];

/// =========================================================================
/// TEXTBOOK SHELF SCREEN — the single entry point for all subjects
/// =========================================================================

class TextbookShelfScreen extends StatelessWidget {
  const TextbookShelfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Textbooks')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.1,
        ),
        itemCount: allTextbooks.length,
        itemBuilder: (context, index) {
          final book = allTextbooks[index];
          return Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                // Uses the LessonsScreen already defined in main.dart.
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LessonsScreenLauncher(book: book),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: book.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(book.icon, color: book.color, size: 26),
                    ),
                    const Spacer(),
                    Text(book.subject,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('${book.lessons.length} chapters',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Thin wrapper so this file doesn't need to redefine LessonsScreen —
/// it just forwards to the one already in main.dart with the right data.
/// (See wiring note below if you'd rather move LessonsScreen here instead.)
class LessonsScreenLauncher extends StatelessWidget {
  final Textbook book;
  const LessonsScreenLauncher({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return LessonsScreen(subject: book.subject, lessons: book.lessons);
  }
}
