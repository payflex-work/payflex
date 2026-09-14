/// Preview of a send-via-link share token, mirroring
/// backend/src/links/links.service.ts's preview response. Funds behind a
/// link sit in an on-chain claimable balance (chain escrow) — PayFlex
/// never holds them.
class ClaimPreview {
  final String linkId;
  final String? claimableBalanceId;
  final String amount;
  final String assetCode;
  final String status;
  final String expiresAt;
  final String senderName;
  final bool claimableBalanceExists;

  ClaimPreview({
    required this.linkId,
    this.claimableBalanceId,
    required this.amount,
    required this.assetCode,
    required this.status,
    required this.expiresAt,
    required this.senderName,
    required this.claimableBalanceExists,
  });

  factory ClaimPreview.fromJson(Map<String, dynamic> json) => ClaimPreview(
        linkId: json['linkId'] as String,
        claimableBalanceId: json['claimableBalanceId'] as String?,
        amount: json['amount'] as String,
        assetCode: json['assetCode'] as String,
        status: json['status'] as String,
        expiresAt: json['expiresAt'] as String,
        senderName: json['senderFirstName'] as String? ?? 'someone',
        claimableBalanceExists: json['claimableBalanceExists'] as bool? ?? false,
      );
}
