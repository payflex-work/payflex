import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../services/api_client.dart';
import '../../services/safebox_service.dart';
import '../../services/wallet_service.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_motion.dart';
import '../../widgets/pf_states.dart';
import '../../widgets/pin_prompt.dart';

/// On-chain admin management for a Safebox. The owner adds/removes admins
/// by invoking the contract's `add_admin`/`remove_admin` from this device
/// — the 3-admin cap is enforced BY THE CONTRACT, so an attempt to add a
/// fourth fails on-ledger, not in this UI.
class SafeboxManageMembersScreen extends StatefulWidget {
  final AppUser user;
  final String safeboxId; // Soroban contract id

  const SafeboxManageMembersScreen({
    super.key,
    required this.user,
    required this.safeboxId,
  });

  @override
  State<SafeboxManageMembersScreen> createState() =>
      _SafeboxManageMembersScreenState();
}

class _SafeboxManageMembersScreenState
    extends State<SafeboxManageMembersScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _addController = TextEditingController();
  bool _isLoading = true;
  String? _owner;
  List<String> _admins = [];

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
    setState(() {
      _isLoading = true;
    });
    try {
      final detail = await _api.getSafeboxDetail(widget.user.id, widget.safeboxId);
      final chain = (detail['chain'] as Map<String, dynamic>?) ?? const {};
      if (mounted) {
        setState(() {
          _owner = chain['owner'] as String?;
          _admins = (chain['admins'] as List<dynamic>?)?.cast<String>() ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  SafeboxService _service(dynamic client) =>
      SafeboxService(stellar: client, rpcUrl: (client as dynamic).sorobanRpcUrl);

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }

  Future<String?> _pin() => promptForPin(context);

  Future<void> _handleAddAdmin() async {
    final admin = _addController.text.trim();
    if (admin.isEmpty) return;
    // Full SDK-backed strkey check (shape + base32 checksum) — a malformed
    // key can never be an admin, and the error says what's wrong.
    final err = publicKeyError(admin);
    if (err != null) {
      _showError(StateError(err));
      return;
    }
    final pin = await _pin();
    if (pin == null || pin.isEmpty) return;
    try {
      final client = await _api.stellarClient();
      await _service(client).addAdmin(
        contractId: widget.safeboxId,
        adminPublicKey: admin,
        pin: pin,
      );
      _addController.clear();
      _loadMembers();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _handleRemoveAdmin(String admin) async {
    final pin = await _pin();
    if (pin == null || pin.isEmpty) return;
    try {
      final client = await _api.stellarClient();
      await _service(client).removeAdmin(
        contractId: widget.safeboxId,
        adminPublicKey: admin,
        pin: pin,
      );
      _loadMembers();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _handleSelfProvision() async {
    // Convenience for the common case: add THIS device's key as admin.
    final me = await WalletService.currentAddress();
    if (me == null) {
      _showError(StateError('No Stellar key on this device.'));
      return;
    }
    _addController.text = me;
  }

  @override
  Widget build(BuildContext context) {
    final isFull = _admins.length >= 3;

    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Contract admins'),
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
                      ),
                      child: Text(
                        isFull
                            ? 'Admin cap reached: the contract allows a maximum of 3 admins.'
                            : '${_admins.length} of 3 admins designated. The cap is enforced on-chain.',
                        style: const TextStyle(color: PfColors.ink, fontSize: 12.5, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: PfSpace.lg),
                    const PfSectionHeader(title: 'Owner'),
                    const SizedBox(height: PfSpace.sm),
                    _memberRow(_owner ?? '—', isOwner: true),
                    const SizedBox(height: PfSpace.lg),
                    const PfSectionHeader(title: 'Designated admins'),
                    const SizedBox(height: PfSpace.sm),
                    if (_admins.isEmpty)
                      const Text(
                        'None yet. Only the owner and admins can withdraw — add at least one for accountability.',
                        style: TextStyle(color: PfColors.inkMuted, fontSize: 12.5, height: 1.4),
                      )
                    else
                      ..._admins.map(_memberRow),
                    const SizedBox(height: PfSpace.xl),
                    const PfSectionHeader(title: 'Add an admin'),
                    const SizedBox(height: PfSpace.sm),
                    TextField(
                      controller: _addController,
                      decoration: InputDecoration(
                        hintText: 'Stellar public key (G…)',
                        filled: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.person_outline_rounded),
                          tooltip: 'Use this device\u2019s key',
                          onPressed: _handleSelfProvision,
                        ),
                      ),
                    ),
                    const SizedBox(height: PfSpace.md),
                    PfPrimaryButton(
                      label: 'Add admin (on-chain)',
                      icon: Icons.admin_panel_settings_outlined,
                      onPressed: isFull ? null : _handleAddAdmin,
                    ),
                    const SizedBox(height: PfSpace.xl),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _memberRow(String publicKey, {bool isOwner = false}) {
    return FutureBuilder<String?>(
      future: WalletService.currentAddress(),
      builder: (context, snapshot) {
        final isMe = snapshot.data == publicKey;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: PfColors.surface,
            borderRadius: BorderRadius.circular(PfRadius.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMe ? 'This device' : (isOwner ? 'Contract owner' : 'Admin'),
                      style: const TextStyle(
                          color: PfColors.ink, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      publicKey,
                      style: const TextStyle(color: PfColors.inkMuted, fontSize: 10.5, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              if (isOwner)
                const PfStatusChip(label: 'Owner', tone: PfTone.info)
              else
                TextButton(
                  onPressed: () => _handleRemoveAdmin(publicKey),
                  child: const Text('Remove'),
                ),
            ],
          ),
        );
      },
    );
  }
}
