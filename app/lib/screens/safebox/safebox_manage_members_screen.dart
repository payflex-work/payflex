import 'package:flutter/material.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../models/safebox.dart';
import '../../services/api_client.dart';
import '../../widgets/pf_balance_card.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_motion.dart';
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

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceAll('ApiException: ', ''))),
    );
  }

  Future<void> _handleAddMember() async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;

    try {
      await _api.addSafeboxMember(widget.safeboxId, text);
      _addController.clear();
      _loadMembers();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _handleRoleToggle(SafeboxMember m) async {
    if (m.role == SafeboxRole.owner) return;

    final newRoleStr = m.role == SafeboxRole.admin ? 'MEMBER' : 'ADMIN';
    if (newRoleStr == 'ADMIN' && _adminCount >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin limit reached: maximum 3 designated admins allowed.')),
      );
      return;
    }

    try {
      await _api.updateSafeboxMemberRole(widget.safeboxId, m.userId, newRoleStr);
      _loadMembers();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFull = _adminCount >= 3;

    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Manage members'),
          backgroundColor: PfColors.offWhite,
        ),
        body: _isLoading
            ? const Center(child: PfBrandedLoader(size: 52))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(PfSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(PfSpace.md),
                      decoration: BoxDecoration(
                        color: isFull ? PfColors.warnWash : PfColors.royalBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(PfRadius.md),
                        border: Border.all(
                          color: isFull ? PfColors.warn : PfColors.royalBlue.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isFull ? Icons.warning_amber_rounded : Icons.shield_outlined,
                            color: isFull ? PfColors.warn : PfColors.royalBlue,
                          ),
                          const SizedBox(width: PfSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Admin seats: $_adminCount / 3 assigned',
                                  style: const TextStyle(color: PfColors.ink, fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isFull
                                      ? 'Maximum 3 designated admins limit reached.'
                                      : 'You can assign up to ${3 - _adminCount} more admin(s).',
                                  style: const TextStyle(color: PfColors.inkFaint, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: PfSpace.lg),
                    Text('Add new member', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: PfSpace.xs),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _addController,
                            decoration: const InputDecoration(hintText: 'Enter member user ID'),
                          ),
                        ),
                        const SizedBox(width: PfSpace.md),
                        PfPrimaryButton(
                          label: 'Add',
                          expanded: false,
                          onPressed: _handleAddMember,
                        ),
                      ],
                    ),
                    const SizedBox(height: PfSpace.xl),
                    Text('Safebox roster (${_members.length})', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: PfSpace.sm),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _members.length,
                      separatorBuilder: (_, __) => const SizedBox(height: PfSpace.sm),
                      itemBuilder: (context, index) {
                        final m = _members[index];
                        return PfPanel(
                          padding: const EdgeInsets.all(PfSpace.md),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: PfColors.royalBlue.withValues(alpha: 0.14),
                                child: Text(
                                  m.name.isNotEmpty ? m.name[0].toUpperCase() : 'U',
                                  style: const TextStyle(color: PfColors.royalBlue, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: PfSpace.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.name,
                                      style: const TextStyle(color: PfColors.ink, fontSize: 14, fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      'Role: ${m.role.label}',
                                      style: const TextStyle(color: PfColors.inkFaint, fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ),
                              if (!m.role.isOwner)
                                TextButton(
                                  onPressed: () => _handleRoleToggle(m),
                                  child: Text(m.role == SafeboxRole.admin ? 'Demote' : 'Promote to admin'),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
