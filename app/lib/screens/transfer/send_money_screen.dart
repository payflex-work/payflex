import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../services/api_client.dart';
import '../../services/transfer_flow.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../utils/money.dart';
import '../../utils/validators.dart';
import '../../widgets/pf_balance_card.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_flow.dart';
import '../../widgets/pf_states.dart';

enum _RecipientMode { payTag, address }

/// Direct payment entry point: PayTag or raw Stellar address. The
/// recipient is resolved against the PayFlex directory first (so the user
/// sees WHO they're paying), then the payment is built, signed on-device,
/// submitted to Horizon, and recorded — see transfer_flow.dart.
///
/// Real-time client-side validation (hardening brief §2): recipient and
/// amount are validated on every keystroke with inline error text, so a
/// malformed address never reaches the (irreversible) payment flow.
class SendMoneyScreen extends StatefulWidget {
  final AppUser user;
  const SendMoneyScreen({super.key, required this.user});

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  final _api = ApiClient();
  _RecipientMode _mode = _RecipientMode.payTag;
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  String _assetCode = 'XLM';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Re-validate on every keystroke so inline errors appear as the user
    // types, not only after a failed submit.
    _recipientController.addListener(_revalidate);
    _amountController.addListener(_revalidate);
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _revalidate() {
    if (mounted) setState(() {});
  }

  /// Inline recipient error, shown under the field as the user types.
  String? get _recipientError {
    final recipient = _recipientController.text.trim();
    if (recipient.isEmpty) return null; // empty shows nothing until submit
    if (_mode == _RecipientMode.payTag) {
      final tag = recipient.startsWith('@') ? recipient.substring(1) : recipient;
      return isValidPayTag(tag) ? null : '3-20 lowercase letters, digits or underscore.';
    }
    return publicKeyError(recipient);
  }

  /// Inline amount error, shown under the field as the user types.
  String? get _amountError {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null;
    return amountError(text);
  }

  /// Full pre-submit check — mirrors exactly what the inline errors show.
  String? _validateForm() {
    final recipientError = _recipientError ?? (_recipientController.text.trim().isEmpty
        ? (_mode == _RecipientMode.address
            ? 'Enter the recipient\u2019s Stellar address.'
            : 'Enter the recipient\u2019s PayTag.')
        : null);
    if (recipientError != null) return recipientError;
    final amountErr = _amountError ?? (_amountController.text.trim().isEmpty ? 'Enter an amount.' : null);
    return amountErr;
  }

  Future<void> _send() async {
    final validationError = _validateForm();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    final recipient = _recipientController.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 1. Resolve the destination (directory lookup — no chain call).
      final target = await _api.resolveTransfer(
        widget.user.id,
        toPayTag: _mode == _RecipientMode.payTag
            ? (recipient.startsWith('@') ? recipient.substring(1) : recipient)
            : null,
        toPublicKey: _mode == _RecipientMode.address ? recipient : null,
      );

      if (!mounted) return;
      // 2-4. PIN → build → sign on-device → submit → record.
      final result = await signAndSubmitTransfer(
        context,
        _api,
        widget.user.id,
        toPublicKey: target.toPublicKey,
        amount: _amountController.text.trim(),
        assetCode: _assetCode,
        kind: TransferKind.transfer,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() => _error = 'Cancelled — no signature was submitted, so nothing moved.');
        return;
      }
      if (result.success) {
        final outcome = outcomeForPayment(
          result,
          headline: 'Sent',
          amount: _amountController.text.trim(),
          assetCode: _assetCode,
          caption: 'to ${target.displayName}',
          methodLabel: 'Direct payment',
        );
        await showPfConfirmation(context, outcome: outcome, receipt: outcome);
        if (mounted) Navigator.of(context).pop();
      } else {
        setState(() => _error = result.errorMessage ?? 'The payment was rejected on-chain.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipientError = _recipientError;
    final amountErrorText = _amountError;
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Send money'),
          backgroundColor: PfColors.offWhite,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  PfSpace.xl, PfSpace.lg, PfSpace.xl, 40,
                ),
                children: [
                  Text(
                    'Where is it going?',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Send to another PayFlex account by PayTag, or straight to '
                    'any Stellar address.',
                    style: TextStyle(
                      color: PfColors.inkMuted,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<_RecipientMode>(
                    segments: const [
                      ButtonSegment(value: _RecipientMode.payTag, label: Text('PayTag')),
                      ButtonSegment(value: _RecipientMode.address, label: Text('Address')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() {
                      _mode = s.first;
                      _revalidate();
                    }),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _recipientController,
                    decoration: InputDecoration(
                      labelText: switch (_mode) {
                        _RecipientMode.payTag => 'Recipient PayTag',
                        _RecipientMode.address => 'Recipient Stellar address',
                      },
                      prefixIcon: const Icon(Icons.alternate_email_outlined, size: 20),
                      errorText: recipientError,
                      errorMaxLines: 2,
                    ),
                    keyboardType: TextInputType.text,
                    inputFormatters:
                        _mode == _RecipientMode.payTag ? payTagInputFormatters() : null,
                    autofillHints: const [],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    switch (_mode) {
                      _RecipientMode.payTag =>
                        'Their @handle — resolved against the PayFlex directory before anything is signed.',
                      _RecipientMode.address => 'Their Stellar public key (G…).',
                    },
                    style: const TextStyle(color: PfColors.inkFaint, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Amount',
                    style: TextStyle(
                      color: PfColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  PfPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: PfColors.surface,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amountController,
                            decoration: const InputDecoration(
                              hintText: '0.00',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: false, // no negative sign at the keyboard
                            ),
                            inputFormatters: amountInputFormatters(),
                            style: PfMoneyType.large.copyWith(
                              color: PfColors.ink,
                            ),
                          ),
                        ),
                        DropdownButton<String>(
                          value: _assetCode,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: 'XLM', child: Text('XLM')),
                          ],
                          onChanged: (v) => setState(() => _assetCode = v!),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (amountErrorText != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                      child: Text(
                        amountErrorText,
                        style: const TextStyle(
                          color: PfColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        parseAmount(_amountController.text) > 0
                            ? 'You\u2019re sending ${formatMoney(_amountController.text, _assetCode)}'
                            : 'Sign the payment with your 6-digit PIN when it\u2019s ready.',
                        style: const TextStyle(
                          color: PfColors.inkMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Stellar payments are irreversible once they confirm on-chain.',
                      style: TextStyle(
                        color: PfColors.inkFaint,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_error != null) ...[
                    PfInlineError(message: _error!),
                    const SizedBox(height: 14),
                  ],
                  PfPrimaryButton(
                    label: 'Review & send',
                    icon: Icons.north_east_rounded,
                    busy: _busy,
                    onPressed: _busy ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kept as a shared helper for other screens' receipt chips.
PfTone transferToneFromBool(bool success) => success ? PfTone.success : PfTone.warn;
