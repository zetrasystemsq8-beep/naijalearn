import 'package:flutter/material.dart';

class Question {
  final String id;
  final String subject;
  final int year;
  final String questionText;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const Question({
    required this.id,
    required this.subject,
    required this.year,
    required this.questionText,
    required this.options,
    required this.correctIndex,
    this.explanation = '',
  });

  factory Question.fromJson(Map<String, dynamic> json, {String? fallbackId}) {
    return Question(
      id: (json['id'] as String?) ?? fallbackId ?? '${json['subject']}_${json['year']}_${json.hashCode}',
      subject: json['subject'] as String,
      year: json['year'] as int,
      questionText: json['question'] as String,
      options: List<String>.from(json['options'] as List),
      correctIndex: json['correctIndex'] as int,
      explanation: (json['explanation'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'year': year,
        'question': questionText,
        'options': options,
        'correctIndex': correctIndex,
        'explanation': explanation,
      };
}

class SubjectInfo {
  final String name;
  final IconData icon;
  final Color color;
  const SubjectInfo(this.name, this.icon, this.color);
}

const List<SubjectInfo> kSubjects = [
  SubjectInfo('English', Icons.menu_book_rounded, Color(0xFF3F51B5)),
  SubjectInfo('Mathematics', Icons.calculate_rounded, Colors.blue),
  SubjectInfo('Physics', Icons.science_rounded, Colors.deepPurple),
  SubjectInfo('Chemistry', Icons.biotech_rounded, Colors.red),
  SubjectInfo('Biology', Icons.eco_rounded, Colors.green),
  SubjectInfo('Economics', Icons.attach_money_rounded, Colors.teal),
  SubjectInfo('Government', Icons.account_balance_rounded, Colors.indigo),
  SubjectInfo('Geography', Icons.public_rounded, Colors.brown),
  SubjectInfo('Literature', Icons.menu_book_rounded, Colors.purple),
  SubjectInfo('Commerce', Icons.shopping_cart_rounded, Colors.orange),
  SubjectInfo('Accounting', Icons.receipt_long_rounded, Colors.cyan),
  SubjectInfo('CRS', Icons.auto_stories_rounded, Colors.deepOrange),
  SubjectInfo('IRS', Icons.mosque_rounded, Colors.green),
  SubjectInfo('Arabic', Icons.translate_rounded, Colors.lime),
];
