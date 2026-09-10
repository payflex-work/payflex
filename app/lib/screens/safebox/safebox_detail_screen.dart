import 'package:flutter/material.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../utils/money.dart';
import '../../models/safebox.dart';
import '../../services/api_client.dart';
import '../../services/local_user_store.dart';
import '../../services/transfer_flow.dart';
import '../../widgets/pf_balance_card.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_flow.dart';
import '../../widgets/pf_motion.dart';
import '../../widgets/pf_states.dart';
import '../../widgets/pin_prompt.dart';
import 'safebox_manage_members_screen.dart';

/// A contribution is a real signed BMONI transfer (member -> treasury,
/// same pattern as SavingsGoal), signed via the same
/// `signAndSubmitTransfer` helper every other money-movement screen in
/// this app uses — not a bespoke confirmation flow. A withdrawal is
/// already treasury-signed server-side by the time the call returns
/// (see backend/src/safebox/safebox.service.ts), so there's nothing to
/// sign client-side; the PIN prompt there is still a deliberate
/// re-confirmation step before pool funds move, not a signature.
class SafeboxDetailScreen extends StatefulWidget {
  final String safeboxId;

  const SafeboxDetailScreen({super.key, required this.safeboxId});

  @override
  State<SafeboxDetailScreen> createState() => _SafeboxDetailScreenState();
}

class _SafeboxDetailScreenState extends State<SafeboxDetailScreen> {
  final ApiClient _api = ApiClient();
  bool _isLoading = true;
  Safebox? _box;
  List<SafeboxTransaction> _transactions = [];
  SafeboxRole _userRole = SafeboxRole.member;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final detail = await _api.getSafeboxDetail(widget.safeboxId);
      final txs = await _api.getSafeboxTransactions(widget.safeboxId);

      SafeboxRole r = SafeboxRole.member;
      if (detail.role.toUpperCase() == 'OWNER') r = SafeboxRole.owner;
      if (detail.role.toUpperCase() == 'ADMIN') r = SafeboxRole.admin;

