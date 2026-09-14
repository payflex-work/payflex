import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../services/api_client.dart';
import '../../services/safebox_service.dart';
import '../../services/wallet_service.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_flow.dart';
import '../../widgets/pf_states.dart';
import '../../widgets/pin_prompt.dart';

/// Creates a Safebox BY DEPLOYING ITS SOROBAN CONTRACT from this device:
/// install wasm → deploy with (owner, native-SAC token) → register the
/// verified contract id with the backend. Nothing here trusts the backend
/// or any server to hold or move the pool's funds — the chain does.
class SafeboxCreateScreen extends StatefulWidget {
  final AppUser user;
  const SafeboxCreateScreen({super.key, required this.user});

  @override
  State<SafeboxCreateScreen> createState() => _SafeboxCreateScreenState();
}

class _SafeboxCreateScreenState extends State<SafeboxCreateScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _api = ApiClient();
  bool _busy = false;
  String? _error;
  String? _statusLine;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the Safebox a name.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _statusLine = 'Confirming with your PIN…';
    });
    try {
      if (!await WalletService.hasWallet()) {
        throw StateError('No Stellar key on this device — finish onboarding first.');
      }
      if (!mounted) return;

      final pin = await promptForPin(context);
      if (!mounted) return;
      if (pin == null || pin.isEmpty) {
        setState(() => _busy = false);
        return;
      }

      setState(() => _statusLine = 'Deploying the Safebox contract on-chain…');
      final client = await _api.stellarClient();
      final safebox = SafeboxService(
        stellar: client,
        rpcUrl: client.sorobanRpcUrl,
      );

      // Deploy + init(owner = this device's key, token = native XLM SAC).
      // The wasm must already be installed on this network; its hash is
      // deployment tooling's output (see backend/contracts/safebox README).
      const wasmHash = String.fromEnvironment('SAFEBOX_WASM_HASH');
      if (wasmHash.isEmpty) {
        throw StateError(
          'No Safebox wasm hash configured. Build backend/contracts/safebox, '
          'install it on this network, and run with '
          '--dart-define=SAFEBOX_WASM_HASH=<hash>.',
        );
      }
      final contractId = await safebox.createSafebox(
        ownerPublicKey: widget.user.stellarPublicKey ?? '',
        wasmHash: wasmHash,
        pin: pin,
      );

      setState(() => _statusLine = 'Registering the verified contract…');
      await _api.registerSafebox(
        widget.user.id,
        contractId: contractId,
        name: name,
        description: _descController.text.trim(),
      );

      if (!mounted) return;
      await showPfConfirmation(
        context,
        outcome: PfFlowOutcome(
          headline: 'Safebox deployed',
          amount: '0.00',
          currency: 'XLM',
          caption: name,
          reference: contractId,
          statusLabel: 'On-chain',
          statusTone: PfTone.success,
          methodLabel: 'Soroban contract',
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deploy a group savings contract',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: PfSpace.xs),
              const Text(
                'The pool lives in a Soroban contract YOU deploy from this '
                'device — owner/admin-only withdrawal and the 3-admin cap '
                'are enforced by the chain, not by PayFlex. Every '
                'contribution and withdrawal is visible to all members in '
                'the contract\u2019s own ledger.',
                style: TextStyle(color: PfColors.inkMuted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: PfSpace.xl),
              const Text(
                'Safebox Name',
                style: TextStyle(color: PfColors.ink, fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: PfSpace.xs),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'e.g. Amina & friends Q4 pool',
                  filled: true,
                ),
              ),
              const SizedBox(height: PfSpace.lg),
              const Text(
                'Description (optional)',
                style: TextStyle(color: PfColors.ink, fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: PfSpace.xs),
              TextField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'What is this pool for?',
                  filled: true,
                ),
              ),
              const SizedBox(height: PfSpace.xl),
              if (_error != null) ...[
                PfInlineError(message: _error!),
                const SizedBox(height: PfSpace.md),
              ],
              if (_statusLine != null && _busy)
                Padding(
                  padding: const EdgeInsets.only(bottom: PfSpace.md),
                  child: Text(
                    _statusLine!,
                    style: const TextStyle(color: PfColors.inkMuted, fontSize: 12.5),
                  ),
                ),
              PfPrimaryButton(
                label: 'Deploy contract',
                icon: Icons.account_balance_outlined,
                busy: _busy,
                onPressed: _busy ? null : _handleCreate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
