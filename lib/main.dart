// lib/main.dart
//
// NaijaLearn — CBT Practice App
// Single-file Flutter application. Material 3. No backend, no auth.
//
// ARCHITECTURE NOTE:
// All quiz content flows through `Question` + `QuestionRepository`.
// To swap in a real question bank later, replace the body of
// `QuestionRepository._buildSampleQuestions()` with data loaded from
// a JSON asset/file via `QuestionRepository.loadFromJsonList(...)`
// or `QuestionRepository.loadFromJsonString(...)`. No other class
// needs to change.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const NaijaLearnApp());
}

/// =========================================================================
/// MODELS
/// =========================================================================

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

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'] as String,
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
  SubjectInfo('Mathematics', Icons.calculate_rounded, Color(0xFF009688)),
  SubjectInfo('Physics', Icons.bolt_rounded, Color(0xFFFF9800)),
  SubjectInfo('Chemistry', Icons.science_rounded, Color(0xFF9C27B0)),
  SubjectInfo('Biology', Icons.eco_rounded, Color(0xFF4CAF50)),
  SubjectInfo('Government', Icons.account_balance_rounded, Color(0xFF795548)),
  SubjectInfo('Economics', Icons.trending_up_rounded, Color(0xFF2196F3)),
  SubjectInfo('Literature', Icons.auto_stories_rounded, Color(0xFFE91E63)),
  SubjectInfo('CRS', Icons.church_rounded, Color(0xFF607D8B)),
  SubjectInfo('Geography', Icons.public_rounded, Color(0xFF00BCD4)),
];

/// =========================================================================
/// QUESTION REPOSITORY (swap-friendly data source)
/// =========================================================================

class QuestionRepository {
  QuestionRepository._();

  static List<Question> _questions = _buildSampleQuestions();

  /// Replace the entire question bank with parsed JSON objects.
  static void loadFromJsonList(List<Map<String, dynamic>> jsonList) {
    _questions = jsonList.map((e) => Question.fromJson(e)).toList();
  }

