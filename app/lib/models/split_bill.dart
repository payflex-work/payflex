/// Mirrors backend/prisma/schema.prisma's SplitBill/SplitBillContributor —
/// pure orchestration: the bill tracks who owes what; each contributor
/// pays the creator with their own on-device Stellar payment, recorded
/// (and verified on Horizon) by the backend with splitBillId set.
class SplitBillContributor {
  final String id;
  final String appUserId;
  final String shareAmount;
  final String status; // PENDING | RECORDED

  SplitBillContributor({
    required this.id,
    required this.appUserId,
    required this.shareAmount,
    required this.status,
  });

  factory SplitBillContributor.fromJson(Map<String, dynamic> json) => SplitBillContributor(
        id: json['id'] as String,
        appUserId: json['appUserId'] as String,
        shareAmount: json['shareAmount'] as String,
        status: json['status'] as String? ?? 'PENDING',
      );
}

class SplitBill {
  final String id;
  final String creatorAppUserId;
  final String description;
  final String assetCode;
  final String totalAmount;
  final String status; // ACTIVE | COMPLETED | CANCELLED
  final List<SplitBillContributor> contributors;

  SplitBill({
    required this.id,
    required this.creatorAppUserId,
    required this.description,
    required this.assetCode,
    required this.totalAmount,
    required this.status,
    required this.contributors,
  });

  factory SplitBill.fromJson(Map<String, dynamic> json) => SplitBill(
        id: json['id'] as String,
        creatorAppUserId: json['creatorAppUserId'] as String,
        description: json['description'] as String,
        assetCode: json['assetCode'] as String,
        totalAmount: json['totalAmount'] as String,
        status: json['status'] as String? ?? 'ACTIVE',
        contributors: (json['contributors'] as List? ?? [])
            .map((e) => SplitBillContributor.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
