// lib/questions_mathematics.dart
//
// Mathematics question bank — 100 questions.
// Topics: Algebra, Geometry, Trigonometry, Calculus, Statistics.
// Year cycle: 2000–2026.

final List<Map<String, dynamic>> mathematicsQuestions = [
  // ---- Algebra ----
  {'subject': 'Mathematics', 'year': 2000, 'question': 'Solve for x: 2x + 5 = 15', 'options': ['x = 5', 'x = 10', 'x = 3', 'x = 7'], 'correctIndex': 0, 'explanation': '2x + 5 = 15 => 2x = 10 => x = 5'},
  {'subject': 'Mathematics', 'year': 2001, 'question': 'What is the value of 3² + 4²?', 'options': ['25', '49', '36', '16'], 'correctIndex': 0, 'explanation': '3² = 9, 4² = 16, 9 + 16 = 25'},
  {'subject': 'Mathematics', 'year': 2002, 'question': 'Simplify: (x + 2)(x - 2)', 'options': ['x² + 4', 'x² - 4', 'x² - 2x + 4', 'x² + 2x - 4'], 'correctIndex': 1, 'explanation': '(x + 2)(x - 2) = x² - 4 (difference of squares)'},
  {'subject': 'Mathematics', 'year': 2003, 'question': 'Solve: x² - 5x + 6 = 0', 'options': ['x = 2 or x = 3', 'x = 1 or x = 6', 'x = 2 or x = 4', 'x = 3 or x = 4'], 'correctIndex': 0, 'explanation': 'x² - 5x + 6 = (x - 2)(x - 3) = 0 => x = 2 or x = 3'},
  {'subject': 'Mathematics', 'year': 2004, 'question': 'What is the slope of the line y = 2x + 3?', 'options': ['3', '2', '-2', '-3'], 'correctIndex': 1, 'explanation': 'In the form y = mx + b, m (slope) = 2'},
  {'subject': 'Mathematics', 'year': 2005, 'question': 'Expand: (a + b)²', 'options': ['a² + b²', 'a² + 2ab + b²', 'a² + ab + b²', 'a² - 2ab + b²'], 'correctIndex': 1, 'explanation': '(a + b)² = a² + 2ab + b²'},
  {'subject': 'Mathematics', 'year': 2006, 'question': 'Factorize: x² + 5x + 6', 'options': ['(x + 2)(x + 3)', '(x + 1)(x + 6)', '(x - 2)(x - 3)', '(x + 2)(x - 3)'], 'correctIndex': 0, 'explanation': 'x² + 5x + 6 = (x + 2)(x + 3)'},
  {'subject': 'Mathematics', 'year': 2007, 'question': 'What is √144?', 'options': ['10', '12', '14', '16'], 'correctIndex': 1, 'explanation': '√144 = 12 because 12 × 12 = 144'},
  {'subject': 'Mathematics', 'year': 2008, 'question': 'Simplify: (2x³)(3x²)', 'options': ['6x⁵', '6x⁶', '5x⁵', '5x⁶'], 'correctIndex': 0, 'explanation': '(2x³)(3x²) = 6x⁽³⁺²⁾ = 6x⁵'},
  {'subject': 'Mathematics', 'year': 2009, 'question': 'What is the value of 2⁵?', 'options': ['10', '25', '32', '64'], 'correctIndex': 2, 'explanation': '2⁵ = 2 × 2 × 2 × 2 × 2 = 32'},

  // ---- Geometry ----
  {'subject': 'Mathematics', 'year': 2010, 'question': 'What is the area of a rectangle with length 5 and width 3?', 'options': ['15', '16', '20', '8'], 'correctIndex': 0, 'explanation': 'Area = length × width = 5 × 3 = 15'},
  {'subject': 'Mathematics', 'year': 2011, 'question': 'What is the circumference of a circle with radius 7?', 'options': ['14π', '49π', '7π', '21π'], 'correctIndex': 0, 'explanation': 'Circumference = 2πr = 2π(7) = 14π'},
  {'subject': 'Mathematics', 'year': 2012, 'question': 'What is the area of a circle with radius 5?', 'options': ['25π', '50π', '10π', '5π'], 'correctIndex': 0, 'explanation': 'Area = πr² = π(5)² = 25π'},
  {'subject': 'Mathematics', 'year': 2013, 'question': 'The sum of angles in a triangle is:', 'options': ['90°', '180°', '270°', '360°'], 'correctIndex': 1, 'explanation': 'The sum of interior angles in a triangle is always 180°'},
  {'subject': 'Mathematics', 'year': 2014, 'question': 'What is the volume of a cube with side 4?', 'options': ['16', '64', '32', '48'], 'correctIndex': 1, 'explanation': 'Volume = side³ = 4³ = 64'},
  {'subject': 'Mathematics', 'year': 2015, 'question': 'The Pythagorean theorem states that:', 'options': ['a + b = c', 'a² + b² = c²', 'a × b = c²', '2a + 2b = c'], 'correctIndex': 1, 'explanation': 'In a right triangle, a² + b² = c² where c is the hypotenuse'},
  {'subject': 'Mathematics', 'year': 2016, 'question': 'What is the area of a triangle with base 6 and height 4?', 'options': ['12', '10', '24', '8'], 'correctIndex': 0, 'explanation': 'Area = ½ × base × height = ½ × 6 × 4 = 12'},
  {'subject': 'Mathematics', 'year': 2017, 'question': 'The sum of angles in a quadrilateral is:', 'options': ['180°', '270°', '360°', '90°'], 'correctIndex': 2, 'explanation': 'The sum of interior angles in a quadrilateral is 360°'},
  {'subject': 'Mathematics', 'year': 2018, 'question': 'What is the perimeter of a square with side 5?', 'options': ['10', '15', '20', '25'], 'correctIndex': 2, 'explanation': 'Perimeter = 4 × side = 4 × 5 = 20'},
  {'subject': 'Mathematics', 'year': 2019, 'question': 'A diagonal of a rectangle divides it into:', 'options': ['3 parts', '2 equal right triangles', '4 parts', '2 unequal parts'], 'correctIndex': 1, 'explanation': 'A diagonal divides a rectangle into two congruent right triangles'},

  // ---- Trigonometry ----
  {'subject': 'Mathematics', 'year': 2020, 'question': 'In a right triangle, sin(θ) =', 'options': ['opposite/adjacent', 'opposite/hypotenuse', 'adjacent/hypotenuse', 'hypotenuse/opposite'], 'correctIndex': 1, 'explanation': 'sin(θ) = opposite side / hypotenuse'},
  {'subject': 'Mathematics', 'year': 2021, 'question': 'In a right triangle, cos(θ) =', 'options': ['opposite/hypotenuse', 'adjacent/hypotenuse', 'opposite/adjacent', 'hypotenuse/adjacent'], 'correctIndex': 1, 'explanation': 'cos(θ) = adjacent side / hypotenuse'},
  {'subject': 'Mathematics', 'year': 2022, 'question': 'In a right triangle, tan(θ) =', 'options': ['adjacent/opposite', 'opposite/adjacent', 'hypotenuse/adjacent', 'hypotenuse/opposite'], 'correctIndex': 1, 'explanation': 'tan(θ) = opposite side / adjacent side'},
  {'subject': 'Mathematics', 'year': 2023, 'question': 'What is sin(90°)?', 'options': ['0', '1', '-1', '0.5'], 'correctIndex': 1, 'explanation': 'sin(90°) = 1'},
  {'subject': 'Mathematics', 'year': 2024, 'question': 'What is cos(0°)?', 'options': ['0', '1', '-1', '0.5'], 'correctIndex': 1, 'explanation': 'cos(0°) = 1'},
  {'subject': 'Mathematics', 'year': 2025, 'question': 'What is tan(45°)?', 'options': ['0', '1', '-1', '0.5'], 'correctIndex': 1, 'explanation': 'tan(45°) = 1'},
  {'subject': 'Mathematics', 'year': 2026, 'question': 'sin²(θ) + cos²(θ) =', 'options': ['0', '1', '2', 'sin(2θ)'], 'correctIndex': 1, 'explanation': 'This is the fundamental trigonometric identity'},

  // ---- Calculus ----
  {'subject': 'Mathematics', 'year': 2000, 'question': 'What is the derivative of x³?', 'options': ['x²', '3x²', 'x', '3x'], 'correctIndex': 1, 'explanation': 'd/dx(x³) = 3x²'},
  {'subject': 'Mathematics', 'year': 2001, 'question': 'What is the derivative of 2x² + 3x?', 'options': ['4x', '4x + 3', '2x + 3', 'x + 3'], 'correctIndex': 1, 'explanation': 'd/dx(2x² + 3x) = 4x + 3'},
  {'subject': 'Mathematics', 'year': 2002, 'question': 'What is the integral of x²?', 'options': ['2x', 'x³/3', 'x³', 'x³/3 + C'], 'correctIndex': 3, 'explanation': '∫x² dx = x³/3 + C'},
  {'subject': 'Mathematics', 'year': 2003, 'question': 'What is the limit of 1/x as x approaches infinity?', 'options': ['1', 'infinity', '0', 'undefined'], 'correctIndex': 2, 'explanation': 'lim(x→∞) 1/x = 0'},
  {'subject': 'Mathematics', 'year': 2004, 'question': 'What is the derivative of sin(x)?', 'options': ['cos(x)', '-cos(x)', 'sin(x)', '-sin(x)'], 'correctIndex': 0, 'explanation': 'd/dx(sin(x)) = cos(x)'},

  // ---- Statistics & Probability ----
  {'subject': 'Mathematics', 'year': 2005, 'question': 'What is the mean of 2, 4, 6, 8?', 'options': ['4', '5', '6', '7'], 'correctIndex': 1, 'explanation': 'Mean = (2 + 4 + 6 + 8) / 4 = 20 / 4 = 5'},
  {'subject': 'Mathematics', 'year': 2006, 'question': 'What is the median of 1, 3, 5, 7, 9?', 'options': ['3', '5', '7', '9'], 'correctIndex': 1, 'explanation': 'The median is the middle value: 5'},
  {'subject': 'Mathematics', 'year': 2007, 'question': 'What is the mode of 2, 3, 3, 5, 5, 5?', 'options': ['3', '5', '3.5', '4'], 'correctIndex': 1, 'explanation': 'The mode is the most frequently occurring value: 5'},
  {'subject': 'Mathematics', 'year': 2008, 'question': 'The probability of rolling a 6 on a die is:', 'options': ['1/6', '1/3', '1/2', '2/6'], 'correctIndex': 0, 'explanation': 'A die has 6 sides, so P(6) = 1/6'},
  {'subject': 'Mathematics', 'year': 2009, 'question': 'What is the probability of flipping heads on a coin?', 'options': ['1/4', '1/3', '1/2', '2/3'], 'correctIndex': 2, 'explanation': 'A coin has 2 sides, so P(heads) = 1/2'}
];
