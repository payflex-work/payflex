import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../protocol/crypto_utils.dart';

/// Service managing the device's independent Ed25519 identity keypair.
///
/// ============================================================================
/// CRITICAL ARCHITECTURAL DISTINCTION (See /docs/offline-protocol.md §3)
/// ============================================================================
/// This device keypair is strictly separated from BMONI's EVM wallet signing key.
///
/// - The BMONI key (EIP-191 / secp256k1) is tied to the user's KYC-verified smart
///   wallet and requires PIN-gated confirmation against BMONI's challenge payloads.
/// - The Device Key (Ed25519) exists specifically so the offline optical handoff,
///   Reserve authorizations, and PaymentConfirmations can be signed and verified
///   on-device without needing BMONI's SDK or any network connection.
///
/// IMPORTANT: This device key proves only:
/// "This specific physical device produced this exact signed message."
/// It does NOT prove real-world legal identity; KYC and financial custody are
/// governed entirely by BMONI at online settlement time.
class DeviceKeyService {
  static const String _keyStorageSlot = 'payflex_device_ed25519_seed_v1';
  static const String _pubKeyStorageSlot = 'payflex_device_ed25519_pubkey_v1';

  static Uint8List? _cachedSeed;
  static Uint8List? _cachedPublicKey;

  /// Custom secure storage hook (injected for testing or platform keystores).
  static Future<String?> Function(String key)? secureReadHook;
  static Future<void> Function(String key, String value)? secureWriteHook;

  /// Initializes or retrieves the existing device keypair.
  static Future<void> initialize() async {
    if (_cachedSeed != null) return;

    String? storedSeedHex;
    if (secureReadHook != null) {
      storedSeedHex = await secureReadHook!(_keyStorageSlot);
    } else {
      final prefs = await SharedPreferences.getInstance();
      storedSeedHex = prefs.getString(_keyStorageSlot);
    }

    if (storedSeedHex != null && storedSeedHex.isNotEmpty) {
      _cachedSeed = CryptoUtils.hexToBytes(storedSeedHex);
      _cachedPublicKey = CryptoUtils.ed25519PublicKeyFromSeed(_cachedSeed!);
    } else {
      // Generate new 32-byte Ed25519 seed on first use
      final newSeed = CryptoUtils.generateEd25519Seed();
      final pubKey = CryptoUtils.ed25519PublicKeyFromSeed(newSeed);

      final seedHex = CryptoUtils.bytesToHex(newSeed);
      final pubHex = CryptoUtils.bytesToHex(pubKey);

      if (secureWriteHook != null) {
        await secureWriteHook!(_keyStorageSlot, seedHex);
        await secureWriteHook!(_pubKeyStorageSlot, pubHex);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyStorageSlot, seedHex);
        await prefs.setString(_pubKeyStorageSlot, pubHex);
      }

      _cachedSeed = newSeed;
      _cachedPublicKey = pubKey;
    }
  }

  /// Returns the device's 32-byte private seed.
  static Future<Uint8List> getPrivateSeed() async {
    if (_cachedSeed == null) await initialize();
    return _cachedSeed!;
  }

  /// Returns the device's 32-byte Ed25519 public key.
  static Future<Uint8List> getPublicKey() async {
    if (_cachedPublicKey == null) await initialize();
    return _cachedPublicKey!;
  }

  /// Returns the device's hex-encoded public key.
  static Future<String> getPublicKeyHex() async {
    final pubKey = await getPublicKey();
    return CryptoUtils.bytesToHex(pubKey);
  }

  /// Signs a raw binary message with the device key.
  static Future<Uint8List> sign(Uint8List message) async {
    final seed = await getPrivateSeed();
    return CryptoUtils.signEd25519(message, seed);
  }

  /// Signs a UTF-8 string, returning the 64-byte signature in hex format.
  static Future<String> signString(String message) async {
    final messageBytes = CryptoUtils.utf8Bytes(message);
    final sigBytes = await sign(messageBytes);
    return CryptoUtils.bytesToHex(sigBytes);
  }

  /// Verifies a signature against an arbitrary Ed25519 public key.
  static bool verify(Uint8List message, Uint8List signature, Uint8List publicKey) {
    return CryptoUtils.verifyEd25519(message, signature, publicKey);
  }

  /// Verifies a hex signature over a string message against a hex public key.
  static bool verifyString({
    required String message,
    required String signatureHex,
    required String publicKeyHex,
  }) {
    try {
      final msgBytes = CryptoUtils.utf8Bytes(message);
      final sigBytes = CryptoUtils.hexToBytes(signatureHex);
      final pubBytes = CryptoUtils.hexToBytes(publicKeyHex);
      return verify(msgBytes, sigBytes, pubBytes);
    } catch (_) {
      return false;
    }
  }

  /// Sets a specific seed (for unit tests and deterministic simulation).
  static void setMockSeed(Uint8List seed) {
    _cachedSeed = seed;
    _cachedPublicKey = CryptoUtils.ed25519PublicKeyFromSeed(seed);
  }

  /// Clears in-memory cache.
  static void resetCache() {
    _cachedSeed = null;
    _cachedPublicKey = null;
  }
}