  /// Replace the entire question bank from a raw JSON string, e.g.
  /// the contents of assets/questions.json (a JSON array of question
  /// objects matching Question.toJson()).
  static void loadFromJsonString(String jsonStr) {
    final decoded = jsonDecode(jsonStr) as List<dynamic>;
    _questions = decoded
        .map((e) => Question.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<Question> getAll() => List.unmodifiable(_questions);

  static List<Question> getForSubject(String subject) =>
      _questions.where((q) => q.subject == subject).toList();

  /// Returns questions for the exact subject+year if any exist,
  /// otherwise falls back to the full subject pool so the demo
  /// always has content regardless of which year is picked.
  static List<Question> getForSubjectAndYear(String subject, int year) {
    final exact =
        _questions.where((q) => q.subject == subject && q.year == year).toList();
    if (exact.isNotEmpty) return exact;
    return getForSubject(subject);
  }

  static List<Question> _buildSampleQuestions() {
    final List<Question> list = [];

    void add(String subject, int year, String q, List<String> options,
        int correct, String explanation) {
      list.add(Question(
        id: '${subject}_${year}_${list.length}',
        subject: subject,
        year: year,
        questionText: q,
        options: options,
        correctIndex: correct,
        explanation: explanation,
      ));
    }

    // ---------------- English ----------------
    add('English', 2021, "Choose the option that best completes the sentence: She is ___ honest woman.",
        ['a', 'an', 'the', 'no article needed'], 1,
        "'Honest' starts with a vowel sound, so 'an' is used.");
    add('English', 2022, "Select the correctly spelt word.",
        ['Accomodate', 'Acommodate', 'Accommodate', 'Acomodate'], 2,
        "The correct spelling is 'Accommodate' with double C and double M.");
    add('English', 2019, "What is the synonym of 'Benevolent'?",
        ['Cruel', 'Kind', 'Selfish', 'Angry'], 1,
        "'Benevolent' means kind and generous.");
    add('English', 2023, "Identify the figure of speech: 'The classroom was a zoo.'",
        ['Simile', 'Metaphor', 'Personification', 'Hyperbole'], 1,
        "A direct comparison without 'like' or 'as' is a metaphor.");
    add('English', 2020, "Choose the antonym of 'Ancient'.",
        ['Old', 'Modern', 'Historic', 'Aged'], 1,
        "'Modern' is the opposite of 'Ancient'.");
    add('English', 2024, "Which sentence is grammatically correct?",
        [
          'He don\'t like rice',
          'He doesn\'t likes rice',
          'He doesn\'t like rice',
          'He not like rice'
        ], 2, "Third person singular negative uses 'doesn't' + base verb.");

    // ---------------- Mathematics ----------------
    add('Mathematics', 2021, "Simplify: 3x + 5x - 2x",
        ['6x', '8x', '10x', '4x'], 0, "3x + 5x - 2x = 6x.");
    add('Mathematics', 2022, "What is the value of x if 2x + 6 = 20?",
        ['5', '6', '7', '8'], 2, "2x = 14, so x = 7.");
    add('Mathematics', 2019, "Find the area of a rectangle with length 8cm and width 5cm.",
        ['13cm²', '26cm²', '40cm²', '45cm²'], 2, "Area = length × width = 8 × 5 = 40cm².");
    add('Mathematics', 2023, "What is 15% of 200?",
        ['20', '25', '30', '35'], 2, "15% of 200 = 0.15 × 200 = 30.");
    add('Mathematics', 2020, "Solve for x: x² = 49",
        ['x = 6', 'x = 7', 'x = 8', 'x = 9'], 1, "√49 = 7.");
    add('Mathematics', 2024, "What is the next number in the sequence: 2, 4, 8, 16, ___?",
        ['20', '24', '32', '18'], 2, "Each term doubles the previous one; 16 × 2 = 32.");

    // ---------------- Physics ----------------
    add('Physics', 2021, "What is the SI unit of force?",
        ['Joule', 'Newton', 'Watt', 'Pascal'], 1, "Force is measured in Newtons (N).");
    add('Physics', 2022, "Which law states that for every action there is an equal and opposite reaction?",
        ["Newton's First Law", "Newton's Second Law", "Newton's Third Law", "Law of Gravitation"], 2,
        "This is Newton's Third Law of Motion.");
    add('Physics', 2019, "What is the speed of light in a vacuum (approx)?",
        ['3 × 10⁶ m/s', '3 × 10⁸ m/s', '3 × 10¹⁰ m/s', '3 × 10⁵ m/s'], 1,
        "The speed of light is approximately 3 × 10⁸ m/s.");
    add('Physics', 2023, "A body at rest has what type of energy relative to motion?",
        ['Kinetic energy only', 'No energy', 'Potential energy only', 'Both kinetic and potential'], 2,
        "A body at rest has zero kinetic energy but may have potential energy.");
    add('Physics', 2020, "What instrument is used to measure current?",
        ['Voltmeter', 'Ammeter', 'Barometer', 'Thermometer'], 1, "An ammeter measures electric current.");
    add('Physics', 2024, "What is the unit of electrical resistance?",
        ['Volt', 'Ampere', 'Ohm', 'Watt'], 2, "Resistance is measured in Ohms (Ω).");

    // ---------------- Chemistry ----------------
    add('Chemistry', 2021, "What is the chemical symbol for Sodium?",
        ['So', 'Sd', 'Na', 'S'], 2, "Sodium's symbol, Na, comes from its Latin name 'Natrium'.");
    add('Chemistry', 2022, "What is the pH of a neutral solution?",
        ['0', '7', '14', '10'], 1, "A neutral solution has a pH of 7.");
    add('Chemistry', 2019, "Which gas is most abundant in the Earth's atmosphere?",
        ['Oxygen', 'Carbon dioxide', 'Nitrogen', 'Hydrogen'], 2, "Nitrogen makes up about 78% of the atmosphere.");
    add('Chemistry', 2023, "What type of bond involves the sharing of electron pairs?",
        ['Ionic bond', 'Covalent bond', 'Metallic bond', 'Hydrogen bond'], 1,
        "A covalent bond forms when atoms share electron pairs.");
    add('Chemistry', 2020, "What is the atomic number of Hydrogen?",
        ['0', '1', '2', '3'], 1, "Hydrogen has 1 proton, giving it atomic number 1.");
    add('Chemistry', 2024, "Which of these is an example of an exothermic reaction?",
        ['Photosynthesis', 'Combustion', 'Melting ice', 'Evaporation'], 1,
        "Combustion releases heat, making it exothermic.");

    // ---------------- Biology ----------------
    add('Biology', 2021, "What is the powerhouse of the cell?",
        ['Nucleus', 'Ribosome', 'Mitochondria', 'Golgi body'], 2,
        "Mitochondria produce ATP, the cell's energy currency.");
    add('Biology', 2022, "Which blood cells are responsible for fighting infection?",
        ['Red blood cells', 'White blood cells', 'Platelets', 'Plasma'], 1,
        "White blood cells (leukocytes) defend the body against infection.");
    add('Biology', 2019, "What process do plants use to make food?",
        ['Respiration', 'Photosynthesis', 'Transpiration', 'Digestion'], 1,
        "Photosynthesis converts light energy into chemical energy in plants.");
    add('Biology', 2023, "How many chambers does the human heart have?",
        ['2', '3', '4', '5'], 2, "The human heart has four chambers.");
    add('Biology', 2020, "Which organ is primarily responsible for filtering blood?",
        ['Liver', 'Kidney', 'Lungs', 'Pancreas'], 1, "The kidneys filter waste from the blood.");
    add('Biology', 2024, "What is the basic unit of heredity?",
        ['Cell', 'Chromosome', 'Gene', 'Protein'], 2, "Genes are the basic units of heredity.");

    // ---------------- Government ----------------
    add('Government', 2021, "What type of government does Nigeria practice?",
        ['Monarchy', 'Federal Republic', 'Unitary state', 'Confederation'], 1,
        "Nigeria operates as a Federal Republic.");
    add('Government', 2022, "How many arms of government are there typically?",
        ['1', '2', '3', '4'], 2, "The three arms are the Executive, Legislature, and Judiciary.");
    add('Government', 2019, "What is the term of office for a Nigerian President?",
        ['3 years', '4 years', '5 years', '6 years'], 1, "A Nigerian President serves a 4-year term per cycle.");
    add('Government', 2023, "What is the principle of separation of powers meant to prevent?",
        ['Economic growth', 'Abuse of power', 'International trade', 'Population growth'], 1,
        "Separation of powers prevents concentration and abuse of power.");
    add('Government', 2020, "Who is the head of the Judiciary in Nigeria?",
        ['The President', 'The Senate President', 'Chief Justice of Nigeria', 'The Speaker'], 2,
        "The Chief Justice of Nigeria heads the judicial arm.");
    add('Government', 2024, "Which body is responsible for making laws in Nigeria?",
        ['Executive', 'Legislature', 'Judiciary', 'Civil Service'], 1, "The Legislature (National Assembly) makes laws.");

    // ---------------- Economics ----------------
    add('Economics', 2021, "What does GDP stand for?",
        ['General Domestic Product', 'Gross Domestic Product', 'Gross Development Plan', 'General Development Product'], 1,
        "GDP stands for Gross Domestic Product.");
    add('Economics', 2022, "What is the study of how individuals and firms make choices called?",
        ['Macroeconomics', 'Microeconomics', 'Sociology', 'Statistics'], 1,
        "Microeconomics studies individual and firm-level decision making.");
    add('Economics', 2019, "What term describes a persistent rise in general price levels?",
        ['Deflation', 'Inflation', 'Recession', 'Depression'], 1, "Inflation is a sustained rise in prices.");
    add('Economics', 2023, "What is the law of demand?",
        [
          'Price and quantity demanded move in the same direction',
          'Price and quantity demanded move in opposite directions',
          'Demand is unaffected by price',
          'Supply determines demand'
        ], 1, "As price rises, quantity demanded typically falls, and vice versa.");
    add('Economics', 2020, "What is a monopoly?",
        [
          'Many sellers, one buyer',
          'A market with a single seller',
          'A market with two sellers',
          'A market with free entry'
        ], 1, "A monopoly exists when one seller dominates the entire market.");
    add('Economics', 2024, "Which sector does agriculture belong to?",
        ['Primary sector', 'Secondary sector', 'Tertiary sector', 'Quaternary sector'], 0,
        "Agriculture is part of the primary sector, extracting raw materials.");

    // ---------------- Literature ----------------
    add('Literature', 2021, "Who wrote 'Things Fall Apart'?",
        ['Wole Soyinka', 'Chinua Achebe', 'Chimamanda Adichie', 'Ben Okri'], 1,
        "'Things Fall Apart' was written by Chinua Achebe.");
    add('Literature', 2022, "What is a 'protagonist'?",
        ['The villain of a story', 'The main character', 'The setting', 'The narrator only'], 1,
        "The protagonist is the central character of a story.");
    add('Literature', 2019, "What literary device compares two unlike things using 'like' or 'as'?",
        ['Metaphor', 'Simile', 'Personification', 'Irony'], 1, "A simile uses 'like' or 'as' to compare things.");
    add('Literature', 2023, "What is the term for the time and place a story occurs?",
        ['Plot', 'Theme', 'Setting', 'Climax'], 2, "Setting refers to the time and place of a narrative.");
    add('Literature', 2020, "What is a 'soliloquy'?",
        [
          'A conversation between two characters',
          'A speech a character makes alone, revealing inner thoughts',
          'The moral of a story',
          'A rhyming poem'
        ], 1, "A soliloquy is a character speaking their thoughts aloud, alone.");
    add('Literature', 2024, "Who wrote the play 'Death and the King's Horseman'?",
        ['Chinua Achebe', 'Wole Soyinka', 'J.P. Clark', 'Zulu Sofola'], 1,
        "Wole Soyinka wrote 'Death and the King's Horseman'.");

    // ---------------- CRS ----------------
    add('CRS', 2021, "Who is regarded as the father of faith in Christianity?",
        ['Moses', 'Abraham', 'David', 'Noah'], 1, "Abraham is called the father of faith.");
    add('CRS', 2022, "How many books are in the New Testament?",
        ['27', '39', '66', '12'], 0, "The New Testament contains 27 books.");
    add('CRS', 2019, "Who betrayed Jesus Christ?",
        ['Peter', 'John', 'Judas Iscariot', 'Thomas'], 2, "Judas Iscariot betrayed Jesus for thirty pieces of silver.");
    add('CRS', 2023, "On which mountain did Moses receive the Ten Commandments?",
        ['Mount Zion', 'Mount Sinai', 'Mount Carmel', 'Mount Ararat'], 1,
        "Moses received the Ten Commandments on Mount Sinai.");
    add('CRS', 2020, "Who was thrown into the lion's den but survived?",
        ['Daniel', 'Jonah', 'Elijah', 'Samuel'], 0, "Daniel survived the lion's den unharmed.");
    add('CRS', 2024, "What is the first book of the Bible?",
        ['Exodus', 'Genesis', 'Leviticus', 'Numbers'], 1, "Genesis is the first book of the Bible.");

    // ---------------- Geography ----------------
    add('Geography', 2021, "What is the largest continent by land area?",
        ['Africa', 'Asia', 'North America', 'Europe'], 1, "Asia is the largest continent by land area.");
    add('Geography', 2022, "Which river is the longest in Africa?",
        ['Niger River', 'Congo River', 'Nile River', 'Zambezi River'], 2, "The Nile River is the longest river in Africa.");
    add('Geography', 2019, "What causes day and night?",
        [
          "The Earth's revolution around the sun",
          "The Earth's rotation on its axis",
          'The Moon orbiting Earth',
          'Seasonal changes'
        ], 1, "Day and night are caused by the Earth's rotation on its axis.");
    add('Geography', 2023, "What type of rock is formed from cooled magma or lava?",
        ['Sedimentary', 'Metamorphic', 'Igneous', 'Organic'], 2, "Igneous rock forms from cooled magma or lava.");
    add('Geography', 2020, "Which layer of the Earth do we live on?",
        ['Core', 'Mantle', 'Crust', 'Outer core'], 2, "Humans live on the Earth's crust, the outermost layer.");
    add('Geography', 2024, "What is the term for a permanent settlement with a large population and administrative functions?",
        ['Village', 'City', 'Hamlet', 'Farmstead'], 1, "A city is a large permanent settlement with administrative functions.");

    return list;
  }
}

/// =========================================================================
/// APP ROOT — theming
/// =========================================================================

class NaijaLearnApp extends StatefulWidget {
  const NaijaLearnApp({super.key});

  @override
  State<NaijaLearnApp> createState() => _NaijaLearnAppState();
}

class _NaijaLearnAppState extends State<NaijaLearnApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  static const Color _seed = Color(0xFF00A86B); // Nigerian green

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NaijaLearn',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF101312),
        fontFamily: 'Roboto',
      ),
      home: SplashScreen(
        themeMode: _themeMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

/// =========================================================================
/// SPLASH SCREEN
/// =========================================================================

class SplashScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  const SplashScreen({super.key, required this.themeMode, required this.onToggleTheme});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _fade = CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.7, curve: Curves.easeIn));
    _scale = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    Timer(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: HomeScreen(themeMode: widget.themeMode, onToggleTheme: widget.onToggleTheme),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.primaryContainer],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(Icons.school_rounded, size: 60, color: scheme.primary),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'NaijaLearn',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Practice. Prepare. Pass.',
                    style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.9)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// HOME SCREEN
