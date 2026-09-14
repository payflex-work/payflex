/// The PayFlex user. The Stellar public key is the PRIMARY account
/// identifier — it owns the funds, signs every payment, and proves login.
/// The secret seed never leaves the device.
class AppUser {
  final String id; // local PayFlex user id (Postgres row)
  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber;
  final String? stellarPublicKey;

  // HARD GATE (docs/fiat-kyc-gap.md): both default false on the backend
  // and NO code path can set them true until a real provider is plugged
  // in. Gated features must check these and refuse honestly.
  final bool identityVerified;
  final bool fiatCapable;

  AppUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phoneNumber,
    this.stellarPublicKey,
    this.identityVerified = false,
    this.fiatCapable = false,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
        email: json['email'] as String,
        phoneNumber: json['phoneNumber'] as String,
        stellarPublicKey: json['stellarPublicKey'] as String?,
        identityVerified: json['identityVerified'] as bool? ?? false,
        fiatCapable: json['fiatCapable'] as bool? ?? false,
      );
}

/// One balance line on the user's Stellar account (mirrors
/// backend/src/stellar/stellar.service.ts's getAccount response).
class AccountBalance {
  final String assetType; // "native" | "credit_alphanum4" | "credit_alphanum12" | "liquidity_pool_shares"
  final String? assetCode;
  final String? assetIssuer;
  final String balance;
  final String? limit;

  AccountBalance({
    required this.assetType,
    this.assetCode,
    this.assetIssuer,
    required this.balance,
    this.limit,
  });

  factory AccountBalance.fromJson(Map<String, dynamic> json) => AccountBalance(
        assetType: json['assetType'] as String,
        assetCode: json['assetCode'] as String?,
        assetIssuer: json['assetIssuer'] as String?,
        balance: json['balance'] as String,
        limit: json['limit'] as String?,
      );

  bool get isNative => assetType == 'native';
  String get displayCode => isNative ? 'XLM' : (assetCode ?? '?');
}
