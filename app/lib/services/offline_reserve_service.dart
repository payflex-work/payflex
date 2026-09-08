import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../protocol/crypto_utils.dart';
import '../protocol/payment_protocol.dart';
import 'device_key_service.dart';

/// Exception thrown when an offline reserve operation fails.
class OfflineReserveException implements Exception {
  final String message;
  OfflineReserveException(this.message);

  @override
  String toString() => 'OfflineReserveException: $message';
}

/// A pre-authorized offline spendable balance certificate.
///
/// Created and signed while online, granting the device authority to issue
/// cryptographically chained [OfflineAuthorization]s up to [initialAmountMinorUnits].
class ReserveAllowance {
  static const String protocolVersion = 'pf-allowance-v1';

  final String allowanceId;
  final String appUserId;
  final String bmoniUserId;
  final int initialAmountMinorUnits;
  int remainingAmountMinorUnits;
  final String currency;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String devicePublicKey;
  int currentSequenceNumber;
  String lastStateHash;
  final String signature; // Device Ed25519 signature over canonical allowance

  ReserveAllowance({
    required this.allowanceId,
    required this.appUserId,
    required this.bmoniUserId,
    required this.initialAmountMinorUnits,
    required this.remainingAmountMinorUnits,
    required this.currency,
    required this.createdAt,
    required this.expiresAt,
    required this.devicePublicKey,
    required this.currentSequenceNumber,
    required this.lastStateHash,
    required this.signature,
  });

  /// Canonical serialization of the allowance definition.
  static String buildCanonicalString({
    required String version,
    required String allowanceId,
    required String appUserId,
    required String bmoniUserId,
    required int initialAmountMinorUnits,
    required String currency,
    required String createdAtIso,
    required String expiresAtIso,
    required String devicePublicKey,
  }) {
    return '$version|allowanceId=$allowanceId|appUserId=$appUserId|bmoniUserId=$bmoniUserId|'
        'currency=$currency|devicePublicKey=$devicePublicKey|expiresAt=$expiresAtIso|'
        'createdAt=$createdAtIso|initialAmountMinorUnits=$initialAmountMinorUnits';
  }

  String get canonicalString => buildCanonicalString(
        version: protocolVersion,
        allowanceId: allowanceId,
        appUserId: appUserId,
        bmoniUserId: bmoniUserId,
        initialAmountMinorUnits: initialAmountMinorUnits,
        currency: currency.toUpperCase(),
        createdAtIso: createdAt.toUtc().toIso8601String(),
        expiresAtIso: expiresAt.toUtc().toIso8601String(),
        devicePublicKey: devicePublicKey,
      );

  bool isExpired({DateTime? now}) {
    final t = (now ?? DateTime.now()).toUtc();
    return t.isAfter(expiresAt);
  }

  /// Verifies signature and integrity of this allowance certificate.
  void verify() {
    final expectedChecksum = CryptoUtils.sha256Hex(canonicalString);
    final pubKeyBytes = CryptoUtils.hexToBytes(devicePublicKey);
    final sigBytes = CryptoUtils.hexToBytes(signature);

    final valid = CryptoUtils.verifyEd25519(
      CryptoUtils.utf8Bytes(expectedChecksum),
      sigBytes,
      pubKeyBytes,
    );
    if (!valid) {
      throw OfflineReserveException('Invalid allowance certificate signature');
    }
  }

  Map<String, dynamic> toJson() => {
        'version': protocolVersion,
        'allowanceId': allowanceId,
        'appUserId': appUserId,
        'bmoniUserId': bmoniUserId,
        'initialAmountMinorUnits': initialAmountMinorUnits,
        'remainingAmountMinorUnits': remainingAmountMinorUnits,
        'currency': currency,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'devicePublicKey': devicePublicKey,
        'currentSequenceNumber': currentSequenceNumber,
        'lastStateHash': lastStateHash,
        'signature': signature,
      };

