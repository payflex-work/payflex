import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';
import '../protocol/crypto_utils.dart';
import '../stellar/stellar_key_service.dart';

/// PIN-gated signing for the Stellar-only app.
///
/// The Stellar secret seed lives in the platform keychain/keystore
/// (StellarKeyService). The PIN is NOT stored anywhere: only a salted
/// SHA-256 verifier lives in SharedPreferences, and it is checked before
/// every signing operation. The PIN gates the *use* of the key on this
/// device — it never touches the key material itself, and it is never
/// sent to the PayFlex backend (login signatures are produced on-device
/// and verified server-side against the registered public key).
///
/// This is the ONLY place in the app allowed to turn a confirmed PIN into
/// a signature. Never sign inline in a screen or another service.
class WalletService {
  static const _pinVerifierKey = 'payflex.stellar.pinVerifier.v1';
  static const _pinSaltKey = 'payflex.stellar.pinSalt.v1';

  /// Test-only injection point — SharedPreferences needs a platform
  /// channel that isn't available under `flutter test`'s engine (same
  /// reason StellarKeyService exposes secure-storage hooks). Null (the
  /// default) means "use the real prefs."
  static Future<Map<String, String>> Function(List<String> keys)? prefsReadHook;
  static Future<void> Function(Map<String, String> values)? prefsWriteHook;

  static Future<Map<String, String>> _read(List<String> keys) async {
    if (prefsReadHook != null) return prefsReadHook!(keys);
    final prefs = await SharedPreferences.getInstance();
    return {for (final k in keys) k: prefs.getString(k) ?? ''};
  }

  static Future<void> _write(Map<String, String> values) async {
    if (prefsWriteHook != null) return prefsWriteHook!(values);
    final prefs = await SharedPreferences.getInstance();
    for (final entry in values.entries) {
      await prefs.setString(entry.key, entry.value);
    }
  }

  /// True once a PIN has been set on this device (and therefore once a
  /// Stellar keypair exists to gate — both are created together).
  static Future<bool> hasPin() async {
    final stored = await _read([_pinVerifierKey]);
    final verifier = stored[_pinVerifierKey];
    return verifier != null && verifier.isNotEmpty;
  }

  /// True once the device holds a Stellar keypair (the thing the PIN gates).
  static Future<bool> hasWallet() => StellarKeyService.hasOptedIn();

  /// The registered public key (G…), or null if no keypair exists yet.
  static Future<String?> currentAddress() async {
    if (!await hasWallet()) return null;
    return (await StellarKeyService.getOrCreateKeyPair()).accountId;
  }

  /// One-time setup: generates the on-device Stellar keypair (idempotent)
  /// and sets the PIN that gates every future signature. Throws if a PIN
  /// already exists — changing a PIN is a separate, deliberate flow.
  static Future<String> provisionWallet(String pin) async {
    if (pin.length != 6 || int.tryParse(pin) == null) {
      throw const FormatException('PIN must be exactly 6 digits.');
    }
    if (await hasPin()) {
      throw StateError('A PIN is already set on this device.');
    }
    final keyPair = await StellarKeyService.getOrCreateKeyPair();
    await _storePinVerifier(pin);
    return keyPair.accountId;
  }

  /// Sets the PIN verifier for the first time.
  static Future<void> setPin(String pin) async {
    if (await hasPin()) {
      throw StateError('A PIN is already set — changing it is a separate flow.');
    }
    await _storePinVerifier(pin);
  }

  static Future<void> _storePinVerifier(String pin) async {
    final salt = CryptoUtils.bytesToHex(CryptoUtils.generateEd25519Seed());
    final verifier = CryptoUtils.sha256Hex('$salt:$pin');
    await _write({_pinSaltKey: salt, _pinVerifierKey: verifier});
  }

  /// Verifies [pin] against the stored verifier. No network, no backend.
  static Future<bool> verifyPin(String pin) async {
    final stored = await _read([_pinSaltKey, _pinVerifierKey]);
    final salt = stored[_pinSaltKey];
    final verifier = stored[_pinVerifierKey];
    if (salt == null || salt.isEmpty || verifier == null || verifier.isEmpty) {
      return false;
    }
    return CryptoUtils.sha256Hex('$salt:$pin') == verifier;
  }

  /// Signs [message] with the device's Stellar Ed25519 key after checking
  /// [pin]. This is the login signature: the backend verifies it against
  /// the user's registered public key. Throws on a wrong PIN.
  static Future<String> signChallenge(String message, String pin) async {
    if (!await verifyPin(pin)) {
      throw StateError('Incorrect PIN.');
    }
    final keyPair = await StellarKeyService.getOrCreateKeyPair();
    final signature = keyPair.sign(Uint8List.fromList(CryptoUtils.utf8Bytes(message)));
    return CryptoUtils.bytesToHex(signature);
  }

  /// Signs the raw bytes of an XDR transaction envelope with the device's
  /// Stellar key after checking [pin] — the one gateway for payment
  /// signing. [network] must match the network the transaction was built
  /// for (the StellarClient owns that knowledge). Throws on a wrong PIN.
  static Future<void> signTransaction(
    Transaction transaction,
    String pin,
    Network network,
  ) async {
    if (!await verifyPin(pin)) {
      throw StateError('Incorrect PIN.');
    }
    final keyPair = await StellarKeyService.getOrCreateKeyPair();
    transaction.sign(keyPair, network);
  }
}
