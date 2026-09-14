import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/safebox.dart';
import '../../services/api_client.dart';
import '../../services/safebox_service.dart';
import '../../services/wallet_service.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../widgets/pf_balance_card.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_flow.dart';
import '../../widgets/pf_motion.dart';
import '../../widgets/pf_states.dart';
import '../../widgets/pin_prompt.dart';
import 'safebox_manage_members_screen.dart';

/// A Safebox backed by the Soroban escrow contract. Everything money-
/// related here is a REAL on-chain invocation signed on this device:
/// contribute pulls the token from the member into the contract; withdraw
/// releases it — and the CONTRACT (not this screen, not the backend)
/// refuses a withdrawal from anyone but the owner or a designated admin.
/// The ledger shown is read from the chain via the backend's read-only
/// endpoint, so no member sees anything but what the contract recorded.
class SafeboxDetailScreen extends StatefulWidget {
  final AppUser user;
  final String safeboxId; // the Soroban contract id (C...)

  const SafeboxDetailScreen({
    super.key,
    required this.user,
    required this.safeboxId,
  });

  @override
  State<SafeboxDetailScreen> createState() => _SafeboxDetailScreenState();
}

class _SafeboxDetailScreenState extends State<SafeboxDetailScreen> {
  final ApiClient _api = ApiClient();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _detail; // registry row + live chain state
  List<SafeboxTransaction> _transactions = [];
  List<double> _runningAfter = const []; // balance after each entry, newest-first
  SafeboxRole _userRole = SafeboxRole.member;
  String? _myPublicKey;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail = await _api.getSafeboxDetail(widget.user.id, widget.safeboxId);
      final ledger = await _api.getSafeboxLedger(widget.user.id, widget.safeboxId);

      final chain = (detail['chain'] as Map<String, dynamic>?) ?? const {};
      final owner = chain['owner'] as String?;
      final admins = (chain['admins'] as List<dynamic>?)?.cast<String>() ?? const [];
      final myKey = widget.user.stellarPublicKey;

      var role = SafeboxRole.member;
      if (myKey != null && owner == myKey) {
        role = SafeboxRole.owner;
      } else if (myKey != null && admins.contains(myKey)) {
        role = SafeboxRole.admin;
      }

      final txs = ledger
          .map(SafeboxTransaction.fromChain)
          .toList()
          .reversed
          .toList(); // newest first

      // Running balance after each entry (chat-ledger style): walk from
      // the newest entry backwards. The newest entry's "after" balance IS
      // the contract's current balance; each older entry's after-balance
      // is the next-newer one adjusted by that entry's signed effect.
      final chainBalance =
          double.tryParse((detail['chain'] as Map<String, dynamic>?)?['balance'] as String? ?? '0') ?? 0;
      var running = chainBalance;
      final runningAfter = <double>[];
      for (final tx in txs) {
        runningAfter.add(running);
        final amount = double.tryParse(tx.amount) ?? 0;
        running += tx.type == SafeboxTxType.contribution ? amount : -amount;
      }
      // runningAfter is newest-first, matching [txs].

