import 'package:flutter_test/flutter_test.dart';
import 'package:payflex/stellar/stellar_errors.dart';

void main() {
  group('StellarErrors.describe', () {
    test('maps op_underfunded to a specific insufficient-balance message', () {
      final message = StellarErrors.describe(operationResultCodes: ['op_underfunded']);
      expect(message, contains("don't have enough balance"));
    });

    test('maps op_no_trust to a specific missing-trustline message', () {
      final message = StellarErrors.describe(operationResultCodes: ['op_no_trust']);
      expect(message, contains('trustline'));
    });

    test('maps op_no_destination to a specific unfunded-recipient message', () {
      final message = StellarErrors.describe(operationResultCodes: ['op_no_destination']);
      expect(message, contains("doesn't exist"));
    });

    test('prefers the operation-level code over the transaction-level code', () {
      final message = StellarErrors.describe(
        transactionResultCode: 'tx_failed',
        operationResultCodes: ['op_underfunded'],
      );
      expect(message, contains("don't have enough balance"));
    });

    test('falls back to the transaction-level code when no operation code is known', () {
      final message = StellarErrors.describe(transactionResultCode: 'tx_bad_seq');
      expect(message, contains('out of sequence'));
    });

    test('never returns a generic "failed" message when a real code is present', () {
      final message = StellarErrors.describe(operationResultCodes: ['op_low_reserve']);
      expect(message.toLowerCase(), isNot(equals('transfer failed')));
      expect(message, contains('minimum XLM reserve'));
    });

    test('names the raw code when it recognizes nothing else, rather than a bare generic message', () {
      final message = StellarErrors.describe(operationResultCodes: ['op_some_future_code']);
      expect(message, contains('op_some_future_code'));
    });

    test('has a last-resort message when there is no code at all', () {
      final message = StellarErrors.describe();
      expect(message, isNotEmpty);
    });
  });
}
