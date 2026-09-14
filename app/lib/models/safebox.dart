/// Safebox models for the Soroban escrow contract (backend/contracts/
/// safebox). Roles come from CHAIN state (owner + admin list), not from a
/// database; the ledger comes from the contract's own storage. There is
/// deliberately no `proposalId`/treasury-signing concept anymore — every
/// ledger entry is an on-chain fact.
library;

enum SafeboxRole { owner, admin, member }

extension SafeboxRoleExtension on SafeboxRole {
  String get label {
    switch (this) {
      case SafeboxRole.owner:
        return 'Owner';
      case SafeboxRole.admin:
        return 'Admin';
      case SafeboxRole.member:
        return 'Member';
    }
  }

  bool get canWithdraw => this == SafeboxRole.owner || this == SafeboxRole.admin;
  bool get isOwner => this == SafeboxRole.owner;
}

enum SafeboxTxType { contribution, withdrawal }

/// One entry of the contract's on-chain ledger (get_ledger), already
/// decoded by SafeboxService/backend from the contract's i128 amounts.
class SafeboxTransaction {
  final String id;
  final SafeboxTxType type;
  final String memberPublicKey;
  final String amount; // decimal string, contract precision
  final DateTime createdAt;

  const SafeboxTransaction({
    required this.id,
    required this.type,
    required this.memberPublicKey,
    required this.amount,
    required this.createdAt,
  });

  /// Builds from the chain ledger row shape:
  /// `{ entry_type, member, amount, created_at }` (index used as id).
  factory SafeboxTransaction.fromChain(Map<String, dynamic> json, {int index = 0}) {
    final isWithdrawal =
        (json['entry_type'] as String? ?? '').toLowerCase() == 'withdrawal';
    final ts = (json['created_at'] as num? ?? 0).toInt();
    return SafeboxTransaction(
      id: '${json['member'] ?? ''}-$ts-$index',
      type: isWithdrawal ? SafeboxTxType.withdrawal : SafeboxTxType.contribution,
      memberPublicKey: json['member'] as String? ?? '',
      amount: json['amount'] as String? ?? '0',
      createdAt: ts > 0
          ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
          : DateTime.now(),
    );
  }
}

/// Shortens a public key for display: `GABCD…WXYZ`.
String shortPublicKey(String pk) {
  if (pk.length <= 12) return pk;
  return '${pk.substring(0, 5)}…${pk.substring(pk.length - 4)}';
}
