// lib/new_account_screen.dart
//
// BASIC SIGN-UP for NaijaLearn — a simple in-app account, no ZetraMail
// needed. This is NOT a ZetraMail account and is not presented as one.
// Later, basic accounts will be required to move to a ZetraMail account.
//
// A brand-new account has no earlier code to receive, so there is NO OTP
// step here: after sign-up the user goes straight to the referral/tutor
// code step and then into the app.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart';

const List<String> kNaijaLearnNigerianStates = [
  'Abia', 'Adamawa', 'Akwa Ibom', 'Anambra', 'Bauchi', 'Bayelsa', 'Benue',
  'Borno', 'Cross River', 'Delta', 'Ebonyi', 'Edo', 'Ekiti', 'Enugu',
  'Federal Capital Territory (Abuja)', 'Gombe', 'Imo', 'Jigawa', 'Kaduna',
  'Kano', 'Katsina', 'Kebbi', 'Kogi', 'Kwara', 'Lagos', 'Nasarawa', 'Niger',
  'Ogun', 'Ondo', 'Osun', 'Oyo', 'Plateau', 'Rivers', 'Sokoto', 'Taraba',
  'Yobe', 'Zamfara',
];

/// Creates a basic NaijaLearn account directly inside the app — no website
/// visit and no ZetraMail required.
class NewAccountScreen extends StatefulWidget {
  const NewAccountScreen({super.key});
  @override
  State<NewAccountScreen> createState() => _NewAccountScreenState();
}

