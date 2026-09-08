import 'package:flutter_test/flutter_test.dart';
import 'package:payflex/protocol/crypto_utils.dart';
import 'package:payflex/protocol/payment_protocol.dart';

void main() {
  group('PaymentRequest', () {
    late final merchantSeed = CryptoUtils.generateEd25519Seed();

    test('Genuine PaymentRequest verifies successfully', () {
      final now = DateTime.now().toUtc();
      final request = PaymentRequest.create(
        requestId: 'req_1234567890abcdef',
        merchantId: 'usr_merchant_99',
        merchantName: 'Amina Cafe',
        amountMinorUnits: 450000,
        currency: 'NGN',
        note: 'Coffee & Breakfast',
        nonce: 'nonce_abc123',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        merchantDeviceSeed: merchantSeed,
      );

      expect(() => request.verify(), returnsNormally);
      expect(request.amountMinorUnits, 450000);
      expect(request.currency, 'NGN');
    });

    test('PaymentRequest fails verification when tampered', () {
      final now = DateTime.now().toUtc();
      final request = PaymentRequest.create(
        requestId: 'req_1234567890abcdef',
        merchantId: 'usr_merchant_99',
        amountMinorUnits: 450000,
        currency: 'NGN',
        nonce: 'nonce_abc123',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        merchantDeviceSeed: merchantSeed,
      );

      // Tamper amount
      final tampered = PaymentRequest(
        requestId: request.requestId,
        merchantId: request.merchantId,
        merchantName: request.merchantName,
        amountMinorUnits: 999999, // Altered
        currency: request.currency,
        note: request.note,
        nonce: request.nonce,
        createdAt: request.createdAt,
        expiresAt: request.expiresAt,
        merchantPublicKey: request.merchantPublicKey,
        checksum: request.checksum,
        signature: request.signature,
      );

      expect(
        () => tampered.verify(),
        throwsA(isA<PaymentProtocolException>()),
      );
    });

    test('Expired PaymentRequest fails verification', () {
      final past = DateTime.now().toUtc().subtract(const Duration(minutes: 20));
      final expired = past.add(const Duration(minutes: 5));

      final request = PaymentRequest.create(
        requestId: 'req_expired_1',
        merchantId: 'usr_merchant_99',
        amountMinorUnits: 200000,
        currency: 'NGN',
        nonce: 'nonce_exp_1',
        createdAt: past,
        expiresAt: expired,
        merchantDeviceSeed: merchantSeed,
      );

      expect(
        () => request.verify(),
        throwsA(isA<PaymentProtocolException>()),
      );
    });

    test('ReplayProtector detects reused requestId and nonce', () {
      final protector = ReplayProtector();
      protector.reset();

      protector.recordRequest('req_unique_1', 'nonce_unique_1');
      expect(protector.isRequestSeen('req_unique_1', 'nonce_other'), isTrue);
      expect(protector.isRequestSeen('req_other', 'nonce_unique_1'), isTrue);

      expect(
        () => protector.recordRequest('req_unique_1', 'nonce_diff'),
        throwsA(isA<PaymentProtocolException>()),
      );
    });
  });

  group('PaymentConfirmation', () {
    late final merchantSeed = CryptoUtils.generateEd25519Seed();
    late final payerSeed = CryptoUtils.generateEd25519Seed();

    test('Genuine PaymentConfirmation verifies against original request', () {
      final now = DateTime.now().toUtc();
      final request = PaymentRequest.create(
        requestId: 'req_conf_test_1',
        merchantId: 'usr_merchant_99',
        amountMinorUnits: 500000,
        currency: 'NGN',
        nonce: 'nonce_conf_1',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        merchantDeviceSeed: merchantSeed,
      );

      final confirmation = PaymentConfirmation.create(
        confirmationId: 'conf_123456789',
        requestId: request.requestId,
        payerId: 'usr_payer_42',
        amountMinorUnits: 500000,
        currency: 'NGN',
        status: 'RESERVE_PENDING',
        authorizationId: 'auth_abc_99',
        timestamp: now.add(const Duration(seconds: 10)),
        payerDeviceSeed: payerSeed,
      );

      expect(() => confirmation.verifyAgainstRequest(request), returnsNormally);
    });

    test('PaymentConfirmation fails when bound to wrong requestId or amount', () {
      final now = DateTime.now().toUtc();
      final request = PaymentRequest.create(
        requestId: 'req_conf_test_1',
        merchantId: 'usr_merchant_99',
        amountMinorUnits: 500000,
        currency: 'NGN',
        nonce: 'nonce_conf_1',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        merchantDeviceSeed: merchantSeed,
      );

      final wrongRequestConfirmation = PaymentConfirmation.create(
        confirmationId: 'conf_123456789',
        requestId: 'req_different_999', // Wrong
        payerId: 'usr_payer_42',
        amountMinorUnits: 500000,
        currency: 'NGN',
        status: 'RESERVE_PENDING',
        timestamp: now,
        payerDeviceSeed: payerSeed,
      );

      expect(
        () => wrongRequestConfirmation.verifyAgainstRequest(request),
        throwsA(isA<PaymentProtocolException>()),
      );

      final wrongAmountConfirmation = PaymentConfirmation.create(
        confirmationId: 'conf_123456789',
        requestId: request.requestId,
        payerId: 'usr_payer_42',
        amountMinorUnits: 100000, // Wrong amount
        currency: 'NGN',
        status: 'RESERVE_PENDING',
        timestamp: now,
        payerDeviceSeed: payerSeed,
      );

      expect(
        () => wrongAmountConfirmation.verifyAgainstRequest(request),
        throwsA(isA<PaymentProtocolException>()),
      );
    });
  });
}
