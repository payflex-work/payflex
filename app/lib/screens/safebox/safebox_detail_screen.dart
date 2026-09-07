import 'package:flutter/material.dart';
import '../../theme/payflex_tokens.dart';
import '../../utils/money.dart';
import '../../models/safebox.dart';
import '../../services/api_client.dart';
import '../../widgets/pf_mark.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_flow.dart';
import '../../widgets/pf_states.dart';
import 'safebox_manage_members_screen.dart';

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
  List<SafeboxMember> _members = [];
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
          _members = detail.members;
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

  Future<void> _handleContribute() async {
    if (_box == null) return;

    final amountController = TextEditingController();
    final noteController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contribute to Safebox'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: '₦ ',
                labelText: 'Contribution Amount',
              ),
            ),
            const SizedBox(height: PayFlexSpacing.md),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Note / Reason (Optional)',
                hintText: 'e.g. September deposit',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Proceed'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) return;

    // Use standard PfPaymentConfirmationSheet
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PfPaymentConfirmationSheet(
        title: 'Deposit to Safebox',
        recipientName: _box!.name,
        purpose: noteController.text.trim().isEmpty
            ? 'Safebox Contribution'
            : noteController.text.trim(),
        amount: amount,
        fee: 0.0,
        onAuthorize: (pin) async {
          return pin.length == 4;
        },
        onSubmit: () async {
          await _api.contributeSafebox(
            widget.safeboxId,
            amount,
            noteController.text.trim(),
          );
        },
        onSuccess: () {
          _loadData();
        },
      ),
    );
  }

  Future<void> _handleWithdraw() async {
    if (_box == null) return;
    if (!_userRole.canWithdraw) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Forbidden: Only Safebox Owner and designated Admins can withdraw.'),
          backgroundColor: PayFlexColors.error,
        ),
      );
      return;
    }

    final amountController = TextEditingController();
    final noteController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw from Safebox'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: '₦ ',
                labelText: 'Withdrawal Amount',
              ),
            ),
            const SizedBox(height: PayFlexSpacing.md),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Mandatory Reason / Note',
                hintText: 'e.g. Kenya flight booking',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Authorize & Pay'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) return;
    if (noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A note/reason is required for withdrawal accountability.')),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PfPaymentConfirmationSheet(
        title: 'Withdraw from Pool',
        recipientName: 'Destination Wallet',
        purpose: noteController.text.trim(),
        amount: amount,
        fee: 0.0,
        onAuthorize: (pin) async {
          return pin.length == 4;
        },
        onSubmit: () async {
          await _api.withdrawSafebox(
            widget.safeboxId,
            amount,
            noteController.text.trim(),
            'acc_self',
          );
        },
        onSuccess: () {
          _loadData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _box == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Safebox Detail')),
        body: const Center(child: PfLoader()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_box!.name),
        actions: [
          if (_userRole.isOwner)
            IconButton(
              icon: const Icon(Icons.group_add_outlined),
              tooltip: 'Manage Members',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SafeboxManageMembersScreen(safeboxId: widget.safeboxId),
                  ),
                );
                _loadData();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _buildHeroCard(),
          Padding(
            padding: const EdgeInsets.horizontal(PayFlexSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: PfPrimaryButton(
                    label: 'Contribute',
                    icon: Icons.arrow_downward,
                    onPressed: _handleContribute,
                  ),
                ),
                if (_userRole.canWithdraw) ...[
                  const SizedBox(width: PayFlexSpacing.md),
                  Expanded(
                    child: PfSecondaryButton(
                      label: 'Withdraw',
                      icon: Icons.arrow_upward,
                      onPressed: _handleWithdraw,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: PayFlexSpacing.lg),
          Padding(
            padding: const EdgeInsets.horizontal(PayFlexSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Group Chat Ledger', style: PayFlexTypography.heading2),
                Text('${_transactions.length} events',
                    style: PayFlexTypography.caption),
              ],
            ),
          ),
          const SizedBox(height: PayFlexSpacing.sm),
          Expanded(
            child: _transactions.isEmpty
                ? Center(
                    child: Text(
                      'No transactions yet. Be the first to contribute!',
                      style: PayFlexTypography.caption,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PayFlexSpacing.lg,
                      vertical: PayFlexSpacing.sm,
                    ),
                    itemCount: _transactions.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: PayFlexSpacing.sm),
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      return _buildChatBubble(tx);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(PayFlexSpacing.lg),
      padding: const EdgeInsets.all(PayFlexSpacing.lg),
      decoration: BoxDecoration(
        color: PayFlexColors.darkSurface,
        borderRadius: BorderRadius.circular(PayFlexRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Safebox Balance', style: PayFlexTypography.caption),
              _roleBadge(_userRole),
            ],
          ),
          const SizedBox(height: PayFlexSpacing.xs),
          Text(
            formatMoney(_box!.currentBalance),
            style: PayFlexTypography.heading1.copyWith(
              color: PayFlexColors.primaryGreen,
              fontSize: 36,
            ),
          ),
          const SizedBox(height: PayFlexSpacing.xs),
          Text(_box!.description, style: PayFlexTypography.bodySmall),
        ],
      ),
    );
  }

  Widget _buildChatBubble(SafeboxTransaction tx) {
    final isContribution = tx.type == SafeboxTxType.contribution;
    final color = isContribution ? PayFlexColors.primaryGreen : PayFlexColors.error;
    final action = isContribution ? 'contributed' : 'withdrew';

    return Container(
      padding: const EdgeInsets.all(PayFlexSpacing.md),
      decoration: BoxDecoration(
        color: PayFlexColors.darkSurfaceAlt,
        borderRadius: BorderRadius.circular(PayFlexRadius.md),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withOpacity(0.2),
            child: Icon(
              isContribution ? Icons.arrow_downward : Icons.arrow_upward,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: PayFlexSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tx.userName,
                      style: PayFlexTypography.bodySmall
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')}',
                      style: PayFlexTypography.caption,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: PayFlexTypography.body
                        .copyWith(color: PayFlexColors.textOffWhite),
                    children: [
                      TextSpan(text: '$action '),
                      TextSpan(
                        text: formatMoney(tx.amount),
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: color),
                      ),
                    ],
                  ),
                ),
                if (tx.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '💬 "${tx.note}"',
                    style: PayFlexTypography.caption
                        .copyWith(fontStyle: FontStyle.italic),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: PayFlexColors.primaryBlue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(PayFlexRadius.xs),
      ),
      child: Text(
        role.label.toUpperCase(),
        style: const TextStyle(
          color: PayFlexColors.primaryBlue,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}