      if (mounted) {
        setState(() {
          _detail = detail;
          _transactions = txs;
          _runningAfter = runningAfter;
          _userRole = role;
          _myPublicKey = myKey;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
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
              decoration: InputDecoration(prefixText: 'XLM ', labelText: amountLabel),
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
    final input = await _promptAmountAndNote(
      title: 'Contribute to Safebox',
      amountLabel: 'Contribution amount',
      noteLabel: 'Note / reason (optional)',
    );
    if (input == null) return;

    if (!mounted) return;
    final pin = await promptForPin(context);
    if (pin == null || pin.isEmpty) return;

    try {
      final client = await _api.stellarClient();
      final safebox = SafeboxService(stellar: client, rpcUrl: client.sorobanRpcUrl);
      await safebox.contribute(
        contractId: widget.safeboxId,
        amountDecimal: input.amount.toStringAsFixed(2),
        pin: pin,
      );
      if (!mounted) return;
      await showPfConfirmation(
        context,
        outcome: PfFlowOutcome(
          headline: 'Contribution made',
          amount: input.amount.toStringAsFixed(2),
          currency: 'XLM',
          caption: 'Recorded in the contract\u2019s own ledger',
          reference: widget.safeboxId,
          statusLabel: 'On-chain',
          statusTone: PfTone.success,
          methodLabel: 'Safebox contribution',
        ),
      );
      await _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _handleWithdraw() async {
    if (!_userRole.canWithdraw) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Forbidden: only the safebox owner and designated admins can withdraw — enforced on-chain.'),
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

    if (!mounted) return;
    final pin = await promptForPin(context);
    if (pin == null || pin.isEmpty) return;

    try {
      final client = await _api.stellarClient();
      final safebox = SafeboxService(stellar: client, rpcUrl: client.sorobanRpcUrl);
      // Withdraw to the caller's own account (self-withdrawal today; a
      // recipient picker would change nothing about the enforcement).
      final me = _myPublicKey ??
          await WalletService.currentAddress();
      if (me == null) throw StateError('No Stellar key on this device.');
      await safebox.withdraw(
        contractId: widget.safeboxId,
        toPublicKey: me,
        amountDecimal: input.amount.toStringAsFixed(2),
        pin: pin,
      );
      if (!mounted) return;
      await showPfConfirmation(
        context,
        outcome: PfFlowOutcome(
          headline: 'Withdrawal sent',
          amount: input.amount.toStringAsFixed(2),
          currency: 'XLM',
          caption: 'Released by the contract to your account',
          reference: widget.safeboxId,
          statusLabel: 'On-chain',
          statusTone: PfTone.success,
          methodLabel: 'Safebox withdrawal',
        ),
      );
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chain = (_detail?['chain'] as Map<String, dynamic>?) ?? const {};
    final balanceRaw = chain['balance'] as String? ?? '0';

    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: Text(_detail?['name'] as String? ?? 'Safebox'),
          backgroundColor: PfColors.offWhite,
          actions: [
            if (_userRole.isOwner)
              IconButton(
                icon: const Icon(Icons.group_add_outlined),
                tooltip: 'Manage admins (on-chain)',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SafeboxManageMembersScreen(
                        user: widget.user,
                        safeboxId: widget.safeboxId,
                      ),
                    ),
                  );
                  _loadData();
                },
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: PfBrandedLoader(size: 52))
            : _error != null
                ? Center(child: PfInlineError(message: _error!, onRetry: _loadData))
                : Column(
                    children: [
                      _buildHeroCard(balanceRaw),
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
                            const PfSectionHeader(title: 'On-chain activity'),
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
                            : SafeboxLedgerList(
                                transactions: _transactions,
                                runningAfter: _runningAfter,
                                myPublicKey: _myPublicKey,
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildHeroCard(String balanceRaw) {
    final box = _detail!;
    final chain = (box['chain'] as Map<String, dynamic>?) ?? const {};
    final closed = chain['closed'] == true;
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
                const Text('Contract balance', style: TextStyle(color: PfColors.inkFaint, fontSize: 12)),
                _roleBadge(_userRole),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$balanceRaw XLM',
              style: PfMoneyType.large.copyWith(color: PfColors.ink),
            ),
            const SizedBox(height: 6),
            if ((box['description'] as String? ?? '').isNotEmpty)
              Text(
                box['description'] as String,
                style: const TextStyle(color: PfColors.inkMuted, fontSize: 12.5, height: 1.4),
              ),
            const SizedBox(height: 8),
            SelectableText(
              widget.safeboxId,
              style: const TextStyle(color: PfColors.inkFaint, fontSize: 10.5, fontFamily: 'monospace'),
            ),
            if (closed)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: PfStatusChip(label: 'Closed on-chain', tone: PfTone.muted),
              ),
          ],
        ),
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

/// The chat-style on-chain ledger. Design goals (design brief §2 item 3:
/// "feel alive and social"): each entry slides/fades in like a new chat
/// message, identity is an at-a-glance colour avatar + short name, the
/// running balance after each entry is printed on the row like a running
/// total in a shared notebook, and YOUR entries are highlighted so a demo
/// viewer instantly sees who did what.
class SafeboxLedgerList extends StatelessWidget {
  final List<SafeboxTransaction> transactions; // newest first
  final List<double> runningAfter; // balance after each entry, newest first
  final String? myPublicKey;

  const SafeboxLedgerList({
    super.key,
    required this.transactions,
    required this.runningAfter,
    this.myPublicKey,
  });

  // Flat, muted avatar palette — social identity without decoration.
  static const _avatarColors = [
    Color(0xFF0B2FBE), // royal blue
    Color(0xFF0E9F4B), // flat success green
    Color(0xFF8A6110), // flat amber-ink
    Color(0xFF5B6580), // slate
    Color(0xFF7D93FF), // periwinkle
  ];

  Color _avatarColor(String key) {
    if (key.isEmpty) return _avatarColors.first;
    var h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _avatarColors[h % _avatarColors.length];
  }

  String _initials(String key) {
    if (key.length >= 2) return key.substring(0, 2).toUpperCase();
    return key.isEmpty ? '?' : key.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: PfSpace.lg,
        vertical: PfSpace.sm,
      ),
      itemCount: transactions.length,
      separatorBuilder: (_, __) => const SizedBox(height: PfSpace.sm),
      itemBuilder: (context, index) {
        final tx = transactions[index];
        final isMe =
            myPublicKey != null && tx.memberPublicKey == myPublicKey;
        return _LedgerEntryTile(
          tx: tx,
          balanceAfter:
              index < runningAfter.length ? runningAfter[index] : null,
          isMe: isMe,
          avatarColor: _avatarColor(tx.memberPublicKey),
          initials: _initials(tx.memberPublicKey),
          // Animate in only the top few entries so a refresh doesn't
          // replay the whole history — just what's new (or a first load's
          // opening cascade).
          animateIn: index < 4,
          delayMs: index * 70,
        );
      },
    );
  }
}

class _LedgerEntryTile extends StatefulWidget {
  final SafeboxTransaction tx;
  final double? balanceAfter;
  final bool isMe;
  final Color avatarColor;
  final String initials;
  final bool animateIn;
  final int delayMs;

  const _LedgerEntryTile({
    required this.tx,
    required this.avatarColor,
    required this.initials,
    required this.animateIn,
    required this.delayMs,
    this.balanceAfter,
    this.isMe = false,
  });

  @override
  State<_LedgerEntryTile> createState() => _LedgerEntryTileState();
}

class _LedgerEntryTileState extends State<_LedgerEntryTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: PfMotion.base,
    );
    if (widget.animateIn) {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final isContribution = tx.type == SafeboxTxType.contribution;
    final toneColor = isContribution ? PfColors.emerald : PfColors.warn;
    final verb = isContribution ? 'contributed' : 'withdrew';
    final signedAmount =
        '${isContribution ? '+' : '−'}${tx.amount} XLM';
    final time =
        '${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')}';
    final balanceAfter = widget.balanceAfter;

    final row = PfPanel(
      padding: const EdgeInsets.all(14),
      showShadow: false,
      color: widget.isMe ? PfColors.successWash : PfColors.surfaceAlt,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Identity avatar: colour + initials, not a direction glyph —
          // who acted is the information a group ledger leads with.
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.avatarColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(
              widget.initials,
              style: TextStyle(
                color: widget.avatarColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: PfSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.isMe ? 'You' : shortPublicKey(tx.memberPublicKey),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: PfColors.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Spacer(),
                    Text(
                      time,
                      style:
                          const TextStyle(color: PfColors.inkFaint, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                        color: PfColors.inkMuted, fontSize: 13),
                    children: [
                      TextSpan(text: '$verb '),
                      TextSpan(
                        text: signedAmount,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: toneColor),
                      ),
                    ],
                  ),
                ),
                if (balanceAfter != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'Balance after · ${balanceAfter.toStringAsFixed(balanceAfter.truncateToDouble() == balanceAfter ? 0 : 2)} XLM',
                      style: const TextStyle(
                          color: PfColors.inkFaint,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - t)),
            child: child,
          ),
        );
      },
      child: row,
    );
  }
}
