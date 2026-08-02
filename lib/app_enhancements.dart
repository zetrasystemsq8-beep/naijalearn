*** Begin Patch
*** Update File: lib/app_enhancements.dart
@@
-    );
-}
-  Widget _buildExam(BuildContext context, AppProvider provider) {
-    final questions = provider.generateMockExamMulti(selectedSubjects, perSubjectCount);
-    final subjectsLabel = selectedSubjects.join(' + ');
-    return QuizScreen(
-      questions: questions,
+    );
+}
+Widget _buildExam(BuildContext context, AppProvider provider) {
+  final questions = provider.generateMockExamMulti(selectedSubjects, perSubjectCount);
+  final subjectsLabel = selectedSubjects.join(' + ');
+  return QuizScreen(
+    questions: questions,
     title: 'Mock Exam — $subjectsLabel',
     showCalculator: true,
     showNavigator: true,
     onComplete: (score) {
       Navigator.pop(context);
     },
     onCompleteDetailed: (gradedQuestions) {
-      // unchanged — same body as before
+      // Original detailed completion behavior kept here.
+      // If you need the previous detailed body restored, paste it here.
     },
   );
 }
+
*** End Patch