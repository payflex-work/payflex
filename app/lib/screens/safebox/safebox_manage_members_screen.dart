import 'package:flutter/material.dart';
import '../../theme/payflex_tokens.dart';
import '../../models/safebox.dart';
import '../../services/api_client.dart';
import '../../widgets/pf_mark.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_states.dart';

class SafeboxManageMembersScreen extends StatefulWidget {
  final String safeboxId;

  const SafeboxManageMembersScreen({super.key, required this.safeboxId});

  @override
  State<SafeboxManageMembersScreen> createState() =>
      _SafeboxManageMembersScreenState();
}

class _SafeboxManageMembersScreenState
    extends State<SafeboxManageMembersScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _addController = TextEditingController();
  bool _isLoading = true;
  List<SafeboxMember> _members = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    try {
      final detail = await _api.getSafeboxDetail(widget.safeboxId);
      if (mounted) {
        setState(() {
          _members = detail.members;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _adminCount =>
      _members.where((m) => m.role == SafeboxRole.admin).length;

  Future<void> _handleAddMember() async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;

    try {
      await _api.addSafeboxMember(widget.safeboxId, text);
      _addController.clear();
      _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('ApiException: ', '')),
            backgroundColor: PayFlexColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleRoleToggle(SafeboxMember m) async {
    if (m.role == SafeboxRole.owner) return;

    final newRoleStr = m.role == SafeboxRole.admin ? 'MEMBER' : 'ADMIN';
    if (newRoleStr == 'ADMIN' && _adminCount >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin limit reached: maximum 3 designated admins allowed.'),
          backgroundColor: PayFlexColors.error,
        ),
      );
      return;
    }

    try {
      await _api.updateSafeboxMemberRole(widget.safeboxId, m.userId, newRoleStr);
      _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('ApiException: ', '')),
            backgroundColor: PayFlexColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFull = _adminCount >= 3;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Members'),
      ),
      body: _isLoading
          ? const Center(child: PfLoader())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(PayFlexSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(PayFlexSpacing.md),
                    decoration: BoxDecoration(
                      color: isFull
                          ? PayFlexColors.warning.withOpacity(0.15)
                          : PayFlexColors.primaryBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(PayFlexRadius.md),
                      border: Border.all(
                        color: isFull
                            ? PayFlexColors.warning
                            : PayFlexColors.primaryBlue.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isFull ? Icons.warning_amber_rounded : Icons.shield_outlined,
                          color: isFull ? PayFlexColors.warning : PayFlexColors.primaryBlue,
                        ),
                        const SizedBox(width: PayFlexSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Admin Seats: $_adminCount / 3 Assigned',
                                style: PayFlexTypography.bodySmall
                                    .copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isFull
                                    ? 'Maximum 3 designated admins limit reached.'
                                    : 'You can assign up to ${3 - _adminCount} more admin(s).',
                                style: PayFlexTypography.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PayFlexSpacing.lg),
                  Text('Add New Member', style: PayFlexTypography.heading2),
                  const SizedBox(height: PayFlexSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addController,
                          decoration: const InputDecoration(
                            hintText: 'Enter member user ID or email',
                          ),
                        ),
                      ),
                      const SizedBox(width: PayFlexSpacing.md),
                      PfPrimaryButton(
                        label: 'Add',
                        onPressed: _handleAddMember,
                      ),
                    ],
                  ),
                  const SizedBox(height: PayFlexSpacing.xl),
                  Text('Safebox Roster (${_members.length})',
                      style: PayFlexTypography.heading2),
                  const SizedBox(height: PayFlexSpacing.sm),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _members.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: PayFlexSpacing.sm),
                    itemBuilder: (context, index) {
                      final m = _members[index];
                      return Container(
                        padding: const EdgeInsets.all(PayFlexSpacing.md),
                        decoration: BoxDecoration(
                          color: PayFlexColors.darkSurface,
                          borderRadius: BorderRadius.circular(PayFlexRadius.md),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  PayFlexColors.primaryBlue.withOpacity(0.2),
                              child: Text(
                                m.name.isNotEmpty ? m.name[0].toUpperCase() : 'U',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: PayFlexSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.name,
                                    style: PayFlexTypography.body
                                        .copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Text('Role: ${m.role.label}',
                                      style: PayFlexTypography.caption),
                                ],
                              ),
                            ),
                            if (!m.role.isOwner)
                              TextButton(
                                onPressed: () => _handleRoleToggle(m),
                                child: Text(m.role == SafeboxRole.admin
                                    ? 'Demote'
                                    : 'Promote to Admin'),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
