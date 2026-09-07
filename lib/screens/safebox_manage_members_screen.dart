import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/safebox_model.dart';
import '../services/safebox_service.dart';
import '../components/branded_loader.dart';
import '../components/primary_button.dart';

/// Screen for Safebox owner to manage members, promote/demote admins (capped at 3),
/// add new members, or initiate deliberate ownership transfer.
class SafeboxManageMembersScreen extends StatefulWidget {
  final String safeboxId;

  const SafeboxManageMembersScreen({super.key, required this.safeboxId});

  @override
  State<SafeboxManageMembersScreen> createState() =>
      _SafeboxManageMembersScreenState();
}

class _SafeboxManageMembersScreenState
    extends State<SafeboxManageMembersScreen> {
  final SafeboxService _service = SafeboxService();
  final TextEditingController _addMemberController = TextEditingController();

  bool _isLoading = true;
  List<SafeboxMemberModel> _members = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _addMemberController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    final list = await _service.getMembers(widget.safeboxId);
    if (mounted) {
      setState(() {
        _members = list;
        _isLoading = false;
      });
    }
  }

  int get _currentAdminCount =>
      _members.where((m) => m.role == SafeboxRole.admin).length;

  Future<void> _handleAddMember() async {
    final name = _addMemberController.text.trim();
    if (name.isEmpty) return;

    try {
      await _service.addMember(widget.safeboxId, name);
      _addMemberController.clear();
      _loadMembers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $name to Safebox!')),
        );
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
    }
  }

  Future<void> _handleRoleToggle(SafeboxMemberModel member) async {
    if (member.role == SafeboxRole.owner) return;

    final newRole = member.role == SafeboxRole.admin
        ? SafeboxRole.member
        : SafeboxRole.admin;

    // Enforce 3-admin cap
    if (newRole == SafeboxRole.admin && _currentAdminCount >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Admin Limit Reached: A Safebox can have at most 3 designated admins in addition to the owner.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      await _service.updateMemberRole(
        safeboxId: widget.safeboxId,
        memberUserId: member.userId,
        newRole: newRole,
      );
      _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showOwnershipTransferDialog(SafeboxMemberModel member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Ownership'),
        content: Text(
          'Are you sure you want to initiate ownership transfer to ${member.name}? '
          'This is a deliberate 2-step action. Both you and ${member.name} must confirm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Ownership transfer request sent to ${member.name}. Awaiting target confirmation.',
                  ),
                ),
              );
            },
            child: const Text('Initiate Transfer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Safebox Members'),
      ),
      body: _isLoading
          ? const Center(child: BrandedLoader(size: 48))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Admin Cap status banner
                  _buildAdminCapBanner(isDark),
                  const SizedBox(height: AppSpacing.lg),

                  // Add member section
                  Text(
                    'Add New Member',
                    style: AppTypography.heading2,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addMemberController,
                          decoration: const InputDecoration(
                            hintText: 'Enter member name or email',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      PrimaryButton(
                        label: 'Add',
                        onPressed: _handleAddMember,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Member List
                  Text(
                    'Safebox Roster (${_members.length})',
                    style: AppTypography.heading2,
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _members.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final member = _members[index];
                      return _buildMemberTile(member, isDark);
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAdminCapBanner(bool isDark) {
    final isFull = _currentAdminCount >= 3;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isFull
            ? AppColors.warning.withOpacity(0.15)
            : AppColors.primaryBlue.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isFull ? AppColors.warning : AppColors.primaryBlue.withOpacity(0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFull ? Icons.warning_amber_rounded : Icons.shield_outlined,
            color: isFull ? AppColors.warning : AppColors.primaryBlue,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin Seats: $_currentAdminCount / 3 Assigned',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isFull
                      ? 'Maximum 3 designated admins limit reached. Demote an admin to promote another.'
                      : 'You can assign up to ${3 - _currentAdminCount} more admin(s) with withdrawal authorization.',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTile(SafeboxMemberModel member, bool isDark) {
    final isOwner = member.role == SafeboxRole.owner;
    final isAdmin = member.role == SafeboxRole.admin;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.darkSurfaceAlt : const Color(0xFFE5E5E0),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primaryBlue.withOpacity(0.2),
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : 'U',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Role: ${member.role.label}',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          if (!isOwner) ...[
            TextButton(
              onPressed: () => _handleRoleToggle(member),
              child: Text(isAdmin ? 'Demote' : 'Promote to Admin'),
            ),
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'transfer') {
                  _showOwnershipTransferDialog(member);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'transfer',
                  child: Text('Transfer Ownership'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
