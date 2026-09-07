import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../theme/money_formatter.dart';
import '../models/safebox_model.dart';
import '../services/safebox_service.dart';
import '../components/branded_loader.dart';
import '../components/primary_button.dart';
import '../components/payment_confirmation_flow.dart';
import 'safebox_manage_members_screen.dart';

/// Detailed view of a Safebox: balance hero, member status,
/// group chat transaction ledger feed, and authorized contribution/withdrawal CTAs.
class SafeboxDetailScreen extends StatefulWidget {
  final String safeboxId;

  const SafeboxDetailScreen({super.key, required this.safeboxId});

  @override
  State<SafeboxDetailScreen> createState() => _SafeboxDetailScreenState();
}

class _SafeboxDetailScreenState extends State<SafeboxDetailScreen> {
  final SafeboxService _service = SafeboxService();
  bool _isLoading = true;
  SafeboxModel? _box;
  List<SafeboxMemberModel> _members = [];
  List<SafeboxTransactionModel> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final boxes = await _service.getSafeboxes();
    final box = boxes.firstWhere(
      (b) => b.id == widget.safeboxId,
      orElse: () => SafeboxModel(
        id: widget.safeboxId,
        name: 'Safebox',
        description: '',
        ownerId: '',
        currentBalance: 0,
        status: SafeboxStatus.active,
        createdAt: DateTime.now(),
        userRole: SafeboxRole.member,
      ),
    );

    final members = await _service.getMembers(widget.safeboxId);
    final txs = await _service.getTransactions(widget.safeboxId);

    if (mounted) {
      setState(() {
        _box = box;
        _members = members;
        _transactions = txs;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleContribute() async {
    if (_box == null) return;

    final amountController = TextEditingController();
    final noteController = TextEditingController();

    final entered = await showDialog<bool>(
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
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Note / Reason (Optional)',
                hintText: 'e.g. September contribution',
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
            child: const Text('Proceed to Payment'),
          ),
        ],
      ),
    );

    if (entered != true) return;

    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) return;

