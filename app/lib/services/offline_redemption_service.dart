import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/format.dart';
import 'transfer_flow.dart';
import '../stellar/stellar_client.dart';
import 'api_client.dart';
import 'offline_reserve_service.dart';

enum RedemptionStatus { pending, settled, failed, expired }

/// Record of an offline transaction and its current redemption state.
class OfflineTransactionRecord {
  final String authorizationId;
  final String requestId;
  final String merchantId;
  final int amountMinorUnits;
  final String currency;
  final DateTime createdAt;
  RedemptionStatus status;
  String? stellarTxHash;
  String? errorMessage;
  DateTime? settledAt;

  OfflineTransactionRecord({
    required this.authorizationId,
    required this.requestId,
    required this.merchantId,
    required this.amountMinorUnits,
    required this.currency,
    required this.createdAt,
    this.status = RedemptionStatus.pending,
    this.stellarTxHash,
    this.errorMessage,
    this.settledAt,
  });

  String get amountDecimal {
    final major = amountMinorUnits / 100.0;
    return major.toStringAsFixed(2);
  }

  Map<String, dynamic> toJson() => {
        'authorizationId': authorizationId,
        'requestId': requestId,
        'merchantId': merchantId,
        'amountMinorUnits': amountMinorUnits,
        'currency': currency,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        if (stellarTxHash != null) 'stellarTxHash': stellarTxHash,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (settledAt != null) 'settledAt': settledAt!.toIso8601String(),
      };

  factory OfflineTransactionRecord.fromJson(Map<String, dynamic> json) {
    return OfflineTransactionRecord(
      authorizationId: json['authorizationId'] as String,
      requestId: json['requestId'] as String,
      merchantId: json['merchantId'] as String,
      amountMinorUnits: (json['amountMinorUnits'] as num).toInt(),
      currency: json['currency'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      status: RedemptionStatus.values.byName(json['status'] as String),
      stellarTxHash: json['stellarTxHash'] as String?,
      errorMessage: json['errorMessage'] as String?,
      settledAt: json['settledAt'] != null
          ? DateTime.parse(json['settledAt'] as String).toUtc()
          : null,
    );
  }
}

/// Reconciliation and settlement of offline authorizations: when internet
/// connectivity is restored, each queued device-signed authorization is
/// settled with a REAL on-device Stellar payment (signed with the user's
/// key after their PIN), then recorded with the backend (which verifies
/// the transaction against Horizon) as kind=OFFLINE_REDEMPTION.
class OfflineRedemptionService {
  static const String _recordsStorageKey = 'payflex_offline_tx_records_v1';
  static const Duration pendingRedemptionWindow = Duration(hours: 48);

  final OfflineReserveService _reserveService;
  final List<OfflineTransactionRecord> _records = [];

  OfflineRedemptionService({OfflineReserveService? reserveService})
      : _reserveService = reserveService ?? OfflineReserveService();

  /// Loads all stored offline transaction records.
  Future<List<OfflineTransactionRecord>> loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recordsStorageKey);
    if (raw == null || raw.isEmpty) return [];

    final list = jsonDecode(raw) as List;
    _records
      ..clear()
      ..addAll(list.map((e) => OfflineTransactionRecord.fromJson(e as Map<String, dynamic>)));
    return List.unmodifiable(_records);
  }

  /// Records a new offline spend transaction.
  Future<void> recordSpend({
    required OfflineAuthorization authorization,
  }) async {
    await loadRecords();
    final record = OfflineTransactionRecord(
      authorizationId: authorization.authorizationId,
      requestId: authorization.requestId,
      merchantId: authorization.merchantId,
      amountMinorUnits: authorization.amountMinorUnits,
      currency: authorization.currency,
      createdAt: authorization.timestamp,
      status: RedemptionStatus.pending,
    );
    _records.insert(0, record);
    await _saveRecords();
  }

  /// Attempts to settle all queued offline authorizations on Stellar.
  /// Each one becomes an ordinary payment: resolve destination → PIN →
  /// build/sign on-device → submit to Horizon → record (verified).
  Future<({int succeeded, int failed, int expired})> syncAndRedeemAll({
    required String appUserId,
    required ApiClient apiClient,
    required BuildContext context,
    DateTime? now,
    StellarClient? client,
  }) async {
    await loadRecords();
    final pendingQueue = await _reserveService.getPendingRedemptionQueue();
    final currentTime = (now ?? DateTime.now()).toUtc();
    final stellar = client ?? await apiClient.stellarClient();

    var succeeded = 0;
    var failed = 0;
    var expired = 0;

    for (final auth in pendingQueue) {
      // Find or create local record
      final recordIndex = _records.indexWhere((r) => r.authorizationId == auth.authorizationId);
      final record = recordIndex != -1
          ? _records[recordIndex]
          : OfflineTransactionRecord(
              authorizationId: auth.authorizationId,
              requestId: auth.requestId,
              merchantId: auth.merchantId,
              amountMinorUnits: auth.amountMinorUnits,
              currency: auth.currency,
              createdAt: auth.timestamp,
            );

      // Check if authorization has exceeded redemption window
      if (currentTime.difference(auth.timestamp) > pendingRedemptionWindow) {
        record.status = RedemptionStatus.expired;
        record.errorMessage = 'Redemption window expired (48h limit exceeded)';
        expired++;
        await _reserveService.removePendingAuthorization(auth.authorizationId);
        if (recordIndex == -1) _records.insert(0, record);
        continue;
      }

      try {
        final amountStr = (auth.amountMinorUnits / 100.0).toStringAsFixed(2);

        // Resolve the destination. A @PayTag goes through the directory;
        // anything else is treated as a raw Stellar public key.
        final isPayTag = auth.merchantId.startsWith('@');
        final target = isPayTag
            ? await apiClient.resolveTransfer(appUserId, toPayTag: auth.merchantId.substring(1))
            : await apiClient.resolveTransfer(appUserId, toPublicKey: auth.merchantId);

        // PIN → build → sign on-device → submit to Horizon → record.
        if (!context.mounted) continue;
        final result = await signAndSubmitTransfer(
          context,
          apiClient,
          appUserId,
          toPublicKey: target.toPublicKey,
          amount: amountStr,
          assetCode: auth.currency.toUpperCase(),
          kind: TransferKind.offlineRedemption,
          offlineAuthorizationId: auth.authorizationId,
          memo: 'offline ${shortRef(auth.authorizationId)}',
          client: stellar,
        );

        if (result != null && result.success) {
          record.status = RedemptionStatus.settled;
          record.stellarTxHash = result.transactionHash;
          record.settledAt = DateTime.now().toUtc();
          record.errorMessage = null;
          succeeded++;

          // Remove from pending reserve queue
          await _reserveService.removePendingAuthorization(auth.authorizationId);
        } else {
          record.status = RedemptionStatus.failed;
          record.errorMessage =
              result?.errorMessage ?? 'Settlement cancelled — no signature was submitted.';
          failed++;
        }
      } catch (e) {
        record.status = RedemptionStatus.failed;
        record.errorMessage = e.toString();
        failed++;
      }

      if (recordIndex == -1) {
        _records.insert(0, record);
      }
    }

    await _saveRecords();
    return (succeeded: succeeded, failed: failed, expired: expired);
  }

  Future<void> _saveRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_records.map((r) => r.toJson()).toList());
    await prefs.setString(_recordsStorageKey, raw);
  }
}
