import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/payflex_tokens.dart';
import '../theme/payflex_theme.dart';
import '../utils/format.dart';
import '../utils/money.dart';
import '../utils/stellar_tx.dart';
import 'pf_balance_card.dart';
import 'pf_buttons.dart';
import 'pf_mark.dart';
import 'pf_states.dart';

/// The tactile payoff for a completed money flow, fired once as the
/// confirmation mark lands. Haptics carry the delight (no visual glow,
/// per the design brief) and degrade silently on platforms that refuse
/// them (web, unsupported API levels) — wrapped in try/catch for that
/// reason. Sound is deliberately omitted: there is no clean asset-free
/// system success-sound API on both platforms, and this polish pass
/// refuses to ship bundled audio for a single moment.
void _fireConfirmationPayoff() {
  try {
    HapticFeedback.heavyImpact();
  } catch (_) {}
}

void _fireRevealTick() {
  try {
    HapticFeedback.lightImpact();
  } catch (_) {}
}

/// Everything a completed money flow needs to render its payoff: the
/// confirmation animation and the receipt. Built once, reused by every
/// entry point (Send, QR Pay, savings, loans, agent, split-bill,
/// send-via-link) so the signature moment is consistent by construction.
class PfFlowOutcome {
  final String headline; // "Sent", "Paid", "Cash-in submitted"…
  final String amount; // decimal string
  final String currency;
  final String? caption; // "to @jane · NGN wallet"
  final String reference; // proposal id
  final String? statusLabel; // e.g. "Signed · settling"
  final PfTone statusTone;
  final String? methodLabel; // e.g. "QR Pay"

  const PfFlowOutcome({
    required this.headline,
    required this.amount,
    required this.currency,
    required this.reference,
    this.caption,
    this.statusLabel,
    this.statusTone = PfTone.info,
    this.methodLabel,
  });
}

/// The single most important animation in the app (design brief §2, item
/// 2): the ribbon/arrow motif draws itself along its path in flat
/// gradient and settles — no glow, no particle burst. Amount and details
/// fade in after the mark lands. [receipt] is shown as a secondary
/// action when the flow can produce one.
Future<void> showPfConfirmation(
  BuildContext context, {
  required PfFlowOutcome outcome,
  PfFlowOutcome? receipt,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PfConfirmationScreen(outcome: outcome, receipt: receipt),
    ),
  );
}

class PfConfirmationScreen extends StatefulWidget {
  final PfFlowOutcome outcome;
  final PfFlowOutcome? receipt;
  const PfConfirmationScreen({
    super.key,
    required this.outcome,
    this.receipt,
  });

  @override
  State<PfConfirmationScreen> createState() => _PfConfirmationScreenState();
}

