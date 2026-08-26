---
*** Begin Patch
*** Update File: lib/main.dart
@@
-import 'wallet_display.dart';
+import 'wallet_display.dart';
+import 'admin_panel.dart';
@@
           _sectionLabel(context, 'Company & Leadership'),
           ..._company.map((c) => _contactTile(context, c)),
+          // Admin menu (only visible to admins)
+          FutureBuilder<Map<String, dynamic>?>(
+            future: () async {
+              try {
+                final client = Supabase.instance.client;
+                final userId = client.auth.currentUser?.id;
+                if (userId == null) return null;
+                final row = await client.from('profiles').select('is_admin').eq('id', userId).maybeSingle();
+                return row as Map<String, dynamic>?;
+              } catch (_) {
+                return null;
+              }
+            }(),
+            builder: (context, snap) {
+              final loaded = snap.connectionState == ConnectionState.done;
+              final isAdmin = loaded && snap.data != null && snap.data!['is_admin'] == true;
+              if (!loaded || !isAdmin) return const SizedBox.shrink();
+              return _MenuTile(
+                icon: Icons.admin_panel_settings_rounded,
+                label: 'Admin',
+                subtitle: 'Manage cent purchase requests',
+                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPanelScreen())),
+              );
+            },
+          ),
*** End Patch
