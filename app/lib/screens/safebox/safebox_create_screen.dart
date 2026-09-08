import 'package:flutter/material.dart';
import '../../theme/payflex_tokens.dart';
import '../../services/api_client.dart';
import '../../widgets/pf_buttons.dart';

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
  final ApiClient _api = ApiClient();

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

      await _api.createSafebox(
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
            content: Text(e.toString().replaceAll('ApiException: ', '')),
            backgroundColor: PayFlexColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Safebox'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(PayFlexSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Group Savings Pool Details',
                style: PayFlexTypography.heading1,
              ),
              const SizedBox(height: PayFlexSpacing.xs),
              Text(
                'Safebox pools are transparent to all members. Anyone can contribute, but only you (and designated admins) can withdraw.',
                style: PayFlexTypography.bodySmall,
              ),
              const SizedBox(height: PayFlexSpacing.xl),
              Text(
                'Safebox Name',
                style: PayFlexTypography.body.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: PayFlexSpacing.xs),
              TextFormField(
                controller: _nameController,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a name for the Safebox';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  hintText: 'e.g. Kenya Trip 2026, House Rent Pool',
                ),
              ),
              const SizedBox(height: PayFlexSpacing.lg),
              Text(
                'Description / Purpose',
                style: PayFlexTypography.body.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: PayFlexSpacing.xs),
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
              const SizedBox(height: PayFlexSpacing.lg),
              Text(
                'Target Amount (Optional)',
                style: PayFlexTypography.body.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: PayFlexSpacing.xs),
              TextFormField(
                controller: _targetController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  prefixText: '₦ ',
                  hintText: '0.00',
                ),
              ),
              const SizedBox(height: PayFlexSpacing.xxl),
              PfPrimaryButton(
                label: 'Create Safebox',
                busy: _isSubmitting,
                onPressed: _handleCreate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
