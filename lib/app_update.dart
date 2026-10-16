// lib/app_update.dart
//
// FORCE UPDATE / VERSION GATE — now with a grace-period WARNING stage.
//
// Behaviour:
//   1. User is on an outdated version (below min_supported_version).
//   2. For the first `grace_days` days after the LATEST version was set,
//      they see a dismissible banner ("update available") — the app
//      still works normally.
//   3. Once grace_days have passed, the banner becomes a full-screen,
//      non-dismissible block (ForceUpdateScreen) — same hard lock as
//      before.
//
// Deliberately "fails open": if the version check itself fails (offline,
// Supabase hiccup, table missing), the app is allowed to continue rather
// than locking everyone out because of a network blip.
//
// SUPABASE SETUP — run this once to add the grace period column:
//
//   ALTER TABLE naijalearn_config ADD COLUMN IF NOT EXISTS grace_days INT DEFAULT 3;
//
// To tune how long the warning shows before it blocks, just update that
// column's value — no app redeploy needed.
//
// MAIN.DART INTEGRATION — 2 small changes, both inside NaijaLearnApp's
// build() method, see instructions below the code block in chat.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of a version check.
class AppUpdateCheckResult {
  final String currentVersion;
  final String minSupportedVersion;
  final String latestVersion;
  final bool mustUpdate;   // hard block — grace period has expired
  final bool showBanner;   // soft warning — still within grace period
  final String updateMessage;
  final String? apkUrl;

  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.minSupportedVersion,
    required this.latestVersion,
    required this.mustUpdate,
    required this.showBanner,
    required this.updateMessage,
    this.apkUrl,
  });

  factory AppUpdateCheckResult.upToDate(String currentVersion) => AppUpdateCheckResult(
        currentVersion: currentVersion,
        minSupportedVersion: currentVersion,
        latestVersion: currentVersion,
        mustUpdate: false,
        showBanner: false,
        updateMessage: '',
      );
}

