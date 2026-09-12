// lib/become_tutor.dart
//
// Tutor application form. Submission does NOT grant tutor access —
// status starts 'pending' and only an admin approval (server-side) can
// flip it to 'approved'. See apply_to_become_tutor RPC.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// TODO(team): confirm this matches your existing quiz subject list.
const List<String> kTutorSubjects = [
  'Mathematics', 'English', 'Biology', 'Chemistry', 'Physics', 'Economics',
  'Government', 'Literature', 'Geography', 'Agricultural Science', 'Further Mathematics',
];

class BecomeTutorScreen extends StatefulWidget {
  const BecomeTutorScreen({super.key});

  @override
  State<BecomeTutorScreen> createState() => _BecomeTutorScreenState();
}

class _BecomeTutorScreenState extends State<BecomeTutorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _experienceController = TextEditingController();
  final _motivationController = TextEditingController();
  final _picker = ImagePicker();

  final Set<String> _selectedSubjects = {};
  XFile? _photo;
  bool _submitting = false;
  bool _checkingExisting = true;
  Map<String, dynamic>? _existingApplication;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkExistingApplication();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _experienceController.dispose();
    _motivationController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingApplication() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _checkingExisting = false);
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('tutor_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (mounted) setState(() => _existingApplication = row);
    } catch (_) {
      // Non-fatal — user can still try to apply.
    } finally {
      if (mounted) setState(() => _checkingExisting = false);
    }
  }

  Future<void> _pickPhoto() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 75);
    if (file != null && mounted) setState(() => _photo = file);
  }

  Future<String?> _uploadPhotoIfNeeded() async {
    if (_photo == null) return null;
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final ext = _photo!.path.split('.').last.toLowerCase();
    final safeExt = ['jpg', 'jpeg', 'png'].contains(ext) ? ext : 'jpg';
    final path = '$userId/tutor_photo_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final bytes = await _photo!.readAsBytes();

    await Supabase.instance.client.storage.from('classroom-media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: safeExt == 'png' ? 'image/png' : 'image/jpeg'),
        );

    return Supabase.instance.client.storage.from('classroom-media').getPublicUrl(path);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSubjects.isEmpty) {
      setState(() => _error = 'Select at least one subject you teach');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final photoUrl = await _uploadPhotoIfNeeded();

      await Supabase.instance.client.rpc('apply_to_become_tutor', params: {
        'p_full_name': _nameController.text.trim(),
        'p_photo_url': photoUrl,
        'p_subjects': _selectedSubjects.toList(),
        'p_description': _descriptionController.text.trim(),
        'p_experience': _experienceController.text.trim(),
        'p_motivation': _motivationController.text.trim(),
      });

      if (mounted) {
        await _checkExistingApplication();
      }
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not submit your application. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingExisting) {
      return Scaffold(appBar: AppBar(title: const Text('Become a Tutor')), body: const Center(child: CircularProgressIndicator()));
    }

    final status = _existingApplication?['status'] as String?;
    if (status != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Become a Tutor')),
        body: _buildStatusScreen(context, status),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Become a Tutor')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Teach on NaijaLearn', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Create your own paid classroom, set your own price, teach students, '
                'and earn from your knowledge. NaijaLearn provides the classroom — you provide the knowledge.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),

              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: scheme.primaryContainer,
                    backgroundImage: _photo != null ? FileImage(File(_photo!.path)) : null,
                    child: _photo == null ? Icon(Icons.add_a_photo_outlined, color: scheme.onPrimaryContainer) : null,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(child: Text('Profile photo (optional)', style: Theme.of(context).textTheme.bodySmall)),

              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
              ),
              const SizedBox(height: 16),

              Text('Subjects you teach', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kTutorSubjects.map((subject) {
                  final selected = _selectedSubjects.contains(subject);
                  return FilterChip(
                    label: Text(subject),
                    selected: selected,
                    onSelected: (v) => setState(() => v ? _selectedSubjects.add(subject) : _selectedSubjects.remove(subject)),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Short teaching description',
                  hintText: 'What do you teach and how?',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _experienceController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Experience / qualification (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _motivationController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Why do you want to teach on NaijaLearn?',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'This field is required' : null,
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Text('Submit Application', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusScreen(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    final Map<String, ({IconData icon, Color color, String title, String message})> copy = {
      'pending': (
        icon: Icons.hourglass_top_rounded, color: Colors.amber.shade800,
        title: 'Application under review',
        message: "We've received your tutor application. An admin will review it shortly.",
      ),
      'approved': (
        icon: Icons.check_circle_rounded, color: Colors.green,
        title: "You're an approved tutor",
        message: 'You can now create classrooms and start teaching.',
      ),
      'rejected': (
        icon: Icons.cancel_outlined, color: scheme.error,
        title: 'Application not approved',
        message: (_existingApplication?['rejection_reason'] as String?) ?? 'Please review and reapply.',
      ),
      'suspended': (
        icon: Icons.block_rounded, color: scheme.error,
        title: 'Tutor account suspended',
        message: (_existingApplication?['rejection_reason'] as String?) ?? 'Contact support for details.',
      ),
    };

    final c = copy[status]!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(c.icon, size: 56, color: c.color),
            const SizedBox(height: 16),
            Text(c.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(c.message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            if (status == 'rejected') ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => setState(() => _existingApplication = null),
                child: const Text('Reapply'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
