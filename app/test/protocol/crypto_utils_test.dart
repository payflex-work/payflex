import 'package:flutter_test/flutter_test.dart';
import 'package:payflex/protocol/crypto_utils.dart';

void main() {
  group('CryptoUtils - SHA-256 & SHA-512', () {
    test('SHA-256 computes correct hash for empty string', () {
      final hash = CryptoUtils.sha256Hex('');
      expect(hash.toLowerCase(), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('SHA-256 computes correct hash for known string', () {
      final hash = CryptoUtils.sha256Hex('PayFlex Offline Protocol');
      expect(hash.length, 64);
      expect(CryptoUtils.sha256Hex('PayFlex Offline Protocol'), hash);
    });

    test('SHA-512 computes correct hash for known string', () {
      final bytes = CryptoUtils.utf8Bytes('PayFlex Ed25519 Signing');
      final digest = CryptoUtils.sha512Bytes(bytes);
      expect(digest.length, 64);
    });
  });

  group('CryptoUtils - Ed25519 RFC 8032', () {
    test('Keypair generation, signing, and verification', () {
      final seed = CryptoUtils.generateEd25519Seed();
      expect(seed.length, 32);

      final pubKey = CryptoUtils.ed25519PublicKeyFromSeed(seed);
      expect(pubKey.length, 32);

      final message = CryptoUtils.utf8Bytes('Authorized payment of 5000 NGN');
      final signature = CryptoUtils.signEd25519(message, seed);
      expect(signature.length, 64);

      final valid = CryptoUtils.verifyEd25519(message, signature, pubKey);
      expect(valid, isTrue);
    });

    test('Verification fails for tampered message', () {
      final seed = CryptoUtils.generateEd25519Seed();
      final pubKey = CryptoUtils.ed25519PublicKeyFromSeed(seed);

      final message = CryptoUtils.utf8Bytes('Authorized payment of 5000 NGN');
      final tamperedMessage = CryptoUtils.utf8Bytes('Authorized payment of 50000 NGN');
      final signature = CryptoUtils.signEd25519(message, seed);

      final valid = CryptoUtils.verifyEd25519(tamperedMessage, signature, pubKey);
      expect(valid, isFalse);
    });

    test('Verification fails for wrong public key', () {
      final seed1 = CryptoUtils.generateEd25519Seed();
      final seed2 = CryptoUtils.generateEd25519Seed();
      final pubKey2 = CryptoUtils.ed25519PublicKeyFromSeed(seed2);

      final message = CryptoUtils.utf8Bytes('Transfer payload');
      final signature = CryptoUtils.signEd25519(message, seed1);

      final valid = CryptoUtils.verifyEd25519(message, signature, pubKey2);
      expect(valid, isFalse);
    });
  });
}
