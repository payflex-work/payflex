import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';

/// Manages the device's Stellar (ED25519) keypair — a THIRD, distinct key
/// alongside the two already in this app:
///   1. BMONI's EVM owner key (secp256k1, EIP-191) — bmoni_embedded_sdk.
///   2. The offline-protocol device key (ED25519) — DeviceKeyService.
///   3. This Stellar key (ED25519, StrKey-encoded) — never reused with #2
///      even though both happen to be ED25519: different encoding
///      (StrKey vs raw hex), different network, different purpose. Mixing
///      them would mean a compromise of one leaks signing capability for
///      the other.
///
/// The secret seed never leaves the device and is never sent to the
/// PayFlex backend or logged. Stored in the
/// platform keychain/keystore via flutter_secure_storage (Keychain on
/// iOS, EncryptedSharedPreferences/Keystore on Android), NOT
/// SharedPreferences, unlike this app's other injectable-storage
/// services — the pasted build brief for this rail was explicit that the
/// secret key needs real secure storage, not just "whatever's easiest."
class StellarKeyService {
  static const _secretSeedKey = 'payflex_stellar_secret_seed_v1';
  static const _storage = FlutterSecureStorage();

  static KeyPair? _cachedKeyPair;

  /// Test-only injection point — flutter_secure_storage needs a real
  /// platform channel that isn't available under `flutter test`'s
  /// engine, same reason DeviceKeyService and WalletService expose
  /// equivalent hooks. Null (the default) means "use the real keychain."
  static Future<String?> Function(String key)? secureReadHook;
  static Future<void> Function(String key, String value)? secureWriteHook;

  /// True once the user has opted into the Stellar rail on this device
  /// (a keypair exists locally) — distinct from whether that account is
  /// funded/activated on-chain, which StellarClient checks separately.
  static Future<bool> hasOptedIn() async {
    final stored = await _read(_secretSeedKey);
    return stored != null && stored.isNotEmpty;
  }

  /// Returns the existing keypair, or generates and persists a new one on
  /// first opt-in. Idempotent — safe to call every time the Stellar
  /// screens open.
  static Future<KeyPair> getOrCreateKeyPair() async {
    if (_cachedKeyPair != null) return _cachedKeyPair!;

    final storedSeed = await _read(_secretSeedKey);
    if (storedSeed != null && storedSeed.isNotEmpty) {
      _cachedKeyPair = KeyPair.fromSecretSeed(storedSeed);
      return _cachedKeyPair!;
    }

    final keyPair = KeyPair.random();
    await _write(_secretSeedKey, keyPair.secretSeed);
    _cachedKeyPair = keyPair;
    return keyPair;
  }

  /// For tests only — clears the in-memory cache so a fresh
  /// getOrCreateKeyPair() call re-reads (or re-generates) from storage.
  static void resetCacheForTest() => _cachedKeyPair = null;

  static Future<String?> _read(String key) async {
    if (secureReadHook != null) return secureReadHook!(key);
    return _storage.read(key: key);
  }

  static Future<void> _write(String key, String value) async {
    if (secureWriteHook != null) {
      await secureWriteHook!(key, value);
      return;
    }
    await _storage.write(key: key, value: value);
  }
}