  factory ReserveAllowance.fromJson(Map<String, dynamic> json) {
    return ReserveAllowance(
      allowanceId: json['allowanceId'] as String,
      appUserId: json['appUserId'] as String,
      bmoniUserId: json['bmoniUserId'] as String,
      initialAmountMinorUnits: (json['initialAmountMinorUnits'] as num).toInt(),
      remainingAmountMinorUnits: (json['remainingAmountMinorUnits'] as num).toInt(),
      currency: (json['currency'] as String).toUpperCase(),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      devicePublicKey: json['devicePublicKey'] as String,
      currentSequenceNumber: (json['currentSequenceNumber'] as num).toInt(),
      lastStateHash: json['lastStateHash'] as String,
      signature: json['signature'] as String,
    );
  }
}

/// A device-signed, state-chained offline payment authorization.
///
/// Issued by the payer device while offline, committing funds from an active
/// [ReserveAllowance] to satisfy a specific [PaymentRequest].
class OfflineAuthorization {
  static const String protocolVersion = 'pf-auth-v1';

  final String authorizationId;
  final String allowanceId;
  final String requestId; // Bound to the specific PaymentRequest
  final String merchantId;
  final int amountMinorUnits;
  final String currency;
  final int sequenceNumber; // Monotonic counter (1, 2, 3...)
  final String previousAuthHash; // Hash of prior state/auth
  final String stateHash; // SHA-256 over canonical fields + previousAuthHash
  final DateTime timestamp;
  final String devicePublicKey;
  final String signature; // Hex-encoded Ed25519 signature over stateHash

  OfflineAuthorization({
    required this.authorizationId,
    required this.allowanceId,
    required this.requestId,
    required this.merchantId,
    required this.amountMinorUnits,
    required this.currency,
    required this.sequenceNumber,
    required this.previousAuthHash,
    required this.stateHash,
    required this.timestamp,
    required this.devicePublicKey,
    required this.signature,
  });

  /// Deterministic canonical serialization format for computing stateHash.
  static String buildCanonicalStateString({
    required String version,
    required String authorizationId,
    required String allowanceId,
    required String requestId,
    required String merchantId,
    required int amountMinorUnits,
    required String currency,
    required int sequenceNumber,
    required String previousAuthHash,
    required String timestampIso,
    required String devicePublicKey,
  }) {
    return '$version|allowanceId=$allowanceId|amountMinorUnits=$amountMinorUnits|'
        'authorizationId=$authorizationId|currency=$currency|devicePublicKey=$devicePublicKey|'
        'merchantId=$merchantId|previousAuthHash=$previousAuthHash|requestId=$requestId|'
        'sequenceNumber=$sequenceNumber|timestamp=$timestampIso';
  }

  String get canonicalStateString => buildCanonicalStateString(
        version: protocolVersion,
        authorizationId: authorizationId,
        allowanceId: allowanceId,
        requestId: requestId,
        merchantId: merchantId,
        amountMinorUnits: amountMinorUnits,
        currency: currency.toUpperCase(),
        sequenceNumber: sequenceNumber,
        previousAuthHash: previousAuthHash,
        timestampIso: timestamp.toUtc().toIso8601String(),
        devicePublicKey: devicePublicKey,
      );

