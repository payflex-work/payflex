import 'dart:async';
import '../models/safebox_model.dart';
import '../components/payment_confirmation_flow.dart';

/// Client-side service for managing Safebox group savings & contribution pools.
/// Calls into standard Transfer pipeline and enforces permissions.
class SafeboxService {
  static final SafeboxService _instance = SafeboxService._internal();
  factory SafeboxService() => _instance;
  SafeboxService._internal();

  // Demo state store for client UI interactivity
  final List<SafeboxModel> _mockSafeboxes = [
    SafeboxModel(
      id: 'sb_vacation_01',
      name: 'Dec 2026 Trip to Kenya ✈️',
      description: 'Group savings pool for flights and accommodation.',
      ownerId: 'usr_me',
      targetAmount: 500000.0,
      currentBalance: 185000.0,
      status: SafeboxStatus.active,
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
      userRole: SafeboxRole.owner,
    ),
    SafeboxModel(
      id: 'sb_rent_02',
      name: 'Apartment Rent Pool 🏠',
      description: 'Shared house rent contributions.',
      ownerId: 'usr_sarah',
      targetAmount: 1200000.0,
      currentBalance: 450000.0,
      status: SafeboxStatus.active,
      createdAt: DateTime.now().subtract(const Duration(days: 60)),
      userRole: SafeboxRole.admin,
    ),
  ];

  final Map<String, List<SafeboxMemberModel>> _mockMembers = {
    'sb_vacation_01': [
      SafeboxMemberModel(
        id: 'm1',
        safeboxId: 'sb_vacation_01',
        userId: 'usr_me',
        name: 'You (Owner)',
        role: SafeboxRole.owner,
        joinedAt: DateTime.now().subtract(const Duration(days: 30)),
      ),
      SafeboxMemberModel(
        id: 'm2',
        safeboxId: 'sb_vacation_01',
        userId: 'usr_alex',
        name: 'Alex Johnson',
        role: SafeboxRole.admin,
        joinedAt: DateTime.now().subtract(const Duration(days: 28)),
      ),
      SafeboxMemberModel(
        id: 'm3',
        safeboxId: 'sb_vacation_01',
        userId: 'usr_grace',
        name: 'Grace Taylor',
        role: SafeboxRole.member,
        joinedAt: DateTime.now().subtract(const Duration(days: 15)),
      ),
    ],
    'sb_rent_02': [
      SafeboxMemberModel(
        id: 'm4',
        safeboxId: 'sb_rent_02',
        userId: 'usr_sarah',
        name: 'Sarah Connor',
        role: SafeboxRole.owner,
        joinedAt: DateTime.now().subtract(const Duration(days: 60)),
      ),
      SafeboxMemberModel(
        id: 'm5',
        safeboxId: 'sb_rent_02',
        userId: 'usr_me',
        name: 'You',
        role: SafeboxRole.admin,
        joinedAt: DateTime.now().subtract(const Duration(days: 60)),
      ),
    ],
  };

  final Map<String, List<SafeboxTransactionModel>> _mockTransactions = {
    'sb_vacation_01': [
      SafeboxTransactionModel(
        id: 'tx_101',
        safeboxId: 'sb_vacation_01',
        userId: 'usr_me',
        userName: 'You',
        type: SafeboxTxType.contribution,
        amount: 50000.0,
        note: 'Initial deposit',
        createdAt: DateTime.now().subtract(const Duration(days: 25)),
        runningBalance: 50000.0,
      ),
      SafeboxTransactionModel(
        id: 'tx_102',
        safeboxId: 'sb_vacation_01',
        userId: 'usr_alex',
        userName: 'Alex Johnson',
        type: SafeboxTxType.contribution,
        amount: 75000.0,
        note: 'Kenya flight deposit',
        createdAt: DateTime.now().subtract(const Duration(days: 20)),
        runningBalance: 125000.0,
      ),
      SafeboxTransactionModel(
        id: 'tx_103',
        safeboxId: 'sb_vacation_01',
        userId: 'usr_grace',
        userName: 'Grace Taylor',
        type: SafeboxTxType.contribution,
        amount: 60000.0,
        note: 'Hotel down payment',
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        runningBalance: 185000.0,
      ),
    ],
  };

