import 'dart:convert';
import 'dart:typed_data';
import 'crypto_utils.dart';

/// Exception thrown when a payment protocol payload is tampered, invalid, or expired.
class PaymentProtocolException implements Exception {
  final String message;
  PaymentProtocolException(this.message);

  @override
  String toString() => 'PaymentProtocolException: $message';
}

/// Canonical, versioned payment request payload (Phase 3 / Offline Protocol).
///
/// Created by the receiver / merchant to request payment. Signed with the
/// merchant device's Ed25519 key.
class PaymentRequest {
  static const String protocolVersion = 'pf-payreq-v1';

  final String requestId;
  final String merchantId; // bmoniUserId or PayTag
  final String? merchantName;
  final int amountMinorUnits;
  final String currency;
  final String? note;
  final String nonce;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String merchantPublicKey; // Hex-encoded 32-byte Ed25519 public key
  final String checksum; // SHA-256 over canonical serialized fields
  final String signature; // Hex-encoded 64-byte Ed25519 signature over checksum

  PaymentRequest({
    required this.requestId,
    required this.merchantId,
    this.merchantName,
    required this.amountMinorUnits,
    required this.currency,
    this.note,
    required this.nonce,
    required this.createdAt,
    required this.expiresAt,
    required this.merchantPublicKey,
    required this.checksum,
    required this.signature,
  });

  /// Creates and signs a new [PaymentRequest] using the merchant device's private seed.
  static PaymentRequest create({
    required String requestId,
    required String merchantId,
    String? merchantName,
    required int amountMinorUnits,
    required String currency,
    String? note,
    required String nonce,
    required DateTime createdAt,
    required DateTime expiresAt,
    required Uint8List merchantDeviceSeed,
  }) {
    final pubKeyBytes = CryptoUtils.ed25519PublicKeyFromSeed(merchantDeviceSeed);
    final merchantPublicKeyHex = CryptoUtils.bytesToHex(pubKeyBytes);

    final canonical = buildCanonicalString(
      version: protocolVersion,
      requestId: requestId,
      merchantId: merchantId,
      merchantName: merchantName ?? '',
      amountMinorUnits: amountMinorUnits,
      currency: currency.toUpperCase(),
      note: note ?? '',
      nonce: nonce,
      createdAtIso: createdAt.toUtc().toIso8601String(),
      expiresAtIso: expiresAt.toUtc().toIso8601String(),
      merchantPublicKey: merchantPublicKeyHex,
    );

    final checksum = CryptoUtils.sha256Hex(canonical);
    final sigBytes = CryptoUtils.signEd25519(
      CryptoUtils.utf8Bytes(checksum),
      merchantDeviceSeed,
    );
    final signatureHex = CryptoUtils.bytesToHex(sigBytes);

    return PaymentRequest(
      requestId: requestId,
      merchantId: merchantId,
      merchantName: merchantName,
      amountMinorUnits: amountMinorUnits,
      currency: currency.toUpperCase(),
      note: note,
      nonce: nonce,
      createdAt: createdAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
      merchantPublicKey: merchantPublicKeyHex,
      checksum: checksum,
      signature: signatureHex,
    );
  }

  /// Deterministic canonical serialization format for signing & hashing.
  static String buildCanonicalString({
    required String version,
    required String requestId,
    required String merchantId,
    required String merchantName,
    required int amountMinorUnits,
    required String currency,
    required String note,
    required String nonce,
    required String createdAtIso,
    required String expiresAtIso,
    required String merchantPublicKey,
  }) {
    return '$version|amountMinorUnits=$amountMinorUnits|createdAt=$createdAtIso|'
        'currency=$currency|expiresAt=$expiresAtIso|merchantId=$merchantId|'
        'merchantName=$merchantName|merchantPublicKey=$merchantPublicKey|'
        'nonce=$nonce|note=$note|requestId=$requestId';
  }

  String get canonicalString => buildCanonicalString(
        version: protocolVersion,
        requestId: requestId,
        merchantId: merchantId,
        merchantName: merchantName ?? '',
        amountMinorUnits: amountMinorUnits,
        currency: currency.toUpperCase(),
        note: note ?? '',
        nonce: nonce,
        createdAtIso: createdAt.toUtc().toIso8601String(),
        expiresAtIso: expiresAt.toUtc().toIso8601String(),
        merchantPublicKey: merchantPublicKey,
      );

