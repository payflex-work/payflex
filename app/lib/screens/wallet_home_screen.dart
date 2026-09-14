import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../models/transfer.dart';
import '../services/api_client.dart';
import '../services/retry.dart';
import '../theme/payflex_tokens.dart';
import '../theme/payflex_theme.dart';
import '../utils/format.dart';
import '../utils/money.dart';
import '../utils/stellar_tx.dart';
import '../widgets/pf_balance_card.dart';
import '../widgets/pf_mark.dart';
import '../widgets/pf_motion.dart';
import '../widgets/pf_states.dart';
import 'settings_screen.dart';
import 'transfer/send_money_screen.dart';
import 'transfer/qr_pay_screen.dart';
import 'transfer/paytag_screen.dart';
import 'safebox/safebox_list_screen.dart';
import 'standing_plans/standing_plans_screen.dart';
import 'admin_screen.dart';
import 'virtual_card_screen.dart';
import 'betting_screen.dart';
import 'savings/savings_screen.dart';
import 'loans/loans_screen.dart';
import 'agent/agent_screen.dart';
import 'split_bill/split_bill_screen.dart';
import 'links/send_via_link_screen.dart';
import 'stellar/stellar_wallet_screen.dart';
import '../services/offline_redemption_service.dart';

/// Wallet home — the dark navy anchor of the app. The user IS a Stellar
/// account: the balance card shows their on-chain XLM (and any issued
/// assets they hold), recent activity merges the backend's verified
/// transfer records with pending offline Reserve spends. Everything else
/// hangs off the header menu; paused features are labelled honestly.
class WalletHomeScreen extends StatefulWidget {
  final AppUser user;
  const WalletHomeScreen({super.key, required this.user});

