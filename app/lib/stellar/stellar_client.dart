import 'package:http/http.dart' as http;
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';
import 'stellar_errors.dart';
import 'stellar_key_service.dart';
import 'stellar_models.dart';

/// Client for PayFlex's Stellar rail. Talks DIRECTLY to Horizon — unlike
/// BMONI, which is only ever reached through PayFlex's own backend (it
/// needs a secret API key and does KYC/custody), Horizon is a public
/// blockchain API designed for exactly this: any wallet SDK talks to it
/// directly, and every operation here signs with the on-device Stellar
/// key (StellarKeyService), never anything server-held. PayFlex's own
/// backend has a THIN companion (see backend/src/stellar/) that only
/// proxies read-only Horizon lookups for its own rate-limiting reasons —
/// it never builds, signs, or submits a transaction on a user's behalf.
class StellarClient {
  final StellarSDK _sdk;
  final Network _network;
  final String? _friendbotUrl;

  StellarClient({
    required String horizonUrl,
    required bool isTestnet,
    String? friendbotUrl,
  })  : _sdk = StellarSDK(horizonUrl),
        _network = isTestnet ? Network.TESTNET : Network.PUBLIC,
        _friendbotUrl = friendbotUrl;

  /// Testnet-only convenience factory matching this rail's default.
  factory StellarClient.testnet() => StellarClient(
        horizonUrl: 'https://horizon-testnet.stellar.org',
        isTestnet: true,
        friendbotUrl: 'https://friendbot.stellar.org',
      );

  /// Built from GET /stellar/network's response — the backend is the one
  /// source of truth for which network this build talks to (same reason
  /// as Env.backendBaseUrl), so the app never hardcodes it twice.
  factory StellarClient.fromNetworkInfo(Map<String, dynamic> info) => StellarClient(
        horizonUrl: info['horizonUrl'] as String,
        isTestnet: info['network'] == 'testnet',
        friendbotUrl: info['friendbotUrl'] as String?,
      );

  Future<bool> isAccountFunded(String publicKey) async {
    try {
      await _sdk.accounts.account(publicKey);
      return true;
    } on ErrorResponse catch (e) {
      if (e.code == 404) return false;
      rethrow;
    }
  }

  /// Testnet only — Friendbot doesn't exist on mainnet. Mainnet
  /// activation instead needs a real minimum-balance payment from an
  /// already-funded account, which this app does not attempt to
  /// automate (a deliberate business decision,
  /// not an oversight).
  Future<void> fundViaFriendbot(String publicKey) async {
    if (_friendbotUrl == null) {
      throw StateError('No Friendbot URL configured — this is only ever available on testnet.');
    }
    final uri = Uri.parse(_friendbotUrl).replace(queryParameters: {'addr': publicKey});
    final response = await http.Client().get(uri);
    if (response.statusCode != 200) {
      throw Exception('Friendbot funding failed (${response.statusCode}): ${response.body}');
    }
  }

  Future<StellarAccountSummary> getAccountSummary(String publicKey) async {
    final account = await _sdk.accounts.account(publicKey);
    return StellarAccountSummary(
      publicKey: publicKey,
      balances: account.balances
          .map((b) => StellarBalance(
                assetType: b.assetType,
                assetCode: b.assetCode,
                assetIssuer: b.assetIssuer,
                balance: b.balance,
                limit: b.limit,
              ))
          .toList(),
    );
  }

  Future<List<StellarHistoryEntry>> getHistory(String publicKey, {int limit = 20}) async {
    final page = await _sdk.payments
        .forAccount(publicKey)
        .order(RequestBuilderOrder.DESC)
        .limit(limit)
        .execute();
    return page.records
        .map((r) => StellarHistoryEntry(
              id: r.id,
              transactionHash: r.transactionHash,
              type: r.type,
              createdAt: DateTime.tryParse(r.createdAt) ?? DateTime.now(),
            ))
        .toList();
  }

  /// Whether [publicKey] already trusts [assetCode] issued by [issuer] —
  /// the pre-flight check every send screen must run before submitting a
  /// non-native payment: a payment to an
  /// account without this trustline fails on-chain, and this app should
  /// catch that before spending a network round trip, not after.
  Future<bool> recipientHasTrustline(String recipientPublicKey, String assetCode, String issuer) async {
    if (assetCode == 'XLM') return true; // native asset needs no trustline
    try {
      final summary = await getAccountSummary(recipientPublicKey);
      return summary.hasTrustlineFor(assetCode, issuer);
    } on ErrorResponse catch (e) {
      if (e.code == 404) return false; // unfunded recipient has no trustlines at all
      rethrow;
    }
  }

  /// Establishes (or removes, with limit "0") a trustline from the
  /// device's own account to an issued asset. Carries a small XLM
  /// reserve cost on-chain — see the Add Asset screen's copy.
  Future<StellarPaymentResult> addTrustline({
    required String assetCode,
    required String issuer,
    String limit = ChangeTrustOperationBuilder.MAX_LIMIT,
  }) async {
    final keyPair = await StellarKeyService.getOrCreateKeyPair();
    final sourceAccount = await _sdk.accounts.account(keyPair.accountId);
    final asset = Asset.createNonNativeAsset(assetCode, issuer);

    final transaction = TransactionBuilder(sourceAccount)
        .addOperation(ChangeTrustOperationBuilder(asset, limit).build())
        .build();
    transaction.sign(keyPair, _network);

    return _submit(transaction);
  }

  /// Builds, signs, and submits a payment. [assetCode] is `"XLM"` for
  /// native, otherwise the trustline's asset code with [issuer] required.
  /// Callers must have already confirmed recipientHasTrustline for
  /// non-native assets and shown the mandatory irreversibility warning —
  /// this method does not re-check either, by design: it is the last
  /// step after the user has already confirmed.
  Future<StellarPaymentResult> sendPayment({
    required String destinationPublicKey,
    required String assetCode,
    String? issuer,
    required String amount,
  }) async {
    final keyPair = await StellarKeyService.getOrCreateKeyPair();
    final sourceAccount = await _sdk.accounts.account(keyPair.accountId);
    final asset = assetCode == 'XLM' ? Asset.NATIVE : Asset.createNonNativeAsset(assetCode, issuer!);

    final transaction = TransactionBuilder(sourceAccount)
        .addOperation(PaymentOperationBuilder(destinationPublicKey, asset, amount).build())
        .build();
    transaction.sign(keyPair, _network);

    return _submit(transaction);
  }

  Future<StellarPaymentResult> _submit(Transaction transaction) async {
    final response = await _sdk.submitTransaction(transaction);
    if (response.success) {
      return StellarPaymentResult(success: true, transactionHash: response.hash);
    }
    final codes = response.extras?.resultCodes;
    return StellarPaymentResult(
      success: false,
      errorCode: (codes?.operationsResultCodes?.isNotEmpty ?? false)
          ? codes!.operationsResultCodes!.first
          : codes?.transactionResultCode,
      errorMessage: StellarErrors.describe(
        transactionResultCode: codes?.transactionResultCode,
        operationResultCodes: codes?.operationsResultCodes,
      ),
    );
  }
}