  /// Independently verifies this authorization against its signature and stateHash.
  void verifyIntegrity({PaymentRequest? boundRequest}) {
    if (amountMinorUnits <= 0) {
      throw OfflineReserveException('Authorization amount must be positive');
    }
    if (sequenceNumber <= 0) {
      throw OfflineReserveException('Invalid sequence number ($sequenceNumber)');
    }

    final computedHash = CryptoUtils.sha256Hex(canonicalStateString);
    if (computedHash.toLowerCase() != stateHash.toLowerCase()) {
      throw OfflineReserveException('Authorization state hash mismatch (tampered authorization)');
    }

    final pubBytes = CryptoUtils.hexToBytes(devicePublicKey);
    final sigBytes = CryptoUtils.hexToBytes(signature);
    final valid = CryptoUtils.verifyEd25519(
      CryptoUtils.utf8Bytes(stateHash),
      sigBytes,
      pubBytes,
    );

    if (!valid) {
      throw OfflineReserveException('Invalid device signature on offline authorization');
    }

    if (boundRequest != null) {
      if (requestId != boundRequest.requestId) {
        throw OfflineReserveException('Authorization requestId ($requestId) does not match request (${boundRequest.requestId})');
      }
      if (amountMinorUnits != boundRequest.amountMinorUnits) {
        throw OfflineReserveException('Authorization amount ($amountMinorUnits) does not match requested amount (${boundRequest.amountMinorUnits})');
      }
      if (currency.toUpperCase() != boundRequest.currency.toUpperCase()) {
        throw OfflineReserveException('Authorization currency ($currency) does not match requested currency (${boundRequest.currency})');
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'version': protocolVersion,
        'authorizationId': authorizationId,
        'allowanceId': allowanceId,
        'requestId': requestId,
        'merchantId': merchantId,
        'amountMinorUnits': amountMinorUnits,
        'currency': currency,
        'sequenceNumber': sequenceNumber,
        'previousAuthHash': previousAuthHash,
        'stateHash': stateHash,
        'timestamp': timestamp.toIso8601String(),
        'devicePublicKey': devicePublicKey,
        'signature': signature,
      };

  factory OfflineAuthorization.fromJson(Map<String, dynamic> json) {
    return OfflineAuthorization(
      authorizationId: json['authorizationId'] as String,
      allowanceId: json['allowanceId'] as String,
      requestId: json['requestId'] as String,
      merchantId: json['merchantId'] as String,
      amountMinorUnits: (json['amountMinorUnits'] as num).toInt(),
      currency: (json['currency'] as String).toUpperCase(),
      sequenceNumber: (json['sequenceNumber'] as num).toInt(),
      previousAuthHash: json['previousAuthHash'] as String,
      stateHash: json['stateHash'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
      devicePublicKey: json['devicePublicKey'] as String,
      signature: json['signature'] as String,
    );
  }
}

/// Service managing offline reserve allowance provisioning, spend authorization chaining,
/// and local verification.
class OfflineReserveService {
  static const String _allowancePrefix = 'payflex_reserve_allowance_';
  static const String _authQueueKey = 'payflex_offline_auth_queue_v1';

  final Map<String, ReserveAllowance> _inMemoryAllowances = {};
  final List<OfflineAuthorization> _pendingAuthQueue = [];

  /// Injected storage hook for testing.
  Future<String?> Function(String key)? storageGetHook;
  Future<void> Function(String key, String value)? storageSetHook;

  /// Provisions a new [ReserveAllowance] while online.
  ///
  /// Requires connectivity to verify user balance. The allowance is signed by
  /// the device key and stored locally.
  Future<ReserveAllowance> provisionAllowance({
    required String appUserId,
    required String bmoniUserId,
    required int amountMinorUnits,
    required String currency,
    Duration validity = const Duration(hours: 24),
    Uint8List? explicitDeviceSeed,
  }) async {
    if (amountMinorUnits <= 0) {
      throw OfflineReserveException('Allowance amount must be greater than zero');
    }

    final seed = explicitDeviceSeed ?? await DeviceKeyService.getPrivateSeed();
    final pubKeyBytes = CryptoUtils.ed25519PublicKeyFromSeed(seed);
    final pubKeyHex = CryptoUtils.bytesToHex(pubKeyBytes);

    final now = DateTime.now().toUtc();
    final expiresAt = now.add(validity);
    final allowanceId = 'alw_${CryptoUtils.bytesToHex(CryptoUtils.generateEd25519Seed()).substring(0, 16)}';

    final canonical = ReserveAllowance.buildCanonicalString(
      version: ReserveAllowance.protocolVersion,
      allowanceId: allowanceId,
      appUserId: appUserId,
      bmoniUserId: bmoniUserId,
      initialAmountMinorUnits: amountMinorUnits,
      currency: currency.toUpperCase(),
      createdAtIso: now.toIso8601String(),
      expiresAtIso: expiresAt.toIso8601String(),
      devicePublicKey: pubKeyHex,
    );

    final checksum = CryptoUtils.sha256Hex(canonical);
    final sigBytes = CryptoUtils.signEd25519(
      CryptoUtils.utf8Bytes(checksum),
      seed,
    );
    final signatureHex = CryptoUtils.bytesToHex(sigBytes);

    final allowance = ReserveAllowance(
      allowanceId: allowanceId,
      appUserId: appUserId,
      bmoniUserId: bmoniUserId,
      initialAmountMinorUnits: amountMinorUnits,
      remainingAmountMinorUnits: amountMinorUnits,
      currency: currency.toUpperCase(),
      createdAt: now,
      expiresAt: expiresAt,
      devicePublicKey: pubKeyHex,
      currentSequenceNumber: 0,
      lastStateHash: checksum,
      signature: signatureHex,
    );

    _inMemoryAllowances[currency.toUpperCase()] = allowance;
    await _saveAllowance(allowance);

    return allowance;
  }

  /// Retrieves the active [ReserveAllowance] for a given [currency].
  Future<ReserveAllowance?> getActiveAllowance(String currency) async {
    final cur = currency.toUpperCase();
    if (_inMemoryAllowances.containsKey(cur)) {
      final alw = _inMemoryAllowances[cur]!;
      if (!alw.isExpired()) return alw;
    }

    final saved = await _loadAllowance(cur);
    if (saved != null && !saved.isExpired()) {
      _inMemoryAllowances[cur] = saved;
      return saved;
    }
    return null;
  }

  /// Spends funds from the active reserve allowance to satisfy [request].
  ///
  /// Increments sequence number, produces chained [OfflineAuthorization],
  /// creates [PaymentConfirmation], and queues for future redemption.
  Future<({OfflineAuthorization authorization, PaymentConfirmation confirmation})> spendFromReserve({
    required PaymentRequest request,
    Uint8List? explicitDeviceSeed,
  }) async {
    request.verify();

    final allowance = await getActiveAllowance(request.currency);
    if (allowance == null) {
      throw OfflineReserveException('No active Reserve allowance found for ${request.currency}');
    }
    if (allowance.isExpired()) {
      throw OfflineReserveException('Reserve allowance for ${request.currency} has expired');
    }
    if (allowance.remainingAmountMinorUnits < request.amountMinorUnits) {
      throw OfflineReserveException(
        'Insufficient offline reserve balance: requested ${request.amountMinorUnits}, remaining ${allowance.remainingAmountMinorUnits}',
      );
    }

    final seed = explicitDeviceSeed ?? await DeviceKeyService.getPrivateSeed();
    final pubKeyBytes = CryptoUtils.ed25519PublicKeyFromSeed(seed);
    final pubKeyHex = CryptoUtils.bytesToHex(pubKeyBytes);

    final nextSeq = allowance.currentSequenceNumber + 1;
    final now = DateTime.now().toUtc();
    final authId = 'auth_${CryptoUtils.bytesToHex(CryptoUtils.generateEd25519Seed()).substring(0, 16)}';
    final previousHash = allowance.lastStateHash;

    final canonicalState = OfflineAuthorization.buildCanonicalStateString(
      version: OfflineAuthorization.protocolVersion,
      authorizationId: authId,
      allowanceId: allowance.allowanceId,
      requestId: request.requestId,
      merchantId: request.merchantId,
      amountMinorUnits: request.amountMinorUnits,
      currency: request.currency.toUpperCase(),
      sequenceNumber: nextSeq,
      previousAuthHash: previousHash,
      timestampIso: now.toIso8601String(),
      devicePublicKey: pubKeyHex,
    );

    final stateHash = CryptoUtils.sha256Hex(canonicalState);
    final sigBytes = CryptoUtils.signEd25519(
      CryptoUtils.utf8Bytes(stateHash),
      seed,
    );
    final signatureHex = CryptoUtils.bytesToHex(sigBytes);

    final authorization = OfflineAuthorization(
      authorizationId: authId,
      allowanceId: allowance.allowanceId,
      requestId: request.requestId,
      merchantId: request.merchantId,
      amountMinorUnits: request.amountMinorUnits,
      currency: request.currency.toUpperCase(),
      sequenceNumber: nextSeq,
      previousAuthHash: previousHash,
      stateHash: stateHash,
      timestamp: now,
      devicePublicKey: pubKeyHex,
      signature: signatureHex,
    );

    // Update allowance state
    allowance.remainingAmountMinorUnits -= request.amountMinorUnits;
    allowance.currentSequenceNumber = nextSeq;
    allowance.lastStateHash = stateHash;

    await _saveAllowance(allowance);
    await _enqueuePendingAuthorization(authorization);

    // Create payment confirmation
    final confId = 'conf_${CryptoUtils.bytesToHex(CryptoUtils.generateEd25519Seed()).substring(0, 16)}';
    final confirmation = PaymentConfirmation.create(
      confirmationId: confId,
      requestId: request.requestId,
      payerId: allowance.bmoniUserId,
      amountMinorUnits: request.amountMinorUnits,
      currency: request.currency.toUpperCase(),
      status: 'RESERVE_PENDING',
      authorizationId: authId,
      timestamp: now,
      payerDeviceSeed: seed,
    );

    return (authorization: authorization, confirmation: confirmation);
  }

  /// Verifies an [OfflineAuthorization] independently from its fields alone.
  static void verifyOfflineAuthorization(
    OfflineAuthorization auth, {
    PaymentRequest? boundRequest,
    ReserveAllowance? allowanceCertificate,
  }) {
    auth.verifyIntegrity(boundRequest: boundRequest);

    if (allowanceCertificate != null) {
      allowanceCertificate.verify();
      if (auth.allowanceId != allowanceCertificate.allowanceId) {
        throw OfflineReserveException('Authorization allowanceId does not match certificate');
      }
      if (auth.devicePublicKey.toLowerCase() != allowanceCertificate.devicePublicKey.toLowerCase()) {
        throw OfflineReserveException('Authorization device key does not match allowance key');
      }
    }
  }

  Future<List<OfflineAuthorization>> getPendingRedemptionQueue() async {
    if (_pendingAuthQueue.isNotEmpty) return List.unmodifiable(_pendingAuthQueue);
    return _loadAuthQueue();
  }

  Future<void> removePendingAuthorization(String authorizationId) async {
    _pendingAuthQueue.removeWhere((a) => a.authorizationId == authorizationId);
    await _saveAuthQueue();
  }

  // ---------------------------------------------------------------------------
  // Internal persistence helpers
  // ---------------------------------------------------------------------------

  Future<void> _saveAllowance(ReserveAllowance allowance) async {
    final raw = jsonEncode(allowance.toJson());
    final key = '$_allowancePrefix${allowance.currency.toUpperCase()}';
    if (storageSetHook != null) {
      await storageSetHook!(key, raw);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, raw);
    }
  }

  Future<ReserveAllowance?> _loadAllowance(String currency) async {
    final key = '$_allowancePrefix${currency.toUpperCase()}';
    String? raw;
    if (storageGetHook != null) {
      raw = await storageGetHook!(key);
    } else {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(key);
    }
    if (raw == null || raw.isEmpty) return null;
    return ReserveAllowance.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _enqueuePendingAuthorization(OfflineAuthorization auth) async {
    _pendingAuthQueue.add(auth);
    await _saveAuthQueue();
  }

  Future<void> _saveAuthQueue() async {
    final raw = jsonEncode(_pendingAuthQueue.map((a) => a.toJson()).toList());
    if (storageSetHook != null) {
      await storageSetHook!(_authQueueKey, raw);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_authQueueKey, raw);
    }
  }

  Future<List<OfflineAuthorization>> _loadAuthQueue() async {
    String? raw;
    if (storageGetHook != null) {
      raw = await storageGetHook!(_authQueueKey);
    } else {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_authQueueKey);
    }
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    final res = list.map((e) => OfflineAuthorization.fromJson(e as Map<String, dynamic>)).toList();
    _pendingAuthQueue
      ..clear()
      ..addAll(res);
    return res;
  }
}
