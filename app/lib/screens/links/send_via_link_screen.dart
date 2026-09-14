import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/claimable_link.dart';
import '../../services/api_client.dart';
import '../../services/transfer_flow.dart';
import '../../services/wallet_service.dart';
import '../../stellar/stellar_models.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../utils/format.dart';
import '../../utils/money.dart';
import '../../widgets/pf_balance_card.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_flow.dart';
import '../../widgets/pf_states.dart';
import '../../widgets/pin_prompt.dart';

/// Send-via-link — NON-CUSTODIAL on native Stellar claimable balances.
///
/// Flow (mirrors backend/src/links/links.service.ts):
///   1. Create the link record → get the share token.
///   2. The app builds an on-chain CREATE_CLAIMABLE_BALANCE with the
///      sender as sole claimant (reclaimable) — funds are escrowed BY THE
///      CHAIN, never in a PayFlex-owned account.
///   3. The backend verifies the claimable balance on Horizon → FUNDED.
///   4. The recipient claims on-chain with their own signature and the
///      backend verifies the claim before marking CLAIMED.
///
/// Funds are escrowed by the chain, never by PayFlex — there is no
/// treasury account anywhere in this architecture.
class SendViaLinkScreen extends StatefulWidget {
  final AppUser user;
  const SendViaLinkScreen({super.key, required this.user});

  @override
  State<SendViaLinkScreen> createState() => _SendViaLinkScreenState();
}

class _SendViaLinkScreenState extends State<SendViaLinkScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Send via link'),
          backgroundColor: PfColors.offWhite,
          bottom: const TabBar(
            indicatorColor: PfColors.royalBlue,
            labelColor: PfColors.ink,
            unselectedLabelColor: PfColors.inkMuted,
            labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            tabs: [Tab(text: 'Send'), Tab(text: 'Claim')],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [_SendTab(user: widget.user), _ClaimTab(user: widget.user)],
        ),
      ),
    );
  }
}

class _SendTab extends StatefulWidget {
  final AppUser user;
  const _SendTab({required this.user});

