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

enum SafeboxStatus { active, closed }

enum SafeboxTxType { contribution, withdrawal }

class SafeboxMemberModel {
  final String id;
  final String safeboxId;
  final String userId;
  final String name;
  final String avatarUrl;
  final SafeboxRole role;
  final DateTime joinedAt;

  const SafeboxMemberModel({
    required this.id,
    required this.safeboxId,
    required this.userId,
    required this.name,
    this.avatarUrl = '',
    required this.role,
    required this.joinedAt,
  });

  factory SafeboxMemberModel.fromJson(Map<String, dynamic> json) {
    SafeboxRole parsedRole = SafeboxRole.member;
    final rStr = (json['role'] as String? ?? 'MEMBER').toUpperCase();
    if (rStr == 'OWNER') parsedRole = SafeboxRole.owner;
    if (rStr == 'ADMIN') parsedRole = SafeboxRole.admin;

    return SafeboxMemberModel(
      id: json['id'] ?? '',
      safeboxId: json['safeboxId'] ?? '',
      userId: json['userId'] ?? '',
      name: json['name'] ?? json['userId'] ?? 'Member',
      avatarUrl: json['avatarUrl'] ?? '',
      role: parsedRole,
      joinedAt: json['joinedAt'] != null
          ? DateTime.parse(json['joinedAt'])
          : DateTime.now(),
    );
  }
}

class SafeboxModel {
  final String id;
  final String name;
  final String description;
  final String ownerId;
  final double? targetAmount;
  final double currentBalance;
  final SafeboxStatus status;
  final DateTime createdAt;
  final SafeboxRole userRole;

  const SafeboxModel({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    this.targetAmount,
    required this.currentBalance,
    required this.status,
    required this.createdAt,
    required this.userRole,
  });

  double get progressPercentage {
    if (targetAmount == null || targetAmount! <= 0) return 0.0;
    return (currentBalance / targetAmount!).clamp(0.0, 1.0);
  }

  factory SafeboxModel.fromJson(Map<String, dynamic> json, {SafeboxRole role = SafeboxRole.member}) {
    return SafeboxModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      ownerId: json['ownerId'] ?? '',
      targetAmount: json['targetAmount'] != null
          ? (json['targetAmount'] as num).toDouble()
          : null,
      currentBalance: json['currentBalance'] != null
          ? (json['currentBalance'] as num).toDouble()
          : 0.0,
      status: json['status'] == 'CLOSED' ? SafeboxStatus.closed : SafeboxStatus.active,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      userRole: role,
    );
  }
}

class SafeboxTransactionModel {
  final String id;
  final String safeboxId;
  final String userId;
  final String userName;
  final SafeboxTxType type;
  final double amount;
  final String note;
  final DateTime createdAt;
  final double runningBalance;

  const SafeboxTransactionModel({
    required this.id,
    required this.safeboxId,
    required this.userId,
    required this.userName,
    required this.type,
    required this.amount,
    required this.note,
    required this.createdAt,
    required this.runningBalance,
  });

  factory SafeboxTransactionModel.fromJson(Map<String, dynamic> json) {
    return SafeboxTransactionModel(
      id: json['id'] ?? '',
      safeboxId: json['safeboxId'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? json['userId'] ?? 'User',
      type: json['type'] == 'WITHDRAWAL'
          ? SafeboxTxType.withdrawal
          : SafeboxTxType.contribution,
      amount: (json['amount'] as num? ?? 0.0).toDouble(),
      note: json['note'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      runningBalance: (json['runningBalance'] as num? ?? 0.0).toDouble(),
    );
  }
}
