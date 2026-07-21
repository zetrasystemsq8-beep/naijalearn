import 'package:naijalearn/src/imports/core_imports.dart';
import 'package:naijalearn/src/imports/packages_imports.dart';

import 'package:naijalearn/src/features/auth/domain/repositories/auth_repository.dart';
import 'package:naijalearn/src/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:naijalearn/src/features/auth/presentation/providers/session_provider.dart';

final authControllerProvider =
    StateNotifierProvider<AuthController, bool>((ref) {
  return AuthController(
    ref: ref,
    repository: ref.read(authRepositoryProvider),
  );
});

class AuthController extends StateNotifier<bool> {
  final Ref _ref;
  final AuthRepository _repository;

  AuthController({
    required Ref ref,
    required AuthRepository repository,
  })  : _ref = ref,
        _repository = repository,
        super(false);

  /// Refreshes the session, then attempts to go home. The router's
  /// redirect logic is the single source of truth for where the
  /// user actually ends up — verified goes home, unverified gets
  /// bounced to the code screen automatically.
  Future<void> _proceedAfterAuth(BuildContext context) async {
    await _ref.read(sessionProvider.notifier).refreshSession();
    if (context.mounted) context.go(AppRoutes.home);
  }

  Future<void> login({
    required BuildContext context,
    required String email,
    required String password,
  }) async {
    state = true;

    final result = await _repository.login(
      email: email,
      password: password,
    );

    state = false;

    result.fold(
      (failure) {
        if (context.mounted) {
          showToast(
            context,
            message: failure.message,
            status: 'error',
          );
        }
      },
      (user) async {
        if (context.mounted) {
          showToast(
            context,
            message: 'Login successful',
            status: 'success',
          );
        }
        await _proceedAfterAuth(context);
      },
    );
  }

  Future<void> signUp({
    required BuildContext context,
    required String name,
    required String email,
    required String password,
  }) async {
    state = true;

    final result = await _repository.signUp(
      name: name,
      email: email,
      password: password,
    );

    state = false;

    result.fold(
      (failure) {
        if (context.mounted) {
          showToast(
            context,
            message: failure.message,
            status: 'error',
          );
        }
      },
      (user) async {
        if (context.mounted) {
          showToast(
            context,
            message: 'Signup successful',
            status: 'success',
          );
        }
        await _proceedAfterAuth(context);
      },
    );
  }

  Future<void> forgotPassword({
    required BuildContext context,
    required String email,
  }) async {
    state = true;

    final result = await _repository.forgotPassword(email: email);

    state = false;

    result.fold(
      (failure) {
        if (context.mounted) {
          showToast(
            context,
            message: failure.message,
            status: 'error',
          );
        }
      },
      (success) {
        if (context.mounted) {
          showToast(
            context,
            message: 'Password reset link sent successfully',
            status: 'success',
          );
          context.go(AppRoutes.login);
        }
      },
    );
  }
}
