import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../models/app_user.dart';
import '../../models/transfer.dart';
import '../../protocol/crypto_utils.dart';
import '../../protocol/fountain_coder.dart';
import '../../protocol/payment_protocol.dart';
import '../../services/api_client.dart';
import '../../services/device_key_service.dart';
import '../../services/offline_reserve_service.dart';
import '../../services/offline_redemption_service.dart';
import '../../services/transfer_flow.dart';
import '../../services/retry.dart';
import '../../theme/payflex_tokens.dart';
import '../../theme/payflex_theme.dart';
import '../../utils/format.dart';
import '../../utils/money.dart';
import '../../widgets/animated_optical_qr.dart';
import '../../widgets/pf_buttons.dart';
import '../../widgets/pf_flow.dart';
import '../../widgets/pf_mark.dart';
import '../../widgets/pf_motion.dart';
import '../../widgets/pf_states.dart';
import '../../widgets/pin_prompt.dart';
import 'send_money_screen.dart' show humanTransferStatus, transferTone;

/// QR Pay Screen with support for:
/// 1. Standard HMAC-signed online QR tokens.
/// 2. Generative animated fountain-coded QR streaming (real optical transport).
/// 3. Offline Reserve payments and device-signed confirmation loop.
class QrPayScreen extends StatefulWidget {
  final AppUser user;
  const QrPayScreen({super.key, required this.user});

  @override
  State<QrPayScreen> createState() => _QrPayScreenState();
}

class _QrPayScreenState extends State<QrPayScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openReserveManager() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PfColors.navyRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PfRadius.lg)),
      ),
      builder: (_) => _OfflineReserveSheet(user: widget.user),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PayFlexTheme.dark,
      child: Scaffold(
        backgroundColor: Colors.transparent, // reveal PfBackground waves
        appBar: AppBar(
          title: const Text('QR Pay'),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              icon: const Icon(Icons.shield_outlined, color: PfColors.emerald),
              tooltip: 'Offline Reserve',
              onPressed: _openReserveManager,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: PfColors.emerald,
            labelColor: PfColors.onNavy,
            unselectedLabelColor: PfColors.onNavyMuted,
            dividerColor: PfColors.navyBorder,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            tabs: const [Tab(text: 'My QR'), Tab(text: 'Scan to pay')],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _MyQrTab(user: widget.user),
            _ScanToPayTab(user: widget.user),
          ],
        ),
      ),
    );
  }
}

class _MyQrTab extends StatefulWidget {
  final AppUser user;
  const _MyQrTab({required this.user});

  @override
  State<_MyQrTab> createState() => _MyQrTabState();
}

