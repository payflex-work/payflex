import 'package:flutter_test/flutter_test.dart';
import 'package:payflex/utils/stellar_tx.dart';

final String realHashForUrl = 'b' * 64;

void main() {
  group('isStellarTxHash — gates when the explorer link is offered', () {
    final realHash = 'a' * 64; // 64 hex chars, like a real Stellar tx hash

    test('accepts a real 64-char lowercase hex hash', () {
      expect(isStellarTxHash(realHash), isTrue);
    });

    test('accepts uppercase hex (normalizes before checking)', () {
      expect(isStellarTxHash(realHash.toUpperCase()), isTrue);
    });

    test('tolerates surrounding whitespace', () {
      expect(isStellarTxHash('  $realHash\n'), isTrue);
    });

    test('rejects a Safebox contract id (C…, not 64 hex chars)', () {
      expect(isStellarTxHash('CABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghij'), isFalse);
    });

    test('rejects a truncated hash', () {
      expect(isStellarTxHash(realHash.substring(0, 63)), isFalse);
    });

    test('rejects a 64-char non-hex string', () {
      expect(isStellarTxHash('z' * 64), isFalse);
    });

    test('rejects a uuid-style reference with dashes', () {
      expect(
        isStellarTxHash('3f2504e0-4f89-11d3-9a0c-0305e82c3301abcdefgh'),
        isFalse,
      );
    });

    test('rejects empty input', () {
      expect(isStellarTxHash(''), isFalse);
    });
  });

  group('explorer URLs', () {
    test('testnet URL points at the testnet explorer', () {
      final url = stellarExpertTxUrl(realHashForUrl, testnet: true);
      expect(url.host, 'stellar.expert');
      expect(url.path, contains('/testnet/'));
    });

    test('mainnet URL omits the testnet segment', () {
      final url = stellarExpertTxUrl(realHashForUrl, testnet: false);
      expect(url.host, 'stellar.expert');
      expect(url.path, isNot(contains('testnet')));
    });

    test('fallback explorer (StellarChain) builds for both networks', () {
      expect(
        stellarChainTxUrl(realHashForUrl, testnet: true).path,
        contains('testnet'),
      );
      expect(
        stellarChainTxUrl(realHashForUrl, testnet: false).path,
        isNot(contains('testnet')),
      );
    });
  });
}
