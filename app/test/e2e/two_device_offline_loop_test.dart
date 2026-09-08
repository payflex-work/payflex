import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payflex/models/transfer.dart';
import 'package:payflex/protocol/crypto_utils.dart';
import 'package:payflex/protocol/fountain_coder.dart';
import 'package:payflex/protocol/payment_protocol.dart';
import 'package:payflex/services/api_client.dart';
import 'package:payflex/services/device_key_service.dart';
import 'package:payflex/services/offline_reserve_service.dart';
import 'package:payflex/services/offline_redemption_service.dart';
import 'package:payflex/services/wallet_service.dart';

/// Mock ApiClient for simulating BMONI online reconnection and settlement.
class MockSettlementApiClient extends ApiClient {
  final Map<String, Proposal> createdProposals = {};

  @override
  Future<Proposal> createTransfer(
    String appUserId, {
    String? toBmoniUserId,
    String? toAddress,
    String? toPayTag,
    required String amount,
    required String currency,
    String? description,
  }) async {
    final proposalId = 'prop_settled_${createdProposals.length + 1}';
    final proposal = Proposal(
      id: proposalId,
      status: 'PENDING',
      nextAction: 'SIGN',
      amount: amount,
      currency: currency,
      toUserId: toBmoniUserId,
      toAddress: toAddress,
      currentSignatures: 0,
      requiredSignatures: 1,
      currentApprovals: 0,
      requiredApprovals: 1,
    );
    createdProposals[proposalId] = proposal;
    return proposal;
  }

  @override
  Future<ProposalSignPayload> getTransferSignPayload(
    String appUserId,
    String proposalId, {
    int maxAttempts = 8,
  }) async {
    return ProposalSignPayload(
      signingPayloadHash: '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
      proposalStatus: 'PENDING',
    );
  }