      if (mounted) {
        setState(() {
          _box = detail.safebox;
          _transactions = txs;
          _userRole = r;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<({double amount, String note})?> _promptAmountAndNote({
    required String title,
    required String amountLabel,
    required String noteLabel,
    bool noteRequired = false,
  }) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(prefixText: '₦ ', labelText: amountLabel),
            ),
            const SizedBox(height: PfSpace.md),
            TextField(
              controller: noteController,
              decoration: InputDecoration(labelText: noteLabel, hintText: 'e.g. September deposit'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );

    if (ok != true) return null;
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) return null;
    final note = noteController.text.trim();
    if (noteRequired && note.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A note/reason is required for withdrawal accountability.')),
        );
      }
      return null;
    }
    return (amount: amount, note: note);
  }

  Future<void> _handleContribute() async {
    if (_box == null) return;
    final input = await _promptAmountAndNote(
      title: 'Contribute to Safebox',
      amountLabel: 'Contribution amount',
      noteLabel: 'Note / reason (optional)',
    );
    if (input == null) return;

    try {
      final tx = await _api.contributeSafebox(
        widget.safeboxId,
        input.amount,
        input.note,
      );
      final proposalId = tx.proposalId;
      final appUserId = await LocalUserStore().getAppUserId();
      if (proposalId == null || appUserId == null) {
        throw Exception('Could not sign the contribution — missing proposal or session info.');
      }
      if (!mounted) return;
      final signed = await signAndSubmitTransfer(context, _api, appUserId, proposalId);
      if (signed != null && mounted) {
        await showPfConfirmation(
          context,
          outcome: PfFlowOutcome(
            headline: 'Contribution made',
            amount: signed.amount,
            currency: signed.currency,
            caption: 'Added to ${_box!.name}',
            reference: signed.id,
            statusLabel: 'Submitted',
            statusTone: PfTone.success,
            methodLabel: 'Safebox contribution',
          ),
        );
        await _loadData();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _handleWithdraw() async {
    if (_box == null) return;
    if (!_userRole.canWithdraw) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Forbidden: Only the safebox owner and designated admins can withdraw.'),
        ),
      );
      return;
    }

    final input = await _promptAmountAndNote(
      title: 'Withdraw from Safebox',
      amountLabel: 'Withdrawal amount',
      noteLabel: 'Mandatory reason / note',
      noteRequired: true,
    );
    if (input == null) return;

    // No client-side signature is needed — the treasury signs the
    // release server-side (see SafeboxService.withdraw) — but a PIN is
    // still required as a deliberate re-confirmation step before moving
    // pool funds, matching every interactive money movement in this app.
    if (!mounted) return;
    final pin = await promptForPin(context);
    if (pin == null || pin.isEmpty) return;

    try {
      final appUserId = await LocalUserStore().getAppUserId();
      if (appUserId == null) {
        throw Exception('No local session — cannot resolve a withdrawal destination.');
      }
      // Only self-withdrawal is supported today (no recipient picker
      // yet) — resolve the current user's own bmoniUserId.
      final me = await _api.getUser(appUserId);
      final tx = await _api.withdrawSafebox(
        widget.safeboxId,
        input.amount,
        input.note,
        me.bmoniUserId,
      );
      if (!mounted) return;
      await showPfConfirmation(
        context,
        outcome: PfFlowOutcome(
          headline: 'Withdrawal sent',
          amount: tx.amount.toStringAsFixed(2),
          currency: 'NGN',
          caption: 'The treasury signed this release automatically.',
          reference: tx.id,
          statusLabel: 'Submitted',
          statusTone: PfTone.success,
          methodLabel: 'Safebox withdrawal',
        ),
      );
      await _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: Text(_box?.name ?? 'Safebox'),
          backgroundColor: PfColors.offWhite,
          actions: [
            if (_userRole.isOwner)
              IconButton(
                icon: const Icon(Icons.group_add_outlined),
                tooltip: 'Manage members',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SafeboxManageMembersScreen(safeboxId: widget.safeboxId),
                    ),
                  );
                  _loadData();
                },
              ),
          ],
        ),
        body: _isLoading || _box == null
            ? const Center(child: PfBrandedLoader(size: 52))
            : Column(
                children: [
                  _buildHeroCard(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PfSpace.lg),
                    child: Row(
                      children: [
                        Expanded(
                          child: PfPrimaryButton(
                            label: 'Contribute',
                            icon: Icons.add_rounded,
                            onPressed: _handleContribute,
                          ),
                        ),
                        if (_userRole.canWithdraw) ...[
                          const SizedBox(width: PfSpace.md),
                          Expanded(
                            child: PfSecondaryButton(
                              label: 'Withdraw',
                              icon: Icons.arrow_upward_rounded,
                              onPressed: _handleWithdraw,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: PfSpace.lg),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PfSpace.lg),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const PfSectionHeader(title: 'Activity'),
                        Text(
                          '${_transactions.length} events',
                          style: const TextStyle(color: PfColors.inkFaint, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PfSpace.sm),
                  Expanded(
                    child: _transactions.isEmpty
                        ? const Center(
                            child: PfEmptyState(
                              compact: true,
                              icon: Icons.receipt_long_outlined,
                              title: 'No activity yet',
                              message: 'Be the first to contribute!',
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: PfSpace.lg,
                              vertical: PfSpace.sm,
                            ),
                            itemCount: _transactions.length,
                            separatorBuilder: (_, __) => const SizedBox(height: PfSpace.sm),
                            itemBuilder: (context, index) => _buildTransactionRow(_transactions[index]),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final box = _box!;
    return Padding(
      padding: const EdgeInsets.all(PfSpace.lg),
      child: PfPanel(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total safebox balance', style: TextStyle(color: PfColors.inkFaint, fontSize: 12)),
                _roleBadge(_userRole),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              formatMoneyValue(box.currentBalance, 'NGN'),
              style: PfMoneyType.large.copyWith(color: PfColors.ink),
            ),
            const SizedBox(height: 6),
            Text(box.description, style: const TextStyle(color: PfColors.inkMuted, fontSize: 12.5, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionRow(SafeboxTransaction tx) {
    final isContribution = tx.type == SafeboxTxType.contribution;
    final toneColor = isContribution ? PfColors.emerald : PfColors.warn;
    final action = isContribution ? 'contributed' : 'withdrew';

    return PfPanel(
      padding: const EdgeInsets.all(14),
      showShadow: false,
      color: PfColors.surfaceAlt,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: toneColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isContribution ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: toneColor,
              size: 17,
            ),
          ),
          const SizedBox(width: PfSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tx.userName,
                      style: const TextStyle(color: PfColors.ink, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: PfColors.inkFaint, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: PfColors.inkMuted, fontSize: 13),
                    children: [
                      TextSpan(text: '$action '),
                      TextSpan(
                        text: formatMoneyValue(tx.amount, 'NGN'),
                        style: TextStyle(fontWeight: FontWeight.w700, color: toneColor),
                      ),
                    ],
                  ),
                ),
                if (tx.note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '"${tx.note}"',
                    style: const TextStyle(color: PfColors.inkFaint, fontSize: 11.5, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleBadge(SafeboxRole role) {
    return PfStatusChip(
      label: role.label,
      tone: switch (role) {
        SafeboxRole.owner => PfTone.info,
        SafeboxRole.admin => PfTone.warn,
        SafeboxRole.member => PfTone.muted,
      },
    );
  }
}
