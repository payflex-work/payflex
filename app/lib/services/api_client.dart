import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/env.dart';
import '../models/app_user.dart';
import '../models/kyc.dart';
import '../models/transfer.dart';
import '../models/microfinance.dart';
import '../models/split_bill.dart';
import '../models/claimable_link.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// The app's only HTTP client. It talks exclusively to the PayFlex
/// backend (never to BMONI directly) — see backend/src/bmoni for why.
///
/// Every screen constructs its own `ApiClient()` instance, so the current
/// session's access token is held as a static field rather than an
/// instance field — otherwise each new instance would start out
/// unauthenticated. See services/session_manager.dart for the only place
/// that's meant to read/write [accessToken]/[refreshToken] outside of the
/// bootstrap-token special case handled inline in [setOwnerAddress].
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

  /// POST /users is public (needed before any token exists) and, for a
  /// brand-new user, returns a one-time [bootstrapToken] scoped to exactly
  /// one call: [setOwnerAddress]. It's null when the user already exists
  /// and already has an owner address (see backend's UsersController).
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
  Future<AppUser> setOwnerAddress(
    String appUserId,
    String ownerAddress, {
    String? bootstrapToken,
  }) async {
    final res = await http.patch(
      _uri('/users/$appUserId/owner-address'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${bootstrapToken ?? accessToken}',
      },
      body: jsonEncode({'ownerAddress': ownerAddress}),
    );
    return AppUser.fromJson(_decodeOrThrow(res));
  }

  Future<List<String>> getSupportedCurrencies() async {
    final res = await http.get(_uri('/onboarding/supported-currencies'), headers: _authHeaders());
    final body = _decodeOrThrow(res);
    return List<String>.from(body['currencies'] as List);
  }

  // --- Auth (challenge-response login using the on-device owner key) ------
  //
  // See backend/src/auth — login reuses the same EVM key/signature already
  // used for BMONI owner-proof challenges, via WalletService.signChallenge.

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

  Future<({String challengeId, String message})> requestOwnerProofChallenge(
    String appUserId,
    String currency,
  ) async {
    final res = await http.post(
      _uri('/users/$appUserId/smart-wallets/owner-proof-challenges'),
      headers: _jsonHeaders(),
      body: jsonEncode({'currency': currency}),
    );
    final body = _decodeOrThrow(res);
    return (
      challengeId: body['challengeId'] as String,
      message: body['message'] as String,
    );
  }

  Future<SmartWallet> createSmartWallet(
    String appUserId, {
    required String currency,
    required String ownerProofChallengeId,
    required String ownerProofSignature,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/smart-wallets'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'currency': currency,
        'ownerProofChallengeId': ownerProofChallengeId,
        'ownerProofSignature': ownerProofSignature,
      }),
    );
    return SmartWallet.fromJson(_decodeOrThrow(res));
  }

  Future<Map<String, dynamic>> getOnboardingStatus(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/onboarding/status'), headers: _authHeaders());
    return _decodeOrThrow(res);
  }

  // --- KYC wizard (Phase 2) ---------------------------------------------

  Future<KycOptions> getKycOptions(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/kyc/options'), headers: _authHeaders());
    return KycOptions.fromJson(_decodeOrThrow(res));
  }

  Future<List<KycOccupation>> getKycOccupations(String appUserId, String search) async {
    final res = await http.get(_uri('/users/$appUserId/kyc/occupations?search=$search'), headers: _authHeaders());
    return _decodeListOrThrow(res)
        .map((e) => KycOccupation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// All three document endpoints share this shape on our own backend:
  /// multipart with a `file` field plus whatever text fields BMONI needs
  /// for that document type (see KycController — it maps `file` to
  /// BMONI's own inconsistent field names internally, so the app only
  /// has to remember one convention).
  Future<void> _submitDocument(
    String path,
    File file,
    Map<String, String> fields,
  ) async {
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers.addAll(_authHeaders());
    request.fields.addAll(fields);
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    _decodeAnyOrThrow(res);
  }

  Future<void> submitIdentificationDocument(
    String appUserId,
    File file, {
    required String type,
    required String documentNumber,
    required String issuingCountry,
  }) => _submitDocument(
        '/users/$appUserId/kyc/documents/identification',
        file,
        {'type': type, 'documentNumber': documentNumber, 'issuingCountry': issuingCountry},
      );

  Future<void> submitProofOfAddress(String appUserId, File file, {required String type}) =>
      _submitDocument('/users/$appUserId/kyc/documents/proof-of-address', file, {'type': type});

  Future<void> submitBiometric(String appUserId, File file, {required String type}) =>
      _submitDocument('/users/$appUserId/kyc/documents/biometric', file, {'type': type});

  Future<Map<String, dynamic>> patchKyc(String appUserId, Map<String, dynamic> body) async {
    final res = await http.patch(
      _uri('/users/$appUserId/kyc'),
      headers: _jsonHeaders(),
      body: jsonEncode(body),
    );
    return _decodeOrThrow(res);
  }

  Future<KycReadiness> getKycReadiness(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/kyc/readiness'), headers: _authHeaders());
    return KycReadiness.fromJson(_decodeOrThrow(res));
  }

  Future<KycReadiness> getUsdReadiness(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/kyc/usd-readiness'), headers: _authHeaders());
    return KycReadiness.fromJson(_decodeOrThrow(res));
  }

  /// The valid sumsubLevelName set is dynamic server-side (depends on
  /// which documents have been submitted) — a 400 here echoes BMONI's
  /// currently-valid list verbatim via ApiException.message. See
  /// backend/src/kyc/dto/kyc-activate.dto.ts.
  Future<Map<String, dynamic>> activateKyc(
    String appUserId, {
    required String currency,
    required String sumsubLevelName,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/kyc/activate?currency=$currency'),
      headers: _jsonHeaders(),
      body: jsonEncode({'sumsubLevelName': sumsubLevelName}),
    );
    return _decodeOrThrow(res);
  }

  // --- Rail onboarding (Phase 2: NGN + USD) -------------------------------

  Future<Map<String, dynamic>> startNigeria(
    String appUserId, {
    required String bvn,
    required int ngnWalletIndex,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/onboarding/start-nigeria'),
      headers: _jsonHeaders(),
      body: jsonEncode({'bvn': bvn, 'ngnWalletIndex': ngnWalletIndex}),
    );
    return _decodeOrThrow(res);
  }

  Future<Map<String, dynamic>> startUsa(String appUserId) async {
    final res = await http.post(_uri('/users/$appUserId/onboarding/start-usa'), headers: _authHeaders());
    return _decodeOrThrow(res);
  }

  Future<Map<String, dynamic>> getVbaUsdStatus(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/vba/usd'), headers: _authHeaders());
    return _decodeOrThrow(res);
  }

  // --- Wallet home (Phase 2: balances + history) --------------------------

  Future<List<SmartWallet>> listWallets(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/wallets'), headers: _authHeaders());
    return _decodeListOrThrow(res)
        .map((e) => SmartWallet.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Balance>> listBalances(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/balances'), headers: _authHeaders());
    final body = _decodeOrThrow(res);
    return (body['balances'] as List)
        .map((e) => Balance.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Transaction>> getTransactions(String appUserId, String smartWalletId) async {
    final res = await http.get(_uri('/users/$appUserId/wallets/$smartWalletId/transactions'), headers: _authHeaders());
    final body = _decodeOrThrow(res);
    return (body['transactions'] as List)
        .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- PayTag (Phase 3) ---------------------------------------------------

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

  // --- Transfers (Phase 3) -------------------------------------------------
  //
  // Every transfer mode (direct, PayTag, QR) ends up calling createTransfer
  // then walking sign-payload -> sign, exactly like TransferService on the
  // backend. Exactly one of toBmoniUserId / toAddress / toPayTag must be set.

  Future<Proposal> createTransfer(
    String appUserId, {
    String? toBmoniUserId,
    String? toAddress,
    String? toPayTag,
    required String amount,
    required String currency,
    String? description,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/transfers'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        if (toBmoniUserId != null) 'toBmoniUserId': toBmoniUserId,
        if (toAddress != null) 'toAddress': toAddress,
        if (toPayTag != null) 'toPayTag': toPayTag,
        'amount': amount,
        'currency': currency,
        if (description != null) 'description': description,
      }),
    );
    return Proposal.fromJson(_decodeOrThrow(res));
  }

  /// Confirmed live: the sign payload is prepared asynchronously and can
  /// 409 for a couple of seconds after the proposal is created — retry
  /// rather than treating one 409 as fatal.
  Future<ProposalSignPayload> getTransferSignPayload(
    String appUserId,
    String proposalId, {
    int maxAttempts = 8,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final res = await http.get(
        _uri('/users/$appUserId/transfers/$proposalId/sign-payload'),
        headers: _authHeaders(),
      );
      if (res.statusCode == 409 && attempt < maxAttempts - 1) {
        await Future.delayed(const Duration(milliseconds: 1500));
        continue;
      }
      return ProposalSignPayload.fromJson(_decodeOrThrow(res));
    }
    throw ApiException(409, 'Sign payload never became ready.');
  }

  Future<Proposal> signTransfer(String appUserId, String proposalId, String signature) async {
    final res = await http.post(
      _uri('/users/$appUserId/transfers/$proposalId/sign'),
      headers: _jsonHeaders(),
      body: jsonEncode({'signature': signature}),
    );
    return Proposal.fromJson(_decodeOrThrow(res));
  }

  Future<Proposal> rejectTransfer(String appUserId, String proposalId, {String? reason}) async {
    final res = await http.post(
      _uri('/users/$appUserId/transfers/$proposalId/reject'),
      headers: _jsonHeaders(),
      body: jsonEncode({if (reason != null) 'reason': reason}),
    );
    return Proposal.fromJson(_decodeOrThrow(res));
  }

  Future<List<Proposal>> listTransfers(String appUserId, String currency) async {
    final res = await http.get(_uri('/users/$appUserId/transfers?currency=$currency'), headers: _authHeaders());
    final body = _decodeOrThrow(res);
    return (body['proposals'] as List)
        .map((e) => Proposal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- QR Pay (Phase 3) -----------------------------------------------------

  Future<String> generateQr(
    String appUserId, {
    required String amount,
    required String currency,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/qr/generate'),
      headers: _jsonHeaders(),
      body: jsonEncode({'amount': amount, 'currency': currency}),
    );
    final body = _decodeOrThrow(res);
    return body['token'] as String;
  }

  /// Called by the payer after scanning — creates the transfer proposal
  /// server-side from the (HMAC-verified) QR token.
  Future<Proposal> payQr(String appUserId, String token) async {
    final res = await http.post(
      _uri('/users/$appUserId/qr/pay'),
      headers: _jsonHeaders(),
      body: jsonEncode({'token': token}),
    );
    return Proposal.fromJson(_decodeOrThrow(res));
  }

  // --- Savings goals (Phase 4) ----------------------------------------------
  //
  // A savings contribution's "pay" call returns the same Proposal shape as
  // every other transfer — sign/submit it via the normal
  // /transfers/:proposalId/sign-payload and /sign routes.

  Future<SavingsGoal> createSavingsGoal(
    String appUserId, {
    required String name,
    required String currency,
    required String targetAmount,
    required String contributionAmount,
    required String frequency, // "DAILY" | "WEEKLY" | "MONTHLY"
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/savings/goals'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'name': name,
        'currency': currency,
        'targetAmount': targetAmount,
        'contributionAmount': contributionAmount,
        'frequency': frequency,
      }),
    );
    return SavingsGoal.fromJson(_decodeOrThrow(res));
  }

  Future<List<SavingsGoal>> listSavingsGoals(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/savings/goals'), headers: _authHeaders());
    return _decodeListOrThrow(res)
        .map((e) => SavingsGoal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<SavingsContribution>> listDueContributions(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/savings/due'), headers: _authHeaders());
    return _decodeListOrThrow(res)
        .map((e) => SavingsContribution.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Proposal> payContribution(String appUserId, String contributionId) async {
    final res = await http.post(
      _uri('/users/$appUserId/savings/contributions/$contributionId/pay'),
      headers: _authHeaders(),
    );
    return Proposal.fromJson(_decodeOrThrow(res));
  }

  // --- Loans (Phase 4) -------------------------------------------------------

  Future<LoanApplication> applyForLoan(
    String appUserId, {
    required String requestedAmount,
    required String currency,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/loans/apply'),
      headers: _jsonHeaders(),
      body: jsonEncode({'requestedAmount': requestedAmount, 'currency': currency}),
    );
    return LoanApplication.fromJson(_decodeOrThrow(res));
  }

  Future<List<LoanApplication>> listLoans(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/loans'), headers: _authHeaders());
    return _decodeListOrThrow(res)
        .map((e) => LoanApplication.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<LoanRepayment>> listRepayments(String appUserId, String loanId) async {
    final res = await http.get(_uri('/users/$appUserId/loans/$loanId/repayments'), headers: _authHeaders());
    return _decodeListOrThrow(res)
        .map((e) => LoanRepayment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Proposal> payRepayment(String appUserId, String repaymentId) async {
    final res = await http.post(_uri('/users/$appUserId/loans/repayments/$repaymentId/pay'), headers: _authHeaders());
    return Proposal.fromJson(_decodeOrThrow(res));
  }

  // --- Agent mode (Phase 4) ---------------------------------------------------

  Future<void> setAgentStatus(String appUserId, bool isAgent) async {
    final res = await http.post(
      _uri('/users/$appUserId/agent/status'),
      headers: _jsonHeaders(),
      body: jsonEncode({'isAgent': isAgent}),
    );
    _decodeAnyOrThrow(res);
  }

  Future<Proposal> agentCashIn(
    String agentAppUserId, {
    String? toBmoniUserId,
    String? toPayTag,
    required String amount,
    required String currency,
  }) async {
    final res = await http.post(
      _uri('/users/$agentAppUserId/agent/cash-in'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        if (toBmoniUserId != null) 'toBmoniUserId': toBmoniUserId,
        if (toPayTag != null) 'toPayTag': toPayTag,
        'amount': amount,
        'currency': currency,
      }),
    );
    return Proposal.fromJson(_decodeOrThrow(res));
  }

  Future<Proposal> agentCashOut(
    String customerAppUserId, {
    String? agentBmoniUserId,
    String? agentPayTag,
    required String amount,
    required String currency,
  }) async {
    final res = await http.post(
      _uri('/users/$customerAppUserId/agent/cash-out'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        if (agentBmoniUserId != null) 'agentBmoniUserId': agentBmoniUserId,
        if (agentPayTag != null) 'agentPayTag': agentPayTag,
        'amount': amount,
        'currency': currency,
      }),
    );
    return Proposal.fromJson(_decodeOrThrow(res));
  }

  Future<List<AgentTransaction>> listAgentTransactions(String agentAppUserId) async {
    final res = await http.get(_uri('/users/$agentAppUserId/agent/transactions'), headers: _authHeaders());
    return _decodeListOrThrow(res)
        .map((e) => AgentTransaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- Split-bill (Phase 5) ---------------------------------------------------
  //
  // Each contributor's "pay" call returns the same Proposal shape as every
  // other transfer — sign/submit via the normal transfer endpoints.

  Future<({SplitBill splitBill, String qrToken})> createSplitBill(
    String appUserId, {
    required String description,
    required String currency,
    required String totalAmount,
    required List<({String? payTag, String? bmoniUserId, String shareAmount})> contributors,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/split-bills'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'description': description,
        'currency': currency,
        'totalAmount': totalAmount,
        'contributors': contributors
            .map((c) => {
                  if (c.payTag != null) 'payTag': c.payTag,
                  if (c.bmoniUserId != null) 'bmoniUserId': c.bmoniUserId,
                  'shareAmount': c.shareAmount,
                })
            .toList(),
      }),
    );
    final body = _decodeOrThrow(res);
    return (
      splitBill: SplitBill.fromJson(body['splitBill'] as Map<String, dynamic>),
      qrToken: body['qrToken'] as String,
    );
  }

  Future<List<SplitBill>> listSplitBills(String appUserId) async {
    final res = await http.get(_uri('/users/$appUserId/split-bills'), headers: _authHeaders());
    return _decodeListOrThrow(res)
        .map((e) => SplitBill.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SplitBill> getSplitBillByToken(String token) async {
    final res = await http.get(_uri('/split-bills/qr/$token'), headers: _authHeaders());
    return SplitBill.fromJson(_decodeOrThrow(res));
  }

  Future<Proposal> paySplitBillShare(String appUserId, String splitBillId) async {
    final res = await http.post(_uri('/users/$appUserId/split-bills/$splitBillId/pay'), headers: _authHeaders());
    return Proposal.fromJson(_decodeOrThrow(res));
  }

  // --- Send-via-link / escrow (Phase 5) ---------------------------------------
  //
  // *** Liability note (see backend's ClaimableLink model + README): while a
  // link is ESCROWED, PayFlex is holding a real customer's funds. This is
  // not "just a feature" — see backend/README.md before changing this flow. ***

  /// Returns either a plain transfer proposal (recipient already has a
  /// bmoniUserId) or an escrow proposal + claim token — check `type`.
  Future<
      ({
        String type, // "DIRECT_TRANSFER" | "ESCROW"
        Proposal? proposal, // set when type == DIRECT_TRANSFER
        Proposal? escrowProposal, // set when type == ESCROW
        String? claimToken, // set when type == ESCROW
      })> sendViaLink(
    String appUserId, {
    String? toBmoniUserId,
    required String amount,
    required String currency,
  }) async {
    final res = await http.post(
      _uri('/users/$appUserId/send-via-link'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        if (toBmoniUserId != null) 'toBmoniUserId': toBmoniUserId,
        'amount': amount,
        'currency': currency,
      }),
    );
    final body = _decodeOrThrow(res);
    final type = body['type'] as String;
    return (
      type: type,
      proposal: type == 'DIRECT_TRANSFER'
          ? Proposal.fromJson(body['proposal'] as Map<String, dynamic>)
          : null,
      escrowProposal: type == 'ESCROW'
          ? Proposal.fromJson(body['escrowProposal'] as Map<String, dynamic>)
          : null,
      claimToken: type == 'ESCROW' ? body['claimToken'] as String : null,
    );
  }

  Future<ClaimPreview> previewClaim(String token) async {
    final res = await http.get(_uri('/claim/$token'), headers: _authHeaders());
    return ClaimPreview.fromJson(_decodeOrThrow(res));
  }

  Future<void> claimLink(String appUserId, String token) async {
    final res = await http.post(_uri('/users/$appUserId/claim/$token'), headers: _authHeaders());
    _decodeAnyOrThrow(res);
  }
}
