import 'package:naijalearn/src/imports/core_imports.dart';
import 'package:naijalearn/src/imports/packages_imports.dart';

import 'package:naijalearn/src/features/auth/presentation/providers/auth_provider.dart';
import 'package:naijalearn/src/features/auth/presentation/providers/session_provider.dart';
import 'package:naijalearn/src/routing/app_routes.dart';

/// Shown whenever the session is "unverified" — right after signup,
/// or on relaunch if the code was never entered. Asks the user to
/// enter the code sitting in their ZetraMail inbox (inside the
/// Zetra ID app). The router's redirect logic sends them home
/// automatically once verification succeeds.
class VerifyCodeScreen extends ConsumerStatefulWidget {
  const VerifyCodeScreen({super.key});

  @override
  ConsumerState<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends ConsumerState<VerifyCodeScreen> {
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    final code = _codeController.text.trim();
    if (code.length < 4) {
      showToast(context, message: 'Enter the code from your ZetraMail', status: 'error');
      return;
    }

    setState(() => _isVerifying = true);

    final repository = ref.read(authRepositoryProvider);
    final result = await repository.verifyCode(code: code);

    setState(() => _isVerifying = false);

    if (!mounted) return;

    result.fold(
      (failure) {
        showToast(context, message: failure.message, status: 'error');
      },
      (user) async {
        showToast(context, message: 'Zetra ID verified', status: 'success');
        await ref.read(sessionProvider.notifier).refreshSession();
        if (mounted) context.go(AppRoutes.home);
      },
    );
  }

  Future<void> _handleResend() async {
    setState(() => _isResending = true);

    final repository = ref.read(authRepositoryProvider);
    final result = await repository.resendCode();

    setState(() => _isResending = false);

    if (!mounted) return;

    result.fold(
      (failure) {
        showToast(context, message: failure.message, status: 'error');
      },
      (_) {
        showToast(context, message: 'A new code was sent to your ZetraMail', status: 'success');
      },
    );
  }

  Future<void> _handleLogout() async {
    await ref.read(sessionProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.theme.colorScheme;
    final tt = context.theme.textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: AppSpacing.xl.h),
                Icon(IconsaxPlusBold.sms_tracking, size: 56, color: cs.primary),
                SizedBox(height: AppSpacing.lg.h),
                Text(
                  'Verify your Zetra ID',
                  style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSpacing.sm.h),
                Text(
                  'Open your ZetraMail in the Zetra ID app, copy the code, and paste it below.',
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                SizedBox(height: AppSpacing.xxxl.h),
                AppTextField(
                  controller: _codeController,
                  enabled: !_isVerifying,
                  label: 'Verification code',
                  keyboardType: TextInputType.number,
                  prefixIcon: const Icon(IconsaxPlusBold.key),
                ),
                SizedBox(height: AppSpacing.lg.h),
                AppButton(
                  label: 'Verify',
                  isLoading: _isVerifying,
                  onPressed: _isVerifying ? null : _handleVerify,
                  width: ButtonSize.large,
                  isFullWidth: false,
                ),
                SizedBox(height: AppSpacing.lg.h),
                TextButton(
                  onPressed: _isResending ? null : _handleResend,
                  child: Text(
                    _isResending ? 'Sending...' : "Didn't get a code? Resend",
                    style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: _handleLogout,
                  child: Text(
                    'Use a different account',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
                SizedBox(height: AppSpacing.xl.h),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
