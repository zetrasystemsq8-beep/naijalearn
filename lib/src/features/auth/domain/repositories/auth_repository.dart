import 'package:nai/src/utils/utils.dart';
import 'package:nai/src/features/auth/domain/entities/user.dart';

abstract class AuthRepository {
  /// Stream of auth state changes. Emits AppUser when authenticated, null when not.
  Stream<AppUser?> get onAuthStateChanged;

  /// Sign in with email and password
  FutureEither<AppUser> login({
    required String email,
    required String password,
  });

  /// Sign up with email, password, and optional name
  FutureEither<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  });

  /// Requests a password reset code be sent to the user's ZetraMail inbox.
  FutureEither<void> forgotPassword({
    required String email,
  });

  /// Confirms the code sent to the user's ZetraMail inbox and sets a new password.
  FutureEither<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Sign out the current user
  FutureEither<void> logout();

  /// Check if the user is currently authenticated natively
  FutureEither<AppUser?> checkAuthState();

  /// Confirms the code the user entered against the one sent to
  /// their ZetraMail inbox, and marks their Zetra ID verified.
  FutureEither<AppUser> verifyCode({
    required String code,
  });

  /// Requests a fresh verification code be sent to the user's
  /// ZetraMail inbox.
  FutureEither<void> resendCode();
}
