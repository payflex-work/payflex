import 'package:flutter/material.dart';
import '../stellar/stellar_client.dart';
import '../stellar/stellar_models.dart';
import '../services/wallet_service.dart';
import '../utils/format.dart';
import '../widgets/pf_flow.dart';
import '../widgets/pf_states.dart';
import '../widgets/pin_prompt.dart';
import 'api_client.dart';

/// Shared by every payment entry point (direct send, QR Pay, split bill,
/// standing plan due payment, link funding, offline redemption). Walks the
/// app's only money-movement sequence:
///
///   resolve recipient → prompt PIN → build the Stellar payment on-device
///   → sign with the user's own key → submit straight to Horizon → record
///   with the backend (verified against the chain before it is stored).
///
/// The backend never sees a signature or builds a transaction: it can only
/// VERIFY what Horizon already accepted.
Future<StellarPaymentResult?> signAndSubmitTransfer(
  BuildContext context,
  ApiClient api,
  String appUserId, {
  required String toPublicKey,
  required String amount,
  required String assetCode,
  String? assetIssuer,
  required TransferKind kind,
  String? qrTokenRef,
  String? splitBillId,
  String? standingPlanId,
  String? offlineAuthorizationId,
  String? memo,
  StellarClient? client,
}) async {
  final stellar = client ?? await ApiClient().stellarClient();
  if (!context.mounted) return null;
  final pin = await promptForPin(context);
  if (pin == null || pin.isEmpty) return null;

  final result = await stellar.sendPaymentWithPin(
    destinationPublicKey: toPublicKey,
    amount: amount,
    assetCode: assetCode,
    issuer: assetIssuer,
    pin: pin,
    memo: memo,
  );
  if (!result.success) {
    if (context.mounted) {
      await showPfErrorDialog(
        context,
        title: 'Payment failed on-chain',
        message: result.errorMessage ?? result.errorCode ?? 'The Stellar network rejected this payment.',
      );
    }
    return result;
  }
  // ignore: dead_code

  // Record it (verified server-side against Horizon). A record failure
  // must never erase the fact the payment happened — surface it, don't
  // roll anything back.
  try {
    await api.recordTransfer(
      appUserId,
      stellarTxHash: result.transactionHash!,
      fromPublicKey: await WalletService.currentAddress() ?? '',
      toPublicKey: toPublicKey,
      amount: amount,
      assetCode: assetCode,
      assetIssuer: assetIssuer,
      kind: kind.wireName,
      qrTokenRef: qrTokenRef,
      splitBillId: splitBillId,
      standingPlanId: standingPlanId,
      offlineAuthorizationId: offlineAuthorizationId,
      memo: memo,
    );
  } catch (e) {
    debugPrint('transfer record failed (payment already on-chain): $e');
  }
  return result;
}

/// A friendly failure dialog for on-chain rejections, kept out of the
/// individual screens. Uses the same visual language as the success flow.
Future<void> showPfErrorDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB3261E)),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// The kinds of payments the app makes. Wire names match the backend's
/// TransferRecord.kind enum exactly (see backend/src/transfer).
enum TransferKind {
  transfer,
  qrPay,
  offlineRedemption,
  splitBill,
  standingPlan,
  linkClaim;

  String get wireName => switch (this) {
        transfer => 'TRANSFER',
        qrPay => 'QR_PAY',
        offlineRedemption => 'OFFLINE_REDEMPTION',
        splitBill => 'SPLIT_BILL',
        standingPlan => 'STANDING_PLAN',
        linkClaim => 'LINK_CLAIM',
      };
}

/// Turns a [StellarPaymentResult] into the shared confirmation-screen
/// outcome used by every payoff in the app.
PfFlowOutcome outcomeForPayment(
  StellarPaymentResult result, {
  required String headline,
  required String amount,
  required String assetCode,
  String? caption,
  required String methodLabel,
}) {
  final success = result.success;
  return PfFlowOutcome(
    headline: headline,
    amount: amount,
    currency: assetCode,
    caption: caption,
    reference: result.transactionHash ?? '—',
    statusLabel: success ? 'Confirmed on Stellar' : 'Failed',
    statusTone: success ? PfTone.success : PfTone.warn,
    methodLabel: methodLabel,
  );
}

/// Short label for a public key in captions, e.g. "GABC…XYZ".
String recipientLabel(String publicKey) => shortRef(publicKey);
