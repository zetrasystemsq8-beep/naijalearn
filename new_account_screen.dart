
const List<String> kNaijaLearnNigerianStates = [
  'Abia', 'Adamawa', 'Akwa Ibom', 'Anambra', 'Bauchi', 'Bayelsa', 'Benue',
  'Borno', 'Cross River', 'Delta', 'Ebonyi', 'Edo', 'Ekiti', 'Enugu',
  'Federal Capital Territory (Abuja)', 'Gombe', 'Imo', 'Jigawa', 'Kaduna',
  'Kano', 'Katsina', 'Kebbi', 'Kogi', 'Kwara', 'Lagos', 'Nasarawa', 'Niger',
  'Ogun', 'Ondo', 'Osun', 'Oyo', 'Plateau', 'Rivers', 'Sokoto', 'Taraba',
  'Yobe', 'Zamfara',
];

/// Creates a brand-new Zetra ID directly inside NaijaLearn — no website
/// visit required at all. Same underlying account system as the
/// website/app registration (same RPCs, same shared Supabase project),
/// just built natively here so Glo (or any carrier blocking GitHub
/// Pages) can't stop someone from signing up.
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

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 13, now.month, now.day),
      helpText: 'Select date of birth',
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
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
          .timeout(const Duration(seconds: 15)) as String?;
      if (internalEmail == null || internalEmail.isEmpty) {
        setState(() => _errorMessage = 'Something went wrong setting up your account. Please try again.');
        return;
      }

      final availabilityRaw = await client
          .rpc('check_registration_availability', params: {
            'p_username': username,
            'p_email': internalEmail,
            'p_phone': null,
          })
          .timeout(const Duration(seconds: 20));
      final availability = Map<String, dynamic>.from(availabilityRaw as Map);
      if (availability['username_taken'] == true) {
        setState(() => _errorMessage = 'That username is already taken.');
        return;
      }

      final dob =
          '${_dateOfBirth!.year.toString().padLeft(4, '0')}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}';

      final response = await client.auth
          .signUp(
            email: internalEmail,
            password: password,
            data: {
              'username': username,
              'full_name': fullName,
              'date_of_birth': dob,
              if (_gender != null) 'gender': _gender,
              'country': _country,
              if (_state != null) 'state': _state,
              if (recoveryEmail.isNotEmpty) 'recovery_email': recoveryEmail,
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.session == null) {
        setState(() => _errorMessage = 'Something went wrong creating your account. Please try again.');
        return;
      }

      // Same security posture as password login: every password-based
      // session gets an OTP step, including a brand-new signup.
      try {
        await client.rpc('request_otp').timeout(const Duration(seconds: 15));
      } catch (_) {
        // Non-fatal — VerifyOtpScreen's own "Resend" button covers this
        // if the code never arrives.
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VerifyOtpScreen()),
        (route) => false,
      );
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message.isNotEmpty ? e.message : 'Something went wrong. Please try again.');
    } on PostgrestException catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } catch (e) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Create Your Zetra ID')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                              'There is no working "forgot password" yet for any Zetra ID, app or website. Write your password down somewhere safe, or set up fingerprint sign-in right after creating your account.',
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
                        : const Text('Create Zetra ID', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