  /// Verifies cryptographic integrity, expiry, and signature.
  void verify({DateTime? now}) {
    final currentTime = (now ?? DateTime.now()).toUtc();
    if (currentTime.isAfter(expiresAt)) {
      throw PaymentProtocolException('Payment request has expired ($expiresAt)');
    }
    if (amountMinorUnits <= 0) {
      throw PaymentProtocolException('Invalid payment amount ($amountMinorUnits)');
    }

    final expectedChecksum = CryptoUtils.sha256Hex(canonicalString);
    if (expectedChecksum.toLowerCase() != checksum.toLowerCase()) {
      throw PaymentProtocolException('Payment request checksum mismatch (tampered payload)');
    }

    final pubKeyBytes = CryptoUtils.hexToBytes(merchantPublicKey);
    final sigBytes = CryptoUtils.hexToBytes(signature);
    final validSig = CryptoUtils.verifyEd25519(
      CryptoUtils.utf8Bytes(checksum),
      sigBytes,
      pubKeyBytes,
    );

    if (!validSig) {
      throw PaymentProtocolException('Invalid merchant device signature');
    }
  }

  Map<String, dynamic> toJson() => {
        'version': protocolVersion,
        'requestId': requestId,
        'merchantId': merchantId,
        if (merchantName != null) 'merchantName': merchantName,
        'amountMinorUnits': amountMinorUnits,
        'currency': currency,
        if (note != null) 'note': note,
        'nonce': nonce,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'merchantPublicKey': merchantPublicKey,
        'checksum': checksum,
        'signature': signature,
      };

  factory PaymentRequest.fromJson(Map<String, dynamic> json) {
    return PaymentRequest(
      requestId: json['requestId'] as String,
      merchantId: json['merchantId'] as String,
      merchantName: json['merchantName'] as String?,
      amountMinorUnits: (json['amountMinorUnits'] as num).toInt(),
      currency: (json['currency'] as String).toUpperCase(),
      note: json['note'] as String?,
      nonce: json['nonce'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      merchantPublicKey: json['merchantPublicKey'] as String,
      checksum: json['checksum'] as String,
      signature: json['signature'] as String,
    );
  }

  String serialize() => jsonEncode(toJson());

  factory PaymentRequest.deserialize(String jsonString) =>
      PaymentRequest.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
}

/// Canonical, device-signed payment confirmation payload (Phase 3 / Offline Protocol).
///
/// Broadcast by the payer device back to the receiver (via optical QR or direct handoff)
/// to close the transaction loop.
class PaymentConfirmation {
  static const String protocolVersion = 'pf-payconf-v1';

  final String confirmationId;
  final String requestId; // Bound to the original PaymentRequest
  final String payerId; // Payer bmoniUserId or PayTag
  final String payerPublicKey; // Hex-encoded 32-byte Ed25519 public key
  final int amountMinorUnits;
  final String currency;
  final String status; // 'SETTLED' (online BMONI) or 'RESERVE_PENDING' (offline Reserve)
  final String? authorizationId; // Set if paid from Offline Reserve
  final DateTime timestamp;
  final String checksum; // SHA-256 over canonical serialized fields
  final String signature; // Hex-encoded 64-byte Ed25519 signature over checksum

  PaymentConfirmation({
    required this.confirmationId,
    required this.requestId,
    required this.payerId,
    required this.payerPublicKey,
    required this.amountMinorUnits,
    required this.currency,
    required this.status,
    this.authorizationId,
    required this.timestamp,
    required this.checksum,
    required this.signature,
  });

  /// Creates and signs a [PaymentConfirmation] using the payer device's private seed.
  static PaymentConfirmation create({
    required String confirmationId,
    required String requestId,
    required String payerId,
    required int amountMinorUnits,
    required String currency,
    required String status,
    String? authorizationId,
    required DateTime timestamp,
    required Uint8List payerDeviceSeed,
  }) {
    final pubKeyBytes = CryptoUtils.ed25519PublicKeyFromSeed(payerDeviceSeed);
    final payerPublicKeyHex = CryptoUtils.bytesToHex(pubKeyBytes);

    final canonical = buildCanonicalString(
      version: protocolVersion,
      confirmationId: confirmationId,
      requestId: requestId,
      payerId: payerId,
      payerPublicKey: payerPublicKeyHex,
      amountMinorUnits: amountMinorUnits,
      currency: currency.toUpperCase(),
      status: status,
      authorizationId: authorizationId ?? '',
      timestampIso: timestamp.toUtc().toIso8601String(),
    );

    final checksum = CryptoUtils.sha256Hex(canonical);
    final sigBytes = CryptoUtils.signEd25519(
      CryptoUtils.utf8Bytes(checksum),
      payerDeviceSeed,
    );
    final signatureHex = CryptoUtils.bytesToHex(sigBytes);

    return PaymentConfirmation(
      confirmationId: confirmationId,
      requestId: requestId,
      payerId: payerId,
      payerPublicKey: payerPublicKeyHex,
      amountMinorUnits: amountMinorUnits,
      currency: currency.toUpperCase(),
      status: status,
      authorizationId: authorizationId,
      timestamp: timestamp.toUtc(),
      checksum: checksum,
      signature: signatureHex,
    );
  }