class _MyQrTabState extends State<_MyQrTab> {
  final _api = ApiClient();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _currency = 'NGN';
  bool _offlineMode = true; // Default to the generative animated offline transport
  String? _onlineToken;
  FountainEncoder? _fountainEncoder;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
      _onlineToken = null;
      _fountainEncoder = null;
    });

    final amountText = _amountController.text.trim();
    if (amountText.isEmpty || double.tryParse(amountText) == null || double.parse(amountText) <= 0) {
      setState(() {
        _busy = false;
        _error = 'Please enter a valid amount';
      });
      return;
    }

    try {
      if (_offlineMode) {
        // Generate real device-signed canonical PaymentRequest
        final seed = await DeviceKeyService.getPrivateSeed();
        final amountMinor = (double.parse(amountText) * 100).round();
        final now = DateTime.now().toUtc();
        final expiresAt = now.add(const Duration(minutes: 30));
        final reqId = 'req_${CryptoUtils.bytesToHex(CryptoUtils.generateEd25519Seed()).substring(0, 16)}';
        final nonce = 'nonce_${CryptoUtils.bytesToHex(CryptoUtils.generateEd25519Seed()).substring(0, 12)}';

        final request = PaymentRequest.create(
          requestId: reqId,
          merchantId: widget.user.id,
          merchantName: '${widget.user.firstName} ${widget.user.lastName}',
          amountMinorUnits: amountMinor,
          currency: _currency,
          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          nonce: nonce,
          createdAt: now,
          expiresAt: expiresAt,
          merchantDeviceSeed: seed,
        );

        final encoder = FountainEncoder.fromString(request.serialize());

        setState(() {
          _fountainEncoder = encoder;
        });
      } else {
        final token = await _api.generateQr(
          widget.user.id,
          amount: _amountController.text,
          currency: _currency,
        );
        setState(() => _onlineToken = token);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(PfSpace.xl, PfSpace.xl, PfSpace.xl, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Request money with QR',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                _offlineMode
                    ? 'Generates a signed, loss-tolerant Animated Optical QR stream that can be scanned without an internet connection.'
                    : 'Generates a standard online QR token that the payer redeems against BMONI.',
                style: const TextStyle(color: PfColors.onNavyMuted, fontSize: 13.5, height: 1.45),
              ),
              const SizedBox(height: 16),

              // Mode selector
              Container(
                decoration: BoxDecoration(
                  color: PfColors.navyRaised2,
                  borderRadius: BorderRadius.circular(PfRadius.sm),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: _ModeTab(
                        label: 'Animated Optical QR (Offline)',
                        active: _offlineMode,
                        onTap: () => setState(() {
                          _offlineMode = true;
                          _onlineToken = null;
                          _fountainEncoder = null;
                        }),
                      ),
                    ),
                    Expanded(
                      child: _ModeTab(
                        label: 'Standard (Online)',
                        active: !_offlineMode,
                        onTap: () => setState(() {
                          _offlineMode = false;
                          _onlineToken = null;
                          _fountainEncoder = null;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      decoration: const InputDecoration(
                        labelText: 'Amount to request',
                        hintText: '0.00',
                        filled: true,
                        fillColor: PfColors.navyRaised2,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: PfColors.navyBorder),
                          borderRadius: BorderRadius.all(Radius.circular(PfRadius.sm)),
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                        color: PfColors.onNavy,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: _currency,
                    dropdownColor: PfColors.navyRaised2,
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(color: PfColors.onNavy),
                    items: const [
                      DropdownMenuItem(value: 'NGN', child: Text('NGN')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                    ],
                    onChanged: (v) => setState(() => _currency = v!),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note / reference (optional)',
                  hintText: 'e.g. Lunch or Market invoice',
                  filled: true,
                  fillColor: PfColors.navyRaised2,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: PfColors.navyBorder),
                    borderRadius: BorderRadius.all(Radius.circular(PfRadius.sm)),
                  ),
                ),
                style: const TextStyle(color: PfColors.onNavy, fontSize: 14),
              ),
              const SizedBox(height: 16),
              PfPrimaryButton(
                label: (_fountainEncoder == null && _onlineToken == null) ? 'Generate QR' : 'Regenerate QR',
                busy: _busy,
                onPressed: _busy ? null : _generate,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                PfInlineError(message: _error!),
              ],

              // Animated Optical QR display
              if (_fountainEncoder != null) ...[
                const SizedBox(height: 28),
                Center(
                  child: AnimatedOpticalQr(
                    encoder: _fountainEncoder!,
                    size: 200,
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: PfColors.navyRaised2,
                      borderRadius: BorderRadius.circular(PfRadius.pill),
                    ),
                    child: Text(
                      '${formatMoney(_amountController.text, _currency)} · Device-Signed Request',
                      style: const TextStyle(
                        color: PfColors.onNavy,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Continuous fountain stream · Loss-tolerant · The payer can scan this without signal. When paid, scan their signed confirmation QR to close the loop.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PfColors.onNavyFaint, fontSize: 12, height: 1.45),
                ),
              ],

              // Online static QR display
              if (_onlineToken != null) ...[
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(PfRadius.lg),
                    boxShadow: PfShadow.onDark,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: QrImageView(
                          data: _onlineToken!,
                          size: 200,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF0A1330),
                          ),
                        ),
                      ),
                      const IgnorePointer(
                        child: SizedBox(
                          width: 248,
                          height: 248,
                          child: PfQrCorners(
                            color: Colors.white,
                            thickness: 3.5,
                            length: 0.14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: PfColors.navyRaised2,
                      borderRadius: BorderRadius.circular(PfRadius.pill),
                    ),
                    child: Text(
                      '${formatMoney(_amountController.text, _currency)} request',
                      style: const TextStyle(
                        color: PfColors.onNavy,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ModeTab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: active ? PfColors.navyRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(PfRadius.xs),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? PfColors.onNavy : PfColors.onNavyMuted,
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ScanToPayTab extends StatefulWidget {
  final AppUser user;
  const _ScanToPayTab({required this.user});

  @override
  State<_ScanToPayTab> createState() => _ScanToPayTabState();
}

class _ScanToPayTabState extends State<_ScanToPayTab> {
  final _api = ApiClient();
  final FountainDecoder _fountainDecoder = FountainDecoder();
  bool _handled = false;
  bool _offline = false;
  String? _error;
  String? _pendingToken;
  bool _opening = false;
  double _fountainProgress = 0.0;
  int _fountainChunksReceived = 0;
  int _fountainTotalChunks = 0;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    // Check if this is an optical fountain packet
    if (raw.startsWith(FountainPacket.prefix)) {
      final isComplete = _fountainDecoder.addFrame(raw);
      if (mounted) {
        setState(() {
          _fountainProgress = _fountainDecoder.progress;
          _fountainChunksReceived = _fountainDecoder.solvedBlocksCount;
          _fountainTotalChunks = _fountainDecoder.totalBlocks;
        });
      }

      if (isComplete) {
        setState(() => _handled = true);
        final payloadString = _fountainDecoder.getPayloadString();
        _fountainDecoder.reset();
        if (payloadString != null) {
          await _handleDecodedPayload(payloadString);
        }
      }
      return;
    }

    // Standard static token
    setState(() => _handled = true);
    await _payOnline(raw);
  }

  Future<void> _handleDecodedPayload(String payload) async {
    try {
      if (payload.contains(PaymentRequest.protocolVersion)) {
        final request = PaymentRequest.deserialize(payload);
        request.verify();

        if (!mounted) return;
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => _ConfirmPaymentScreen(
              user: widget.user,
              offlineRequest: request,
            ),
          ),
        );
      } else if (payload.contains(PaymentConfirmation.protocolVersion)) {
        final confirmation = PaymentConfirmation.deserialize(payload);
        if (!mounted) return;
        await _showConfirmationReceivedDialog(confirmation);
      } else {
        throw PaymentProtocolException('Unrecognized payload format');
      }
    } catch (e) {
      setState(() => _error = 'Verification failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _handled = false;
          _fountainProgress = 0.0;
          _fountainChunksReceived = 0;
          _fountainTotalChunks = 0;
        });
      }
    }
  }

  Future<void> _showConfirmationReceivedDialog(PaymentConfirmation conf) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PfColors.navyRaised,
        title: const Text('Payment Confirmation Received', style: TextStyle(color: PfColors.onNavy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatMoney((conf.amountMinorUnits / 100.0).toStringAsFixed(2), conf.currency),
              style: PfMoneyType.medium.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text('From: ${shortRef(conf.payerId)}', style: const TextStyle(color: PfColors.onNavyMuted)),
            Text('Status: ${conf.status}', style: const TextStyle(color: PfColors.emerald)),
            Text('Ref: ${shortRef(conf.confirmationId)}', style: const TextStyle(color: PfColors.onNavyFaint)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _payOnline(String token) async {
    setState(() {
      _offline = false;
      _error = null;
      _pendingToken = token;
      _opening = true;
    });
    try {
      final proposal = await withRetry(() => _api.payQr(widget.user.id, token));
      if (!mounted) return;
      setState(() => _opening = false);
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => _ConfirmPaymentScreen(user: widget.user, proposal: proposal),
        ),
      );
    } on OfflineException catch (e) {
      setState(() {
        _opening = false;
        _offline = true;
        _error = e.toString();
      });
    } catch (e) {
      setState(() {
        _opening = false;
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _handled = false;
          _pendingToken = null;
          _opening = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_offline) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: PfEmptyState(
            icon: Icons.wifi_off_rounded,
            title: 'You\u2019re offline',
            message: _error ?? 'Check your connection — or scan an Animated Optical QR from an offline merchant.',
            actionLabel: 'Retry',
            onAction: () => _pendingToken != null ? _payOnline(_pendingToken!) : setState(() => _offline = false),
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: PfEmptyState(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Scan error',
            message: _error!,
            actionLabel: 'Scan again',
            onAction: () => setState(() => _error = null),
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(onDetect: _onDetect),
        Center(
          child: Hero(
            tag: 'pf-qr-frame',
            child: SizedBox(
              width: 264,
              height: 264,
              child: PfQrCorners(
                color: _fountainProgress > 0 ? PfColors.emerald : Colors.white,
                thickness: 4,
                length: 0.16,
              ),
            ),
          ),
        ),

        // Live fountain stream assembly HUD
        if (_fountainProgress > 0)
          Positioned(
            top: 24,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: PfColors.navy.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(PfRadius.md),
                border: Border.all(color: PfColors.emerald.withValues(alpha: 0.6)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.stream_rounded, color: PfColors.emerald, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Assembling Optical Fountain: $_fountainChunksReceived/$_fountainTotalChunks blocks (${(_fountainProgress * 100).toInt()}%)',
                        style: const TextStyle(
                          color: PfColors.onNavy,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _fountainProgress,
                      backgroundColor: PfColors.navyBorder,
                      valueColor: const AlwaysStoppedAnimation<Color>(PfColors.emerald),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          ),

        Positioned(
          bottom: 64,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: PfColors.navy.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(PfRadius.pill),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.center_focus_weak_rounded, color: PfColors.onNavyMuted, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Point at any PayFlex QR or Animated Stream',
                    style: TextStyle(color: PfColors.onNavy, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_opening)
          Container(
            color: PfColors.navy.withValues(alpha: 0.85),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PfBrandedLoader(size: 56),
                  SizedBox(height: 18),
                  Text(
                    'Opening payment…',
                    style: TextStyle(color: PfColors.onNavyMuted, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Confirm and pay sheet. Supports both online BMONI proposals and offline Reserve requests.
class _ConfirmPaymentScreen extends StatefulWidget {
  final AppUser user;
  final Proposal? proposal;
  final PaymentRequest? offlineRequest;

  const _ConfirmPaymentScreen({
    required this.user,
    this.proposal,
    this.offlineRequest,
  }) : assert(proposal != null || offlineRequest != null);

  @override
  State<_ConfirmPaymentScreen> createState() => _ConfirmPaymentScreenState();
}

class _ConfirmPaymentScreenState extends State<_ConfirmPaymentScreen> {
  final _api = ApiClient();
  final _reserveService = OfflineReserveService();
  final _redemptionService = OfflineRedemptionService();

  bool _signing = false;
  String? _error;
  ReserveAllowance? _allowance;

  @override
  void initState() {
    super.initState();
    _checkAllowance();
  }

  Future<void> _checkAllowance() async {
    if (widget.offlineRequest != null) {
      final alw = await _reserveService.getActiveAllowance(widget.offlineRequest!.currency);
      setState(() => _allowance = alw);
    }
  }

  Future<void> _confirmAndPay() async {
    setState(() {
      _signing = true;
      _error = null;
    });

    try {
      if (widget.offlineRequest != null) {
        // Pay from Offline Reserve
        final req = widget.offlineRequest!;
        final spend = await _reserveService.spendFromReserve(request: req);

        // Record in local offline transactions
        await _redemptionService.recordSpend(authorization: spend.authorization);

        if (!mounted) return;

        // Broadcast signed confirmation back via animated QR
        final encoder = FountainEncoder.fromString(spend.confirmation.serialize());

        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => _OfflineConfirmationBroadcastScreen(
              confirmation: spend.confirmation,
              encoder: encoder,
            ),
          ),
        );
      } else {
        // Online BMONI proposal flow
        final signed = await signAndSubmitTransfer(
          context,
          _api,
          widget.user.id,
          widget.proposal!.id,
        );
        if (signed == null) {
          setState(() {
            _signing = false;
            _error = 'Signature cancelled — nothing was submitted.';
          });
          return;
        }
        if (!mounted) return;
        final outcome = PfFlowOutcome(
          headline: 'Paid',
          amount: signed.amount,
          currency: signed.currency,
          caption: 'QR payment · ${shortRef(widget.proposal!.toUserId ?? widget.proposal!.toAddress ?? 'wallet')}',
          reference: signed.id,
          statusLabel: humanTransferStatus(signed.status),
          statusTone: transferTone(signed.status),
          methodLabel: 'QR Pay',
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PfConfirmationScreen(outcome: outcome, receipt: outcome),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _signing = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOffline = widget.offlineRequest != null;
    final amount = isOffline
        ? (widget.offlineRequest!.amountMinorUnits / 100.0).toStringAsFixed(2)
        : widget.proposal!.amount;
    final currency = isOffline ? widget.offlineRequest!.currency : widget.proposal!.currency;
    final recipient = isOffline
        ? (widget.offlineRequest!.merchantName ?? shortRef(widget.offlineRequest!.merchantId))
        : shortRef(widget.proposal!.toUserId ?? widget.proposal!.toAddress ?? 'wallet');

    return Theme(
      data: PayFlexTheme.dark,
      child: Scaffold(
        backgroundColor: Colors.transparent, // reveal PfBackground waves
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: PfColors.onNavy),
            onPressed: _signing ? null : () => Navigator.of(context).pop(false),
          ),
          title: Text(isOffline ? 'Confirm offline payment' : 'Confirm payment'),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: PfSpace.xl, vertical: PfSpace.lg),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Hero(
                          tag: 'pf-qr-frame',
                          child: SizedBox(
                            width: 168,
                            height: 168,
                            child: PfQrCorners(
                              color: isOffline ? PfColors.emerald : Colors.white,
                              thickness: 3,
                              length: 0.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isOffline ? 'Paying from Offline Reserve' : 'You\u2019re about to pay',
                          style: const TextStyle(color: PfColors.onNavyMuted, fontSize: 13.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          formatMoney(amount, currency),
                          style: PfMoneyType.large.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'to $recipient',
                          style: const TextStyle(color: PfColors.onNavyMuted, fontSize: 13.5),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: PfColors.navyRaised,
                            borderRadius: BorderRadius.circular(PfRadius.md),
                            border: Border.all(color: PfColors.navyBorder),
                          ),
                          child: Column(
                            children: [
                              _ConfirmRow(
                                label: 'Method',
                                value: isOffline ? 'Offline Reserve (Device-Signed)' : 'QR Pay (BMONI)',
                              ),
                              const SizedBox(height: 10),
                              _ConfirmRow(label: 'Amount', value: formatMoney(amount, currency)),
                              const SizedBox(height: 10),
                              _ConfirmRow(label: 'To', value: recipient),
                              if (isOffline && widget.offlineRequest!.note != null) ...[
                                const SizedBox(height: 10),
                                _ConfirmRow(label: 'Note', value: widget.offlineRequest!.note!),
                              ],
                              const SizedBox(height: 10),
                              _ConfirmRow(
                                label: 'Reference',
                                value: shortRef(isOffline ? widget.offlineRequest!.requestId : widget.proposal!.id),
                              ),
                            ],
                          ),
                        ),
                        if (isOffline) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: PfColors.emerald.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(PfRadius.sm),
                              border: Border.all(color: PfColors.emerald.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, color: PfColors.emerald, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _allowance != null
                                        ? 'Reserve available: ${formatMoney((_allowance!.remainingAmountMinorUnits / 100.0).toStringAsFixed(2), _allowance!.currency)}'
                                        : 'Checking reserve allowance…',
                                    style: const TextStyle(color: PfColors.onNavy, fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          PfInlineError(message: _error!),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                PfPrimaryButton(
                  label: isOffline ? 'Authorize offline payment' : 'Confirm & pay',
                  icon: Icons.north_east_rounded,
                  busy: _signing,
                  onPressed: _signing ? null : _confirmAndPay,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen broadcasting the signed confirmation back to the receiver via animated QR.
class _OfflineConfirmationBroadcastScreen extends StatelessWidget {
  final PaymentConfirmation confirmation;
  final FountainEncoder encoder;

  const _OfflineConfirmationBroadcastScreen({
    required this.confirmation,
    required this.encoder,
  });

  @override
  Widget build(BuildContext context) {
    final amount = (confirmation.amountMinorUnits / 100.0).toStringAsFixed(2);
    final outcome = PfFlowOutcome(
      headline: 'Payment verified',
      amount: amount,
      currency: confirmation.currency,
      caption: 'Offline Reserve · Settlement pending with BMONI',
      reference: confirmation.confirmationId,
      statusLabel: 'Settlement pending',
      statusTone: PfTone.info,
      methodLabel: 'Offline Reserve',
    );

    return Theme(
      data: PayFlexTheme.dark,
      child: Scaffold(
        backgroundColor: Colors.transparent, // reveal PfBackground waves
        appBar: AppBar(
          title: const Text('Payment verified'),
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PfSpace.xl),
            child: Column(
              children: [
                Center(
                  child: AnimatedOpticalQr(
                    encoder: encoder,
                    size: 200,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: PfColors.navyRaised2,
                    borderRadius: BorderRadius.circular(PfRadius.pill),
                  ),
                  child: const Text(
                    'Signed Confirmation Stream',
                    style: TextStyle(
                      color: PfColors.emerald,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Show this animated QR code to the receiver so their device can verify and record your payment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PfColors.onNavyMuted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),
                PfSecondaryButton(
                  label: 'View receipt & done',
                  icon: Icons.receipt_long_outlined,
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => PfConfirmationScreen(outcome: outcome, receipt: outcome),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  const _ConfirmRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: PfColors.onNavyMuted, fontSize: 12.5),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
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

/// Offline Reserve management sheet.
class _OfflineReserveSheet extends StatefulWidget {
  final AppUser user;
  const _OfflineReserveSheet({required this.user});

  @override
  State<_OfflineReserveSheet> createState() => _OfflineReserveSheetState();
}

class _OfflineReserveSheetState extends State<_OfflineReserveSheet> {
  final _reserveService = OfflineReserveService();
  final _redemptionService = OfflineRedemptionService();
  final _amountController = TextEditingController(text: '20000');
  final String _currency = 'NGN';
  ReserveAllowance? _allowance;
  List<OfflineTransactionRecord> _records = [];
  bool _busy = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final alw = await _reserveService.getActiveAllowance(_currency);
    final recs = await _redemptionService.loadRecords();
    if (mounted) {
      setState(() {
        _allowance = alw;
        _records = recs;
      });
    }
  }

  Future<void> _provision() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final amountMinor = (double.parse(_amountController.text) * 100).round();
      final alw = await _reserveService.provisionAllowance(
        appUserId: widget.user.id,
        bmoniUserId: widget.user.id,
        amountMinorUnits: amountMinor,
        currency: _currency,
      );
      setState(() {
        _allowance = alw;
        _statusMessage = 'Provisioned ${formatMoney(_amountController.text, _currency)} offline allowance!';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    final pin = await promptForPin(context);
    if (pin == null || pin.isEmpty) return;

    setState(() {
      _busy = true;
      _statusMessage = 'Syncing offline transactions with BMONI…';
    });

    try {
      final result = await _redemptionService.syncAndRedeemAll(
        appUserId: widget.user.id,
        apiClient: ApiClient(),
        pin: pin,
      );
      await _load();
      setState(() {
        _statusMessage = 'Sync complete: ${result.succeeded} settled, ${result.failed} failed, ${result.expired} expired.';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Sync error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_rounded, color: PfColors.emerald, size: 24),
              const SizedBox(width: 10),
              const Text(
                'Offline Reserve',
                style: TextStyle(color: PfColors.onNavy, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: PfColors.onNavyMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Pre-authorize spendable balance while online to make device-signed offline payments when disconnected.',
            style: TextStyle(color: PfColors.onNavyMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (_allowance != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PfColors.navyRaised2,
                borderRadius: BorderRadius.circular(PfRadius.sm),
                border: Border.all(color: PfColors.emerald.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Active Offline Allowance', style: TextStyle(color: PfColors.onNavyMuted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    formatMoney((_allowance!.remainingAmountMinorUnits / 100.0).toStringAsFixed(2), _allowance!.currency),
                    style: PfMoneyType.large.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Expires: ${formatTimestampLong(_allowance!.expiresAt.toIso8601String())}',
                    style: const TextStyle(color: PfColors.onNavyFaint, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'Top up allowance',
                    hintText: '20000',
                    filled: true,
                    fillColor: PfColors.navyRaised2,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: PfColors.navyBorder),
                      borderRadius: BorderRadius.all(Radius.circular(PfRadius.sm)),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: PfColors.onNavy, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              PfPrimaryButton(
                label: 'Provision',
                busy: _busy,
                onPressed: _busy ? null : _provision,
                height: 48,
              ),
            ],
          ),
          if (_records.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Offline Spends (${_records.length})',
                  style: const TextStyle(color: PfColors.onNavy, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.sync_rounded, size: 16),
                  label: const Text('Sync & Redeem'),
                  onPressed: _busy ? null : _sync,
                ),
              ],
            ),
            const SizedBox(height: 6),
            ..._records.take(3).map((r) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: PfColors.navyRaised2,
                    borderRadius: BorderRadius.circular(PfRadius.xs),
                  ),
                  child: Row(
                    children: [
                      Text(
                        formatMoney(r.amountDecimal, r.currency),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'to ${shortRef(r.merchantId)}',
                        style: const TextStyle(color: PfColors.onNavyMuted, fontSize: 12),
                      ),
                      const Spacer(),
                      PfStatusChip(
                        label: r.status.name.toUpperCase(),
                        tone: r.status == RedemptionStatus.settled ? PfTone.success : PfTone.info,
                      ),
                    ],
                  ),
                )),
          ],
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _statusMessage!,
              style: const TextStyle(color: PfColors.emerald, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}
