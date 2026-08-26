// lib/main.dart
//
// NaijaLearn — CBT Practice App
// Material 3.
//
// Question content lives in per-subject files (questions_*.dart).
// Gamification (XP, streak, badges, leaderboard, daily challenge, mock
// exams, analytics) lives in app_enhancements.dart and plugs in via
// AppProvider, without replacing any of the CBT screens below.
// Certification eligibility tracking lives in certification.dart.
// AI Study Coach, Score Predictor, Career Mode, Hall of Fame, Live Quiz
// Battles, Mistakes Vault, Bookmarks, Report Card, and small shared
// widgets (StreakSaverBanner, PaceMeter, dailyGoalStatusText) live in
// career_features.dart.
// Textbooks (multi-subject lesson shelf) live in textbooks.dart.
// Flashcards, Coin Shop, Spin Wheel, Multi-Exam Countdown, Topic
// Mastery, and Focus Mode live in features5.dart.
// Force-update / version gate lives in app_update.dart.
//
// THEME: the app's seed color is Nigerian green by default, but switches
// to an ocean-blue seed whenever CoinService.oceanThemeActive is true —
// making the Coin Shop's Ocean Theme Pack purchase actually visible
// across the whole app, not just a cosmetic flag sitting unused.
//
// Authentication: NaijaLearn is a client of the existing Zetra ecosystem.
// Users are NOT created here — they must already have a Zetra account.
// Login is email+password (signInWithPassword), matching how the rest of
// the Zetra ecosystem (NAI) authenticates. The user types their ZetraMail
// address; it's resolved to the internal auth_email via the
// resolve_login_email(...) Supabase RPC, and Supabase Auth's password
// sign-in is called using ONLY that internal auth_email — the user never
// sees or types it. If the RPC returns null/empty, or the password is
// wrong, we show "Invalid ZetraMail or password."
//
// Verification code step: a code is ALWAYS required after password login,
// on every single login attempt — not just for unverified profiles. This
// is a deliberate second factor: knowing the ZetraMail + password alone is
// not enough to get in, since the code only shows up in the account
// owner's ZetraMail inbox (via the Zetra ID app). request_otp is called
// exactly once, right after signInWithPassword succeeds.
//
// Session-vs-verified tracking: Supabase creates a valid session the
// instant signInWithPassword succeeds — BEFORE the OTP step runs. So a
// bare "is there a session?" check is not enough to know someone has
// fully logged in; if the app process is killed while the user is
// fetching their code from the ZetraMail app, a naive check would send
// them straight into HomeScreen on relaunch, skipping the code entirely.
// To prevent that, AuthService stores a `nl_otp_verified` flag in
// Supabase Auth's own per-user metadata: reset to false at the start of
// every login(), set to true only once verifyCode() succeeds. SplashScreen
// checks this flag (not just session presence) to decide whether to route
// to HomeScreen or back to VerifyOtpScreen — and does NOT re-request a
// code in that second case, since the one already sent is still valid.
//
// This does NOT use Supabase's built-in signInWithOtp/verifyOTP (which
// rejects the .internal auth email domain with "Email address is
// invalid") — it uses the backend's own request_otp/verify_otp RPCs,
// the same ones NAI uses.
//
// FORCE UPDATE: before deciding where to route (Login vs Home vs
// VerifyOtp), SplashScreen asks AppUpdateService whether this build is
// too old to keep running. If so, it's replaced entirely by
// ForceUpdateScreen — a non-dismissible wall — instead of continuing on
// to auth/session routing. See app_update.dart for the Supabase-backed
// version check itself.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import 'app_enhancements.dart';
import 'certification.dart';
import 'career_features.dart';
import 'textbooks.dart';
import 'features5.dart';
import 'zetra_pay.dart';
import 'wallet_display.dart';
import 'admin_panel.dart';
import 'academic_arena.dart';
import 'world_challenge.dart';
import 'study_squads.dart';
import 'nai_mentor.dart';
import 'guest_mode.dart';
import 'app_update.dart';
import 'questions_english.dart';
import 'questions_accounting.dart';
import 'questions_arabic.dart';
import 'questions_biology.dart';
import 'questions_commerce.dart';
import 'questions_crs.dart';
import 'questions_economics.dart';
import 'questions_geography.dart';
import 'questions_government.dart';
import 'questions_irs.dart';
import 'questions_literature.dart';
import 'questions_mathematics.dart';
import 'questions_physics.dart';
import 'questions_chemistry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  
  await NotificationService.instance.init();
  
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider.value(value: CoinService.instance),
        ChangeNotifierProvider.value(value: FlashcardService.instance),
        ChangeNotifierProvider.value(value: MasteryService.instance),
        ChangeNotifierProvider.value(value: ExamCountdownService.instance),
      ],
      child: const NaijaLearnApp(),
    ),
  );
}

