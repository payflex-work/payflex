import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/api_client.dart';
import '../theme/payflex_tokens.dart';
import '../theme/payflex_theme.dart';
import '../widgets/pf_balance_card.dart';
import '../widgets/pf_buttons.dart';
import '../widgets/pf_motion.dart';
import '../widgets/pf_states.dart';

/// There is no client-side admin gate here — the backend rejects every
/// call with 403 unless the caller's own account is flagged isAdmin
/// (AdminGuard). This screen shows a plain "admin access required" state
/// on that 403 rather than pretending the check happens client-side; the
/// menu entry itself is visible to everyone, same as any other screen —
/// the real boundary is server-side, not "can they find the button."
class AdminScreen extends StatefulWidget {
  final AppUser user;
  const AdminScreen({super.key, required this.user});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _api = ApiClient();
  Map<String, dynamic>? _stats;
  bool _loading = true;
  bool _forbidden = false;
  String? _error;
  bool _triggering = false;
  String? _triggerResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _forbidden = false;
    });
    try {
      final stats = await _api.getAdminStats();
      setState(() => _stats = stats);
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        setState(() => _forbidden = true);
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _triggerSavingsDueCheck() async {
    setState(() {
      _triggering = true;
      _triggerResult = null;
    });
    try {
      final res = await _api.triggerSavingsDueCheck();
      setState(() => _triggerResult =
          'Savings: ${res['contributionsCreated']} contribution(s) now due across ${res['goalsChecked']} goal(s).');
    } catch (e) {
      setState(() => _triggerResult = e.toString());
    } finally {
      if (mounted) setState(() => _triggering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(title: const Text('Admin'), backgroundColor: PfColors.offWhite),
        body: _loading
            ? const Center(child: PfBrandedLoader(size: 52))
            : _forbidden
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(PfSpace.xl),
                      child: PfEmptyState(
                        icon: Icons.lock_outline_rounded,
                        title: 'Admin access required',
                        message: "Your account isn't flagged as an admin. "
                            'An existing admin can grant access, or run '
                            "`npm run provision:admin` for the first one.",
                      ),
                    ),
                  )
                : _error != null
                    ? Center(child: PfInlineError(message: _error!, onRetry: _load))
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: PfColors.royalBlue,
                        child: ListView(
                          padding: const EdgeInsets.all(PfSpace.lg),
                          children: [
                            const PfSectionHeader(title: 'Operational stats'),
                            const SizedBox(height: PfSpace.sm),
                            _statsGrid(),
                            const SizedBox(height: PfSpace.xl),
                            const PfSectionHeader(title: 'Actions'),
                            const SizedBox(height: PfSpace.sm),
                            PfPanel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Run savings due-check now',
                                    style: TextStyle(color: PfColors.ink, fontSize: 14.5, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    "Marks any savings goal's contribution due immediately, "
                                    'rather than waiting for the hourly scheduler.',
                                    style: TextStyle(color: PfColors.inkMuted, fontSize: 12.5, height: 1.4),
                                  ),
                                  const SizedBox(height: 14),
                                  PfPrimaryButton(
                                    label: 'Run due-check',
                                    busy: _triggering,
                                    onPressed: _triggering ? null : _triggerSavingsDueCheck,
                                  ),
                                  if (_triggerResult != null) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      _triggerResult!,
                                      style: const TextStyle(color: PfColors.inkFaint, fontSize: 12),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }

  Widget _statsGrid() {
    final s = _stats!;
    final loansByStatus = (s['loansByStatus'] as Map<String, dynamic>? ?? {});
    final tiles = <(String, String)>[
      ('Total users', '${s['totalUsers']}'),
      ('Agents', '${s['totalAgents']}'),
      ('Admins', '${s['totalAdmins']}'),
      ('Safeboxes', '${s['totalSafeboxes']}'),
      ('Savings goals', '${s['totalSavingsGoals']}'),
      ('Split bills', '${s['totalSplitBills']}'),
      ('Pending escrowed links', '${s['pendingEscrowedLinks']}'),
      ('Agent transactions', '${s['totalAgentTransactions']}'),
      for (final entry in loansByStatus.entries) ('Loans: ${entry.key}', '${entry.value}'),
    ];

    return Wrap(
      spacing: PfSpace.sm,
      runSpacing: PfSpace.sm,
      children: tiles
          .map(
            (t) => SizedBox(
              width: 160,
              child: PfPanel(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.$2, style: PfMoneyType.small.copyWith(color: PfColors.ink)),
                    const SizedBox(height: 4),
                    Text(t.$1, style: const TextStyle(color: PfColors.inkFaint, fontSize: 11.5)),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
