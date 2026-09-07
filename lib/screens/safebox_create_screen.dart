import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/safebox_service.dart';
import '../components/primary_button.dart';

/// Screen to initialize a new group Safebox savings pool.
class SafeboxCreateScreen extends StatefulWidget {
  const SafeboxCreateScreen({super.key});

  @override
  State<SafeboxCreateScreen> createState() => _SafeboxCreateScreenState();
}

class _SafeboxCreateScreenState extends State<SafeboxCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final SafeboxService _service = SafeboxService();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      double? target;
      if (_targetController.text.trim().isNotEmpty) {
        target = double.tryParse(_targetController.text.trim());
      }

      await _service.createSafebox(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        targetAmount: target,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Safebox created successfully!')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Safebox'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Group Savings Pool Details',
                style: AppTypography.heading1,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Safebox pools are transparent to all members. Anyone can contribute, but only you (and designated admins) can withdraw.',
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xl),

              // Name Field
              Text(
                'Safebox Name',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: _nameController,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a name for the Safebox';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  hintText: 'e.g. Vacation 2026, House Rent Pool',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Description Field
              Text(
                'Description / Purpose',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please describe the purpose of this pool';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  hintText: 'Describe who this pool is for and how funds will be used.',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Optional Target Amount
              Text(
                'Target Amount (Optional)',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: _targetController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  prefixText: '₦ ',
                  hintText: '0.00',
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              PrimaryButton(
                label: 'Create Safebox',
                fullWidth: true,
                isLoading: _isSubmitting,
                onPressed: _handleCreate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