/// =========================================================================
/// AUTHENTICATION (Zetra ecosystem client — email+password + mandatory OTP)
/// =========================================================================

class ZetraProfile {
  final String id;
  final String zetramail;
  final String username;
  final bool verified;
  final String? avatarUrl;

  ZetraProfile({
    required this.id,
    required this.zetramail,
    required this.username,
    required this.verified,
    this.avatarUrl,
  });

  factory ZetraProfile.fromMap(Map<String, dynamic> map) {
    return ZetraProfile(
      id: map['id'] as String,
      zetramail: map['zetramail'] as String? ?? '',
      username: map['username'] as String? ?? '',
      verified: map['verified'] as bool? ?? false,
      avatarUrl: map['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'zetramail': zetramail,
        'username': username,
        'verified': verified,
        'avatar_url': avatarUrl,
      };
}

// ...
// The rest of the file remains unchanged except for the insertion below
// in ContactSupportScreen.build children where we add the Admin menu.
// For brevity, I'm including the ContactSupportScreen section here with the
// admin FutureBuilder inserted; the rest of the file is unchanged.

/// =========================================================================
/// CONTACT SUPPORT
/// =========================================================================

class _SupportContact {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String subtitle;
  final Uri uri;
  const _SupportContact({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.uri,
  });
}

class ContactSupportScreen extends StatelessWidget {
  const ContactSupportScreen({super.key});

  static final List<_SupportContact> _general = [
    _SupportContact(
      icon: Icons.chat_rounded,
      color: const Color(0xFF25D366),
      label: 'WhatsApp (Private Line)',
      value: '+234 805 660 4409',
      subtitle: 'Fastest way to reach the team directly',
      uri: Uri.parse('https://wa.me/2348056604409'),
    ),
    _SupportContact(
      icon: Icons.phone_rounded,
      color: Colors.blue,
      label: 'Official Support Line',
      value: '0806 542 5732',
      subtitle: 'Call for general enquiries',
      uri: Uri.parse('tel:08065425732'),
    ),
    _SupportContact(
      icon: Icons.email_rounded,
      color: Colors.orange,
      label: 'App Support Email',
      value: 'naijalearn01@gmail.com',
      subtitle: 'Bugs, account issues, feedback',
      uri: Uri.parse('mailto:naijalearn01@gmail.com?subject=NaijaLearn%20Support'),
    ),
  ];

  static final List<_SupportContact> _company = [
    _SupportContact(
      icon: Icons.business_rounded,
      color: Colors.indigo,
      label: 'Zetra Company Email',
      value: 'zetraworld0@gmail.com',
      subtitle: 'General company enquiries',
      uri: Uri.parse('mailto:zetraworld0@gmail.com?subject=NaijaLearn%20Enquiry'),
    ),
    _SupportContact(
      icon: Icons.person_rounded,
      color: Colors.deepPurple,
      label: 'Founder / CEO',
      value: 'coderinnovator@gmail.com',
      subtitle: 'Direct line to the founder',
      uri: Uri.parse('mailto:coderinnovator@gmail.com?subject=NaijaLearn%20-%20Message%20for%20the%20CEO'),
    ),
  ];

  Future<void> _open(BuildContext context, Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open that automatically. Please reach out manually.')),
      );
    }
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
    );
  }

  Widget _contactTile(BuildContext context, _SupportContact c) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _open(context, c.uri),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: c.color.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
                  child: Icon(c.icon, color: c.color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(c.value, style: TextStyle(fontSize: 13, color: scheme.primary, fontWeight: FontWeight.w600)),
                      Text(c.subtitle, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Support')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.primaryContainer.withOpacity(0.4), borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                Icon(Icons.support_agent_rounded, color: scheme.primary, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Having a problem or challenge with the app? Reach out through any of the channels below — we read everything.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          _sectionLabel(context, 'Talk to the Team'),
          ..._general.map((c) => _contactTile(context, c)),
          _sectionLabel(context, 'Company & Leadership'),
          ..._company.map((c) => _contactTile(context, c)),
          // Admin menu (only visible to admins)
          FutureBuilder<Map<String, dynamic>?>(
            future: () async {
              try {
                final client = Supabase.instance.client;
                final userId = client.auth.currentUser?.id;
                if (userId == null) return null;
                final row = await client.from('profiles').select('is_admin').eq('id', userId).maybeSingle();
                return row as Map<String, dynamic>?;
              } catch (_) {
                return null;
              }
            }(),
            builder: (context, snap) {
              final loaded = snap.connectionState == ConnectionState.done;
              final isAdmin = loaded && snap.data != null && snap.data!['is_admin'] == true;
              if (!loaded || !isAdmin) return const SizedBox.shrink();
              return _MenuTile(
                icon: Icons.admin_panel_settings_rounded,
                label: 'Admin',
                subtitle: 'Manage cent purchase requests',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPanelScreen())),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ... rest of main.dart unchanged
