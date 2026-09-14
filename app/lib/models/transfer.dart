/// PayTag resolution, transfer-record confirmation, and QR payload models
/// mirroring backend/src/transfer (Stellar-native).
class PayTagUser {
  final String appUserId;
  final String? stellarPublicKey;
  final String firstName;
  final String lastName;

  PayTagUser({
    required this.appUserId,
    this.stellarPublicKey,
    required this.firstName,
    required this.lastName,
  });

  factory PayTagUser.fromJson(Map<String, dynamic> json) => PayTagUser(
        appUserId: json['appUserId'] as String,
        stellarPublicKey: json['stellarPublicKey'] as String?,
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
      );
}

/// Result of POST /users/:id/transfers/resolve — the destination public key
/// the app builds the on-device payment against, plus a display name.
class TransferTarget {
  final String toPublicKey;
  final String firstName;
  final String lastName;

  TransferTarget({
    required this.toPublicKey,
    required this.firstName,
    required this.lastName,
  });

  factory TransferTarget.fromJson(Map<String, dynamic> json) => TransferTarget(
        toPublicKey: json['toPublicKey'] as String,
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
      );

  String get displayName => '$firstName $lastName';
}

/// The backend's stored copy of a payment the app already made on-chain.
/// Created only after the backend verified the real Horizon transaction
/// matches every field — see backend/src/transfer/transfer.service.ts.
class TransferRecord {
  final String id;
  final String stellarTxHash;
  final String fromPublicKey;
  final String toPublicKey;
  final String amount;
  final String assetCode;
  final String? assetIssuer;
  final String kind;
  final String? memo;
  final String createdAt;

  TransferRecord({
    required this.id,
    required this.stellarTxHash,
    required this.fromPublicKey,
    required this.toPublicKey,
    required this.amount,
    required this.assetCode,
    this.assetIssuer,
    required this.kind,
    this.memo,
    required this.createdAt,
  });

  factory TransferRecord.fromJson(Map<String, dynamic> json) => TransferRecord(
        id: json['id'] as String,
        stellarTxHash: json['stellarTxHash'] as String,
        fromPublicKey: json['fromPublicKey'] as String,
        toPublicKey: json['toPublicKey'] as String,
        amount: json['amount'] as String,
        assetCode: json['assetCode'] as String,
        assetIssuer: json['assetIssuer'] as String?,
        kind: json['kind'] as String? ?? 'TRANSFER',
        memo: json['memo'] as String?,
        createdAt: json['createdAt'] as String,
      );
}

/// Payload carried inside the HMAC-signed QR token (see
/// backend/src/transfer/qr-pay.service.ts). The payer's app resolves it
/// via the public /qr/decode endpoint before building the payment.
class QrPayload {
  final String recipientAppUserId;
  final String recipientStellarPublicKey;
  final String amount;
  final String assetCode;
  final String? assetIssuer;
  final String expiresAt;

  QrPayload({
    required this.recipientAppUserId,
    required this.recipientStellarPublicKey,
    required this.amount,
    required this.assetCode,
    this.assetIssuer,
    required this.expiresAt,
  });

  factory QrPayload.fromJson(Map<String, dynamic> json) => QrPayload(
        recipientAppUserId: json['recipientAppUserId'] as String,
        recipientStellarPublicKey: json['recipientStellarPublicKey'] as String,
        amount: json['amount'] as String,
        assetCode: json['assetCode'] as String,
        assetIssuer: json['assetIssuer'] as String?,
        expiresAt: json['expiresAt'] as String,
      );
}

/// Shared status label used across every transfer payoff. Known kinds map
/// to product language; anything else falls back to plain Title Case so a
/// new backend kind never renders as raw code.
String humanTransferStatus(String status) {
  switch (status.toUpperCase()) {
    case 'OFFLINE_REDEMPTION':
      return 'Offline payment';
    case 'QR_PAY':
      return 'QR payment';
    case 'TRANSFER':
      return 'Direct payment';
    case 'SPLIT_BILL':
      return 'Split bill';
    case 'STANDING_PLAN':
      return 'Standing plan';
    case 'LINK_CLAIM':
      return 'Link claim';
  }
  final words = status.toLowerCase().split('_');
  if (words.isEmpty) return status;
  return words.map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}
