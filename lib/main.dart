*** Begin Patch
*** Update File: lib/main.dart
@@
 class _ProfileTab extends StatelessWidget {
   const _ProfileTab();
 
   @override
   Widget build(BuildContext context) {
     final provider = context.watch<AppProvider>();
     final stats = provider.stats;
     final scheme = Theme.of(context).colorScheme;
+    
@@
-                    child: Row(
-                      children: [
-                        icon,
-                        const SizedBox(width: 8),
-                        Expanded(
-                          child: Column(
-                            crossAxisAlignment: CrossAxisAlignment.start,
-                            children: [
-                              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
-                              Text(subtitle, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
-                            ],
-                          ),
-                        ),
-                      ],
-                    ),
-                    onTap: onTap,
+                    child: Row(
+                      children: [
+                        icon,
+                        const SizedBox(width: 8),
+                        Expanded(
+                          child: Column(
+                            crossAxisAlignment: CrossAxisAlignment.start,
+                            children: [
+                              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
+                              Text(subtitle, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
+                            ],
+                          ),
+                        ),
+                      ],
+                    ),
+                    onTap: onTap,
*** End Patch