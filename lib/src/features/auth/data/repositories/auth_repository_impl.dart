import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nai/src/imports/core_imports.dart';
import 'package:nai/src/imports/packages_imports.dart';

import 'package:nai/src/features/auth/domain/entities/user.dart';
import 'package:nai/src/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  final _authStateController = StreamController<AppUser?>.broadcast();

  AuthRepositoryImpl() {
    _supabase.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      if (session == null) {
        _authStateController.add(null);
        return;
      }
      final user = await _fetchAppUser(session.user.id);
      _authStateController.add(user);
    });
  }

  Future<AppUser?> _fetchAppUser(String userId) async {
    try {
      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (profile == null) return null;

      return _mapProfile(profile);
    } catch (e) {
      debugPrint("_fetchAppUser error: $e");
      return null;
    }
  }

  AppUser _mapProfile(Map<String, dynamic> json) {
    return AppUser(
      id: json["id"].toString(),
      email: json["zetramail"] ?? "",
      name: json["full_name"] ?? json["username"],
      photoUrl: json["photo_url"],
      zetraId: json["zetra_id"],
      zetraMail: json["zetramail"],
      verified: json["verified"] == true,
    );
  }

  @override
  Stream<AppUser?> get onAuthStateChanged => _authStateController.stream;

  /// Shared by login() and signUp(): both just authenticate against an
  /// existing ZetraMail + password (NAI never creates accounts — Zetra ID
  /// does). The ZetraMail address isn't the real Supabase Auth email, so
  /// it's resolved to the internal auth email first via resolve_login_email,
  /// the same RPC Zetra ID's own login screen uses. If the account is found
  /// but not yet verified for NAI, a fresh OTP is sent automatically so
  /// it's waiting when the router redirects the user to VerifyCodeScreen.
  Future<Either<Failure, AppUser>> _authenticate({
    required String email,
    required String password,
    required String notFoundMessage,
  }) async {
    try {
      debugPrint("===== RESOLVE LOGIN EMAIL (Supabase) =====");
      debugPrint(email);

      final resolvedEmail = await _supabase.rpc(
        'resolve_login_email',
        params: {"p_identifier": email},
      ) as String?;

      if (resolvedEmail == null || resolvedEmail.isEmpty) {
        return left(ServerFailure(notFoundMessage));
      }

      debugPrint("===== AUTHENTICATE (Supabase) =====");
      debugPrint(resolvedEmail);

      final response = await _supabase.auth.signInWithPassword(
        email: resolvedEmail,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        return left(ServerFailure(notFoundMessage));
      }

      final appUser = await _fetchAppUser(user.id);
      if (appUser == null) {
        return left(ServerFailure("Could not load your profile. Please try again."));
      }

      if (!appUser.verified) {
        try {
          await _supabase.rpc('request_otp');
        } catch (e) {
          debugPrint("request_otp error: $e");
        }
      }

      _authStateController.add(appUser);
      return right(appUser);
    } on AuthException catch (e) {
      debugPrint("Authenticate AuthException: ${e.message}");
      return left(ServerFailure(notFoundMessage));
    } on PostgrestException catch (e) {
      debugPrint("Authenticate PostgrestException: ${e.message}");
      return left(ServerFailure(notFoundMessage));
    } catch (e) {
      debugPrint(e.toString());
      return left(ServerFailure(e.toString()));
    }
  }

  @override
  FutureEither<AppUser> login({
    required String email,
    required String password,
  }) {
    return _authenticate(
      email: email,
      password: password,
      notFoundMessage: "Invalid ZetraMail or password.",
    );
  }

  @override
  FutureEither<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  }) {
    // NAI never creates new accounts. Accounts only exist if they were
    // created in the Zetra ID app. "Signing up" here means authenticating
    // against an existing ZetraMail + password — if it's valid, this is
    // effectively a login (with an automatic OTP send if unverified). If
    // it's invalid, the ZetraMail doesn't exist yet and we tell the user
    // to create it in the Zetra ID app first.
    return _authenticate(
      email: email,
      password: password,
      notFoundMessage: "No ZetraMail account found. Please create your ZetraMail in the Zetra ID app first.",
    );
  }

  @override
  FutureEither<void> forgotPassword({
    required String email,
  }) async {
    try {
      debugPrint("===== REQUEST PASSWORD RESET (Supabase) =====");
      debugPrint(email);

      await _supabase.rpc('request_password_reset', params: {
        "p_zetramail": email,
      });

      return right(null);
    } on PostgrestException catch (e) {
      debugPrint("forgotPassword PostgrestException: ${e.message}");
      return left(ServerFailure(e.message));
    } catch (e) {
      return left(ServerFailure(e.toString()));
    }
  }

  @override
  FutureEither<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      debugPrint("===== CONFIRM PASSWORD RESET (Supabase) =====");
      debugPrint(email);

      final result = await _supabase.rpc('confirm_password_reset', params: {
        "p_zetramail": email,
        "p_code": code,
        "p_new_password": newPassword,
      });

      final bool success = result == true;

      if (!success) {
        return left(ServerFailure("Invalid or expired code. Please try again."));
      }

      return right(null);
    } on PostgrestException catch (e) {
      debugPrint("confirmPasswordReset PostgrestException: ${e.message}");
      return left(ServerFailure(e.message));
    } catch (e) {
      return left(ServerFailure(e.toString()));
    }
  }

  @override
  FutureEither<void> logout() async {
    try {
      await _supabase.auth.signOut();
      _authStateController.add(null);
      return right(null);
    } on AuthException catch (e) {
      return left(ServerFailure(e.message));
    } catch (e) {
      return left(ServerFailure(e.toString()));
    }
  }

  @override
  FutureEither<AppUser?> checkAuthState() async {
    try {
      final session = _supabase.auth.currentSession;

      debugPrint("========== CHECK AUTH (Supabase) ==========");
      debugPrint(session?.user.id ?? "No session");

      if (session == null) {
        return right(null);
      }

      final appUser = await _fetchAppUser(session.user.id);
      return right(appUser);
    } catch (e) {
      debugPrint("checkAuthState Exception:");
      debugPrint(e.toString());
      return right(null);
    }
  }

  @override
  FutureEither<AppUser> verifyCode({
    required String code,
  }) async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) {
        return left(ServerFailure("You're not signed in. Please log in again."));
      }

      final result = await _supabase.rpc('verify_otp', params: {"p_code": code});

      debugPrint("===== VERIFY RESPONSE (Supabase) =====");
      debugPrint(result.toString());

      final bool success = result == true;

      if (!success) {
        return left(ServerFailure("Invalid or expired code. Please try again."));
      }

      final appUser = await _fetchAppUser(session.user.id);
      if (appUser == null) {
        return left(ServerFailure("Could not load your profile. Please try again."));
      }

      _authStateController.add(appUser);
      return right(appUser);
    } on PostgrestException catch (e) {
      debugPrint("verifyCode PostgrestException: ${e.message}");
      return left(ServerFailure(e.message));
    } catch (e) {
      debugPrint(e.toString());
      return left(ServerFailure(e.toString()));
    }
  }

  @override
  FutureEither<void> resendCode() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) {
        return left(ServerFailure("You're not signed in. Please log in again."));
      }

      await _supabase.rpc('request_otp');

      debugPrint("===== RESEND CODE (Supabase) =====");

      return right(null);
    } on PostgrestException catch (e) {
      debugPrint("resendCode PostgrestException: ${e.message}");
      return left(ServerFailure(e.message));
    } catch (e) {
      return left(ServerFailure(e.toString()));
    }
  }
}
