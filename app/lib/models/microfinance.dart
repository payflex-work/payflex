/// Standing-plan and (paused) agent models for the Stellar-only app,
/// mirroring backend/prisma/schema.prisma's StandingPlan/StandingPlanPayment.
library;

class StandingPlan {
  final String id;
  final String name;
  final String assetCode;
  final String? assetIssuer;
  final String amount;
  final String frequency;
  final String? toPublicKey;
  final String? toPayTag;
  final String? description;
  final String status;
  final String totalPaid;

  StandingPlan({
    required this.id,
    required this.name,
    required this.assetCode,
    this.assetIssuer,
    required this.amount,
    required this.frequency,
    this.toPublicKey,
    this.toPayTag,
    this.description,
    required this.status,
    required this.totalPaid,
  });

  factory StandingPlan.fromJson(Map<String, dynamic> json) => StandingPlan(
        id: json['id'] as String,
        name: json['name'] as String,
        assetCode: json['assetCode'] as String,
        assetIssuer: json['assetIssuer'] as String?,
        amount: json['amount'] as String,
        frequency: json['frequency'] as String,
        toPublicKey: json['toPublicKey'] as String?,
        toPayTag: json['toPayTag'] as String?,
        description: json['description'] as String?,
        status: json['status'] as String? ?? 'ACTIVE',
        totalPaid: json['totalPaid'] as String? ?? '0',
      );
}

class StandingPlanPayment {
  final String id;
  final String amount;
  final String status;
  final String dueAt;
  final StandingPlan? plan;

  StandingPlanPayment({
    required this.id,
    required this.amount,
    required this.status,
    required this.dueAt,
    this.plan,
  });

  factory StandingPlanPayment.fromJson(Map<String, dynamic> json) =>
      StandingPlanPayment(
        id: json['id'] as String,
        amount: json['amount'] as String,
        status: json['status'] as String,
        dueAt: json['dueAt'] as String,
        plan: json['standingPlan'] != null
            ? StandingPlan.fromJson(json['standingPlan'] as Map<String, dynamic>)
            : null,
      );
}
