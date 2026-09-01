// lib/app_update.dart
//
// FORCE UPDATE / VERSION GATE
//
// Lets you remotely require a minimum app version. When you ship a new
// build that changes something old clients can't safely talk to, bump
// `min_supported_version` in the `naijalearn_config` Supabase table. Any
// device running an older build than that gets a full-screen,
// non-dismissible "please update" screen instead of the app — before
// login, before anything else touches the backend.
//
// Deliberately "fails open": if the version check itself fails (offline,
// Supabase hiccup, table missing), the app is allowed to continue rather
// than locking everyone out because of a network blip.
//
// IMPORTANT: this reads from `naijalearn_config`, NOT `app_config`.
// NaijaLearn was moved to its own dedicated table because `app_config`
// is already used by Tribunal (id=1 singleton conflict).
//
// SUPABASE SETUP (already done — table exists):
//
//   create table if not exists public.naijalearn_config (
//     id int primary key default 1,
//     min_supported_version text not null default '1.0.0',
//     latest_version text not null default '1.0.0',
//     update_message text,
//     zetra_store_url text,
//     updated_at timestamptz not null default now(),
//     constraint naijalearn_config_singleton check (id = 1)
//   );
//
// To FORCE an update later: just raise min_supported_version in that row
// to match your new build's version in pubspec.yaml. No app redeploy
// needed to flip the switch.
//
// PUBSPEC: requires these two dependencies —
//   package_info_plus: ^8.0.0
//   url_launcher: ^6.3.0
//
// MAIN.DART INTEGRATION: unchanged — SplashScreen already calls
// AppUpdateService.instance.checkForUpdate() and shows ForceUpdateScreen
// if mustUpdate is true. No changes needed there.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of a version check — either the app is fine to continue, or it
/// must show the force-update wall.
class AppUpdateCheckResult {
  final String currentVersion;
  final String minSupportedVersion;
  final String latestVersion;
  final bool mustUpdate;
  final String updateMessage;
  final String? zetraStoreUrl;

  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.minSupportedVersion,
    required this.latestVersion,
    required this.mustUpdate,
    required this.updateMessage,
    this.zetraStoreUrl,
  });

  factory AppUpdateCheckResult.upToDate(String currentVersion) => AppUpdateCheckResult(
        currentVersion: currentVersion,
        minSupportedVersion: currentVersion,
        latestVersion: currentVersion,
        mustUpdate: false,
        updateMessage: '',
      );
}

class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<AppUpdateCheckResult> checkForUpdate() async {
    late final String currentVersion;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      currentVersion = packageInfo.version;
    } catch (e) {
      debugPrint('[AppUpdateService] Could not read app version (non-fatal): $e');
      return const AppUpdateCheckResult(
        currentVersion: '0.0.0',
        minSupportedVersion: '0.0.0',
        latestVersion: '0.0.0',
        mustUpdate: false,
        updateMessage: '',
      );
    }

    try {
      final row = await _client.from('naijalearn_config').select().eq('id', 1).maybeSingle();
      if (row == null) {
        debugPrint('[AppUpdateService] No naijalearn_config row found — skipping version gate.');
        return AppUpdateCheckResult.upToDate(currentVersion);
      }

      final minVersion = row['min_supported_version'] as String? ?? '0.0.0';
      final latestVersion = row['latest_version'] as String? ?? currentVersion;
      final message = (row['update_message'] as String?)?.trim();
      final zetraStoreUrl = row['zetra_store_url'] as String?;

      final mustUpdate = _isVersionLower(currentVersion, minVersion);

      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        minSupportedVersion: minVersion,
        latestVersion: latestVersion,
        mustUpdate: mustUpdate,
        updateMessage: (message == null || message.isEmpty)
            ? 'A new version of NaijaLearn is required to continue. Please update to keep using the app.'
            : message,
        zetraStoreUrl: zetraStoreUrl,
      );
    } catch (e) {
      debugPrint('[AppUpdateService] Version check failed (non-fatal, allowing app to continue): $e');
      return AppUpdateCheckResult.upToDate(currentVersion);
    }
  }

  bool _isVersionLower(String current, String min) {
    final c = _parseVersion(current);
    final m = _parseVersion(min);
    for (var i = 0; i < 3; i++) {
      if (c[i] != m[i]) return c[i] < m[i];
    }
    return false;
  }

  List<int> _parseVersion(String v) {
    final cleaned = v.split('+').first;
    final parts = cleaned.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts.take(3).toList();
  }
}

/// Full-screen, non-dismissible "please update" wall. Explains to users
/// who don't have Zetra Store installed that they need to get it first,
/// then tapping the button sends them to download Zetra Store itself —
/// not a raw APK — so they land in the one place that always has the
/// latest, correct version of every Zetra app.
class ForceUpdateScreen extends StatelessWidget {
  final AppUpdateCheckResult result;
  const ForceUpdateScreen({super.key, required this.result});

  Future<void> _openZetraStore(BuildContext context) async {
    final url = result.zetraStoreUrl;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update link is not available right now — please check back shortly.')),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link. Please update manually.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(26)),
                  child: Icon(Icons.system_update_rounded, size: 50, color: scheme.primary),
                ),
                const SizedBox(height: 28),
                Text(
                  'Update Required',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  result.updateMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // Explanation for users who don't have Zetra Store yet —
                // stops them from feeling lost or confused by the button.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: scheme.primary),
                          const SizedBox(width: 8),
                          const Text('New here?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'All Zetra apps — including NaijaLearn — are now downloaded and updated through Zetra Store. '
                        'If you don\'t have Zetra Store installed yet, tap the button below to get it first. '
                        'Once it\'s installed, open it and download NaijaLearn from there.',
                        style: TextStyle(fontSize: 12.5, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Installed: v${result.currentVersion}  •  Required: v${result.minSupportedVersion}',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withOpacity(0.7)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => _openZetraStore(context),
                    icon: const Icon(Icons.storefront_rounded),
                    label: const Text('Get Zetra Store', style: TextStyle(fontSize: 16)),
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
