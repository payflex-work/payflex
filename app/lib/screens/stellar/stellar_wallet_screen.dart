import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../stellar/stellar_client.dart';
import '../../stellar/stellar_key_service.dart';
import '../../stellar/stellar_models.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../widgets/pf_balance_card.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_motion.dart';
import '../../widgets/pf_states.dart';
import 'stellar_add_asset_screen.dart';
import 'stellar_send_screen.dart';

/// PayFlex's Stellar rail — an additional, OPTIONAL wallet that sits
/// alongside the primary BMONI wallet, never routed through it. See
/// the root README's "Stellar rail" section for the full architecture and why this exists.
///
/// This screen is honest about state at every step: not opted in yet ->
/// opted in but not funded on-chain -> funded, with real balances,
/// trustlines, and history. Never implies "your money is here" before
/// the account is actually activated on the Stellar network.
class StellarWalletScreen extends StatefulWidget {
  const StellarWalletScreen({super.key});

  @override
  State<StellarWalletScreen> createState() => _StellarWalletScreenState();
}

enum _StellarWalletState { loading, notOptedIn, unfunded, funded, error }

class _StellarWalletScreenState extends State<StellarWalletScreen> {
  final _api = ApiClient();
  StellarClient? _client;
  String? _publicKey;
  StellarAccountSummary? _summary;
  List<StellarHistoryEntry> _history = [];
  _StellarWalletState _state = _StellarWalletState.loading;
  String? _error;
  bool _funding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _state = _StellarWalletState.loading;
      _error = null;
    });
    try {
      final networkInfo = await _api.getStellarNetwork();
      _client = StellarClient.fromNetworkInfo(networkInfo);

      final optedIn = await StellarKeyService.hasOptedIn();
      if (!optedIn) {
        setState(() => _state = _StellarWalletState.notOptedIn);
        return;
      }

      final keyPair = await StellarKeyService.getOrCreateKeyPair();
      _publicKey = keyPair.accountId;

      final funded = await _client!.isAccountFunded(_publicKey!);
      if (!funded) {
        setState(() => _state = _StellarWalletState.unfunded);
        return;
      }

      final summary = await _client!.getAccountSummary(_publicKey!);
      final history = await _client!.getHistory(_publicKey!);
      setState(() {
        _summary = summary;
        _history = history;
        _state = _StellarWalletState.funded;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _state = _StellarWalletState.error;
      });
    }
  }

  Future<void> _optIn() async {
    await StellarKeyService.getOrCreateKeyPair();
    await _load();
  }

  Future<void> _fundViaFriendbot() async {
    setState(() => _funding = true);
    try {
      await _client!.fundViaFriendbot(_publicKey!);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _funding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.light,
      child: Scaffold(
        backgroundColor: PfColors.offWhite,
        appBar: AppBar(
          title: const Text('Stellar wallet'),
          backgroundColor: PfColors.offWhite,
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline_rounded, color: PfColors.inkFaint),
              tooltip: 'About this wallet',
              onPressed: () => _showAboutSheet(context),
            ),
          ],
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    switch (_state) {
      case _StellarWalletState.loading:
        return const Center(child: PfBrandedLoader(size: 52));
      case _StellarWalletState.error:
        return Center(child: Padding(padding: const EdgeInsets.all(PfSpace.xl), child: PfInlineError(message: _error!, onRetry: _load)));
      case _StellarWalletState.notOptedIn:
        return _notOptedInView();
      case _StellarWalletState.unfunded:
        return _unfundedView();
      case _StellarWalletState.funded:
        return _fundedView();
    }
  }

  Widget _notOptedInView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PfSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PfEmptyState(
              icon: Icons.hub_outlined,
              title: 'An optional Stellar wallet',
              message:
                  'This is a second, separate wallet on the Stellar network — a real '
                  'blockchain, not BMONI. It sits alongside your main PayFlex wallet, '
                  'never replaces it. Your BMONI wallet stays the regulated, KYC\'d '
                  'account this app is built on; Stellar is here for people who want '
                  'a crypto-native option too.',
            ),
            const SizedBox(height: PfSpace.lg),
            PfPrimaryButton(label: 'Create my Stellar wallet', onPressed: _optIn),
          ],
        ),
      ),
    );
  }

  Widget _unfundedView() {
    final isTestnet = _client != null; // network info already resolved by this point
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PfSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PfEmptyState(
              icon: Icons.hourglass_empty_rounded,
              title: 'Not activated yet',
              message:
                  'Your Stellar address exists, but every Stellar account needs a small '
                  'minimum XLM balance before it can hold or send anything — it isn\'t '
                  'usable until that first funding lands on-chain.\n\n'
                  '${_publicKey ?? ''}',
            ),
            const SizedBox(height: PfSpace.lg),
            if (isTestnet)
              PfPrimaryButton(
                label: 'Fund with testnet Friendbot',
                busy: _funding,
                onPressed: _funding ? null : _fundViaFriendbot,
              )
            else
              const Text(
                'On mainnet, send a real minimum-balance XLM payment to this address '
                'from an already-funded account to activate it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PfColors.inkMuted, fontSize: 12.5),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fundedView() {
    final summary = _summary!;
    return RefreshIndicator(
      onRefresh: _load,
      color: PfColors.royalBlue,
      child: ListView(
        padding: const EdgeInsets.all(PfSpace.lg),
        children: [
          PfPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your Stellar address', style: TextStyle(color: PfColors.inkFaint, fontSize: 11.5)),
                const SizedBox(height: 4),
                SelectableText(
                  summary.publicKey,
                  style: const TextStyle(color: PfColors.ink, fontSize: 12.5, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          const SizedBox(height: PfSpace.lg),
          const PfSectionHeader(title: 'Balances'),
          const SizedBox(height: PfSpace.sm),
          ...summary.balances.map(_balanceTile),
          const SizedBox(height: PfSpace.lg),
          Row(
            children: [
              Expanded(
                child: PfPrimaryButton(
                  label: 'Send',
                  onPressed: () => _openSend(),
                ),
              ),
              const SizedBox(width: PfSpace.md),
              Expanded(
                child: OutlinedButton(
                  onPressed: _openAddAsset,
                  child: const Text('Add asset'),
                ),
              ),
            ],
          ),
          const SizedBox(height: PfSpace.xl),
          const PfSectionHeader(title: 'Recent activity'),
          const SizedBox(height: PfSpace.sm),
          if (_history.isEmpty)
            const PfEmptyState(
              compact: true,
              icon: Icons.history_rounded,
              title: 'No activity yet',
              message: 'Payments you send or receive on this address will show up here.',
            )
          else
            ..._history.map(_historyTile),
        ],
      ),
    );
  }

  Widget _balanceTile(StellarBalance b) {
    return PfPanel(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.displayCode, style: const TextStyle(color: PfColors.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                if (!b.isNative)
                  Text(
                    'Issuer: ${b.assetIssuer}',
                    style: const TextStyle(color: PfColors.inkFaint, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(b.balance, style: const TextStyle(color: PfColors.ink, fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _historyTile(StellarHistoryEntry h) {
    return PfPanel(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.type, style: const TextStyle(color: PfColors.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(
                  h.transactionHash,
                  style: const TextStyle(color: PfColors.inkFaint, fontSize: 11, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSend() async {
    if (_summary == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StellarSendScreen(client: _client!, summary: _summary!)),
    );
    _load();
  }

  Future<void> _openAddAsset() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StellarAddAssetScreen(client: _client!)),
    );
    _load();
  }

  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: PfColors.offWhite,
      builder: (context) => const Padding(
        padding: EdgeInsets.all(PfSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About the Stellar wallet', style: TextStyle(color: PfColors.ink, fontSize: 16, fontWeight: FontWeight.w700)),
            SizedBox(height: 10),
            Text(
              'This is a separate, optional rail on the real Stellar network — a '
              'public blockchain, not BMONI. Your Stellar key lives only on this '
              'device and is never sent to PayFlex\'s servers.\n\n'
              'Unlike BMONI transfers, Stellar payments are irreversible the moment '
              'they confirm on-chain — there is no undo. Double-check every address '
              'before sending.',
              style: TextStyle(color: PfColors.inkMuted, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
