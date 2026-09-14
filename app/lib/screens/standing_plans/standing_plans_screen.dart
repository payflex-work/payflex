import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/microfinance.dart';
import '../../services/api_client.dart';
import '../../services/transfer_flow.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../utils/format.dart';
import '../../utils/money.dart';
import '../../widgets/pf_balance_card.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_flow.dart';
import '../../widgets/pf_motion.dart';
import '../../widgets/pf_states.dart';

/// Recurring payments — PayFlex's own scheduled-payment layer on Stellar.
/// The scheduler can only mark a payment DUE (no delegated debit exists
/// on Stellar, and this app refuses to pretend otherwise — the
/// pre-authorization question stays open and honest). Paying a due
/// payment is the normal on-device flow: PIN → build → sign → submit →
/// record (verified) → report against the plan.
class StandingPlansScreen extends StatefulWidget {
  final AppUser user;
  const StandingPlansScreen({super.key, required this.user});

  @override
  State<StandingPlansScreen> createState() => _StandingPlansScreenState();
}

class _StandingPlansScreenState extends State<StandingPlansScreen> {
  final _api = ApiClient();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _recipientController = TextEditingController();
  String _assetCode = 'XLM';
  String _frequency = 'MONTHLY';
  List<StandingPlan> _plans = [];
  final Map<String, List<StandingPlanPayment>> _duePaymentsByPlan = {};
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _recipientController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final plans = await _api.listStandingPlans(widget.user.id);
      final due = await _api.listDueStandingPlanPayments(widget.user.id);
      _duePaymentsByPlan.clear();
      for (final payment in due) {
        final planId = payment.plan?.id;
        if (planId == null) continue;
        _duePaymentsByPlan.putIfAbsent(planId, () => []).add(payment);
      }
      setState(() => _plans = plans);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final recipient = _recipientController.text.trim();
    if (_nameController.text.trim().isEmpty || _amountController.text.trim().isEmpty || recipient.isEmpty) {
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      // Accept either a @PayTag or a raw Stellar address in the same
      // field — the backend resolves a PayTag to a key at creation time.
      final isPayTag = recipient.startsWith('@');
      await _api.createStandingPlan(
        widget.user.id,
        name: _nameController.text.trim(),
        assetCode: _assetCode,
        amount: _amountController.text.trim(),
        frequency: _frequency,
        toPayTag: isPayTag ? recipient.substring(1) : null,
        toPublicKey: isPayTag ? null : recipient,
      );
      _nameController.clear();
      _amountController.clear();
      _recipientController.clear();
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _pay(StandingPlanPayment payment) async {
    try {
      final plan = payment.plan;
      if (plan?.toPublicKey == null) {
        throw StateError('This plan has no resolved destination key.');
      }
      // PIN → build → sign on-device → submit → record (kind=STANDING_PLAN).
      final result = await signAndSubmitTransfer(
        context,
        _api,
        widget.user.id,
        toPublicKey: plan!.toPublicKey!,
        amount: payment.amount,
        assetCode: plan.assetCode,
        assetIssuer: plan.assetIssuer,
        kind: TransferKind.standingPlan,
        standingPlanId: payment.id,
      );
      if (!mounted) return;
      if (result == null) return; // cancelled at the PIN prompt
      if (result.success) {
        // Report it against the plan — the backend cross-checks the
        // verified TransferRecord referencing this payment.
        await _api.recordStandingPlanPayment(
          widget.user.id,
          payment.id,
          result.transactionHash!,
        );
        if (!mounted) return;
        await showPfConfirmation(
          context,
          outcome: outcomeForPayment(
            result,
            headline: 'Payment sent',
            amount: payment.amount,
            assetCode: plan.assetCode,
            caption: plan.name.isNotEmpty ? 'Standing plan: ${plan.name}' : null,
            methodLabel: 'Standing plan',
          ),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _togglePause(StandingPlan plan) async {
    final next = plan.status == 'PAUSED' ? 'ACTIVE' : 'PAUSED';
    try {
      await _api.setStandingPlanStatus(widget.user.id, plan.id, next);
      await _load();
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
        appBar: AppBar(title: const Text('Standing plans'), backgroundColor: PfColors.offWhite),
        body: _loading && _plans.isEmpty
            ? const Center(child: PfBrandedLoader(size: 52))
            : RefreshIndicator(
                onRefresh: _load,
                color: PfColors.royalBlue,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(PfSpace.xl, 8, PfSpace.xl, 48),
                  children: [
                    if (_error != null) ...[
                      PfInlineError(message: _error!, onRetry: _load),
                      const SizedBox(height: 14),
                    ],
                    _createPanel(),
                    const SizedBox(height: 24),
                    const PfSectionHeader(title: 'Your standing plans'),
                    const SizedBox(height: 10),
                    if (_plans.isEmpty && _error == null)
                      const PfEmptyState(
                        compact: true,
                        icon: Icons.event_repeat_outlined,
                        title: 'No standing plans yet',
                        message: 'Set up a recurring payment to a PayTag or address — '
                            "you'll still sign each one when it's due.",
                      ),
                    ..._plans.map(_planCard),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _createPanel() {
    return PfPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'New standing plan',
            style: TextStyle(color: PfColors.ink, fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            "Marked due on schedule, but never sent without you signing it "
            '— there is no way to pre-authorize a debit on Stellar.',
            style: TextStyle(color: PfColors.inkMuted, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name (e.g. Rent)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _recipientController,
            decoration: const InputDecoration(
              labelText: 'Recipient',
              hintText: '@paytag or a Stellar address (G…)',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                width: 110,
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
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _frequency,
            decoration: const InputDecoration(labelText: 'Frequency'),
            items: const [
              DropdownMenuItem(value: 'DAILY', child: Text('Daily')),
              DropdownMenuItem(value: 'WEEKLY', child: Text('Weekly')),
              DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly')),
            ],
            onChanged: (v) => setState(() => _frequency = v!),
          ),
          const SizedBox(height: 14),
          PfPrimaryButton(
            label: 'Create plan',
            busy: _creating,
            onPressed: _creating ? null : _create,
          ),
        ],
      ),
    );
  }

  Widget _planCard(StandingPlan plan) {
    final due = _duePaymentsByPlan[plan.id] ?? [];
    final isPaused = plan.status == 'PAUSED';
    final destination =
        plan.toPayTag != null ? '@${plan.toPayTag}' : shortRef(plan.toPublicKey ?? '');
    return PfPanel(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(color: PfColors.ink, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formatMoney(plan.amount, plan.assetCode)} · ${plan.frequency.toLowerCase()} '
                      '· to $destination',
                      style: const TextStyle(color: PfColors.inkMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              PfStatusChip(
                label: isPaused ? 'Paused' : 'Active',
                tone: isPaused ? PfTone.muted : PfTone.success,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Total paid: ${formatMoney(plan.totalPaid, plan.assetCode)}',
                style: const TextStyle(color: PfColors.inkFaint, fontSize: 12),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _togglePause(plan),
                child: Text(isPaused ? 'Resume' : 'Pause'),
              ),
            ],
          ),
          if (due.isNotEmpty) ...[
            const Divider(height: 22),
            ...due.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${formatMoney(p.amount, plan.assetCode)} due',
                        style: const TextStyle(color: PfColors.ink, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    PfGradientChip(label: 'Pay', onPressed: () => _pay(p)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
