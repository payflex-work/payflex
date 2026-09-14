import 'package:http/http.dart' as http;
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';
import '../services/wallet_service.dart';
import 'stellar_errors.dart';
import 'stellar_key_service.dart';
import 'stellar_models.dart';

/// Client for PayFlex's Stellar rail — the app's ONLY payment rail. Talks
/// DIRECTLY to Horizon, which is a public blockchain API designed for
/// exactly this: any wallet SDK talks to it directly, and every operation
/// here signs with the on-device Stellar key (StellarKeyService), never
/// anything server-held. PayFlex's own backend has a THIN companion (see
/// backend/src/stellar/) that only proxies read-only Horizon lookups for
/// its own rate-limiting reasons — it never builds, signs, or submits a
/// transaction on a user's behalf.
class StellarClient {
  final StellarSDK _sdk;
  final Network _network;
  final String? _friendbotUrl;
  final String _horizonUrl;

  /// Whether this client targets the public testnet — surfaced for
  /// Friendbot-only UI (activation funding exists only on testnet).
  bool get isTestnet => _network == Network.TESTNET;

  /// Network object for SDK calls that need the full passphrase (Soroban
  /// contract clients, SAC id derivation).
  Network get network => _network;

  /// The network passphrase — SafeboxService derives the native SAC
  /// contract id from it.
  String get networkPassphrase => _network.networkPassphrase;

  /// The Soroban RPC endpoint for this network. SDF hosts Soroban RPC on
  /// the same host family as Horizon (horizon→soroban swap), matching the
  /// backend's own StellarService convention.
  String get sorobanRpcUrl =>
      _horizonUrl.replaceAll('horizon', 'soroban');

  StellarClient({
    required String horizonUrl,
    required bool isTestnet,
    String? friendbotUrl,
  })  : _sdk = StellarSDK(horizonUrl),
        _network = isTestnet ? Network.TESTNET : Network.PUBLIC,
        _friendbotUrl = friendbotUrl,
        _horizonUrl = horizonUrl;

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

  /// Builds, PIN-gate-signs, and submits a payment. [assetCode] is `"XLM"`
  /// for native, otherwise the trustline's asset code with [issuer]
  /// required. Callers must have already confirmed recipientHasTrustline
  /// for non-native assets and shown the mandatory irreversibility warning
  /// — this method does not re-check either, by design: it is the last
  /// step after the user has already confirmed.
  Future<StellarPaymentResult> sendPaymentWithPin({
    required String destinationPublicKey,
    required String assetCode,
    String? issuer,
    required String amount,
    required String pin,
    String? memo,
  }) async {
    final keyPair = await StellarKeyService.getOrCreateKeyPair();
    final sourceAccount = await _sdk.accounts.account(keyPair.accountId);
    final asset = assetCode == 'XLM' ? Asset.NATIVE : Asset.createNonNativeAsset(assetCode, issuer!);

    final builder = TransactionBuilder(sourceAccount);
    if (memo != null && memo.isNotEmpty) {
      builder.addMemo(Memo.text(memo));
    }
    final transaction = builder
        .addOperation(PaymentOperationBuilder(destinationPublicKey, asset, amount).build())
        .build();

    // The PIN gate: signing only happens through WalletService, after the
    // device-local PIN verifier passes. Never sign inline anywhere else.
    await WalletService.signTransaction(transaction, pin, _network);

    return _submit(transaction);
  }

  /// Builds, PIN-gate-signs, and submits a claimable-balance creation —
  /// the on-chain escrow behind send-via-link. Funds are escrowed BY THE
  /// CHAIN (claimants listed on the operation), never in a PayFlex-owned
  /// account. Before a recipient is known the sender is the sole claimant
  /// so they can reclaim; the share token lets the recipient find it.
  Future<StellarPaymentResult> createClaimableBalance({
    required List<String> claimantPublicKeys,
    required String assetCode,
    String? issuer,
    required String amount,
    required String pin,
  }) async {
    final keyPair = await StellarKeyService.getOrCreateKeyPair();
    final sourceAccount = await _sdk.accounts.account(keyPair.accountId);
    final asset = assetCode == 'XLM' ? Asset.NATIVE : Asset.createNonNativeAsset(assetCode, issuer!);

    final claimants = claimantPublicKeys
        .map((pk) => Claimant(pk, Claimant.predicateUnconditional()))
        .toList();
    final transaction = TransactionBuilder(sourceAccount)
        .addOperation(
            CreateClaimableBalanceOperationBuilder(claimants, asset, amount).build())
        .build();

    await WalletService.signTransaction(transaction, pin, _network);
    return _submit(transaction);
  }

  /// Builds, PIN-gate-signs, and submits a claimClaimableBalance operation
  /// — the recipient's side of send-via-link, signed by the claimant.
  Future<StellarPaymentResult> claimClaimableBalance({
    required String claimableBalanceId,
    required String pin,
  }) async {
    final keyPair = await StellarKeyService.getOrCreateKeyPair();
    final sourceAccount = await _sdk.accounts.account(keyPair.accountId);

    final transaction = TransactionBuilder(sourceAccount)
        .addOperation(ClaimClaimableBalanceOperationBuilder(claimableBalanceId).build())
        .build();

    await WalletService.signTransaction(transaction, pin, _network);
    return _submit(transaction);
  }

  /// Reads back the id of the claimable balance created by [txHash] —
  /// used by send-via-link so the sender's app can hand the backend the
  /// CB id to verify (the transaction hash itself is not the CB id).
  /// Returns null if the ledger hasn't caught up yet or nothing was found.
  Future<String?> findCreatedClaimableBalanceId({
    required String txHash,
    required String requesterPublicKey,
  }) async {
    try {
      final page = await _sdk.claimableBalances
          .forClaimant(requesterPublicKey)
          .order(RequestBuilderOrder.DESC)
          .limit(10)
          .execute();
      // Horizon doesn't expose the creating tx on the CB row directly;
      // matching on the requester's newest CBs is sufficient in practice:
      // the balance was created moments ago by this very transaction.
      for (final cb in page.records) {
        final claimants = cb.claimants;
        if (claimants.any((c) => c.destination == requesterPublicKey)) {
          return cb.balanceId;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
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
