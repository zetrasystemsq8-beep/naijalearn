// lib/zetra_pay.dart
//
// Thin client for the shared ZTC "app currency" system. NaijaLearn's
// in-app currency IS Cent itself (cents_per_unit = 1 for 'naijalearn') —
// there's no separate wrapped "Coin". Buying converts CP -> Cent;
// spending/crediting only ever touches the app_currency_balances row,
// never the CP wallet directly.

import 'package:supabase_flutter/supabase_flutter.dart';

class ZetraPay {
  ZetraPay._();

  static const String naijaLearnAppId = 'naijalearn';
  static SupabaseClient get _client => Supabase.instance.client;

  static String get _requireUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in.');
    return id;
  }

  static Future<Map<String, dynamic>> _getMyWallet() async {
    final userId = _requireUserId;
    final wallet = await _client.from('wallets').select('id').eq('user_id', userId).single();
    return wallet;
  }

  /// Buys Cent using CP from the user's shared wallet. p_cent_amount is
  /// the amount of CP-subunits to spend; returns null on success or an
  /// error message on failure.
  static Future<String?> buyAppCurrency({
    required String appId,
    required double centAmount,
  }) async {
    try {
      final myWallet = await _getMyWallet();

      final result = await _client.rpc('buy_app_currency', params: {
        'p_wallet_id': myWallet['id'],
        'p_app_id': appId,
        'p_cent_amount': centAmount,
      });

      if (result is Map && result['success'] == true) return null;
      return 'Purchase failed';
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return 'Something went wrong. Please try again.';
    }
  }

  /// Debits the app-specific balance for an in-app purchase (shop item,
  /// streak freeze, etc). Returns null on success or an error message.
  static Future<String?> spendAppCurrency({
    required String appId,
    required double unitAmount,
  }) async {
    try {
      final result = await _client.rpc('spend_app_currency', params: {
        'p_app_id': appId,
        'p_unit_amount': unitAmount,
      });
      if (result is Map && result['success'] == true) return null;
      return 'Purchase failed';
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return 'Something went wrong. Please try again.';
    }
  }

  /// Awards free Cent (daily login bonus, spin wheel win). Server-side
  /// caps this at 10 Cent per call regardless of what's passed in.
  static Future<String?> creditAppCurrency({
    required String appId,
    required double unitAmount,
  }) async {
    try {
      final result = await _client.rpc('credit_app_currency', params: {
        'p_app_id': appId,
        'p_unit_amount': unitAmount,
      });
      if (result is Map && result['success'] == true) return null;
      return 'Reward failed';
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return 'Something went wrong. Please try again.';
    }
  }

  static Future<double> getAppCurrencyBalance(String appId) async {
    final userId = _requireUserId;
    final data = await _client
        .from('app_currency_balances')
        .select('balance')
        .eq('user_id', userId)
        .eq('app_id', appId)
        .maybeSingle();
    return (data?['balance'] as num?)?.toDouble() ?? 0.0;
  }
}
