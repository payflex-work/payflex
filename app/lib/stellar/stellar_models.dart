/// One balance line for an account — either native XLM (assetCode/issuer
/// null) or a trustline to an issued asset.
class StellarBalance {
  final String assetType; // "native" | "credit_alphanum4" | "credit_alphanum12"
  final String? assetCode;
  final String? assetIssuer;
  final String balance;
  final String? limit;

  const StellarBalance({
    required this.assetType,
    this.assetCode,
    this.assetIssuer,
    required this.balance,
    this.limit,
  });

  bool get isNative => assetType == 'native';
  String get displayCode => isNative ? 'XLM' : (assetCode ?? '?');
}

/// Funded on-chain account summary — balances double as the trustline
/// list (any non-native balance IS a trustline).
class StellarAccountSummary {
  final String publicKey;
  final List<StellarBalance> balances;

  const StellarAccountSummary({required this.publicKey, required this.balances});

  bool hasTrustlineFor(String assetCode, String issuer) => balances.any(
        (b) => !b.isNative && b.assetCode == assetCode && b.assetIssuer == issuer,
      );
}

class StellarHistoryEntry {
  final String id;
  final String transactionHash;
  final String type;
  final DateTime createdAt;

  const StellarHistoryEntry({
    required this.id,
    required this.transactionHash,
    required this.type,
    required this.createdAt,
  });
}

class StellarPaymentResult {
  final bool success;
  final String? transactionHash;
  final String? errorCode; // e.g. "op_no_trust", "op_underfunded" — see StellarErrors.
  final String? errorMessage; // Human-readable, ready to show the user.

  const StellarPaymentResult({
    required this.success,
    this.transactionHash,
    this.errorCode,
    this.errorMessage,
  });
}