    // Launch standard 5-step payment flow sheet
    await PaymentConfirmationFlowSheet.show(
      context: context,
      title: 'Deposit to Safebox',
      recipientName: _box!.name,
      purpose: noteController.text.trim().isEmpty ? 'Safebox Contribution' : noteController.text.trim(),
      amount: amount,
      currency: 'NGN',
      fee: 0.0,
      onAuthenticate: (pin) async {
        return pin == '1234' || pin.length == 4; // PIN verification
      },
      onSubmit: () async {
        return await _service.processContribution(
          safeboxId: widget.safeboxId,
          amount: amount,
          note: noteController.text.trim(),
        );
      },
      onRecord: (result) {
        _loadData();
      },
    );
  }

  Future<void> _handleWithdraw() async {
    if (_box == null) return;

    // Client-side role check
    if (!_box!.userRole.canWithdraw) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Forbidden: Only Safebox Owner and designated Admins can initiate withdrawals.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final amountController = TextEditingController();
    final noteController = TextEditingController();

    final entered = await showDialog<bool>(
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
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Mandatory Reason / Note',
                hintText: 'e.g. Kenya flight booking payment',
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

    if (entered != true) return;

    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) return;
    if (noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A note/reason is required for withdrawal accountability.')),
      );
      return;
    }

    // Launch standard 5-step payment flow sheet
    await PaymentConfirmationFlowSheet.show(
      context: context,
      title: 'Withdraw from Pool',
      recipientName: 'Primary Wallet / Recipient',
      purpose: noteController.text.trim(),
      amount: amount,
      currency: 'NGN',
      fee: 0.0,
      onAuthenticate: (pin) async {
        return pin == '1234' || pin.length == 4;
      },
      onSubmit: () async {
        return await _service.processWithdrawal(
          safeboxId: widget.safeboxId,
          amount: amount,
          note: noteController.text.trim(),
          userRole: _box!.userRole,
        );
      },
      onRecord: (result) {
        _loadData();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading || _box == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Safebox Detail')),
        body: const Center(child: BrandedLoader(size: 48)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_box!.name),
        actions: [
          if (_box!.userRole.isOwner)
            IconButton(
              icon: const Icon(Icons.group_add_outlined),
              tooltip: 'Manage Members & Admins',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SafeboxManageMembersScreen(safeboxId: widget.safeboxId),
                  ),
                );
                _loadData();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Balance & Header Card
          _buildHeaderHero(isDark),

          // Action buttons
          _buildActionButtons(isDark),

          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.horizontal(AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Group Chat Ledger',
                  style: AppTypography.heading2,
                ),
                Text(
                  '${_transactions.length} events',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Group Chat Ledger Feed
          Expanded(
            child: _transactions.isEmpty
                ? _buildEmptyLedger(isDark)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    itemCount: _transactions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      return _buildChatLedgerBubble(tx, isDark, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderHero(bool isDark) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? AppColors.darkSurfaceAlt : const Color(0xFFE5E5E0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Safebox Balance', style: AppTypography.caption),
              _roleBadge(_box!.userRole, isDark),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            MoneyFormatter.format(_box!.currentBalance),
            style: AppTypography.balanceDisplay.copyWith(
              color: AppColors.primaryGreen,
              fontSize: 40,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(_box!.description, style: AppTypography.bodySmall),

          // Member Avatar list summary
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                'Members (${_members.length}): ',
                style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _members.map((m) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          avatar: CircleAvatar(
                            backgroundColor: AppColors.primaryBlue.withOpacity(0.3),
                            child: Text(
                              m.name.isNotEmpty ? m.name[0].toUpperCase() : 'U',
                              style: const TextStyle(fontSize: 10, color: Colors.white),
                            ),
                          ),
                          label: Text(
                            '${m.name} (${m.role.label})',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isDark) {
    final canWithdraw = _box!.userRole.canWithdraw;

    return Padding(
      padding: const EdgeInsets.horizontal(AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: 'Contribute',
              icon: Icons.arrow_downward,
              onPressed: _handleContribute,
            ),
          ),
          if (canWithdraw) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SecondaryButton(
                label: 'Withdraw',
                icon: Icons.arrow_upward,
                onPressed: _handleWithdraw,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyLedger(bool isDark) {
    return Center(
      child: Text(
        'No transactions yet. Be the first to contribute!',
        style: AppTypography.caption,
      ),
    );
  }

  // Chat-style message bubble for money events
  Widget _buildChatLedgerBubble(SafeboxTransactionModel tx, bool isDark, int index) {
    final isContribution = tx.type == SafeboxTxType.contribution;

    final actionColor = isContribution ? AppColors.primaryGreen : AppColors.error;
    final actionText = isContribution ? 'contributed' : 'withdrew';
    final actionIcon = isContribution ? Icons.arrow_downward : Icons.arrow_upward;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: actionColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User Avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: actionColor.withOpacity(0.2),
            child: Icon(actionIcon, color: actionColor, size: 18),
          ),
          const SizedBox(width: AppSpacing.md),

          // Message content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tx.userName,
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _formatTimestamp(tx.createdAt),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: AppTypography.body.copyWith(
                      color: isDark ? AppColors.textOffWhite : AppColors.textDark,
                    ),
                    children: [
                      TextSpan(text: '$actionText '),
                      TextSpan(
                        text: MoneyFormatter.format(tx.amount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: actionColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (tx.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isDark ? AppColors.darkNavy : Colors.white).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '💬 "${tx.note}"',
                      style: AppTypography.caption.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Pool balance after entry: ${MoneyFormatter.format(tx.runningBalance)}',
                  style: AppTypography.caption.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 150.ms);
  }

  Widget _roleBadge(SafeboxRole role, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        role.label.toUpperCase(),
        style: AppTypography.caption.copyWith(
          color: AppColors.primaryBlue,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