/// =========================================================================

class HomeScreen extends StatelessWidget {
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  const HomeScreen({super.key, required this.themeMode, required this.onToggleTheme});

  Future<void> _pickYearAndStart(BuildContext context, SubjectInfo subject) async {
    final year = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => YearPickerSheet(subject: subject),
    );
    if (year == null || !context.mounted) return;

    final questions = QuestionRepository.getForSubjectAndYear(subject.name, year);
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExamInstructionsScreen(subject: subject, year: year, questions: questions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.school_rounded, color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('NaijaLearn',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                          Text('Choose a subject to practice',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Toggle dark mode',
                      onPressed: onToggleTheme,
                      icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      colors: [scheme.primary, scheme.primary.withOpacity(0.75)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CBT Practice Mode',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(
                              'Simulate real exam conditions with a timer,\nquestion navigator and instant results.',
                              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12.5, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.bolt_rounded, color: Colors.white.withOpacity(0.85), size: 42),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.15,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final subject = kSubjects[index];
                    final count = QuestionRepository.getForSubject(subject.name).length;
                    return SubjectCard(
                      subject: subject,
                      questionCount: count,
                      onTap: () => _pickYearAndStart(context, subject),
                    );
                  },
                  childCount: kSubjects.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SubjectCard extends StatelessWidget {
  final SubjectInfo subject;
  final int questionCount;
  final VoidCallback onTap;
  const SubjectCard({super.key, required this.subject, required this.questionCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: subject.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(subject.icon, color: subject.color, size: 26),
              ),
              const Spacer(),
              Text(subject.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('$questionCount questions',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// =========================================================================
/// YEAR PICKER
/// =========================================================================

class YearPickerSheet extends StatelessWidget {
  final SubjectInfo subject;
  const YearPickerSheet({super.key, required this.subject});

  @override
  Widget build(BuildContext context) {
    final years = List.generate(2026 - 2000 + 1, (i) => 2026 - i); // newest first
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(subject.icon, color: subject.color),
                    const SizedBox(width: 10),
                    Text('${subject.name} — Select Year',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.6,
                  ),
                  itemCount: years.length,
                  itemBuilder: (context, index) {
                    final year = years[index];
                    return Material(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).pop(year),
                        child: Center(
                          child: Text('$year', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// =========================================================================
/// EXAM INSTRUCTIONS
/// =========================================================================

class ExamInstructionsScreen extends StatelessWidget {
  final SubjectInfo subject;
  final int year;
  final List<Question> questions;
  const ExamInstructionsScreen(
      {super.key, required this.subject, required this.year, required this.questions});

  static const int durationMinutes = 20;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Exam Instructions')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: subject.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(subject.icon, color: subject.color, size: 32),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    Text('$year Practice Set', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),
            _InfoTile(icon: Icons.quiz_rounded, label: 'Questions', value: '${questions.length}'),
            _InfoTile(icon: Icons.timer_rounded, label: 'Duration', value: '$durationMinutes minutes'),
            _InfoTile(icon: Icons.check_circle_rounded, label: 'Question type', value: 'Multiple choice (4 options)'),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Instructions', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('• Answer all questions before time runs out.\n'
                      '• You may skip a question and return to it later.\n'
                      '• Use the question navigator to jump to any question.\n'
                      '• The exam auto-submits when the timer reaches zero.'),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Exam', style: TextStyle(fontSize: 16)),
                onPressed: questions.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ExamScreen(
                              subject: subject,
                              year: year,
                              questions: questions,
                              durationMinutes: durationMinutes,
                            ),
                          ),
                        );
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// =========================================================================
/// EXAM SCREEN (CBT interface)
/// =========================================================================

enum QuestionStatus { unanswered, answered, skipped }

class ExamScreen extends StatefulWidget {
  final SubjectInfo subject;
  final int year;
  final List<Question> questions;
  final int durationMinutes;

  const ExamScreen({
    super.key,
    required this.subject,
    required this.year,
    required this.questions,
    required this.durationMinutes,
  });

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  late List<int?> _selectedAnswers;
  late List<QuestionStatus> _statuses;
  int _currentIndex = 0;
  late int _remainingSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _selectedAnswers = List<int?>.filled(widget.questions.length, null);
    _statuses = List<QuestionStatus>.filled(widget.questions.length, QuestionStatus.unanswered);
    _remainingSeconds = widget.durationMinutes * 60;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
        _submitExam();
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _selectOption(int optionIndex) {
    setState(() {
      _selectedAnswers[_currentIndex] = optionIndex;
      _statuses[_currentIndex] = QuestionStatus.answered;
    });
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.questions.length) return;
    setState(() => _currentIndex = index);
  }

  void _skipQuestion() {
    setState(() {
      if (_statuses[_currentIndex] == QuestionStatus.unanswered) {
        _statuses[_currentIndex] = QuestionStatus.skipped;
      }
    });
    if (_currentIndex < widget.questions.length - 1) {
      _goTo(_currentIndex + 1);
    }
  }

  Future<void> _confirmSubmit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Exam?'),
        content: Text(
          'You have answered ${_selectedAnswers.where((a) => a != null).length} of '
          '${widget.questions.length} questions. Submit now?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed == true) _submitExam();
  }

  void _submitExam() {
    _timer?.cancel();
    int correct = 0;
    for (int i = 0; i < widget.questions.length; i++) {
      if (_selectedAnswers[i] != null && _selectedAnswers[i] == widget.questions[i].correctIndex) {
        correct++;
      }
    }
    final skipped = _statuses.where((s) => s == QuestionStatus.skipped).length;
    final unanswered = _selectedAnswers.where((a) => a == null).length;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          subject: widget.subject,
          year: widget.year,
          questions: widget.questions,
          selectedAnswers: _selectedAnswers,
          correctCount: correct,
          skippedCount: skipped,
          unansweredCount: unanswered,
        ),
      ),
    );
  }

  void _openNavigator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QuestionNavigatorSheet(
        totalQuestions: widget.questions.length,
        statuses: _statuses,
        currentIndex: _currentIndex,
        onSelect: (index) {
          Navigator.pop(context);
          _goTo(index);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final question = widget.questions[_currentIndex];
    final answeredCount = _selectedAnswers.where((a) => a != null).length;
    final progress = (answeredCount) / widget.questions.length;
    final isLowTime = _remainingSeconds <= 60;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subject.name} • ${widget.year}'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isLowTime ? scheme.errorContainer : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.timer_rounded,
                    size: 18, color: isLowTime ? scheme.onErrorContainer : scheme.onPrimaryContainer),
                const SizedBox(width: 6),
                Text(
                  _formattedTime,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isLowTime ? scheme.onErrorContainer : scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Question ${_currentIndex + 1} of ${widget.questions.length}',
                        style: Theme.of(context).textTheme.bodySmall),
                    TextButton.icon(
                      onPressed: _openNavigator,
                      icon: const Icon(Icons.grid_view_rounded, size: 18),
                      label: const Text('Navigator'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
                child: child,
              )),
              child: SingleChildScrollView(
                key: ValueKey(_currentIndex),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        question.questionText,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 18),
                    ...List.generate(question.options.length, (i) {
                      final isSelected = _selectedAnswers[_currentIndex] == i;
                      final letter = String.fromCharCode(65 + i); // A, B, C, D
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: isSelected ? scheme.primaryContainer : scheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _selectOption(i),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected ? scheme.primary : scheme.outlineVariant,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
                                    child: Text(
                                      letter,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(child: Text(question.options[i], style: const TextStyle(fontSize: 15))),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _currentIndex > 0 ? () => _goTo(_currentIndex - 1) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: const Text('Previous'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _skipQuestion,
                      icon: const Icon(Icons.skip_next_rounded),
                      label: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _currentIndex == widget.questions.length - 1
                        ? FilledButton.icon(
                            onPressed: _confirmSubmit,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Submit'),
                          )
                        : FilledButton.icon(
                            onPressed: () => _goTo(_currentIndex + 1),
                            icon: const Icon(Icons.chevron_right_rounded),
                            label: const Text('Next'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =========================================================================
/// QUESTION NAVIGATOR
/// =========================================================================

class QuestionNavigatorSheet extends StatelessWidget {
  final int totalQuestions;
  final List<QuestionStatus> statuses;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const QuestionNavigatorSheet({
    super.key,
    required this.totalQuestions,
    required this.statuses,
    required this.currentIndex,
    required this.onSelect,
  });

  Color _colorFor(BuildContext context, QuestionStatus status, bool isCurrent) {
    final scheme = Theme.of(context).colorScheme;
    if (isCurrent) return scheme.primary;
    switch (status) {
      case QuestionStatus.answered:
        return Colors.green;
      case QuestionStatus.skipped:
        return Colors.orange;
      case QuestionStatus.unanswered:
        return scheme.surfaceContainerHighest;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Question Navigator',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _LegendDot(color: Colors.green, label: 'Answered'),
                _LegendDot(color: Colors.orange, label: 'Skipped'),
                _LegendDot(color: scheme.surfaceContainerHighest, label: 'Unanswered', border: true),
                _LegendDot(color: scheme.primary, label: 'Current'),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1,
                ),
                itemCount: totalQuestions,
                itemBuilder: (context, index) {
                  final isCurrent = index == currentIndex;
                  final color = _colorFor(context, statuses[index], isCurrent);
                  final isFilled = isCurrent || statuses[index] != QuestionStatus.unanswered;
                  return Material(
                    color: isFilled ? color : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: color, width: isFilled ? 0 : 1.4),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelect(index),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isFilled ? Colors.white : scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool border;
  const _LegendDot({required this.color, required this.label, this.border = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: border ? Border.all(color: Theme.of(context).colorScheme.outline) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// =========================================================================
/// RESULTS SCREEN
/// =========================================================================

class ResultsScreen extends StatelessWidget {
  final SubjectInfo subject;
  final int year;
  final List<Question> questions;
  final List<int?> selectedAnswers;
  final int correctCount;
  final int skippedCount;
  final int unansweredCount;

  const ResultsScreen({
    super.key,
    required this.subject,
    required this.year,
    required this.questions,
    required this.selectedAnswers,
    required this.correctCount,
    required this.skippedCount,
    required this.unansweredCount,
  });

  double get _percentage => (correctCount / questions.length) * 100;

  String get _grade {
    final p = _percentage;
    if (p >= 75) return 'A';
    if (p >= 60) return 'B';
    if (p >= 50) return 'C';
    if (p >= 40) return 'D';
    return 'F';
  }

  String get _gradeLabel {
    switch (_grade) {
      case 'A':
        return 'Excellent';
      case 'B':
        return 'Very Good';
      case 'C':
        return 'Good';
      case 'D':
        return 'Pass';
      default:
        return 'Needs Improvement';
    }
  }

  Color _gradeColor(BuildContext context) {
    switch (_grade) {
      case 'A':
        return Colors.green;
      case 'B':
        return Colors.lightGreen;
      case 'C':
        return Colors.amber;
      case 'D':
        return Colors.orange;
      default:
        return Theme.of(context).colorScheme.error;
    }
  }

  String get _analysis {
    final p = _percentage;
    if (p >= 75) {
      return "Outstanding performance! You've demonstrated a strong grasp of ${subject.name}. Keep practising to maintain this level.";
    } else if (p >= 50) {
      return "Solid effort. You understand most of the ${subject.name} concepts, but reviewing the questions you missed will help you improve further.";
    } else {
      return "There's room for improvement. Focus on reviewing your wrong answers and revisit the core topics in ${subject.name} before your next attempt.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wrongCount = questions.length - correctCount - unansweredCount + (unansweredCount - skippedCount).clamp(0, questions.length) * 0; 
    final actualWrong = questions.length - correctCount - unansweredCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _percentage / 100),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 180,
                        height: 180,
                        child: CircularProgressIndicator(
                          value: value,
                          strokeWidth: 12,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(_gradeColor(context)),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${(value * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                          Text('Grade $_grade',
                              style: TextStyle(color: _gradeColor(context), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(_gradeLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${subject.name} • $year Practice Set', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            Row(
              children: [
                _StatCard(label: 'Correct', value: '$correctCount', color: Colors.green),
                const SizedBox(width: 10),
                _StatCard(label: 'Wrong', value: '$actualWrong', color: Colors.red),
                const SizedBox(width: 10),
                _StatCard(label: 'Skipped', value: '$unansweredCount', color: Colors.orange),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.insights_rounded, color: scheme.primary),
                      const SizedBox(width: 8),
                      const Text('Performance Analysis', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(_analysis, style: const TextStyle(height: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                icon: const Icon(Icons.rate_review_rounded),
                label: const Text('Review Answers'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReviewScreen(questions: questions, selectedAnswers: selectedAnswers),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Retake Exam'),
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => ExamInstructionsScreen(subject: subject, year: year, questions: questions),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton.icon(
                icon: const Icon(Icons.home_rounded),
                label: const Text('Back to Home'),
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

/// =========================================================================
/// REVIEW SCREEN
/// =========================================================================

class ReviewScreen extends StatelessWidget {
  final List<Question> questions;
  final List<int?> selectedAnswers;
  const ReviewScreen({super.key, required this.questions, required this.selectedAnswers});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Review Answers')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: questions.length,
        itemBuilder: (context, index) {
          final question = questions[index];
          final selected = selectedAnswers[index];
          final isCorrect = selected == question.correctIndex;
          final wasAnswered = selected != null;

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: !wasAnswered
                    ? scheme.outlineVariant
                    : (isCorrect ? Colors.green : Colors.red),
                width: 1.4,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('Q${index + 1}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
                    ),
                    const Spacer(),
                    Icon(
                      !wasAnswered
                          ? Icons.remove_circle_outline_rounded
                          : (isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded),
                      color: !wasAnswered ? Colors.orange : (isCorrect ? Colors.green : Colors.red),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      !wasAnswered ? 'Skipped' : (isCorrect ? 'Correct' : 'Wrong'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: !wasAnswered ? Colors.orange : (isCorrect ? Colors.green : Colors.red),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(question.questionText, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
                const SizedBox(height: 10),
                ...List.generate(question.options.length, (i) {
                  final isCorrectOption = i == question.correctIndex;
                  final isSelectedOption = i == selected;
                  Color? bg;
                  if (isCorrectOption) {
                    bg = Colors.green.withOpacity(0.15);
                  } else if (isSelectedOption && !isCorrectOption) {
                    bg = Colors.red.withOpacity(0.15);
                  }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCorrectOption
                            ? Colors.green
                            : (isSelectedOption ? Colors.red : scheme.outlineVariant),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: scheme.surface,
                          child: Text(String.fromCharCode(65 + i), style: const TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(question.options[i], style: const TextStyle(fontSize: 13.5))),
                        if (isCorrectOption) const Icon(Icons.check_rounded, color: Colors.green, size: 18),
                        if (isSelectedOption && !isCorrectOption)
                          const Icon(Icons.close_rounded, color: Colors.red, size: 18),
                      ],
                    ),
                  );
                }),
                if (question.explanation.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, size: 18, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(question.explanation,
                              style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