class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const _prefVersionKey = 'nl_update_first_seen_version';
  static const _prefTimeKey = 'nl_update_first_seen_at';

  /// The rest of the app (the banner host in main.dart) listens to this
  /// to know whether to show the dismissible banner right now.
  final ValueNotifier<AppUpdateCheckResult?> lastResult = ValueNotifier(null);

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
        showBanner: false,
        updateMessage: '',
      );
    }

    try {
      final row = await _client.from('naijalearn_config').select().eq('id', 1).maybeSingle();
      if (row == null) {
        debugPrint('[AppUpdateService] No naijalearn_config row found — skipping version gate.');
        final result = AppUpdateCheckResult.upToDate(currentVersion);
        lastResult.value = result;
        return result;
      }

      final minVersion = row['min_supported_version'] as String? ?? '0.0.0';
      final latestVersion = row['latest_version'] as String? ?? currentVersion;
      final message = (row['update_message'] as String?)?.trim();
      final apkUrl = row['apk_url'] as String?;
      final graceDays = (row['grace_days'] as int?) ?? 3;

      final isBehind = _isVersionLower(currentVersion, minVersion);

      if (!isBehind) {
        final result = AppUpdateCheckResult.upToDate(currentVersion);
        lastResult.value = result;
        return result;
      }

      // Track when THIS user first saw THIS latest version, so the grace
      // period is per-version, not reset every app launch.
      final prefs = await SharedPreferences.getInstance();
      final storedVersion = prefs.getString(_prefVersionKey);
      final storedAt = prefs.getInt(_prefTimeKey);

      DateTime firstSeenAt;
      if (storedVersion == latestVersion && storedAt != null) {
        firstSeenAt = DateTime.fromMillisecondsSinceEpoch(storedAt);
      } else {
        firstSeenAt = DateTime.now();
        await prefs.setString(_prefVersionKey, latestVersion);
        await prefs.setInt(_prefTimeKey, firstSeenAt.millisecondsSinceEpoch);
      }

      final elapsed = DateTime.now().difference(firstSeenAt);
      final graceExpired = elapsed >= Duration(days: graceDays);

      final finalMessage = (message == null || message.isEmpty)
          ? 'A new version of NaijaLearn is required to continue. Please update to keep using the app.'
          : message;

      final result = AppUpdateCheckResult(
        currentVersion: currentVersion,
        minSupportedVersion: minVersion,
        latestVersion: latestVersion,
        mustUpdate: graceExpired,
        showBanner: !graceExpired,
        updateMessage: finalMessage,
        apkUrl: apkUrl,
      );
      lastResult.value = result;
      return result;
    } catch (e) {
      debugPrint('[AppUpdateService] Version check failed (non-fatal, allowing app to continue): $e');
      final result = AppUpdateCheckResult.upToDate(currentVersion);
      lastResult.value = result;
      return result;
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

/// Full-screen, non-dismissible "please update" wall. Shown only once the
/// grace period has fully expired (AppUpdateCheckResult.mustUpdate).
class ForceUpdateScreen extends StatelessWidget {
  final AppUpdateCheckResult result;
  const ForceUpdateScreen({super.key, required this.result});

  Future<void> _downloadUpdate(BuildContext context) async {
    final url = result.apkUrl;
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
        const SnackBar(content: Text('Could not open the link. Please try again.')),
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
          child: SingleChildScrollView(
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
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    border: Border.all(color: Colors.amber.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 20, color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          Text(
                            'How to update — follow these steps',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.amber.shade900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _StepLine(number: '1', text: 'Tap the green "Download Update" button below. The file will download to your phone.'),
                      const SizedBox(height: 10),
                      _StepLine(number: '2', text: 'Open the downloaded file to install it.'),
                      const SizedBox(height: 10),
                      _StepLine(number: '3', text: 'Your phone may show a warning like "Unsafe app blocked" or "Unknown app". This is normal — it only means the app did not come from the Play Store.'),
                      const SizedBox(height: 10),
                      _StepLine(number: '4', text: 'Tap "More details" or the three-dot menu, then tap "Install anyway" to continue.'),
                      const SizedBox(height: 10),
                      _StepLine(number: '5', text: 'Wait for it to install, then open NaijaLearn again like normal.'),
                      const SizedBox(height: 12),
                      Text(
                        'This is safe. NaijaLearn is only ever shared this way — directly from our team.',
                        style: TextStyle(fontSize: 12, height: 1.4, color: Colors.amber.shade900, fontStyle: FontStyle.italic),
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
                    onPressed: () => _downloadUpdate(context),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download Update', style: TextStyle(fontSize: 16)),
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

class _StepLine extends StatelessWidget {
  final String number;
  final String text;
  const _StepLine({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.amber.shade800, shape: BoxShape.circle),
          child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.amber.shade900)),
        ),
      ],
    );
  }
}

// =====================================================================
// SOFT WARNING BANNER — shown during the grace period, dismissible for
// this session. Wrap your MaterialApp's `builder:` with this widget (see
// chat instructions) so it floats above whatever screen is currently
// showing, without needing to touch every individual screen.
// =====================================================================
class UpdateBannerHost extends StatefulWidget {
  final Widget child;
  const UpdateBannerHost({super.key, required this.child});

  @override
  State<UpdateBannerHost> createState() => _UpdateBannerHostState();
}

class _UpdateBannerHostState extends State<UpdateBannerHost> {
  bool _dismissed = false;

  Future<void> _openDownload(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUpdateCheckResult?>(
      valueListenable: AppUpdateService.instance.lastResult,
      builder: (context, result, _) {
        final show = result != null && result.showBanner && !_dismissed;
        return Stack(
          textDirection: TextDirection.ltr,
          children: [
            widget.child,
            if (show)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 8))],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.system_update_rounded, color: Colors.white),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'A new version of NaijaLearn is available',
                            style: TextStyle(color: Colors.white, fontSize: 13.5),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _dismissed = true),
                          child: const Text('Later', style: TextStyle(color: Colors.white70)),
                        ),
                        ElevatedButton(
                          onPressed: () => _openDownload(result!.apkUrl),
                          child: const Text('Update'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
