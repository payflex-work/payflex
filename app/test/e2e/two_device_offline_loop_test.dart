import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:payflex/protocol/crypto_utils.dart';
import 'package:payflex/protocol/fountain_coder.dart';
import 'package:payflex/protocol/payment_protocol.dart';
import 'package:payflex/services/offline_reserve_service.dart';

/// E2E two-device OFFLINE loop: the cryptographic core of the offline
/// Reserve protocol (allowance provisioning, optical fountain transport,
/// reserve spend, replay protection) is INDEPENDENT of the payment rail
/// and therefore still exercised fully offline here.
///
/// The online REDEMPTION step is now a real on-device Stellar payment
/// (see OfflineRedemptionService.syncAndRedeemAll → signAndSubmitTransfer);
/// it requires Horizon and a platform secure-storage keychain, neither of
/// which exist under `flutter test`'s engine. The rail settlement itself is
/// proven on the live testnet by
/// backend/scripts/stellar-testnet-walkthrough.ts (same wire protocol,
/// official SDK) and the backend's e2e suites verify the recorded
/// OFFLINE_REDEMPTION transfer. This test documents that split honestly
/// instead of faking a settlement.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('E2E Two-Device Offline Payment (optical loop, rail-agnostic core)', () {
    // Device A (Receiver / Merchant: Amina Cafe)
    final deviceASeed = CryptoUtils.generateEd25519Seed();
    const merchantDeviceId = 'dev_merchant_amina_01';

    // Device B (Sender / Payer: Babatunde)
    final deviceBSeed = CryptoUtils.generateEd25519Seed();
    const payerAppUserId = 'usr_payer_baba_02';
    const payerStellarPublicKey =
        'GATESTPAYERKEY0000000000000000000000000000000000000000000000000001';

    test('Full offline optical loop: request → reserve spend → confirmation', () async {
      // -----------------------------------------------------------------------
      // STAGE 1: Payer (Device B) provisions an Offline Reserve while online
      // (the backing Stellar payment happened on-chain before going offline)
      // -----------------------------------------------------------------------
      final payerReserveStorage = <String, String>{};
      final payerReserveService = OfflineReserveService();
      payerReserveService.storageGetHook = (k) async => payerReserveStorage[k];
      payerReserveService.storageSetHook = (k, v) async {
        payerReserveStorage[k] = v;
      };

      final allowance = await payerReserveService.provisionAllowance(
        appUserId: payerAppUserId,
        stellarPublicKey: payerStellarPublicKey,
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
        merchantId: merchantDeviceId,
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
      expect(parsedRequestOnPayer.merchantId, merchantDeviceId);

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
      expect(updatedAllowance!.remainingAmountMinorUnits, 1500000); // 2000000 - 500000

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

      // -----------------------------------------------------------------------
      // STAGE 6: Payer reconnects to internet & redeems on Stellar
      //
      // The real path (OfflineRedemptionService.syncAndRedeemAll) signs an
      // on-device Stellar payment and records it as OFFLINE_REDEMPTION;
      // that needs Horizon + platform secure storage, so it is verified
      // against the live testnet by
      // backend/scripts/stellar-testnet-walkthrough.ts and the backend e2e
      // suites rather than faked here.
      // -----------------------------------------------------------------------
      expect(authorization.authorizationId, isNotNull);
    });
  });
}
