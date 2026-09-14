import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/env.dart';
import '../models/app_user.dart';
import '../models/transfer.dart';
import '../models/split_bill.dart';
import '../models/claimable_link.dart';
import '../models/microfinance.dart';
import '../stellar/stellar_client.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// The app's only HTTP client. It talks exclusively to the PayFlex backend
/// (Stellar itself is reached directly by StellarClient — Horizon is a
/// public API). This client handles: account directory, challenge login,
/// payment RECORDING (the backend verifies each one against Horizon),
/// PayTag/QR/split-bill/link/safebox/standing-plan orchestration.
///
/// Every screen constructs its own `ApiClient()` instance, so the current
/// session's access token is held as a static field rather than an
/// instance field — otherwise each new instance would start out
/// unauthenticated. See services/session_manager.dart for the only place
/// that's meant to read/write [accessToken]/[refreshToken].
class ApiClient {
  final String baseUrl;
  ApiClient({this.baseUrl = Env.backendBaseUrl});

  static String? accessToken;
  static String? refreshToken;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _authHeaders() =>
      accessToken != null ? {'Authorization': 'Bearer $accessToken'} : {};

  Map<String, String> _jsonHeaders() => {
        'Content-Type': 'application/json',
        ..._authHeaders(),
      };

  dynamic _decodeAnyOrThrow(http.Response res) {
    final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final message = body is Map && body['message'] != null
          ? (body['message'] is List
              ? (body['message'] as List).join('; ')
              : body['message'].toString())
          : res.body;
      throw ApiException(res.statusCode, message);
    }
    return body;
  }

  Map<String, dynamic> _decodeOrThrow(http.Response res) =>
      _decodeAnyOrThrow(res) as Map<String, dynamic>;

  List<dynamic> _decodeListOrThrow(http.Response res) =>
      _decodeAnyOrThrow(res) as List<dynamic>;

  // --- Account creation (public — no token exists yet) ---------------------
  //
  // POST /users returns a one-time bootstrapToken scoped to exactly one
  // call: PATCH /users/:id/stellar-public-key. Null when the user already
  // exists and already has a key registered.

  Future<({AppUser user, String? bootstrapToken})> createUser({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneNumber,
  }) async {
    final res = await http.post(
      _uri('/users'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phoneNumber': phoneNumber,
      }),
    );
    final body = _decodeOrThrow(res);
    return (
      user: AppUser.fromJson(body['user'] as Map<String, dynamic>),
      bootstrapToken: body['bootstrapToken'] as String?,
    );
  }

  Future<AppUser> getUser(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId'), headers: _authHeaders());
    return AppUser.fromJson(_decodeOrThrow(res));
  }

  /// [bootstrapToken], when given, is used instead of the session's access
  /// token — this is the one call the bootstrap token issued by
  /// [createUser] is allowed to make (see AuthGuard on the backend).
  Future<AppUser> setStellarPublicKey(
    String appUserId,
    String stellarPublicKey, {
    String? bootstrapToken,
  }) async {
    final res = await http.patch(
      _uri('/users/$appUserId/stellar-public-key'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${bootstrapToken ?? accessToken}',
      },
      body: jsonEncode({'stellarPublicKey': stellarPublicKey}),
    );
    return AppUser.fromJson(_decodeOrThrow(res));
  }

  // --- Auth (challenge-response login using the on-device Stellar key) ------
  //
  // The backend issues a challenge string; the app signs it with the
  // device's Stellar secret seed (WalletService.signChallenge) and the
  // backend verifies the Ed25519 signature against the registered key.

  Future<String> requestLoginChallenge(String appUserId) async {
    final res = await http.post(
      _uri('/auth/challenge'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'appUserId': appUserId}),
    );
    final body = _decodeOrThrow(res);
    return body['message'] as String;
  }

  Future<void> login(String appUserId, String signature) async {
    final res = await http.post(
      _uri('/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'appUserId': appUserId, 'signature': signature}),
    );
    final body = _decodeOrThrow(res);
    accessToken = body['accessToken'] as String;
    refreshToken = body['refreshToken'] as String;
  }

  /// Returns false (leaving tokens untouched) rather than throwing on a
  /// revoked/expired refresh token — callers use this to decide whether to
  /// fall back to a PIN-triggered full login, not to surface an error.
  Future<bool> tryRefresh() async {
    if (refreshToken == null) return false;
    final res = await http.post(
      _uri('/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (res.statusCode >= 400) return false;
    final body = _decodeOrThrow(res);
    accessToken = body['accessToken'] as String;
    refreshToken = body['refreshToken'] as String;
    return true;
  }

  static void clearSession() {
    accessToken = null;
    refreshToken = null;
  }

  // --- Onboarding (Stellar account activation) -------------------------------

  Future<Map<String, dynamic>> getOnboardingStatus(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/onboarding/status'), headers: _authHeaders());
    return _decodeOrThrow(res);
  }

  Future<void> confirmActivation(String appUserId) async {
    final res = await http.post(
      _uri('/users/$appUserId/onboarding/confirm-activation'),
      headers: _authHeaders(),
    );
    _decodeAnyOrThrow(res);
  }

  // --- Stellar network config --------------------------------------------------
  //
  // Server-driven network config only: one source of truth for which
  // Horizon this build talks to. Every actual Stellar operation (keypair,
  // signing, submission) happens on-device via StellarClient.

  Future<Map<String, dynamic>> getStellarNetwork() async {
    final res = await http.get(_uri('/stellar/network'), headers: _authHeaders());
    return _decodeOrThrow(res);
  }

  /// Builds the Stellar client from the backend's network config.
  Future<StellarClient> stellarClient() async {
    return StellarClient.fromNetworkInfo(await getStellarNetwork());
  }

  /// Read-only account lookup through the backend's throttled Horizon
  /// proxy — mirrors backend GET /stellar/accounts/:publicKey (see
  /// stellar.controller.ts). Returns the Horizon account JSON whose
  /// `balances` array AccountBalance.fromJson parses.
  Future<Map<String, dynamic>> getStellarAccount(String publicKey) async {
    final res = await http.get(
      _uri('/stellar/accounts/$publicKey'),
      headers: _authHeaders(),
    );
    return _decodeOrThrow(res);
  }

  // --- PayTag ---------------------------------------------------------------

  Future<void> registerPayTag(String appUserId, String tag) async {
    final res = await http.post(
      _uri('/users/$appUserId/paytag'),
      headers: _jsonHeaders(),
      body: jsonEncode({'tag': tag}),
    );
    _decodeAnyOrThrow(res);
  }

  Future<String?> getMyPayTag(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/paytag'), headers: _authHeaders());
    final body = _decodeAnyOrThrow(res);
    return body == null ? null : (body as Map<String, dynamic>)['tag'] as String?;
  }

  Future<PayTagUser> resolvePayTag(String tag) async {
    final res = await http.get(_uri('/paytag/$tag'), headers: _authHeaders());
    return PayTagUser.fromJson(_decodeOrThrow(res));
  }

  // --- Transfers (Stellar-native) ----------------------------------------------
  //
  // resolve: turn a PayTag / raw key into a destination public key + name
  //          BEFORE the app builds the payment.
  // record:  after the app signed and submitted on-device, the backend
  //          pulls the transaction from Horizon and verifies every field
  //          before storing it. Exactly one of toPayTag/toPublicKey.

  Future<TransferTarget> resolveTransfer(
    String appUserId, {
    String? toPayTag,
    String? toPublicKey,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/transfers/resolve'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        if (toPayTag != null) 'toPayTag': toPayTag,
        if (toPublicKey != null) 'toPublicKey': toPublicKey,
      }),
    );
    return TransferTarget.fromJson(_decodeOrThrow(res));
  }

  Future<TransferRecord> recordTransfer(
    String appUserId, {
    required String stellarTxHash,
    required String fromPublicKey,
    required String toPublicKey,
    required String amount,
    required String assetCode,
    String? assetIssuer,
    String? kind,
    String? qrTokenRef,
    String? splitBillId,
    String? standingPlanId,
    String? offlineAuthorizationId,
    String? memo,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/transfers/record'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'stellarTxHash': stellarTxHash,
        'fromPublicKey': fromPublicKey,
        'toPublicKey': toPublicKey,
        'amount': amount,
        'assetCode': assetCode,
        if (assetIssuer != null) 'assetIssuer': assetIssuer,
        if (kind != null) 'kind': kind,
        if (qrTokenRef != null) 'qrTokenRef': qrTokenRef,
        if (splitBillId != null) 'splitBillId': splitBillId,
        if (standingPlanId != null) 'standingPlanId': standingPlanId,
        if (offlineAuthorizationId != null) 'offlineAuthorizationId': offlineAuthorizationId,
        if (memo != null) 'memo': memo,
      }),
    );
    return TransferRecord.fromJson(_decodeOrThrow(res));
  }

  Future<List<TransferRecord>> listTransfers(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/transfers'), headers: _authHeaders());
    return _decodeListOrThrow(res)
        .map((e) => TransferRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- QR Pay ---------------------------------------------------------------

  /// Generates a short-lived HMAC-signed payment request QR. The token
  /// embeds the recipient's Stellar public key.
  Future<String> generateQr(
    String appUserId, {
    required String amount,
    required String assetCode,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/qr/generate'),
      headers: _jsonHeaders(),
      body: jsonEncode({'amount': amount, 'assetCode': assetCode}),
    );
    final body = _decodeOrThrow(res);
    return body['token'] as String;
  }

  /// Public decode endpoint: the PAYER's app calls this after scanning.
  Future<QrPayload> decodeQr(String token) async {
    final res = await http.get(_uri('/qr/decode?token=$token'), headers: _authHeaders());
    return QrPayload.fromJson(_decodeOrThrow(res));
  }

  // --- Standing Plans -----------------------------------------------------------
  //
  // The backend can only mark a payment DUE (no delegated debit exists on
  // Stellar, and this app refuses to fake one). A due payment is paid via
  // the normal on-device flow, then reported with recordPayment which
  // cross-checks the verified TransferRecord.

  Future<StandingPlan> createStandingPlan(
    String appUserId, {
    required String name,
    required String assetCode,
    required String amount,
    required String frequency, // "DAILY" | "WEEKLY" | "MONTHLY"
    String? toPayTag,
    String? toPublicKey,
    String? description,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/standing-plans'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'name': name,
        'assetCode': assetCode,
        'amount': amount,
        'frequency': frequency,
        if (toPayTag != null) 'toPayTag': toPayTag,
        if (toPublicKey != null) 'toPublicKey': toPublicKey,
        if (description != null) 'description': description,
      }),
    );
    return StandingPlan.fromJson(_decodeOrThrow(res));
  }

  Future<List<StandingPlan>> listStandingPlans(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/standing-plans'), headers: _authHeaders());
    return _decodeListOrThrow(res)
        .map((e) => StandingPlan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<StandingPlanPayment>> listDueStandingPlanPayments(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/standing-plans/due'), headers: _authHeaders());
    return _decodeListOrThrow(res)
        .map((e) => StandingPlanPayment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setStandingPlanStatus(
    String appUserId,
    String planId,
    String status, // "ACTIVE" | "PAUSED" | "CANCELLED"
  ) async {
    final res = await http.put(
      _uri('/users/$appUserId/standing-plans/$planId/status'),
      headers: _jsonHeaders(),
      body: jsonEncode({'status': status}),
    );
    _decodeAnyOrThrow(res);
  }

  /// Reports a due payment as paid on-chain. The backend requires a
  /// verified TransferRecord (kind=STANDING_PLAN) referencing this
  /// payment first — call recordTransfer with standingPlanId before this.
  Future<void> recordStandingPlanPayment(
    String appUserId,
    String paymentId,
    String stellarTxHash,
  ) async {
    final res = await http.post(
      _uri('/users/$appUserId/standing-plans/payments/$paymentId/record'),
      headers: _jsonHeaders(),
      body: jsonEncode({'stellarTxHash': stellarTxHash}),
    );
    _decodeAnyOrThrow(res);
  }

  // --- Admin ----------------------------------------------------------------------
  //
  // Every call here needs the caller's own access token to already carry
  // isAdmin (see backend/src/admin/admin.guard.ts) — there is no
  // client-side gate, the backend rejects a non-admin with 403 regardless
  // of what this screen shows.

  Future<Map<String, dynamic>> getAdminStats() async {
    final res = await http.get(_uri('/admin/stats'), headers: _authHeaders());
    return _decodeOrThrow(res);
  }

  Future<Map<String, dynamic>> triggerStandingPlanDueCheck() async {
    final res = await http.post(_uri('/standing-plans/run-due-check'), headers: _authHeaders());
    return _decodeOrThrow(res);
  }

  // --- Split-bill -------------------------------------------------------------
  //
  // Orchestration only: the bill tracks who owes what; each contributor's
  // payment is an independent on-device Stellar payment recorded via
  // recordTransfer (splitBillId set).

  Future<SplitBill> createSplitBill(
    String appUserId, {
    required String description,
    required String assetCode,
    required String totalAmount,
    required List<({String? payTag, String? publicKey, String shareAmount})> contributors,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/split-bills'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'description': description,
        'assetCode': assetCode,
        'totalAmount': totalAmount,
        'contributorsJson': jsonEncode(contributors
            .map((c) => {
                  if (c.payTag != null) 'payTag': c.payTag,
                  if (c.publicKey != null) 'publicKey': c.publicKey,
                  'shareAmount': c.shareAmount,
                })
            .toList()),
      }),
    );
    return SplitBill.fromJson(_decodeOrThrow(res));
  }

  Future<List<SplitBill>> listSplitBills(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/split-bills'), headers: _authHeaders());
    return _decodeListOrThrow(res)
        .map((e) => SplitBill.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SplitBill> getSplitBillDetail(String appUserId, String splitBillId) async {
    final res = await http.get(
      _uri('/users/$appUserId/split-bills/$splitBillId'),
      headers: _authHeaders(),
    );
    return SplitBill.fromJson(_decodeOrThrow(res));
  }

  // --- Send-via-link (non-custodial, on-chain claimable balance) ---------------
  //
  // Flow: sendViaLink → the app creates an on-chain CREATE_CLAIMABLE_BALANCE
  // (sender as reclaimant) → registerClaimableBalance (backend verifies the
  // CB on Horizon) → recipient claims on-chain → claim() (backend verifies
  // the claim tx AND that the CB is gone from the ledger).

  Future<({String linkId, String shareToken, Map<String, dynamic> instructions})>
      sendViaLink(
    String appUserId, {
    required String amount,
    required String assetCode,
    String? assetIssuer,
    String? expiresInDays,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/send-via-link'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'amount': amount,
        'assetCode': assetCode,
        if (assetIssuer != null) 'assetIssuer': assetIssuer,
        if (expiresInDays != null) 'expiresInDays': expiresInDays,
      }),
    );
    final body = _decodeOrThrow(res);
    return (
      linkId: body['linkId'] as String,
      shareToken: body['shareToken'] as String,
      instructions: body['instructions'] as Map<String, dynamic>,
    );
  }

  Future<TransferRecord?> registerClaimableBalance(
    String appUserId,
    String linkId,
    String claimableBalanceId,
  ) async {
    final res = await http.post(
      _uri('/users/$appUserId/links/$linkId/claimable-balance'),
      headers: _jsonHeaders(),
      body: jsonEncode({'claimableBalanceId': claimableBalanceId}),
    );
    final body = _decodeOrThrow(res);
    return body['id'] == null ? null : TransferRecord.fromJson(body);
  }

  Future<List<Map<String, dynamic>>> listLinks(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/links'), headers: _authHeaders());
    return _decodeListOrThrow(res).map((e) => e as Map<String, dynamic>).toList();
  }

  Future<ClaimPreview> previewLink(String token) async {
    final res = await http.get(_uri('/links/preview?token=$token'), headers: _authHeaders());
    return ClaimPreview.fromJson(_decodeOrThrow(res));
  }

  Future<void> claimLink(
    String appUserId,
    String linkId, {
    required String claimantPublicKey,
    required String claimTxHash,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/links/$linkId/claim'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'claimantPublicKey': claimantPublicKey,
        'claimTxHash': claimTxHash,
      }),
    );
    _decodeAnyOrThrow(res);
  }

  // --- Safebox (Soroban escrow contract) ----------------------------------------
  //
  // The on-chain contract (backend/contracts/safebox) is the source of
  // truth: owner/admin-only withdrawal, 3-admin cap, shared ledger. The
  // backend registers deployed contracts and reads chain state; the
  // contribute/withdraw invocations are built and signed by the app
  // (see SafeboxService for the app-side invocation helpers).

  Future<List<Map<String, dynamic>>> listSafeboxes(String appUserId) async {
    final res = await http.get(_uri('/safebox'), headers: _authHeaders());
    return _decodeListOrThrow(res).map((e) => e as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>> registerSafebox(
    String appUserId, {
    required String contractId,
    required String name,
    String? description,
  }) async {
    final res = await http.post(
      _uri('/safebox'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'contractId': contractId,
        'name': name,
        if (description != null) 'description': description,
      }),
    );
    return _decodeOrThrow(res);
  }

  Future<Map<String, dynamic>> getSafeboxDetail(String appUserId, String contractId) async {
    final res = await http.get(_uri('/safebox/$contractId'), headers: _authHeaders());
    return _decodeOrThrow(res);
  }

  Future<List<Map<String, dynamic>>> getSafeboxLedger(String appUserId, String contractId) async {
    final res = await http.get(_uri('/safebox/$contractId/ledger'), headers: _authHeaders());
    return _decodeListOrThrow(res).map((e) => e as Map<String, dynamic>).toList();
  }
}
