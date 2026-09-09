import 'package:flutter/material.dart';
import '../../stellar/stellar_client.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_states.dart';

/// Establishes a trustline — the mechanism that lets a Stellar account
/// hold and receive a specific issued asset (e.g. a stablecoin like
/// USDC). Plain-language about what that actually means: a small amount
/// of the account's own XLM gets reserved on-chain for as long as the
/// trustline exists, released only if it's later removed.
class StellarAddAssetScreen extends StatefulWidget {
  final StellarClient client;
  const StellarAddAssetScreen({super.key, required this.client});

  @override
  State<StellarAddAssetScreen> createState() => _StellarAddAssetScreenState();
}

class _StellarAddAssetScreenState extends State<StellarAddAssetScreen> {
  final _codeController = TextEditingController();
  final _issuerController = TextEditingController();
  bool _submitting = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _codeController.dispose();
    _issuerController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim().toUpperCase();
    final issuer = _issuerController.text.trim();
    if (code.isEmpty || issuer.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.client.addTrustline(assetCode: code, issuer: issuer);
      if (result.success) {
        setState(() => _done = true);
      } else {
        setState(() => _error = result.errorMessage);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(title: const Text('Add an asset'), backgroundColor: PfColors.offWhite),
        body: SafeArea(
          child: _done ? _doneView() : _formView(),
        ),
      ),
    );
  }

  Widget _doneView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PfSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: PfColors.success, size: 56),
            const SizedBox(height: 14),
            const Text('Trustline added', style: TextStyle(color: PfColors.ink, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'You can now hold and receive this asset.',
              style: TextStyle(color: PfColors.inkMuted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            PfPrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }

  Widget _formView() {
    return ListView(
      padding: const EdgeInsets.all(PfSpace.xl),
      children: [
        Container(
          padding: const EdgeInsets.all(PfSpace.md),
          decoration: BoxDecoration(
            color: PfColors.royalBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(PfRadius.md),
            border: Border.all(color: PfColors.royalBlue.withValues(alpha: 0.3)),
          ),
          child: const Text(
            'A trustline lets your Stellar account hold a specific asset issued by '
            'someone else (e.g. a stablecoin). It reserves a small amount of your '
            'own XLM on-chain for as long as it stays open — you get that XLM back '
            'if you remove the trustline later.',
            style: TextStyle(color: PfColors.ink, fontSize: 12.5, height: 1.45),
          ),
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          PfInlineError(message: _error!),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Asset code', hintText: 'e.g. USDC'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _issuerController,
          decoration: const InputDecoration(labelText: 'Issuer address', hintText: 'G...'),
        ),
        const SizedBox(height: 24),
        PfPrimaryButton(label: 'Add trustline', busy: _submitting, onPressed: _submitting ? null : _submit),
      ],
    );
  }
}
