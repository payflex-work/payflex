import 'package:flutter_test/flutter_test.dart';
import 'package:payflex/protocol/crypto_utils.dart';
import 'package:payflex/protocol/payment_protocol.dart';
import 'package:payflex/services/device_key_service.dart';
import 'package:payflex/services/offline_reserve_service.dart';

void main() {
  group('OfflineReserveService', () {
    late final payerSeed = CryptoUtils.generateEd25519Seed();
    late final merchantSeed = CryptoUtils.generateEd25519Seed();
    late final mockStorage = <String, String>{};

    late OfflineReserveService service;

    setUp(() {
      mockStorage.clear();
      service = OfflineReserveService();
      service.storageGetHook = (k) async => mockStorage[k];
      service.storageSetHook = (k, v) async {
        mockStorage[k] = v;
      };

      DeviceKeyService.setMockSeed(payerSeed);
    });

    test('Provisions and verifies a new ReserveAllowance', () async {
      final allowance = await service.provisionAllowance(
        appUserId: 'app_user_1',
        bmoniUserId: 'bmoni_user_1',
        amountMinorUnits: 2500000, // ₦25,000.00
        currency: 'NGN',
        explicitDeviceSeed: payerSeed,
      );

      expect(allowance.initialAmountMinorUnits, 2500000);
      expect(allowance.remainingAmountMinorUnits, 2500000);
      expect(allowance.currentSequenceNumber, 0);
      expect(() => allowance.verify(), returnsNormally);

      final retrieved = await service.getActiveAllowance('NGN');
      expect(retrieved, isNotNull);
      expect(retrieved!.allowanceId, allowance.allowanceId);
    });

    test('Spends from allowance, increments monotonic sequence, chains state hash', () async {
      await service.provisionAllowance(
        appUserId: 'app_user_1',
        bmoniUserId: 'bmoni_user_1',
        amountMinorUnits: 1000000, // ₦10,000.00
        currency: 'NGN',
        explicitDeviceSeed: payerSeed,
      );

      final now = DateTime.now().toUtc();
      final request1 = PaymentRequest.create(
        requestId: 'req_1',
        merchantId: 'usr_merchant',
        amountMinorUnits: 300000, // ₦3,000.00
        currency: 'NGN',
        nonce: 'nonce_1',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
        merchantDeviceSeed: merchantSeed,
      );

      final spend1 = await service.spendFromReserve(
        request: request1,
        explicitDeviceSeed: payerSeed,
      );

      expect(spend1.authorization.sequenceNumber, 1);
      expect(spend1.authorization.amountMinorUnits, 300000);
      expect(spend1.confirmation.status, 'RESERVE_PENDING');
      expect(spend1.confirmation.authorizationId, spend1.authorization.authorizationId);

      // Verify authorization independently
      expect(
        () => OfflineReserveService.verifyOfflineAuthorization(
          spend1.authorization,
          boundRequest: request1,
        ),
        returnsNormally,
      );

      // Second spend: sequence increments and previous hash matches state hash of spend 1
      final request2 = PaymentRequest.create(
        requestId: 'req_2',
        merchantId: 'usr_merchant_2',
        amountMinorUnits: 400000, // ₦4,000.00
        currency: 'NGN',
        nonce: 'nonce_2',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
        merchantDeviceSeed: merchantSeed,
      );

      final spend2 = await service.spendFromReserve(
        request: request2,
        explicitDeviceSeed: payerSeed,
      );

      expect(spend2.authorization.sequenceNumber, 2);
      expect(spend2.authorization.previousAuthHash, spend1.authorization.stateHash);

      final alw = await service.getActiveAllowance('NGN');
      expect(alw!.remainingAmountMinorUnits, 300000); // 1000000 - 300000 - 400000 = 300000
    });

    test('Overspending remaining allowance throws OfflineReserveException', () async {
      await service.provisionAllowance(
        appUserId: 'app_user_1',
        bmoniUserId: 'bmoni_user_1',
        amountMinorUnits: 200000, // ₦2,000.00
        currency: 'NGN',
        explicitDeviceSeed: payerSeed,
      );

      final request = PaymentRequest.create(
        requestId: 'req_overspend',
        merchantId: 'usr_merchant',
        amountMinorUnits: 500000, // ₦5,000.00 (Exceeds ₦2,000.00)
        currency: 'NGN',
        nonce: 'nonce_over',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
        merchantDeviceSeed: merchantSeed,
      );

      expect(
        () => service.spendFromReserve(request: request, explicitDeviceSeed: payerSeed),
        throwsA(isA<OfflineReserveException>()),
      );
    });

    test('Tampered OfflineAuthorization fails independent verification', () async {
      final now = DateTime.now().toUtc();
      final request = PaymentRequest.create(
        requestId: 'req_tamper_auth',
        merchantId: 'usr_merchant',
        amountMinorUnits: 100000,
        currency: 'NGN',
        nonce: 'nonce_tamp',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
        merchantDeviceSeed: merchantSeed,
      );

      await service.provisionAllowance(
        appUserId: 'app_user_1',
        bmoniUserId: 'bmoni_user_1',
        amountMinorUnits: 500000,
        currency: 'NGN',
        explicitDeviceSeed: payerSeed,
      );

      final spend = await service.spendFromReserve(
        request: request,
        explicitDeviceSeed: payerSeed,
      );

      // Create tampered authorization with changed amount
      final tamperedAuth = OfflineAuthorization(
        authorizationId: spend.authorization.authorizationId,
        allowanceId: spend.authorization.allowanceId,
        requestId: spend.authorization.requestId,
        merchantId: spend.authorization.merchantId,
        amountMinorUnits: 999999, // Tampered
        currency: spend.authorization.currency,
        sequenceNumber: spend.authorization.sequenceNumber,
        previousAuthHash: spend.authorization.previousAuthHash,
        stateHash: spend.authorization.stateHash,
        timestamp: spend.authorization.timestamp,
        devicePublicKey: spend.authorization.devicePublicKey,
        signature: spend.authorization.signature,
      );

      expect(
        () => OfflineReserveService.verifyOfflineAuthorization(tamperedAuth),
        throwsA(isA<OfflineReserveException>()),
      );
    });
  });
}
