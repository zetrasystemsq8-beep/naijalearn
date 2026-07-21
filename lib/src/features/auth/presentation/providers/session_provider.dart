import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nai/src/features/auth/domain/entities/user.dart';
import 'package:nai/src/features/auth/domain/repositories/auth_repository.dart';
import 'package:nai/src/features/auth/data/repositories/auth_repository_impl.dart';

/// Provides the AuthRepository instance
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl();
});

/// Provides the current session state
final sessionProvider =
    StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  final repo = ref.read(authRepositoryProvider);
  return SessionNotifier(repository: repo);
});

/// Session states
enum SessionStatus {
  unknown,
  authenticated,
  unverified,
  unauthenticated,
}

class SessionState {
  final SessionStatus status;
  final AppUser? user;

  const SessionState({
    this.status = SessionStatus.unknown,
    this.user,
  });

  SessionState copyWith({
    SessionStatus? status,
    AppUser? user,
  }) {
    return SessionState(
      status: status ?? this.status,
      user: user ?? this.user,
    );
  }

  bool get isAuthenticated => status == SessionStatus.authenticated;

  /// True when a token exists and belongs to a real account, but the
  /// account hasn't entered its ZetraMail verification code yet.
  bool get isUnverified => status == SessionStatus.unverified;
}

class SessionNotifier extends StateNotifier<SessionState> {
  final AuthRepository _repository;

  SessionNotifier({
    required AuthRepository repository,
  })  : _repository = repository,
        super(const SessionState()) {
    // Listen to backend auth state changes
    _repository.onAuthStateChanged.listen((user) {
      state = _stateForUser(user);
    });

    refreshSession();
  }

  /// Expose auth state changes as a stream for GoRouterRefreshStream
  Stream<AppUser?> get authStateChanges => _repository.onAuthStateChanged;

  SessionState _stateForUser(AppUser? user) {
    if (user == null) {
      return const SessionState(status: SessionStatus.unauthenticated);
    }
    if (!user.verified) {
      return SessionState(status: SessionStatus.unverified, user: user);
    }
    return SessionState(status: SessionStatus.authenticated, user: user);
  }

  /// Checks whether the stored backend JWT is valid.
  Future<void> refreshSession() async {
    final result = await _repository.checkAuthState();

    result.fold(
      (_) {
        state = const SessionState(
          status: SessionStatus.unauthenticated,
        );
      },
      (user) {
        state = _stateForUser(user);
      },
    );
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const SessionState(status: SessionStatus.unauthenticated);
  }
}