  @override
  State<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends State<WalletHomeScreen> {
  final _api = ApiClient();
  List<AccountBalance> _balances = [];
  List<TransferRecord> _recent = [];
  bool _loading = true;
  bool _offline = false;
  String? _error;
  String? _stellarKey;

  // Balance count-up runs once per app session, not on every refresh.
  static bool _balanceRevealed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _offline = false;
      _error = null;
    });
    try {
      _stellarKey = widget.user.stellarPublicKey;
      if (_stellarKey == null) {
        throw StateError(
          'No Stellar key registered for this account — finish onboarding first.',
        );
      }

      // On-chain balances via the backend's throttled Horizon proxy.
      final account = await withRetry(() => _api.getStellarAccount(_stellarKey!));
      final balances = (account['balances'] as List)
          .map((e) => AccountBalance.fromJson(e as Map<String, dynamic>))
          .toList();

      // The app's own verified transfer records.
      List<TransferRecord> recent = [];
      try {
        recent = await _api.listTransfers(widget.user.id);
      } catch (_) {
        recent = [];
      }

      // Merge local offline transactions (not yet settled on-chain).
      try {
        final offlineRecords = await OfflineRedemptionService().loadRecords();
        for (final rec in offlineRecords) {
          final alreadyPresent =
              recent.any((t) => t.stellarTxHash == rec.stellarTxHash);
          if (!alreadyPresent) {
            recent.insert(
              0,
              TransferRecord(
                id: rec.authorizationId,
                stellarTxHash: rec.stellarTxHash ?? rec.authorizationId,
                fromPublicKey: _stellarKey!,
                toPublicKey: rec.merchantId,
                amount: rec.amountDecimal,
                assetCode: rec.currency,
                kind: 'OFFLINE_REDEMPTION',
                memo: rec.status == RedemptionStatus.settled
                    ? 'Settled'
                    : 'Offline · settlement pending',
                createdAt: rec.createdAt.toIso8601String(),
              ),
            );
          }
        }
      } catch (_) {}

      setState(() {
        _balances = balances;
        _recent = recent;
      });
    } on OfflineException catch (e) {
      setState(() {
        _offline = true;
        _error = e.toString();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  AccountBalance? get _primary {
    for (final b in _balances) {
      if (b.isNative) return b;
    }
    return _balances.isEmpty ? null : _balances.first;
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.dark,
      child: Scaffold(
        backgroundColor: Colors.transparent, // reveal PfBackground waves
        body: Stack(
          children: [
            // Flat watermark of the ribbon, low opacity, behind content.
            const Positioned(
              top: 120,
              right: -140,
              child: PfWatermark(size: 380),
            ),
            SafeArea(
              child: Column(
                children: [
                  _header(),
                  Expanded(child: _body()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final firstName = widget.user.firstName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(PfSpace.xl, PfSpace.lg, PfSpace.md, 4),
      child: Row(
        children: [
          Image.asset(
            'assets/brand/payflex_logo.png',
            width: 34,
            height: 34,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const PfMarkIcon(size: 30, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hi, $firstName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PfColors.onNavy,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  'Your Stellar wallet',
                  style: TextStyle(color: PfColors.onNavyMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          _HeaderIconButton(
            icon: Icons.alternate_email_outlined,
            tooltip: 'PayTag',
            onTap: () => _push(PayTagScreen(user: widget.user)),
          ),
          _HeaderIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Settings',
            onTap: () => _push(SettingsScreen(user: widget.user)),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: PfColors.onNavy,
              size: 24,
            ),
            tooltip: 'More',
            color: PfColors.navyRaised2,
            surfaceTintColor: Colors.transparent,
            onSelected: (value) {
              final screen = switch (value) {
                'safebox' => SafeboxListScreen(user: widget.user),
                'standing-plans' => StandingPlansScreen(user: widget.user),
                'admin' => AdminScreen(user: widget.user),
                'virtual-card' => const VirtualCardScreen(),
                'betting' => const BettingScreen(),
                'stellar' => const StellarWalletScreen(),
                'savings' => const SavingsScreen(),
                'loans' => const LoansScreen(),
                'agent' => const AgentScreen(),
                'split-bill' => SplitBillScreen(user: widget.user),
                'send-via-link' => SendViaLinkScreen(user: widget.user),
                _ => null,
              };
              if (screen != null) _push(screen);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'safebox', child: Text('Safebox savings')),
              PopupMenuItem(value: 'standing-plans', child: Text('Standing plans')),
              PopupMenuItem(value: 'split-bill', child: Text('Split bills')),
              PopupMenuItem(value: 'send-via-link', child: Text('Send via link')),
              PopupMenuItem(value: 'stellar', child: Text('Stellar details')),
              PopupMenuItem(value: 'admin', child: Text('Admin')),
              PopupMenuDivider(),
              // Paused pending real fiat/KYC providers — honest states, see
              // docs/fiat-kyc-gap.md. Not hidden: reachable and refused.
              PopupMenuItem(value: 'virtual-card', child: Text('Virtual card (coming soon)')),
              PopupMenuItem(value: 'agent', child: Text('Agent mode (coming soon)')),
              PopupMenuItem(value: 'betting', child: Text('Betting funding (coming soon)')),
              PopupMenuItem(value: 'savings', child: Text('Savings goals (paused)')),
              PopupMenuItem(value: 'loans', child: Text('Loans (paused)')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _balances.isEmpty) {
      return const Center(child: PfBrandedLoader(size: 56));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: PfColors.emerald,
      backgroundColor: PfColors.navyRaised2,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(PfSpace.xl, 12, PfSpace.xl, 120),
        children: [
          if (_offline)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: PfInlineError(
                message: _error ?? "You're offline — showing what we cached.",
                onRetry: _load,
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: PfInlineError(message: _error!, onRetry: _load),
            ),
          if (_balances.isEmpty && _error == null)
            const PfEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Account not activated yet',
              message:
                  'Your Stellar account needs its first funding to hold or '
                  'send anything. On testnet, Friendbot can do it instantly.',
            ),
          ..._walletSection(),
          const SizedBox(height: 6),
          _actionsRow(),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 28),
            _recentHeader(),
            const SizedBox(height: 8),
            ..._recent.take(5).map((t) => _RecentTxRow(record: t)),
          ],
        ],
      ),
    );
  }

  List<Widget> _walletSection() {
    final primary = _primary;
    if (primary == null) return const [];
    final rest = _balances.where((b) => b != primary).toList();
    // Count up only on the first reveal this session — mutating this
    // directly (rather than a collection-if inside the list below) since
    // it only needs to affect a *future* build, not this one.
    final countUp = !_balanceRevealed;
    _balanceRevealed = true;
    return [
      PfBalanceCard(
        currency: primary.displayCode,
        amount: primary.balance,
        countUp: countUp,
        statusLabel: 'Active',
        address: _stellarKey ?? '',
        onTap: () => _push(const StellarWalletScreen()),
      ),
      const SizedBox(height: 6),
      ...rest.map(
        (b) => PfWalletRow(
          currency: b.displayCode,
          amount: b.balance,
          address: b.assetIssuer ?? '',
          active: true,
          onTap: () => _push(const StellarWalletScreen()),
        ),
      ),
    ];
  }

  Widget _actionsRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 128,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PfRadius.md),
              boxShadow: PfShadow.button,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PfRadius.md),
              child: Material(
                color: Colors.transparent,
                child: Ink(
                  decoration: const BoxDecoration(gradient: PfGradient.primary),
                  child: InkWell(
                    onTap: () => _push(SendMoneyScreen(user: widget.user)),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.north_east_rounded, color: Colors.white, size: 22),
                          Spacer(),
                          Text(
                            'Send money',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'PayTag · Stellar address',
                            style: TextStyle(
                              color: Color(0xB3FFFFFF),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 128,
            decoration: BoxDecoration(
              color: PfColors.navyRaised,
              borderRadius: BorderRadius.circular(PfRadius.md),
              border: Border.all(color: PfColors.navyBorder),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _push(QrPayScreen(user: widget.user)),
                borderRadius: BorderRadius.circular(PfRadius.md),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.qr_code_rounded, color: PfColors.onNavy, size: 22),
                      Spacer(),
                      Text(
                        'QR Pay',
                        style: TextStyle(
                          color: PfColors.onNavy,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Scan or share a request',
                        style: TextStyle(
                          color: PfColors.onNavyMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _recentHeader() {
    return const Row(
      children: [
        Expanded(child: PfSectionHeader(title: 'Recent activity')),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: PfColors.onNavy, size: 22),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}

/// A single recent-activity row: flat direction glyph in a quiet circle,
/// formatted amount, status + relative date.
class _RecentTxRow extends StatelessWidget {
  final TransferRecord record;
  const _RecentTxRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final t = record;
    final isOut = t.fromPublicKey == _ownerKey;
    final tone = t.kind == 'OFFLINE_REDEMPTION' && t.memo?.contains('pending') == true
        ? PfTone.info
        : PfTone.success;

    final onChain = isStellarTxHash(t.stellarTxHash);
    final row = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isOut ? PfColors.navyRaised2 : PfColors.emerald.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOut ? Icons.north_east_rounded : Icons.south_west_rounded,
              size: 17,
              color: isOut ? PfColors.onNavyMuted : PfColors.emerald,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOut ? 'Sent' : 'Received',
                  style: const TextStyle(
                    color: PfColors.onNavy,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: humanTransferStatus(t.kind),
                        style: TextStyle(color: switch (tone) {
                          PfTone.warn => const Color(0xFFFFD28A),
                          PfTone.success => const Color(0xFF62E39A),
                          PfTone.info || PfTone.muted => PfColors.onNavyFaint,
                        }),
                      ),
                      TextSpan(
                        text: ' · ${formatTimestamp(t.createdAt)}',
                        style: const TextStyle(color: PfColors.onNavyFaint),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            '${isOut ? '−' : '+'}${formatMoney(t.amount, t.assetCode)}',
            style: TextStyle(
              color: isOut ? PfColors.onNavyMuted : Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onChain) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.open_in_new_rounded,
              color: PfColors.onNavyFaint,
              size: 15,
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
    );

    // Real on-chain payments get a tap-through to the public explorer;
    // pending offline spends (no chain hash yet) stay inert.
    if (!onChain) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(PfRadius.sm),
        onTap: () async {
          final testnet = await resolveTestnet();
          openStellarExplorer(t.stellarTxHash, testnet: testnet);
        },
        child: row,
      ),
    );
  }
}

/// Set once per load from the authenticated user's registered key — used
/// only for the Sent/Received direction glyph.
String? _ownerKey;