  static String buildCanonicalString({
    required String version,
    required String confirmationId,
    required String requestId,
    required String payerId,
    required String payerPublicKey,
    required int amountMinorUnits,
    required String currency,
    required String status,
    required String authorizationId,
    required String timestampIso,
  }) {
    return '$version|amountMinorUnits=$amountMinorUnits|authorizationId=$authorizationId|'
        'confirmationId=$confirmationId|currency=$currency|payerId=$payerId|'
        'payerPublicKey=$payerPublicKey|requestId=$requestId|status=$status|timestamp=$timestampIso';
  }

  String get canonicalString => buildCanonicalString(
        version: protocolVersion,
        confirmationId: confirmationId,
        requestId: requestId,
        payerId: payerId,
        payerPublicKey: payerPublicKey,
        amountMinorUnits: amountMinorUnits,
        currency: currency.toUpperCase(),
        status: status,
        authorizationId: authorizationId ?? '',
        timestampIso: timestamp.toUtc().toIso8601String(),
      );

  /// Verifies confirmation integrity and binding against the original [request].
  void verifyAgainstRequest(PaymentRequest request) {
    if (requestId != request.requestId) {
      throw PaymentProtocolException('Confirmation requestId ($requestId) does not match request (${request.requestId})');
    }
    if (amountMinorUnits != request.amountMinorUnits) {
      throw PaymentProtocolException('Confirmation amount ($amountMinorUnits) does not match requested amount (${request.amountMinorUnits})');
    }
    if (currency.toUpperCase() != request.currency.toUpperCase()) {
      throw PaymentProtocolException('Confirmation currency ($currency) does not match requested currency (${request.currency})');
    }

    final expectedChecksum = CryptoUtils.sha256Hex(canonicalString);
    if (expectedChecksum.toLowerCase() != checksum.toLowerCase()) {
      throw PaymentProtocolException('Confirmation checksum mismatch (tampered payload)');
    }

    final pubKeyBytes = CryptoUtils.hexToBytes(payerPublicKey);
    final sigBytes = CryptoUtils.hexToBytes(signature);
    final validSig = CryptoUtils.verifyEd25519(
      CryptoUtils.utf8Bytes(checksum),
      sigBytes,
      pubKeyBytes,
    );

    if (!validSig) {
      throw PaymentProtocolException('Invalid payer device signature on confirmation');
    }
  }

  Map<String, dynamic> toJson() => {
        'version': protocolVersion,
        'confirmationId': confirmationId,
        'requestId': requestId,
        'payerId': payerId,
        'payerPublicKey': payerPublicKey,
        'amountMinorUnits': amountMinorUnits,
        'currency': currency,
        'status': status,
        if (authorizationId != null) 'authorizationId': authorizationId,
        'timestamp': timestamp.toIso8601String(),
        'checksum': checksum,
        'signature': signature,
      };

  factory PaymentConfirmation.fromJson(Map<String, dynamic> json) {
    return PaymentConfirmation(
      confirmationId: json['confirmationId'] as String,
      requestId: json['requestId'] as String,
      payerId: json['payerId'] as String,
      payerPublicKey: json['payerPublicKey'] as String,
      amountMinorUnits: (json['amountMinorUnits'] as num).toInt(),
      currency: (json['currency'] as String).toUpperCase(),
      status: json['status'] as String,
      authorizationId: json['authorizationId'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
      checksum: json['checksum'] as String,
      signature: json['signature'] as String,
    );
  }

  String serialize() => jsonEncode(toJson());

  factory PaymentConfirmation.deserialize(String jsonString) =>
      PaymentConfirmation.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
}

/// In-memory and persistent replay protector preventing duplicate requests or confirmations.
class ReplayProtector {
  static final ReplayProtector instance = ReplayProtector();

  final Set<String> _seenRequestIds = {};
  final Set<String> _seenNonces = {};
  final Set<String> _seenConfirmations = {};

  bool isRequestSeen(String requestId, String nonce) {
    return _seenRequestIds.contains(requestId) || _seenNonces.contains(nonce);
  }

  void recordRequest(String requestId, String nonce) {
    if (isRequestSeen(requestId, nonce)) {
      throw PaymentProtocolException('Replay detected: request ID or nonce already processed');
    }
    _seenRequestIds.add(requestId);
    _seenNonces.add(nonce);
  }

  bool isConfirmationSeen(String confirmationId) {
    return _seenConfirmations.contains(confirmationId);
  }

  void recordConfirmation(String confirmationId) {
    if (isConfirmationSeen(confirmationId)) {
      throw PaymentProtocolException('Replay detected: confirmation ID already processed');
    }
    _seenConfirmations.add(confirmationId);
  }

  void reset() {
    _seenRequestIds.clear();
    _seenNonces.clear();
    _seenConfirmations.clear();
  }
}
