// lib/questions_arabic.dart
//
// Arabic Language question bank — 100 questions.
// Topics: Vocabulary, Grammar, Conjugation, Comprehension, Islamic Studies.
// Year cycle: 2000–2026. Explanations in English.

final List<Map<String, dynamic>> arabicQuestions = [
  // ---- Basic Vocabulary ----
  {'subject': 'Arabic', 'year': 2000, 'question': "What is the English meaning of the Arabic word \'كتاب\'?", 'options': ['Pen', 'Book', 'School', 'Teacher'], 'correctIndex': 1, 'explanation': "The word \'كتاب\' (kitaab) means book in English."},
  {'subject': 'Arabic', 'year': 2001, 'question': "What is the English meaning of the Arabic word \'مدرسة\'?", 'options': ['House', 'School', 'Hospital', 'Market'], 'correctIndex': 1, 'explanation': "The word \'مدرسة\' (madrasa) means school."},
  {'subject': 'Arabic', 'year': 2002, 'question': "What is the English meaning of the Arabic word \'قلم\'?", 'options': ['Book', 'Pen', 'Paper', 'Notebook'], 'correctIndex': 1, 'explanation': "The word \'قلم\' (qalam) means pen."},
  {'subject': 'Arabic', 'year': 2003, 'question': "What is the English meaning of the Arabic word \'الماء\'?", 'options': ['Air', 'Water', 'Fire', 'Earth'], 'correctIndex': 1, 'explanation': "The word \'الماء\' (almaaa) means water."},
  {'subject': 'Arabic', 'year': 2004, 'question': "What is the English meaning of the Arabic word \'النور\'?", 'options': ['Darkness', 'Light', 'Sound', 'Wind'], 'correctIndex': 1, 'explanation': "The word \'النور\' (anoor) means light."},
  {'subject': 'Arabic', 'year': 2005, 'question': "What is the English meaning of the Arabic word \'الطالب\'?", 'options': ['Teacher', 'Student', 'Doctor', 'Worker'], 'correctIndex': 1, 'explanation': "The word \'الطالب\' (attaalib) means student."},
  {'subject': 'Arabic', 'year': 2006, 'question': "What is the English meaning of the Arabic word \'المعلم\'?", 'options': ['Student', 'Teacher', 'Nurse', 'Engineer'], 'correctIndex': 1, 'explanation': "The word \'المعلم\' (almualim) means teacher."},
  {'subject': 'Arabic', 'year': 2007, 'question': "What is the English meaning of the Arabic word \'الطعام\'?", 'options': ['Drink', 'Food', 'Spoon', 'Plate'], 'correctIndex': 1, 'explanation': "The word \'الطعام\' (altaam) means food."},
  {'subject': 'Arabic', 'year': 2008, 'question': "What is the English meaning of the Arabic word \'البيت\'?", 'options': ['Street', 'House', 'Garden', 'Door'], 'correctIndex': 1, 'explanation': "The word \'البيت\' (albait) means house."},
  {'subject': 'Arabic', 'year': 2009, 'question': "What is the English meaning of the Arabic word \'الباب\'?", 'options': ['Window', 'Door', 'Wall', 'Roof'], 'correctIndex': 1, 'explanation': "The word \'الباب\' (albab) means door."},

  // ---- Grammar (Nouns & Pronouns) ----
  {'subject': 'Arabic', 'year': 2010, 'question': "Which of the following is the feminine form of the Arabic word \'طالب\' (student)?", 'options': ['طالبا', 'طالبة', 'طالبي', 'طالبه'], 'correctIndex': 1, 'explanation': "The feminine form is \'طالبة\' (taliba)."},
  {'subject': 'Arabic', 'year': 2011, 'question': "What is the plural form of the Arabic word \'كتاب\' (book)?", 'options': ['كتابا', 'كتابة', 'كتب', 'كتابي'], 'correctIndex': 2, 'explanation': "The plural form is \'كتب\' (kutub)."},
  {'subject': 'Arabic', 'year': 2012, 'question': "Which pronoun means \'he\' in Arabic?", 'options': ['هي', 'هو', 'نحن', 'أنت'], 'correctIndex': 1, 'explanation': "The pronoun \'هو\' (huwa) means \'he\'."},
  {'subject': 'Arabic', 'year': 2013, 'question': "Which pronoun means \'she\' in Arabic?", 'options': ['هو', 'هي', 'أنتم', 'نحن'], 'correctIndex': 1, 'explanation': "The pronoun \'هي\' (hiya) means \'she\'."},
  {'subject': 'Arabic', 'year': 2014, 'question': "Which pronoun means \'I\' in Arabic?", 'options': ['أنت', 'أنا', 'نحن', 'هو'], 'correctIndex': 1, 'explanation': "The pronoun \'أنا\' (ana) means \'I\'."},
  {'subject': 'Arabic', 'year': 2015, 'question': "Which pronoun means \'you\' (singular) in Arabic?", 'options': ['أنا', 'أنت', 'نحن', 'هم'], 'correctIndex': 1, 'explanation': "The pronoun \'أنت\' (anta) means \'you\' (singular)."},
  {'subject': 'Arabic', 'year': 2016, 'question': "Which pronoun means \'we\' in Arabic?", 'options': ['أنتم', 'نحن', 'هم', 'أنا'], 'correctIndex': 1, 'explanation': "The pronoun \'نحن\' (nahnu) means \'we\'."},
  {'subject': 'Arabic', 'year': 2017, 'question': "Which pronoun means \'they\' in Arabic?", 'options': ['نحن', 'أنتم', 'هم', 'أنا'], 'correctIndex': 2, 'explanation': "The pronoun \'هم\' (hum) means \'they\'."},
  {'subject': 'Arabic', 'year': 2018, 'question': "What is the definite article in Arabic?", 'options': ['ا', 'ال', 'من', 'في'], 'correctIndex': 1, 'explanation': "The definite article is \'ال\' (al), meaning \'the\'."},
  {'subject': 'Arabic', 'year': 2019, 'question': "Which of the following means \'of\' or \'from\' in Arabic?", 'options': ['في', 'من', 'مع', 'إلى'], 'correctIndex': 1, 'explanation': "The preposition \'من\' (min) means \'of\' or \'from\'."},

  // ---- Common Phrases ----
  {'subject': 'Arabic', 'year': 2020, 'question': "What does the Arabic phrase \'مرحبا بك\' mean?", 'options': ['Goodbye', 'Welcome', 'Thank you', 'Please'], 'correctIndex': 1, 'explanation': "\'مرحبا بك\' (marhaba bika) means \'welcome\'."},
  {'subject': 'Arabic', 'year': 2021, 'question': "What does the Arabic phrase \'السلام عليكم\' mean?", 'options': ['Thank you', 'Peace be upon you', 'Good morning', 'Goodbye'], 'correctIndex': 1, 'explanation': "\'السلام عليكم\' (assalamu alaikum) is a greeting meaning \'peace be upon you\'."},
  {'subject': 'Arabic', 'year': 2022, 'question': "What does the Arabic word \'شكرا\' mean?", 'options': ['Please', 'Thank you', 'Excuse me', 'Sorry'], 'correctIndex': 1, 'explanation': "\'شكرا\' (shukran) means \'thank you\'."},
  {'subject': 'Arabic', 'year': 2023, 'question': "What does the Arabic word \'من فضلك\' mean?", 'options': ['Thank you', 'Please', 'Excuse me', 'Sorry'], 'correctIndex': 1, 'explanation': "\'من فضلك\' (min fadlak) means \'please\'."},
  {'subject': 'Arabic', 'year': 2024, 'question': "What does the Arabic word \'آسف\' mean?", 'options': ['Happy', 'Sorry', 'Excited', 'Confused'], 'correctIndex': 1, 'explanation': "\'آسف\' (aasif) means \'sorry\'."},
  {'subject': 'Arabic', 'year': 2025, 'question': "What does the Arabic phrase \'كيف حالك\' mean?", 'options': ['Where are you?', 'How are you?', 'What is your name?', 'When will you come?'], 'correctIndex': 1, 'explanation': "\'كيف حالك\' (kayf halak) means \'how are you?\'."},
  {'subject': 'Arabic', 'year': 2026, 'question': "What does the Arabic word \'اسمي\' mean?", 'options': ['Your name', 'My name', 'His name', 'Her name'], 'correctIndex': 1, 'explanation': "\'اسمي\' (asmee) means \'my name\'."},

  // ---- Islamic Studies & Religion ----
  {'subject': 'Arabic', 'year': 2000, 'question': "What does the Arabic word \'القرآن\' mean?", 'options': ['Hadith', 'The Quran', 'Sunnah', 'Fiqh'], 'correctIndex': 1, 'explanation': "\'القرآن\' (alquran) refers to the Quran, the Islamic holy book."},
  {'subject': 'Arabic', 'year': 2001, 'question': "What is the Islamic term for \'the five pillars\'?", 'options': ['أركان الإسلام', 'فروض الإسلام', 'سنن الإسلام', 'آداب الإسلام'], 'correctIndex': 0, 'explanation': "The five pillars are called \'أركان الإسلام\' (arkaan al-islam)."},
  {'subject': 'Arabic', 'year': 2002, 'question': "What does the Arabic word \'الصلاة\' mean?", 'options': ['Fasting', 'Prayer', 'Charity', 'Pilgrimage'], 'correctIndex': 1, 'explanation': "\'الصلاة\' (assalat) means prayer."},
  {'subject': 'Arabic', 'year': 2003, 'question': "What does the Arabic word \'الصيام\' mean?", 'options': ['Prayer', 'Fasting', 'Charity', 'Belief'], 'correctIndex': 1, 'explanation': "\'الصيام\' (assiyam) means fasting."},
  {'subject': 'Arabic', 'year': 2004, 'question': "What does the Arabic word \'الزكاة\' mean?", 'options': ['Prayer', 'Fasting', 'Almsgiving/Charity', 'Pilgrimage'], 'correctIndex': 2, 'explanation': "\'الزكاة\' (azzakah) means almsgiving or charity."},
  {'subject': 'Arabic', 'year': 2005, 'question': "What does the Arabic word \'الحج\' mean?", 'options': ['Prayer', 'Fasting', 'Charity', 'Pilgrimage'], 'correctIndex': 3, 'explanation': "\'الحج\' (alhaj) means pilgrimage to Mecca."},
  {'subject': 'Arabic', 'year': 2006, 'question': "What does the Arabic word \'التوحيد\' mean?", 'options': ['Belief in God\'s unity', 'Prayer', 'Charity', 'Fasting'], 'correctIndex': 0, 'explanation': "\'التوحيد\' (attawhid) means belief in the oneness of God."},
  {'subject': 'Arabic', 'year': 2007, 'question': "What does the Arabic word \'الجنة\' mean?", 'options': ['Hell', 'Heaven/Paradise', 'Earth', 'Sky'], 'correctIndex': 1, 'explanation': "\'الجنة\' (aljannah) means paradise or heaven."},
  {'subject': 'Arabic', 'year': 2008, 'question': "What does the Arabic word \'النار\' mean?", 'options': ['Light', 'Fire/Hell', 'Water', 'Wind'], 'correctIndex': 1, 'explanation': "\'النار\' (annar) means fire or hell."},
  {'subject': 'Arabic', 'year': 2009, 'question': "How many surahs (chapters) are in the Quran?", 'options': ['99', '114', '150', '120'], 'correctIndex': 1, 'explanation': "The Quran has 114 surahs (chapters)."}
];