  Future<List<SafeboxModel>> getSafeboxes() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.from(_mockSafeboxes);
  }

  Future<SafeboxModel> createSafebox({
    required String name,
    required String description,
    double? targetAmount,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final id = 'sb_${DateTime.now().millisecondsSinceEpoch}';
    final safebox = SafeboxModel(
      id: id,
      name: name,
      description: description,
      ownerId: 'usr_me',
      targetAmount: targetAmount,
      currentBalance: 0.0,
      status: SafeboxStatus.active,
      createdAt: DateTime.now(),
      userRole: SafeboxRole.owner,
    );

    _mockSafeboxes.insert(0, safebox);
    _mockMembers[id] = [
      SafeboxMemberModel(
        id: 'm_owner',
        safeboxId: id,
        userId: 'usr_me',
        name: 'You (Owner)',
        role: SafeboxRole.owner,
        joinedAt: DateTime.now(),
      ),
    ];
    _mockTransactions[id] = [];

    return safebox;
  }

  Future<List<SafeboxMemberModel>> getMembers(String safeboxId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return List.from(_mockMembers[safeboxId] ?? []);
  }

  Future<List<SafeboxTransactionModel>> getTransactions(String safeboxId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final list = _mockTransactions[safeboxId] ?? [];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.from(list);
  }

  Future<PaymentResultPayload> processContribution({
    required String safeboxId,
    required double amount,
    String? note,
  }) async {
    final boxIndex = _mockSafeboxes.indexWhere((b) => b.id == safeboxId);
    if (boxIndex == -1) {
      return PaymentResultPayload(
        success: false,
        transactionId: '',
        recipientName: 'Safebox',
        amount: amount,
        error: 'Safebox not found',
      );
    }

    final box = _mockSafeboxes[boxIndex];
    final newBalance = box.currentBalance + amount;

    _mockSafeboxes[boxIndex] = SafeboxModel(
      id: box.id,
      name: box.name,
      description: box.description,
      ownerId: box.ownerId,
      targetAmount: box.targetAmount,
      currentBalance: newBalance,
      status: box.status,
      createdAt: box.createdAt,
      userRole: box.userRole,
    );

    final txId = 'tx_${DateTime.now().millisecondsSinceEpoch}';
    final tx = SafeboxTransactionModel(
      id: txId,
      safeboxId: safeboxId,
      userId: 'usr_me',
      userName: 'You',
      type: SafeboxTxType.contribution,
      amount: amount,
      note: note ?? 'Contribution',
      createdAt: DateTime.now(),
      runningBalance: newBalance,
    );

    _mockTransactions.putIfAbsent(safeboxId, () => []).insert(0, tx);

    return PaymentResultPayload(
      success: true,
      transactionId: txId,
      recipientName: box.name,
      amount: amount,
    );
  }

  Future<PaymentResultPayload> processWithdrawal({
    required String safeboxId,
    required double amount,
    required String note,
    required SafeboxRole userRole,
  }) async {
    // Client-side double check before API call
    if (!userRole.canWithdraw) {
      return PaymentResultPayload(
        success: false,
        transactionId: '',
        recipientName: 'Safebox Pool',
        amount: amount,
        error: 'Forbidden: Only Safebox Owner and designated Admins can withdraw funds.',
      );
    }

    final boxIndex = _mockSafeboxes.indexWhere((b) => b.id == safeboxId);
    if (boxIndex == -1) {
      return PaymentResultPayload(
        success: false,
        transactionId: '',
        recipientName: 'Safebox Pool',
        amount: amount,
        error: 'Safebox not found',
      );
    }

    final box = _mockSafeboxes[boxIndex];
    if (box.currentBalance < amount) {
      return PaymentResultPayload(
        success: false,
        transactionId: '',
        recipientName: box.name,
        amount: amount,
        error: 'Insufficient balance in Safebox pool.',
      );
    }

    final newBalance = box.currentBalance - amount;
    _mockSafeboxes[boxIndex] = SafeboxModel(
      id: box.id,
      name: box.name,
      description: box.description,
      ownerId: box.ownerId,
      targetAmount: box.targetAmount,
      currentBalance: newBalance,
      status: box.status,
      createdAt: box.createdAt,
      userRole: box.userRole,
    );

    final txId = 'tx_w_${DateTime.now().millisecondsSinceEpoch}';
    final tx = SafeboxTransactionModel(
      id: txId,
      safeboxId: safeboxId,
      userId: 'usr_me',
      userName: 'You (${userRole.label})',
      type: SafeboxTxType.withdrawal,
      amount: amount,
      note: note,
      createdAt: DateTime.now(),
      runningBalance: newBalance,
    );

    _mockTransactions.putIfAbsent(safeboxId, () => []).insert(0, tx);

    return PaymentResultPayload(
      success: true,
      transactionId: txId,
      recipientName: box.name,
      amount: amount,
    );
  }

  Future<void> updateMemberRole({
    required String safeboxId,
    required String memberUserId,
    required SafeboxRole newRole,
  }) async {
    final memberList = _mockMembers[safeboxId] ?? [];
    if (newRole == SafeboxRole.admin) {
      final currentAdmins = memberList.filterAdminsCount();
      if (currentAdmins >= 3) {
        throw Exception('Admin limit reached: maximum 3 designated admins allowed per Safebox.');
      }
    }

    final idx = memberList.indexWhere((m) => m.userId == memberUserId);
    if (idx != -1) {
      final old = memberList[idx];
      memberList[idx] = SafeboxMemberModel(
        id: old.id,
        safeboxId: old.safeboxId,
        userId: old.userId,
        name: old.name,
        role: newRole,
        joinedAt: old.joinedAt,
      );
    }
  }

  Future<void> addMember(String safeboxId, String name) async {
    final memberList = _mockMembers[safeboxId] ?? [];
    final id = 'usr_${DateTime.now().millisecondsSinceEpoch}';
    memberList.add(
      SafeboxMemberModel(
        id: 'm_${DateTime.now().millisecondsSinceEpoch}',
        safeboxId: safeboxId,
        userId: id,
        name: name,
        role: SafeboxRole.member,
        joinedAt: DateTime.now(),
      ),
    );
  }
}

extension MemberListHelpers on List<SafeboxMemberModel> {
  int filterAdminsCount() {
    return where((m) => m.role == SafeboxRole.admin).length;
  }
}
