// lib/create_classroom.dart
//
// Approved tutors only — the create_classroom RPC also enforces this
// server-side. Paying the classroom creation fee (read server-side from
// app_config, not hardcoded) and creating the classroom happen
// atomically in that RPC; if the fee can't be charged, nothing is
// created. A preview step shows the tutor exactly what students will
// see before anything is charged or published.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_enhancements.dart' show GradientHeader, GradientButton;
import 'buy_cent.dart';
import 'classroom_shared.dart' show kExamCategories, loadSubjects, formatCpCent;

enum _Duration { thirtyDays, ninetyDays, unlimited }

class CreateClassroomScreen extends StatefulWidget {
  const CreateClassroomScreen({super.key});

  @override
  State<CreateClassroomScreen> createState() => _CreateClassroomScreenState();
}

class _CreateClassroomScreenState extends State<CreateClassroomScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _rulesController = TextEditingController();
  final _introController = TextEditingController();
  final _priceController = TextEditingController();
  final _capacityController = TextEditingController(text: '50');
  final _picker = ImagePicker();

  String? _subject;
  List<String> _availableSubjects = [];
  String _examCategory = kExamCategories.last; // 'General/Other'
  bool _isPaid = true;
  _Duration _duration = _Duration.thirtyDays;
  XFile? _coverImage;
  bool _submitting = false;
  String? _error;

  int? _creationFeeCent;
  double? _platformFeePercent;
  bool _loadingConfig = true;

  @override
  void initState() {
    super.initState();
    loadSubjects().then((subjects) {
      if (mounted) setState(() => _availableSubjects = subjects);
    });
    _loadFeeConfig();
  }

  Future<void> _loadFeeConfig() async {
    try {
      final config = await Supabase.instance.client
          .from('app_config')
          .select('classroom_creation_fee_cent, platform_fee_percent')
          .eq('app_id', 'naijalearn')
          .single();
      if (mounted) {
        setState(() {
          _creationFeeCent = config['classroom_creation_fee_cent'] as int;
          _platformFeePercent = (config['platform_fee_percent'] as num).toDouble();
        });
      }
    } catch (_) {
      // Falls back to null — UI shows a generic message instead of a
      // possibly-wrong number; the RPC is still the source of truth.
    } finally {
      if (mounted) setState(() => _loadingConfig = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _rulesController.dispose();
    _introController.dispose();
    _priceController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 75);
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

  String get _durationLabel {
    switch (_duration) {
      case _Duration.thirtyDays:
        return '30 days';
      case _Duration.ninetyDays:
        return '90 days';
      case _Duration.unlimited:
        return 'Unlimited';
    }
  }

  Future<void> _openPreview() async {
    if (!_formKey.currentState!.validate()) return;
    if (_subject == null) {
      setState(() => _error = 'Select a subject');
      return;
    }
    setState(() => _error = null);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => _ClassroomPreview(
          scrollController: scrollController,
          name: _nameController.text.trim(),
          subject: _subject!,
          examCategory: _examCategory,
          description: _descriptionController.text.trim(),
          introInfo: _introController.text.trim(),
          rules: _rulesController.text.trim(),
          coverImage: _coverImage,
          isPaid: _isPaid,
          priceCent: _isPaid ? (int.tryParse(_priceController.text) ?? 0) : 0,
          capacity: int.tryParse(_capacityController.text) ?? 0,
          durationLabel: _durationLabel,
          creationFeeCent: _creationFeeCent ?? 2000,
        ),
      ),
    );

    if (confirmed == true) _submit();
  }

  Future<void> _submit() async {
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
        'p_exam_category': _examCategory,
        'p_description': _descriptionController.text.trim(),
        'p_cover_image_url': coverUrl,
        'p_rules': _rulesController.text.trim(),
        'p_intro_info': _introController.text.trim(),
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
    final fee = _creationFeeCent ?? 2000;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Not enough balance'),
        content: Text('Creating a classroom costs ${formatCpCent(fee)}. Top up your wallet first.'),
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
    final feeLabel = _loadingConfig ? '...' : formatCpCent(_creationFeeCent ?? 2000);
    final feePercent = _platformFeePercent ?? 10.0;

    return Scaffold(
      body: Column(
        children: [
          const GradientHeader(title: 'Create Classroom'),
          Expanded(
            child: SingleChildScrollView(
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
                              'Creating a classroom costs $feeLabel, charged after you preview and publish.',
                              style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    _SectionLabel('Classroom Information'),
                    const SizedBox(height: 12),

                    GestureDetector(
                      onTap: _pickCover,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
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
                                      const SizedBox(height: 2),
                                      Text('Recommended: 16:9', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                                    ],
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Classroom name', hintText: 'e.g. JAMB Biology Masterclass 2027', border: OutlineInputBorder()),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a classroom name' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Description', hintText: 'What will students learn?', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      initialValue: _subject,
                      decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
                      items: _availableSubjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) => setState(() => _subject = v),
                    ),
                    const SizedBox(height: 16),

                    Text('Exam / category', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: kExamCategories.map((c) {
                        return ChoiceChip(
                          label: Text(c),
                          selected: _examCategory == c,
                          onSelected: (_) => setState(() => _examCategory = c),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 28),
                    _SectionLabel('Learning Experience'),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _introController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Introductory information (optional)',
                        hintText: 'What should new students know before joining?',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _rulesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Classroom rules (optional)',
                        hintText: 'e.g. Be respectful, submit assignments on time...',
                        border: OutlineInputBorder(),
                      ),
                    ),
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

                    const SizedBox(height: 28),
                    _SectionLabel('Pricing'),
                    const SizedBox(height: 12),

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
                        decoration: const InputDecoration(labelText: 'Price per student (in Cent)', border: OutlineInputBorder()),
                        validator: (v) {
                          if (!_isPaid) return null;
                          final n = int.tryParse(v ?? '');
                          if (n == null || n <= 0) return 'Enter a price greater than 0';
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                      if (_priceController.text.isNotEmpty && int.tryParse(_priceController.text) != null) ...[
                        const SizedBox(height: 8),
                        Builder(builder: (context) {
                          final price = int.parse(_priceController.text);
                          final fee = (price * feePercent / 100).round();
                          return Text(
                            'Students pay ${formatCpCent(price)} · you receive ${formatCpCent(price - fee)} · NaijaLearn takes ${formatCpCent(fee)} (${feePercent.toStringAsFixed(0)}%)',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          );
                        }),
                      ],
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                        child: Text(_error!, style: TextStyle(color: scheme.error)),
                      ),
                    ],

                    const SizedBox(height: 24),
                    GradientButton(
                      label: 'Preview Classroom',
                      icon: Icons.visibility_outlined,
                      onPressed: _submitting ? null : _openPreview,
                      height: 54,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
  }
}

class _ClassroomPreview extends StatefulWidget {
  final ScrollController scrollController;
  final String name, subject, examCategory, description, introInfo, rules, durationLabel;
  final XFile? coverImage;
  final bool isPaid;
  final int priceCent, capacity, creationFeeCent;

  const _ClassroomPreview({
    required this.scrollController,
    required this.name,
    required this.subject,
    required this.examCategory,
    required this.description,
    required this.introInfo,
    required this.rules,
    required this.coverImage,
    required this.isPaid,
    required this.priceCent,
    required this.capacity,
    required this.durationLabel,
    required this.creationFeeCent,
  });

  @override
  State<_ClassroomPreview> createState() => _ClassroomPreviewState();
}

class _ClassroomPreviewState extends State<_ClassroomPreview> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(child: Text('This is how students will see your classroom', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context, false)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: widget.coverImage != null
                      ? Image.file(File(widget.coverImage!.path), fit: BoxFit.cover)
                      : Container(color: scheme.primaryContainer, child: Icon(Icons.school_rounded, color: scheme.onPrimaryContainer, size: 40)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text(widget.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
                  if (widget.examCategory != 'General/Other') Chip(label: Text(widget.examCategory), visualDensity: VisualDensity.compact),
                ],
              ),
              const SizedBox(height: 4),
              Text(widget.subject, style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              Text('0/${widget.capacity} students • ${widget.durationLabel}', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              Text(
                widget.isPaid ? formatCpCent(widget.priceCent) : 'Free',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: widget.isPaid ? scheme.primary : Colors.green),
              ),
              if (widget.description.isNotEmpty) ...[
                const Divider(height: 32),
                Text('About This Classroom', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(widget.description),
              ],
              if (widget.introInfo.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(widget.introInfo),
              ],
              if (widget.rules.isNotEmpty) ...[
                const Divider(height: 32),
                Text('Classroom Rules', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(widget.rules),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _submitting
                    ? null
                    : () {
                        setState(() => _submitting = true);
                        Navigator.pop(context, true);
                      },
                child: Text('Publish — Pay ${formatCpCent(widget.creationFeeCent)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
