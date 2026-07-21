/// Centralized route path constants for GoRouter.
///
/// Use these variables instead of raw strings throughout the app.
/// Example:
/// `context.go(AppRoutes.onboarding)` instead of
/// `context.go('/onboarding')`.
abstract final class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String home = '/';
  static const String onboarding = '/onboarding';

  static const String login = '/login';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgot-password';

  // NEW: Verification screen
  static const String verifyCode = '/verify-code';

  static const String nigeriaNews = '/nigeria-news';
  static const String governmentServices = '/government-services';
  static const String wikiSearch = '/wiki-search';

  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String search = '/search';
}