  @override
  Future<Proposal> signTransfer(String appUserId, String proposalId, String signature) async {
    final existing = createdProposals[proposalId]!;
    final settled = Proposal(
      id: existing.id,
      status: 'SETTLED',
      nextAction: null,
      amount: existing.amount,
      currency: existing.currency,
      toUserId: existing.toUserId,
      toAddress: existing.toAddress,
      currentSignatures: 1,
      requiredSignatures: 1,
      currentApprovals: 1,
      requiredApprovals: 1,
    );
    createdProposals[proposalId] = settled;
    return settled;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // The real BmoniEmbeddedSdk needs a provisioned on-device wallet and
  // platform secure storage, neither of which exist in this VM test —
  // MockSettlementApiClient never checks the signature value itself, so
  // any placeholder is fine here (same simulated-signer role the
  // backend's own sandbox scripts give ethers.Wallet).
  WalletService.signDigestHook = (digestHex, pin) async => '0xmocksignature';

  group('E2E Two-Device Offline Payment & Reconciliation Loop', () {
    // Device A (Receiver / Merchant: Amina Cafe)
    final deviceASeed = CryptoUtils.generateEd25519Seed();
    const merchantAppUserId = 'usr_merchant_amina_01';
    const merchantBmoniId = 'bmoni_merchant_amina_01';

    // Device B (Sender / Payer: Babatunde)
    final deviceBSeed = CryptoUtils.generateEd25519Seed();
    const payerAppUserId = 'usr_payer_baba_02';
    const payerBmoniId = 'bmoni_payer_baba_02';

    test('Full End-to-End Two-Device Offline Loop with Optical Fountain Transport', () async {
      // -----------------------------------------------------------------------
      // STAGE 1: Payer (Device B) provisions an Offline Reserve while online
      // -----------------------------------------------------------------------
      final payerReserveStorage = <String, String>{};
      final payerReserveService = OfflineReserveService();
      payerReserveService.storageGetHook = (k) async => payerReserveStorage[k];
      payerReserveService.storageSetHook = (k, v) async {
        payerReserveStorage[k] = v;
      };

      final allowance = await payerReserveService.provisionAllowance(
        appUserId: payerAppUserId,
        bmoniUserId: payerBmoniId,
        amountMinorUnits: 2000000, // ₦20,000.00 NGN
        currency: 'NGN',
        validity: const Duration(hours: 24),
        explicitDeviceSeed: deviceBSeed,
      );

      expect(allowance.remainingAmountMinorUnits, 2000000);
      expect(allowance.isExpired(), isFalse);

      // -----------------------------------------------------------------------
      // STAGE 2: Both devices go offline (Airplane Mode)
      // Receiver (Device A) creates a PaymentRequest for ₦5,000.00
      // -----------------------------------------------------------------------
      final now = DateTime.now().toUtc();
      final paymentRequest = PaymentRequest.create(
        requestId: 'req_offline_tx_001',
        merchantId: merchantBmoniId,
        merchantName: 'Amina Cafe',
        amountMinorUnits: 500000, // ₦5,000.00 NGN
        currency: 'NGN',
        note: '2x Jollof Special + Drinks',
        nonce: 'nonce_987654321',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        merchantDeviceSeed: deviceASeed,
      );

      // Verify request integrity on Device A
      expect(() => paymentRequest.verify(), returnsNormally);

      // Receiver begins streaming the PaymentRequest via Animated Optical Fountain QR
      final receiverFountainEncoder = FountainEncoder.fromString(
        paymentRequest.serialize(),
        blockSize: 48,
      );
      expect(receiverFountainEncoder.k, greaterThan(1));

      // -----------------------------------------------------------------------
      // STAGE 3: Payer (Device B) scans Optical Fountain frames with camera
      // (Simulating packet transmission over camera: frames arrive out of order and dropped)
      // -----------------------------------------------------------------------
      final capturedFramesByDeviceB = <String>[];
      for (var i = 0; i < 25; i++) {
        capturedFramesByDeviceB.add(receiverFountainEncoder.nextFrame());
      }

      // Introduce simulated real-world optical packet shuffling and 40% loss
      capturedFramesByDeviceB.shuffle(Random(1337));
      final receivedFrames = capturedFramesByDeviceB.take(15).toList();

      final payerFountainDecoder = FountainDecoder();
      var requestReconstructed = false;
      for (final frame in receivedFrames) {
        if (payerFountainDecoder.addFrame(frame)) {
          requestReconstructed = true;
          break;
        }
      }

      // If 15 frames weren't enough due to heavy loss, supply a couple more until complete
      if (!requestReconstructed) {
        for (var i = 0; i < 10; i++) {
          final extraFrame = receiverFountainEncoder.nextFrame();
          if (payerFountainDecoder.addFrame(extraFrame)) {
            requestReconstructed = true;
            break;
          }
        }
      }

      expect(requestReconstructed, isTrue);
      expect(payerFountainDecoder.isComplete, isTrue);

      final decodedRequestPayload = payerFountainDecoder.getPayloadString()!;
      final parsedRequestOnPayer = PaymentRequest.deserialize(decodedRequestPayload);

      // Payer verifies receiver's request
      parsedRequestOnPayer.verify();
      expect(parsedRequestOnPayer.amountMinorUnits, 500000);
      expect(parsedRequestOnPayer.merchantId, merchantBmoniId);

      // -----------------------------------------------------------------------
      // STAGE 4: Payer (Device B) authorizes spend from Offline Reserve
      // -----------------------------------------------------------------------
      final spendResult = await payerReserveService.spendFromReserve(
        request: parsedRequestOnPayer,
        explicitDeviceSeed: deviceBSeed,
      );

      final authorization = spendResult.authorization;
      final confirmation = spendResult.confirmation;

      expect(authorization.sequenceNumber, 1);
      expect(authorization.amountMinorUnits, 500000);
      expect(confirmation.status, 'RESERVE_PENDING');
      expect(confirmation.authorizationId, authorization.authorizationId);

      // Check payer's remaining reserve balance
      final updatedAllowance = await payerReserveService.getActiveAllowance('NGN');
      expect(updatedAllowance!.remainingAmountMinorUnits, 1500000); // 2000000 - 500000 = 1500000

      // Record spend in payer's offline transaction journal
      final payerRedemptionService = OfflineRedemptionService(reserveService: payerReserveService);
      await payerRedemptionService.recordSpend(authorization: authorization);

      // -----------------------------------------------------------------------
      // STAGE 5: Payer (Device B) streams signed PaymentConfirmation via Animated QR
      // Receiver (Device A) scans confirmation to close the optical loop
      // -----------------------------------------------------------------------
      final payerConfirmationEncoder = FountainEncoder.fromString(
        confirmation.serialize(),
        blockSize: 48,
      );

      final confirmationFrames = <String>[];
      for (var i = 0; i < 20; i++) {
        confirmationFrames.add(payerConfirmationEncoder.nextFrame());
      }
      confirmationFrames.shuffle(Random(999));

      final receiverConfirmationDecoder = FountainDecoder();
      var confirmationReconstructed = false;
      for (final frame in confirmationFrames) {
        if (receiverConfirmationDecoder.addFrame(frame)) {
          confirmationReconstructed = true;
          break;
        }
      }

      expect(confirmationReconstructed, isTrue);
      final decodedConfirmationStr = receiverConfirmationDecoder.getPayloadString()!;
      final parsedConfirmation = PaymentConfirmation.deserialize(decodedConfirmationStr);

      // Receiver independently verifies the confirmation against the original request
      parsedConfirmation.verifyAgainstRequest(paymentRequest);
      expect(parsedConfirmation.status, 'RESERVE_PENDING');
      expect(parsedConfirmation.amountMinorUnits, 500000);

      // Receiver records confirmation in replay cache
      final replayProtector = ReplayProtector();
      expect(replayProtector.isConfirmationSeen(parsedConfirmation.confirmationId), isFalse);
      replayProtector.recordConfirmation(parsedConfirmation.confirmationId);

      // -----------------------------------------------------------------------
      // STAGE 6: Payer reconnects to internet & Redeems authorization with BMONI
      // -----------------------------------------------------------------------
      final mockApiClient = MockSettlementApiClient();

      // Payer syncs and redeems queue
      // (Using mock EVM PIN signing)
      final redemptionResult = await payerRedemptionService.syncAndRedeemAll(
        appUserId: payerAppUserId,
        apiClient: mockApiClient,
        pin: '123456',
      );

      expect(redemptionResult.succeeded, 1);
      expect(redemptionResult.failed, 0);
      expect(redemptionResult.expired, 0);

      // Verify records show SETTLED
      final finalRecords = await payerRedemptionService.loadRecords();
      expect(finalRecords.length, 1);
      expect(finalRecords.first.status, RedemptionStatus.settled);
      expect(finalRecords.first.proposalId, isNotNull);

      // Verify pending queue is emptied
      final pendingQueue = await payerReserveService.getPendingRedemptionQueue();
      expect(pendingQueue.isEmpty, isTrue);
    });
  });
}
