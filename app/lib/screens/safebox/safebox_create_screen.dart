import 'package:flutter/material.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
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
            backgroundColor: PfColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Create New Safebox'),
          backgroundColor: PfColors.offWhite,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(PfSpace.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Group Savings Pool Details',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: PfSpace.xs),
                const Text(
                  'Safebox pools are transparent to all members. Anyone can '
                  'contribute, but only you (and designated admins) can withdraw.',
                  style: TextStyle(color: PfColors.inkMuted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: PfSpace.xl),
                const Text(
                  'Safebox Name',
                  style: TextStyle(color: PfColors.ink, fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: PfSpace.xs),
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
                const SizedBox(height: PfSpace.lg),
                const Text(
                  'Description / Purpose',
                  style: TextStyle(color: PfColors.ink, fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: PfSpace.xs),
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
                const SizedBox(height: PfSpace.lg),
                const Text(
                  'Target Amount (Optional)',
                  style: TextStyle(color: PfColors.ink, fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: PfSpace.xs),
                TextFormField(
                  controller: _targetController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    prefixText: '₦ ',
                    hintText: '0.00',
                  ),
                ),
                const SizedBox(height: PfSpace.xxl),
                PfPrimaryButton(
                  label: 'Create Safebox',
                  busy: _isSubmitting,
                  onPressed: _handleCreate,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