class _NewAccountScreenState extends State<NewAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _recoveryEmailController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _errorMessage;
  DateTime? _dateOfBirth;
  String? _gender;
  String _country = 'Nigeria';
  String? _state;

  static const List<String> _genderOptions = ['Male', 'Female', 'Prefer not to say'];

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _recoveryEmailController.dispose();
    super.dispose();
  }

  void _fail(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 13, now.month, now.day),
      helpText: 'Select date of birth',
    );
    if (picked != null && mounted) setState(() => _dateOfBirth = picked);
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String? _validateRecoveryEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null; // optional
    final emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
    if (!emailRegex.hasMatch(v)) return 'Enter a valid email, or leave this blank';
    return null;
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateOfBirth == null) {
      setState(() => _errorMessage = 'Please select your date of birth.');
      return;
    }
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final fullName = _fullNameController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final recoveryEmail = _recoveryEmailController.text.trim();

    try {
      final client = Supabase.instance.client;

      final internalEmail = await client
          .rpc('internal_auth_email', params: {'p_username': username})
          .timeout(kNetTimeout) as String?;
      if (internalEmail == null || internalEmail.isEmpty) {
        _fail('Something went wrong setting up your account. Please try again.');
        return;
      }

      final availabilityRaw = await client
          .rpc('check_registration_availability', params: {
            'p_username': username,
            'p_email': internalEmail,
            'p_phone': null,
          })
          .timeout(kNetTimeout);
      final availability = Map<String, dynamic>.from(availabilityRaw as Map);
      if (availability['username_taken'] == true) {
        _fail('That username is already taken.');
        return;
      }

      final dob =
          '${_dateOfBirth!.year.toString().padLeft(4, '0')}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}';

      final response = await client.auth
          .signUp(
            email: internalEmail,
            password: password,
            data: {
              'account_type': 'basic',
              'username': username,
              'full_name': fullName,
              'date_of_birth': dob,
              if (_gender != null) 'gender': _gender,
              'country': _country,
              if (_state != null) 'state': _state,
              if (recoveryEmail.isNotEmpty) 'recovery_email': recoveryEmail,
            },
          )
          .timeout(kNetTimeout);

      if (response.session == null) {
        _fail('Something went wrong creating your account. Please try again.');
        return;
      }

      // NO OTP for a brand-new basic account: there is no earlier code to
      // receive. Mark the session verified so the app (and the splash
      // screen on the next launch) lets them straight in.
      try {
        await client.auth.updateUser(UserAttributes(data: {'nl_otp_verified': true})).timeout(kQuickTimeout);
      } catch (e) {
        debugPrint('[NewAccount] Could not set otp-verified flag (non-fatal): $e');
      }

      ZetraProfile profile;
      try {
        profile = await AuthService.instance.loadCurrentProfile();
      } catch (e) {
        // Profile row may not be readable yet — build a minimal one so the
        // user is never blocked from entering the app.
        debugPrint('[NewAccount] Profile load failed, using minimal profile: $e');
        profile = ZetraProfile(
          id: response.user?.id ?? client.auth.currentUser?.id ?? '',
          zetramail: '',
          username: username,
          verified: false,
        );
      }

      if (!mounted) return;
      await routeAfterFullyVerifiedLogin(context, profile);
    } on AuthRetryableFetchException {
      _fail(kOfflineMessage);
    } on AuthException catch (e) {
      _fail(e.message.isNotEmpty ? e.message : 'Something went wrong. Please try again.');
    } on PostgrestException catch (_) {
      _fail('Something went wrong. Please try again.');
    } catch (e) {
      _fail(friendlyError(e, fallback: 'Something went wrong. Please try again.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Basic Sign-Up')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Honest note: this is a basic account, not ZetraMail.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade200, width: 1.2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.blue.shade700, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This is a basic NaijaLearn account — it is not a ZetraMail account. You can start learning right away. You will be asked to get a ZetraMail account later.',
                          style: TextStyle(color: Colors.blue.shade900, fontSize: 12.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Prominent, honest recovery-risk warning — not buried text.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.shade300, width: 1.4),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('If you forget this password, it cannot currently be recovered.',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              'There is no working "forgot password" yet. Write your password down somewhere safe.',
                              style: TextStyle(color: Colors.red.shade900, fontSize: 12, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _fullNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.badge_outlined)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your full name' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v == null || v.trim().length < 3) ? 'At least 3 characters' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) => (v != _passwordController.text) ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _recoveryEmailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Recovery email (optional)',
                    helperText: "Saved for later — doesn't recover your account yet",
                    helperMaxLines: 2,
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: _validateRecoveryEmail,
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _pickDateOfBirth,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date of Birth', prefixIcon: Icon(Icons.cake_outlined)),
                    child: Text(_dateOfBirth == null ? 'Select date' : _formatDate(_dateOfBirth!)),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _gender,
                  decoration: const InputDecoration(labelText: 'Gender (optional)', prefixIcon: Icon(Icons.people_outline)),
                  items: _genderOptions.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _country,
                  decoration: const InputDecoration(labelText: 'Country', prefixIcon: Icon(Icons.public_outlined)),
                  items: const [DropdownMenuItem(value: 'Nigeria', child: Text('Nigeria')), DropdownMenuItem(value: 'Other', child: Text('Other'))],
                  onChanged: (v) => setState(() {
                    _country = v ?? 'Nigeria';
                    if (_country != 'Nigeria') _state = null;
                  }),
                ),
                if (_country == 'Nigeria') ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _state,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'State (optional)', prefixIcon: Icon(Icons.map_outlined)),
                    items: kNaijaLearnNigerianStates.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setState(() => _state = v),
                  ),
                ],
                const SizedBox(height: 20),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
                    child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: _loading ? null : _createAccount,
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Text('Create Basic Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Basic login — username + password, no OTP. Only for BASIC accounts
/// (made through Basic Sign-Up). ZetraMail accounts must use the normal
/// Log In so they keep their OTP step.
class BasicLoginScreen extends StatefulWidget {
  const BasicLoginScreen({super.key});
  @override
  State<BasicLoginScreen> createState() => _BasicLoginScreenState();
}

class _BasicLoginScreenState extends State<BasicLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _errorMessage;

  static const String _invalidMessage = 'Invalid username or password.';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _fail(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    try {
      final client = Supabase.instance.client;

      final internalEmail = await client
          .rpc('internal_auth_email', params: {'p_username': username})
          .timeout(kNetTimeout) as String?;
      if (internalEmail == null || internalEmail.isEmpty) {
        _fail(_invalidMessage);
        return;
      }

      final response = await client.auth
          .signInWithPassword(email: internalEmail, password: password)
          .timeout(kNetTimeout);
      final user = response.user;
      if (user == null) {
        _fail(_invalidMessage);
        return;
      }

      // Only basic accounts may skip OTP. A ZetraMail account that ends up
      // here is signed straight back out and pointed to the normal login.
      if (user.userMetadata?['account_type'] != 'basic') {
        await AuthService.instance.signOut();
        _fail('This is not a basic account. Please use the normal Log In with your ZetraMail.');
        return;
      }

      try {
        await client.auth.updateUser(UserAttributes(data: {'nl_otp_verified': true})).timeout(kQuickTimeout);
      } catch (e) {
        debugPrint('[BasicLogin] Could not set otp-verified flag (non-fatal): $e');
      }

      ZetraProfile profile;
      try {
        profile = await AuthService.instance.loadCurrentProfile();
      } catch (e) {
        debugPrint('[BasicLogin] Profile load failed, using minimal profile: $e');
        profile = ZetraProfile(id: user.id, zetramail: '', username: username, verified: false);
      }

      if (!mounted) return;
      await routeAfterFullyVerifiedLogin(context, profile);
    } on AuthRetryableFetchException {
      _fail(kOfflineMessage);
    } on AuthException {
      _fail(_invalidMessage);
    } on PostgrestException {
      _fail('Something went wrong. Please try again.');
    } catch (e) {
      _fail(friendlyError(e, fallback: 'Something went wrong. Please try again.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Basic Login')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.shade700, width: 1.4),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('You are not a fully verified user',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900, fontSize: 13.5)),
                            const SizedBox(height: 4),
                            Text(
                              'A basic login is not a real ZetraMail account, so it has no code verification and fewer protections. Please consider signing up for a ZetraMail account later.',
                              style: TextStyle(color: Colors.amber.shade900, fontSize: 12.5, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your username' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                ),
                const SizedBox(height: 20),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
                    child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Text('Log In (Basic)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