class _PfConfirmationScreenState extends State<PfConfirmationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _tickFired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..forward();
    // The mark lands at t≈1.0 but the eye reads the payoff at the amount
    // reveal (0.52–0.74 of the timeline) — fire the heavy haptic as the
    // headline lands there, once.
    _controller.addListener(() {
      if (!_tickFired && _controller.value >= 0.55) {
        _tickFired = true;
        _fireConfirmationPayoff();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outcome = widget.outcome;
    return Theme(
      data: PayFlexTheme.dark,
      child: Scaffold(
        backgroundColor: Colors.transparent, // reveal PfBackground waves
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PfSpace.xl,
              vertical: PfSpace.lg,
            ),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 36),
                        SizedBox(
                          width: 168,
                          height: 168,
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) => CustomPaint(
                              painter: PfMarkPainter(t: _controller.value),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _Reveal(
                          controller: _controller,
                          from: 0.45,
                          to: 0.66,
                          child: Text(
                            outcome.headline,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: PfColors.onNavy,
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Reveal(
                          controller: _controller,
                          from: 0.52,
                          to: 0.74,
                          child: _RevealTick(
                            controller: _controller,
                            fireAt: 0.74,
                            child: Text(
                              formatMoney(outcome.amount, outcome.currency),
                              textAlign: TextAlign.center,
                              style: PfMoneyType.large.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _Reveal(
                          controller: _controller,
                          from: 0.6,
                          to: 0.82,
                          child: Text(
                            outcome.caption ?? 'Settled through your PayFlex wallet',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: PfColors.onNavyMuted,
                              fontSize: 14.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _Reveal(
                          controller: _controller,
                          from: 0.62,
                          to: 0.86,
                          child: PfPanel(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            radius: PfRadius.sm,
                            showShadow: false,
                            child: Column(
                              children: [
                                _MetaRow(
                                  label: 'Reference',
                                  value: shortRef(outcome.reference),
                                  selectable: false,
                                ),
                                if (outcome.methodLabel != null) ...[
                                  const SizedBox(height: 10),
                                  _MetaRow(
                                    label: 'Method',
                                    value: outcome.methodLabel!,
                                  ),
                                ],
                                if (outcome.statusLabel != null) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      const Text(
                                        'Status',
                                        style: TextStyle(
                                          color: PfColors.onNavyMuted,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                      const Spacer(),
                                      PfStatusChip(
                                        label: outcome.statusLabel!,
                                        tone: outcome.statusTone,
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        // The credibility layer: when the reference is a
                        // real Stellar transaction hash, offer the public
                        // explorer. Anyone technical in the room can verify
                        // the payment is real — don't hide the rail.
                        if (isStellarTxHash(outcome.reference))
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _ExplorerChip(hash: outcome.reference),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _Reveal(
                  controller: _controller,
                  from: 0.68,
                  to: 0.9,
                  child: Column(
                    children: [
                      if (widget.receipt != null) ...[
                        PfSecondaryButton(
                          label: 'View receipt',
                          onPressed: () =>
                              showPfReceipt(context, outcome: widget.receipt!),
                          icon: Icons.receipt_long_outlined,
                          height: 48,
                        ),
                        const SizedBox(height: 10),
                      ],
                      PfPrimaryButton(
                        label: 'Done',
                        height: 52,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Official-looking receipt — amount hierarchy, reference, timestamp,
/// status badge, small flat logo mark (design brief §3). Paper surface,
/// designed rows, never a wall of raw JSON.
class PfReceiptScreen extends StatelessWidget {
  final PfFlowOutcome outcome;
  const PfReceiptScreen({super.key, required this.outcome});

  @override
  Widget build(BuildContext context) {
    final o = outcome;
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Receipt'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(PfSpace.xl),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: PfColors.navy,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(PfRadius.lg),
                    ),
                    boxShadow: PfShadow.onDark,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/brand/payflex_logo.png',
                            width: 26,
                            height: 26,
                            errorBuilder: (_, __, ___) => const PfMarkIcon(
                              size: 26,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'PayFlex',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            o.methodLabel ?? 'Receipt',
                            style: const TextStyle(
                              color: Color(0xB3FFFFFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        o.headline,
                        style: const TextStyle(
                          color: Color(0xB3FFFFFF),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatMoney(o.amount, o.currency),
                          style: PfMoneyType.large.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (o.caption != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          o.caption!,
                          style: const TextStyle(
                            color: PfColors.onNavyMuted,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          if (o.statusLabel != null)
                            PfStatusChip(
                              label: o.statusLabel!,
                              tone: o.statusTone,
                            ),
                          const Spacer(),
                          Text(
                            'PayFlex · ${o.currency}',
                            style: const TextStyle(
                              color: PfColors.onNavyMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: PfColors.surface,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(PfRadius.lg),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _ReceiptRow(
                        label: 'Reference',
                        value: o.reference,
                        selectable: true,
                      ),
                      if (o.caption != null)
                        _ReceiptRow(label: 'To', value: o.caption!),
                      _ReceiptRow(
                        label: 'Status',
                        value: o.statusLabel ?? 'Settling',
                      ),
                      const SizedBox(height: 4),
                      const _ReceiptRow(
                        label: 'Settlement',
                        value: 'Signed on your device · settled on Stellar',
                      ),
                      if (isStellarTxHash(o.reference))
                        _ExplorerReceiptRow(hash: o.reference),
                      const Divider(height: 24),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: Text(
                          'Kept for your records — PayFlex',
                          style: TextStyle(
                            color: PfColors.inkFaint,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool selectable;
  final VoidCallback? onTap;
  const _ReceiptRow({
    required this.label,
    required this.value,
    this.selectable = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      color: PfColors.ink,
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      height: 1.4,
    );
    final valueWidget = selectable
        ? SelectableText(value, style: textStyle)
        : Text(value,
            style: onTap != null
                ? textStyle.copyWith(color: PfColors.royalBlue)
                : textStyle,
            textAlign: TextAlign.right);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: PfColors.inkMuted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: onTap == null
                ? valueWidget
                : GestureDetector(onTap: onTap, child: valueWidget),
          ),
        ],
      ),
    );
  }
}

/// Small flat chip on the dark confirmation panel: opens the transaction
/// on a public Stellar explorer. Never shown for non-chain references.
/// Network (testnet vs mainnet) comes from the backend's config — cached
/// once per app run after the first look-up.
class _ExplorerChip extends StatefulWidget {
  final String hash;
  const _ExplorerChip({required this.hash});

  @override
  State<_ExplorerChip> createState() => _ExplorerChipState();
}

class _ExplorerChipState extends State<_ExplorerChip> {
  bool? _testnet;

  @override
  void initState() {
    super.initState();
    resolveTestnet().then((t) {
      if (mounted) setState(() => _testnet = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final testnet = _testnet;
    final label = testnet == null
        ? 'On the Stellar network · verify'
        : testnet
            ? 'On the Stellar testnet · verify'
            : 'On the Stellar network · verify';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(PfRadius.sm),
        onTap: testnet == null
            ? null
            : () => openStellarExplorer(widget.hash, testnet: testnet),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: PfColors.navyRaised2,
            borderRadius: BorderRadius.circular(PfRadius.sm),
            border: Border.all(color: PfColors.navyBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_outlined,
                  color: PfColors.accentOnDark, size: 15),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: PfColors.accentOnDark,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.open_in_new_rounded,
                  color: PfColors.accentOnDark, size: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Receipt variant of the explorer link — light-surface row that opens
/// the transaction on a public explorer.
class _ExplorerReceiptRow extends StatefulWidget {
  final String hash;
  const _ExplorerReceiptRow({required this.hash});

  @override
  State<_ExplorerReceiptRow> createState() => _ExplorerReceiptRowState();
}

class _ExplorerReceiptRowState extends State<_ExplorerReceiptRow> {
  bool? _testnet;

  @override
  void initState() {
    super.initState();
    resolveTestnet().then((t) {
      if (mounted) setState(() => _testnet = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final testnet = _testnet;
    return _ReceiptRow(
      label: 'Stellar',
      value: testnet == null
          ? 'Transaction hash (verifiable on any explorer)'
          : 'View on StellarExpert →',
      selectable: false,
      onTap: testnet == null
          ? null
          : () => openStellarExplorer(widget.hash, testnet: testnet),
    );
  }
}

Future<void> showPfReceipt(BuildContext context, {required PfFlowOutcome outcome}) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PfReceiptScreen(outcome: outcome)),
  );
}


/// Compact single-shot success (KYC done, escrow claimed, goal created…).
/// The ribbon draws once and settles; the dialog can't be dismissed
/// accidentally while it plays — the only action is [actionLabel].
Future<void> showPfSimpleSuccess(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = 'Done',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PfSuccessDialog(
      title: title,
      message: message,
      actionLabel: actionLabel,
    ),
  );
}

class _PfSuccessDialog extends StatefulWidget {
  final String title;
  final String message;
  final String actionLabel;
  const _PfSuccessDialog({
    required this.title,
    required this.message,
    required this.actionLabel,
  });

  @override
  State<_PfSuccessDialog> createState() => _PfSuccessDialogState();
}

class _PfSuccessDialogState extends State<_PfSuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.dark,
      child: Dialog(
        backgroundColor: PfColors.navyRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PfRadius.lg),
          side: const BorderSide(color: PfColors.navyBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: PfMarkPainter(t: _controller.value),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _Reveal(
                controller: _controller,
                from: 0.5,
                to: 0.72,
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: PfColors.onNavy,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _Reveal(
                controller: _controller,
                from: 0.6,
                to: 0.84,
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: PfColors.onNavyMuted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              PfPrimaryButton(
                label: widget.actionLabel,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fires one light haptic tick when the shared controller passes
/// [fireAt] — the "numbers landed" beat after the heavy impact.
class _RevealTick extends StatefulWidget {
  final AnimationController controller;
  final double fireAt;
  final Widget child;
  const _RevealTick({
    required this.controller,
    required this.fireAt,
    required this.child,
  });

  @override
  State<_RevealTick> createState() => _RevealTickState();
}

class _RevealTickState extends State<_RevealTick> {
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!_fired && widget.controller.value >= widget.fireAt) {
      _fired = true;
      _fireRevealTick();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Fade-and-rise reveal gated to an interval of the shared controller.
class _Reveal extends StatelessWidget {
  final AnimationController controller;
  final double from;
  final double to;
  final Widget child;
  const _Reveal({
    required this.controller,
    required this.from,
    required this.to,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = CurvedAnimation(
      parent: controller,
      curve: Interval(from, to, curve: Curves.easeOut),
    );
    final offset = CurvedAnimation(
      parent: controller,
      curve: Interval(from, to, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(offset),
        child: child,
      ),
    );
  }
}

/// Meta row used on the dark confirmation panel.
class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final bool selectable;
  const _MetaRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: PfColors.onNavyMuted, fontSize: 12.5),
        ),
        const Spacer(),
        Flexible(
          child: selectable
              ? SelectableText(
                  value,
                  style: const TextStyle(
                    color: PfColors.onNavy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Text(
                  value,
                  style: const TextStyle(
                    color: PfColors.onNavy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ],
    );
  }
}
