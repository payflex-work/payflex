import 'package:flutter/material.dart';
import '../../stellar/stellar_client.dart';
import '../../stellar/stellar_models.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_states.dart';
import '../../widgets/pin_prompt.dart';

/// Stellar payments are irreversible the instant they confirm on-chain —
/// there is no counter-signer to contest them. This screen never lets a
/// send submit without an explicit, separate "this cannot be undone"
/// confirmation naming the exact recipient address, and it checks the
/// recipient's trustline BEFORE submitting for any non-native asset —
/// Stellar rejects that payment on-chain otherwise, and this app should
/// say so clearly up front, not after a failed network round trip.
class StellarSendScreen extends StatefulWidget {
  final StellarClient client;
  final StellarAccountSummary summary;
  const StellarSendScreen({super.key, required this.client, required this.summary});

  @override
  State<StellarSendScreen> createState() => _StellarSendScreenState();
}

class _StellarSendScreenState extends State<StellarSendScreen> {
  final _destinationController = TextEditingController();
  final _amountController = TextEditingController();
  late StellarBalance _selectedAsset;
  bool _sending = false;
  String? _error;
  StellarPaymentResult? _result;

  @override
  void initState() {
    super.initState();
    _selectedAsset = widget.summary.balances.first;
    // Real-time validation: inline errors while the user types.
    _destinationController.addListener(() => mounted ? setState(() {}) : null);
    _amountController.addListener(() => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// Inline recipient error — a malformed address must never reach the
  /// (irreversible) payment flow, so this is checked on every keystroke.
  String? get _destinationError {
    final destination = _destinationController.text.trim();
    if (destination.isEmpty) return null;
    return publicKeyError(destination);
  }

  String? get _amountErrorText {
    final amount = _amountController.text.trim();
    if (amount.isEmpty) return null;
    return amountError(amount);
  }

  Future<void> _submit() async {
    final destination = _destinationController.text.trim();
    final amount = _amountController.text.trim();
    // Full pre-submit gate: the inline errors and this check share one
    // source of truth, so what blocks submit is exactly what's on screen.
    final destErr = _destinationError ??
        (destination.isEmpty ? 'Enter the recipient\u2019s Stellar address.' : null);
    final amtErr = _amountErrorText ?? (amount.isEmpty ? 'Enter an amount.' : null);
    if (destErr != null || amtErr != null) {
      setState(() => _error = destErr ?? amtErr);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      if (!_selectedAsset.isNative) {
        final hasTrustline = await widget.client.recipientHasTrustline(
          destination,
          _selectedAsset.assetCode!,
          _selectedAsset.assetIssuer!,
        );
        if (!hasTrustline) {
          setState(() {
            _error = "This recipient hasn't set up a trustline for ${_selectedAsset.displayCode} "
                'yet — they need to add it before you can send this asset to them.';
            _sending = false;
          });
          return;
        }
      }

      if (!mounted) return;
      final confirmed = await _confirmIrreversible(destination, amount);
      if (!mounted) return;
      if (confirmed != true) {
        setState(() => _sending = false);
        return;
      }

      final pin = await promptForPin(context);
      if (pin == null || pin.isEmpty) {
        setState(() => _sending = false);
        return;
      }
      final result = await widget.client.sendPaymentWithPin(
        destinationPublicKey: destination,
        assetCode: _selectedAsset.displayCode,
        issuer: _selectedAsset.assetIssuer,
        amount: amount,
        pin: pin,
      );
      setState(() => _result = result);
      if (!result.success) {
        setState(() => _error = result.errorMessage);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<bool?> _confirmIrreversible(String destination, String amount) {
    return showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: PayFlexTheme.light,
        child: AlertDialog(
          backgroundColor: PfColors.offWhite,
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: PfColors.warn),
              SizedBox(width: 8),
              Text('This cannot be undone'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Once this confirms on the Stellar network, it cannot be reversed, '
                'cancelled, or refunded by anyone — including PayFlex. Double-check '
                'the address below before continuing.',
                style: TextStyle(color: PfColors.inkMuted, fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(PfSpace.md),
                decoration: BoxDecoration(
                  color: PfColors.warnWash,
                  borderRadius: BorderRadius.circular(PfRadius.md),
                  border: Border.all(color: PfColors.warn.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$amount ${_selectedAsset.displayCode}',
                      style: const TextStyle(color: PfColors.ink, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text('to', style: TextStyle(color: PfColors.inkFaint, fontSize: 11.5)),
                    SelectableText(
                      destination,
                      style: const TextStyle(color: PfColors.ink, fontSize: 12.5, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: PfColors.warn),
              child: const Text('Send anyway'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(title: const Text('Send on Stellar'), backgroundColor: PfColors.offWhite),
        body: SafeArea(
          child: _result?.success == true ? _successView() : _formView(),
        ),
      ),
    );
  }

  Widget _successView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PfSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: PfColors.success, size: 56),
            const SizedBox(height: 14),
            const Text('Payment sent', style: TextStyle(color: PfColors.ink, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SelectableText(
              _result!.transactionHash ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: PfColors.inkFaint, fontSize: 12, fontFamily: 'monospace'),
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
        if (_error != null) ...[
          PfInlineError(message: _error!),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: _destinationController,
          decoration: InputDecoration(
            labelText: 'Recipient Stellar address',
            hintText: 'G...',
            errorText: _destinationError,
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<StellarBalance>(
          initialValue: _selectedAsset,
          decoration: const InputDecoration(labelText: 'Asset'),
          items: widget.summary.balances
              .map((b) => DropdownMenuItem(value: b, child: Text('${b.displayCode} (${b.balance} available)')))
              .toList(),
          onChanged: (v) => setState(() => _selectedAsset = v!),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _amountController,
          decoration: InputDecoration(
            labelText: 'Amount',
            errorText: _amountErrorText,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
          inputFormatters: amountInputFormatters(),
        ),
        const SizedBox(height: 24),
        PfPrimaryButton(label: 'Review and send', busy: _sending, onPressed: _sending ? null : _submit),
      ],
    );
  }
}