  @override
  State<_SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<_SendTab> {
  final _api = ApiClient();
  final _amountController = TextEditingController();
  String _assetCode = 'XLM';
  bool _busy = false;
  String? _error;
  String? _shareToken;
  String? _status;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
      _shareToken = null;
      _status = null;
    });
    try {
      // 1. Create the link record and get the share token.
      final link = await _api.sendViaLink(
        widget.user.id,
        amount: _amountController.text.trim(),
        assetCode: _assetCode,
      );

      // 2. Create the on-chain claimable balance — the sender is the sole
      //    claimant until the recipient claims, so nothing is ever held by
      //    PayFlex. The PIN prompt happens inside the shared flow.
      if (!mounted) return;
      final pin = await promptForPin(context);
      if (pin == null || pin.isEmpty) {
        setState(() => _status = 'Cancelled — the on-chain escrow was not created.');
        return;
      }
      final stellar = await _api.stellarClient();
      final senderKey = (await WalletService.currentAddress())!;
      final cb = await stellar.createClaimableBalance(
        claimantPublicKeys: [senderKey],
        assetCode: _assetCode,
        amount: _amountController.text.trim(),
        pin: pin,
      );
      if (!cb.success) {
        setState(() => _error = cb.errorMessage ?? 'The Stellar network rejected the escrow.');
        return;
      }

      // 3. Look up the created claimable balance and register its id with
      //    the backend, which verifies it on Horizon before marking the
      //    link FUNDED. (The CB id is read back from the sender's
      //      claimable balances; the tx hash alone is not the CB id.)
      final cbId = await stellar.findCreatedClaimableBalanceId(
        txHash: cb.transactionHash!,
        requesterPublicKey: senderKey,
      );
      if (cbId == null) {
        setState(() => _error =
            'Escrow created (tx ${shortRef(cb.transactionHash ?? '')}) but the claimable balance '
                'id could not be read back yet — retry in a moment so the link is marked funded.');
        return;
      }
      await _api.registerClaimableBalance(widget.user.id, link.linkId, cbId);

      setState(() {
        _shareToken = link.shareToken;
        _status =
            'Escrow verified on-chain. Share the token below — funds sit in a '
            'claimable balance YOU can reclaim, never in a PayFlex account.';
      });
      await _celebrateSend(cb);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _celebrateSend(StellarPaymentResult result) {
    return showPfConfirmation(
      context,
      outcome: outcomeForPayment(
        result,
        headline: 'Link funded on-chain',
        amount: _amountController.text.trim(),
        assetCode: _assetCode,
        caption: 'Claimable balance · reclaimable by you until claimed',
        methodLabel: 'Send via link',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(PfSpace.xl, PfSpace.xl, PfSpace.xl, 48),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PfColors.navy,
                borderRadius: BorderRadius.circular(PfRadius.md),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: PfColors.onNavyMuted, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your funds are escrowed ON-CHAIN in a Stellar claimable '
                      'balance — never in a PayFlex account. You can reclaim '
                      'them yourself until the recipient claims.',
                      style: TextStyle(
                        color: PfColors.onNavyMuted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 116,
                  child: DropdownButtonFormField<String>(
                    initialValue: _assetCode,
                    decoration: const InputDecoration(labelText: 'Asset'),
                    items: const [
                      DropdownMenuItem(value: 'XLM', child: Text('XLM')),
                    ],
                    onChanged: (v) => setState(() => _assetCode = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              PfInlineError(message: _error!),
              const SizedBox(height: 14),
            ],
            if (_status != null) ...[
              PfPanel(
                padding: const EdgeInsets.all(12),
                color: PfColors.surfaceAlt,
                showShadow: false,
                child: Text(
                  _status!,
                  style: const TextStyle(color: PfColors.inkMuted, fontSize: 13, height: 1.45),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_shareToken != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: PfColors.successWash,
                  borderRadius: BorderRadius.circular(PfRadius.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.link_rounded, color: PfColors.success, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Share this claim token',
                          style: TextStyle(
                            color: PfColors.success,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _shareToken!,
                      style: const TextStyle(
                        color: PfColors.ink,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            PfPrimaryButton(
              label: 'Fund link on-chain',
              icon: Icons.link_rounded,
              busy: _busy,
              onPressed: _busy ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClaimTab extends StatefulWidget {
  final AppUser user;
  const _ClaimTab({required this.user});

  @override
  State<_ClaimTab> createState() => _ClaimTabState();
}

class _ClaimTabState extends State<_ClaimTab> {
  final _api = ApiClient();
  final _tokenController = TextEditingController();
  ClaimPreview? _preview;
  bool _busy = false;
  bool _claiming = false;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      _preview = await _api.previewLink(_tokenController.text.trim());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim() async {
    setState(() {
      _claiming = true;
      _error = null;
    });
    try {
      // The claim itself is an on-chain claimClaimableBalance operation
      // signed by the recipient (this device's key).
      final pin = await promptForPin(context);
      if (pin == null || pin.isEmpty) {
        setState(() => _status = 'Cancelled — nothing was claimed.');
        return;
      }
      final stellar = await _api.stellarClient();
      final claimTx = await stellar.claimClaimableBalance(
        claimableBalanceId: _preview!.claimableBalanceId!,
        pin: pin,
      );
      if (!claimTx.success) {
        setState(() => _error = claimTx.errorMessage ?? 'The on-chain claim failed.');
        return;
      }

      // Report the claim (with the tx hash) so the backend can verify it.
      final me = await WalletService.currentAddress();
      await _api.claimLink(
        widget.user.id,
        _preview!.linkId,
        claimantPublicKey: me!,
        claimTxHash: claimTx.transactionHash!,
      );
      if (!mounted) return;
      await showPfSimpleSuccess(
        context,
        title: 'Claimed',
        message: 'Funds moved from the claimable balance to your account — verified on-chain.',
        actionLabel: 'Done',
      );
      if (mounted) {
        setState(() {
          _preview = null;
          _status = null;
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(PfSpace.xl, PfSpace.xl, PfSpace.xl, 48),
          children: [
            Text(
              'Have a claim token?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Paste the token you received — preview what\u2019s waiting, then '
              'claim it on-chain into your account.',
              style: TextStyle(color: PfColors.inkMuted, fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Claim token',
                prefixIcon: Icon(Icons.link_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 10),
            PfSecondaryButton(
              label: 'Preview',
              onPressed: _busy ? null : _loadPreview,
            ),
            if (p != null) ...[
              const SizedBox(height: 18),
              PfPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatMoney(p.amount, p.assetCode),
                            style: PfMoneyType.large.copyWith(color: PfColors.ink),
                          ),
                        ),
                        PfStatusChip(
                          label: p.status == 'FUNDED' ? 'Waiting for you' : p.status,
                          tone: p.status == 'FUNDED' ? PfTone.info : PfTone.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'from ${p.senderName}',
                      style: const TextStyle(color: PfColors.inkMuted, fontSize: 13.5),
                    ),
                    if (!p.claimableBalanceExists) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'The on-chain escrow for this link has not been created yet.',
                        style: TextStyle(color: PfColors.warn, fontSize: 12.5),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          'Expires',
                          style: TextStyle(color: PfColors.inkMuted, fontSize: 12.5),
                        ),
                        const Spacer(),
                        Text(
                          p.expiresAt,
                          style: const TextStyle(
                            color: PfColors.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (p.status == 'FUNDED' && p.claimableBalanceExists)
                      PfPrimaryButton(
                        label: 'Claim on-chain',
                        busy: _claiming,
                        onPressed: _claiming ? null : _claim,
                      )
                    else
                      const Text(
                        'This link has already been claimed or expired.',
                        style: TextStyle(color: PfColors.inkMuted, fontSize: 13),
                      ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              PfInlineError(message: _error!),
            ],
            if (_status != null) ...[
              const SizedBox(height: 14),
              PfInlineError(message: _status!, onRetry: null),
            ],
          ],
        ),
      ),
    );
  }
}
