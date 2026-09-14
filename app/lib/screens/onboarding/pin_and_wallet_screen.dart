import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../services/api_client.dart';
import '../../services/session_manager.dart';
import '../../services/wallet_service.dart';
import '../../stellar/stellar_client.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_motion.dart';
import '../../widgets/pf_balance_card.dart';
import '../../widgets/pf_states.dart';
import '../wallet_home_screen.dart';

/// Onboarding steps 2-4, Stellar-native:
///
///   1. Set the 6-digit PIN that will gate every signature on this device.
///   2. Generate the user's Stellar keypair ON THIS DEVICE (secure
///      storage) and register its public key with the backend using the
///      one-time bootstrap token.
///   3. Log in (challenge signed with the new key) and fund the account
///      via Friendbot on testnet — mainnet funding is a deliberate manual
///      act, never automated here.
///
/// The secret seed never leaves the device; only the public key crosses
/// the network. Everything that touches key material goes through
/// WalletService / StellarKeyService — never inline here.
class PinAndWalletScreen extends StatefulWidget {
  final AppUser user;
  final String? bootstrapToken;
  const PinAndWalletScreen({super.key, required this.user, this.bootstrapToken});

  @override
  State<PinAndWalletScreen> createState() => _PinAndWalletScreenState();
}

enum _Step { setPin, generateKey, fund, done }

class _PinAndWalletScreenState extends State<PinAndWalletScreen> {
  final _api = ApiClient();
  final _pinController = TextEditingController();
  _Step _step = _Step.setPin;
  String? _error;
  bool _busy = false;
  String? _publicKey;
  StellarClient? _client;
  bool _funded = false;
  String? _pin;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (await WalletService.hasPin()) {
      // Returning to a half-finished onboarding: the key already exists.
      _publicKey = await WalletService.currentAddress();
      if (_publicKey != null) {
        await _enterApp();
        return;
      }
    }
    if (mounted) setState(() => _step = _Step.setPin);
  }

  Future<void> _submitPin() async {
    if (_pinController.text.length != 6) {
      setState(() => _error = 'PIN must be exactly 6 digits');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _pin = _pinController.text;
      setState(() => _step = _Step.generateKey);
      await _generateAndRegisterKey();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateAndRegisterKey() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Generates on-device (secure storage) and sets the PIN verifier.
      _publicKey = await WalletService.provisionWallet(_pin!);

      // Register the PUBLIC key — the bootstrap token is scoped to exactly
      // this one call (see AuthGuard on the backend).
      await _api.setStellarPublicKey(
        widget.user.id,
        _publicKey!,
        bootstrapToken: widget.bootstrapToken,
      );

      // Real login now: the challenge is signed with the new key, proving
      // on-device ownership, so every route from here has an access token.
      await SessionManager.login(widget.user.id, _pin!);

      final network = await _api.getStellarNetwork();
      _client = StellarClient.fromNetworkInfo(network);

      _funded = await _client!.isAccountFunded(_publicKey!);
      if (!mounted) return;
      setState(() => _step = _funded ? _Step.done : _Step.fund);
      if (_funded) await _enterApp();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fundViaFriendbot() async {
    if (_client == null || _publicKey == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _client!.fundViaFriendbot(_publicKey!);
      await _api.confirmActivation(widget.user.id);
      if (!mounted) return;
      setState(() => _step = _Step.done);
      await _enterApp();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterApp() async {
    if (!mounted) return;
    final user = await _api.getUser(widget.user.id);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => WalletHomeScreen(user: user)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.dark,
      child: Scaffold(
        backgroundColor: Colors.transparent, // reveal PfBackground waves
        appBar: AppBar(
          title: const Text('Create your wallet'),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(PfSpace.xl),
                child: _buildStep(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _stepTitle => switch (_step) {
        _Step.setPin => 'Secure your wallet',
        _Step.generateKey => 'Creating your account',
        _Step.fund => 'Activate your account',
        _Step.done => 'Done',
      };

  String get _stepSubtitle => switch (_step) {
        _Step.setPin =>
          'A 6-digit PIN gates every signature on this device. PayFlex never '
              'stores it — only a verifiable digest lives on this phone.',
        _Step.generateKey =>
          'Generating your Stellar key on this device. The secret never '
              'leaves this phone — not even PayFlex can move your money.',
        _Step.fund =>
          'Your account needs a small one-time XLM balance to activate on '
              'the Stellar network. On testnet, Friendbot funds it instantly.',
        _Step.done => '',
      };

  Widget _buildStep() {
    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PfInlineError(message: _error!, onRetry: () => setState(() => _error = null)),
          const SizedBox(height: 16),
        ],
      );
    }
    if (_busy) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PfBrandedLoader(size: 64),
          SizedBox(height: 22),
          Text(
            'Working…',
            style: TextStyle(color: PfColors.onNavyMuted, fontSize: 14),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _stepTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          _stepSubtitle,
          style: const TextStyle(
            color: PfColors.onNavyMuted,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 26),
        switch (_step) {
          _Step.setPin => _pinStep(),
          _Step.fund => _fundStep(),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }

  Widget _pinStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: PfColors.onNavy,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 10,
          ),
          decoration: const InputDecoration(
            labelText: 'PIN',
            counterText: '',
            filled: true,
            fillColor: PfColors.navyRaised2,
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          children: [
            Icon(Icons.shield_outlined, size: 14, color: PfColors.onNavyFaint),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Used to sign every transfer — it never leaves this device.',
                style: TextStyle(
                  color: PfColors.onNavyFaint,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        PfPrimaryButton(
          label: 'Set PIN & create wallet',
          icon: Icons.lock_outline_rounded,
          busy: _busy,
          onPressed: _busy ? null : _submitPin,
        ),
      ],
    );
  }

  Widget _fundStep() {
    final isTestnet = _client?.isTestnet ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_publicKey != null)
          PfPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            radius: PfRadius.sm,
            showShadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Stellar address',
                  style: TextStyle(color: PfColors.onNavyMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _publicKey!,
                  style: const TextStyle(
                    color: PfColors.onNavy,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        if (isTestnet)
          PfPrimaryButton(
            label: 'Fund with testnet Friendbot',
            icon: Icons.water_drop_outlined,
            busy: _busy,
            onPressed: _busy ? null : _fundViaFriendbot,
          )
        else
          const Text(
            'On mainnet, send a real minimum-balance XLM payment to this '
            'address from an already-funded account to activate it. PayFlex '
            'deliberately does not automate this.',
            style: TextStyle(color: PfColors.onNavyMuted, fontSize: 12.5, height: 1.45),
          ),
      ],
    );
  }
}
