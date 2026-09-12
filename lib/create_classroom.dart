// lib/create_classroom.dart
//
// Approved tutors only — the create_classroom RPC also enforces this
// server-side. Paying the 2,000-Cent creation fee and creating the
// classroom happen atomically in that RPC; if the fee can't be charged,
// nothing is created.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'become_tutor.dart' show kTutorSubjects;
import 'buy_cent.dart';

// TODO(team): confirm this category list.
const List<String> kClassroomCategories = [
  'JAMB', 'WAEC', 'NECO', 'Mathematics', 'English', 'Biology', 'Chemistry', 'Physics',
];

enum _Duration { thirtyDays, ninetyDays, unlimited }

class CreateClassroomScreen extends StatefulWidget {
  const CreateClassroomScreen({super.key});

  @override
  State<CreateClassroomScreen> createState() => _CreateClassroomScreenState();
}

class _CreateClassroomScreenState extends State<CreateClassroomScreen> {
  static const int _creationFeeCent = 2000;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _capacityController = TextEditingController(text: '50');
  final _picker = ImagePicker();

  String? _subject;
  final Set<String> _categories = {};
  bool _isPaid = true;
  _Duration _duration = _Duration.thirtyDays;
  XFile? _coverImage;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 75);
    if (file != null && mounted) setState(() => _coverImage = file);
  }

  Future<String?> _uploadCoverIfNeeded() async {
    if (_coverImage == null) return null;
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final ext = _coverImage!.path.split('.').last.toLowerCase();
    final safeExt = ['jpg', 'jpeg', 'png'].contains(ext) ? ext : 'jpg';
    final path = '$userId/classroom_cover_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final bytes = await _coverImage!.readAsBytes();

    await Supabase.instance.client.storage.from('classroom-media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: safeExt == 'png' ? 'image/png' : 'image/jpeg'),
        );

    return Supabase.instance.client.storage.from('classroom-media').getPublicUrl(path);
  }

  int? get _durationDays {
    switch (_duration) {
      case _Duration.thirtyDays:
        return 30;
      case _Duration.ninetyDays:
        return 90;
      case _Duration.unlimited:
        return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_subject == null) {
      setState(() => _error = 'Select a subject');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final coverUrl = await _uploadCoverIfNeeded();
      final price = _isPaid ? int.parse(_priceController.text) : 0;

      final result = await Supabase.instance.client.rpc('create_classroom', params: {
        'p_name': _nameController.text.trim(),
        'p_subject': _subject,
        'p_categories': _categories.toList(),
        'p_description': _descriptionController.text.trim(),
        'p_cover_image_url': coverUrl,
        'p_is_paid': _isPaid,
        'p_price_cent': price,
        'p_capacity': int.parse(_capacityController.text),
        'p_duration_days': _durationDays,
      });

      if (mounted) {
        final classroom = Map<String, dynamic>.from(result as Map);
        Navigator.pop(context, classroom);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Classroom created.'), backgroundColor: Colors.green),
        );
      }
    } on PostgrestException catch (e) {
      if (e.message.toLowerCase().contains('insufficient')) {
        _showInsufficientBalanceDialog();
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      setState(() => _error = 'Could not create the classroom. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showInsufficientBalanceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Not enough Cent'),
        content: const Text(
          'Creating a classroom costs 2,000 Cent. Your wallet balance is too low — top up first.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const BuyCentScreen()));
            },
            child: const Text('Buy Cent'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Classroom')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: scheme.onPrimaryContainer, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Creating a classroom costs $_creationFeeCent Cent, charged when you tap create below.',
                        style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              GestureDetector(
                onTap: _pickCover,
                child: Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outline),
                    image: _coverImage != null ? DecorationImage(image: FileImage(File(_coverImage!.path)), fit: BoxFit.cover) : null,
                  ),
                  child: _coverImage == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
                              const SizedBox(height: 6),
                              Text('Add cover image', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                            ],
                          ),
                        )
                      : null,
                ),
              ),

              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Classroom name', hintText: 'e.g. JAMB Biology Masterclass 2027', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a classroom name' : null,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _subject,
                decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
                items: kTutorSubjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _subject = v),
              ),
              const SizedBox(height: 16),

              Text('Categories (optional)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kClassroomCategories.map((c) {
                  final selected = _categories.contains(c);
                  return FilterChip(
                    label: Text(c),
                    selected: selected,
                    onSelected: (v) => setState(() => v ? _categories.add(c) : _categories.remove(c)),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description', hintText: 'What will students learn?', border: OutlineInputBorder()),
              ),

              const SizedBox(height: 20),
              Text('Classroom type', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Paid')),
                  ButtonSegment(value: false, label: Text('Free')),
                ],
                selected: {_isPaid},
                onSelectionChanged: (s) => setState(() => _isPaid = s.first),
              ),

              if (_isPaid) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Price per student (₦ / Cent)', border: OutlineInputBorder()),
                  validator: (v) {
                    if (!_isPaid) return null;
                    final n = int.tryParse(v ?? '');
                    if (n == null || n <= 0) return 'Enter a price greater than 0';
                    return null;
                  },
                ),
                if (_priceController.text.isNotEmpty && int.tryParse(_priceController.text) != null) ...[
                  const SizedBox(height: 8),
                  Builder(builder: (context) {
                    final price = int.parse(_priceController.text);
                    final fee = (price * 0.10).round();
                    return Text(
                      'You receive ₦${price - fee} per student · NaijaLearn takes ₦$fee (10%)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    );
                  }),
                ],
              ],

              const SizedBox(height: 16),
              TextFormField(
                controller: _capacityController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Maximum students', border: OutlineInputBorder()),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Enter a valid capacity';
                  return null;
                },
              ),

              const SizedBox(height: 16),
              Text('Duration', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<_Duration>(
                segments: const [
                  ButtonSegment(value: _Duration.thirtyDays, label: Text('30 days')),
                  ButtonSegment(value: _Duration.ninetyDays, label: Text('90 days')),
                  ButtonSegment(value: _Duration.unlimited, label: Text('Unlimited')),
                ],
                selected: {_duration},
                onSelectionChanged: (s) => setState(() => _duration = s.first),
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
                      : Text('Pay $_creationFeeCent Cent & Create Classroom', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
