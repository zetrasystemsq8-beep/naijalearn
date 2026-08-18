// lib/app_update.dart
//
// FORCE UPDATE / VERSION GATE
//
// Lets you remotely require a minimum app version. When you ship a new
// build that changes something old clients can't safely talk to (a
// breaking Supabase RPC signature, a new mandatory table, etc.), bump
// `min_supported_version` in the `app_config` Supabase table. Any device
// running an older build than that gets a full-screen, non-dismissible
// "please update" screen instead of the app — before login, before
// anything else touches the backend.
//
// Deliberately "fails open": if the version check itself fails (offline,
// Supabase hiccup, table missing), the app is allowed to continue rather
// than locking everyone out because of a network blip.
//
// SUPABASE SETUP (run once in the SQL editor):
//
//   create table if not exists public.app_config (
//     id int primary key default 1,
//     min_supported_version text not null default '1.0.0',
//     latest_version text not null default '1.0.0',
//     update_message text,
//     android_store_url text,
//     ios_store_url text,
//     updated_at timestamptz not null default now(),
//     constraint app_config_singleton check (id = 1)
//   );
//
//   insert into public.app_config (id, min_supported_version, latest_version, update_message, android_store_url, ios_store_url)
//   values (1, '1.0.0', '1.0.0', 'A new version of NaijaLearn is available.', 'https://play.google.com/store/apps/details?id=YOUR_PACKAGE', 'https://apps.apple.com/app/idYOUR_APP_ID')
//   on conflict (id) do nothing;
//
//   alter table public.app_config enable row level security;
//
//   create policy "app_config_public_read" on public.app_config
//     for select using (true);
//
// To FORCE an update later: just raise min_supported_version in that row
// (e.g. via the Supabase table editor) to match your new build's version
// in pubspec.yaml. No app redeploy needed to flip the switch.
//
// PUBSPEC: add these two dependencies —
//   package_info_plus: ^8.0.0
//   url_launcher: ^6.3.0
//
// MAIN.DART INTEGRATION (3 small edits — see chat message for exact diff):
//   1. import 'app_update.dart';
//   2. In SplashScreen's Timer callback, check AppUpdateService before
//      deciding the destination widget.
//   3. Nothing else — ForceUpdateScreen is self-contained.

import 'dart:io';
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
  final String? androidStoreUrl;
  final String? iosStoreUrl;

  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.minSupportedVersion,
    required this.latestVersion,
    required this.mustUpdate,
    required this.updateMessage,
    this.androidStoreUrl,
    this.iosStoreUrl,
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

  /// Compares the installed build's version (from pubspec.yaml, read via
  /// package_info_plus) against the `min_supported_version` row in
  /// Supabase. Never throws — any failure here is treated as "allow the
  /// app to continue" so a bad network moment can't lock everyone out.
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
      final row = await _client.from('app_config').select().eq('id', 1).maybeSingle();
      if (row == null) {
        debugPrint('[AppUpdateService] No app_config row found — skipping version gate.');
        return AppUpdateCheckResult.upToDate(currentVersion);
      }

      final minVersion = row['min_supported_version'] as String? ?? '0.0.0';
      final latestVersion = row['latest_version'] as String? ?? currentVersion;
      final message = (row['update_message'] as String?)?.trim();
      final androidUrl = row['android_store_url'] as String?;
      final iosUrl = row['ios_store_url'] as String?;

      final mustUpdate = _isVersionLower(currentVersion, minVersion);

      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        minSupportedVersion: minVersion,
        latestVersion: latestVersion,
        mustUpdate: mustUpdate,
        updateMessage: (message == null || message.isEmpty)
            ? 'A new version of NaijaLearn is required to continue. Please update to keep using the app.'
            : message,
        androidStoreUrl: androidUrl,
        iosStoreUrl: iosUrl,
      );
    } catch (e) {
      debugPrint('[AppUpdateService] Version check failed (non-fatal, allowing app to continue): $e');
      return AppUpdateCheckResult.upToDate(currentVersion);
    }
  }

  /// Simple semantic-version comparison (major.minor.patch). Missing
  /// segments default to 0, so "1.2" is treated as "1.2.0".
  bool _isVersionLower(String current, String min) {
    final c = _parseVersion(current);
    final m = _parseVersion(min);
    for (var i = 0; i < 3; i++) {
      if (c[i] != m[i]) return c[i] < m[i];
    }
    return false;
  }

  List<int> _parseVersion(String v) {
    final cleaned = v.split('+').first; // drop build number like "1.2.3+45"
    final parts = cleaned.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts.take(3).toList();
  }
}

/// Full-screen, non-dismissible "please update" wall. Shown in place of
/// the app whenever AppUpdateService reports mustUpdate == true.
class ForceUpdateScreen extends StatelessWidget {
  final AppUpdateCheckResult result;
  const ForceUpdateScreen({super.key, required this.result});

  Future<void> _openStore(BuildContext context) async {
    final url = Platform.isIOS ? result.iosStoreUrl : result.androidStoreUrl;
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
        const SnackBar(content: Text('Could not open the store. Please update manually.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // canPop: false — this screen is a hard wall. There is no "skip" or
    // back gesture; the only way forward is updating the app.
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
                const SizedBox(height: 8),
                Text(
                  'Installed: v${result.currentVersion}  •  Required: v${result.minSupportedVersion}',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withOpacity(0.7)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => _openStore(context),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Update Now', style: TextStyle(fontSize: 16)),
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
