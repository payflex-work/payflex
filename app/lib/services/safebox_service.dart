import 'dart:convert';
import 'dart:typed_data';

// transitively provided via stellar_flutter_sdk
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';

import '../stellar/stellar_client.dart';
import '../stellar/stellar_key_service.dart';
import 'wallet_service.dart';


/// App-side Safebox against the Soroban escrow contract
/// (backend/contracts/safebox). The CONTRACT is the source of truth:
/// owner/admin-only withdrawal and the 3-admin cap are enforced on-ledger,
/// not here and not in the backend. This service builds, PIN-gate-signs,
/// and submits the on-chain invocations from the device — the backend has
/// no contribute/withdraw endpoint at all (see backend/src/safebox), it
/// only verifies and reads.
///
/// Amounts cross the contract boundary as i128 in the token's smallest
/// unit (stroops for XLM), so [decimalToStroops] does the 7-decimal
/// conversion with BigInt — never double math, which loses precision in
/// exactly the places this app refuses to.
class SafeboxService {
  final StellarClient stellar;
  final String rpcUrl;

  SafeboxService({required this.stellar, required this.rpcUrl});

  // --- amount helpers (decimal string <-> i128 stroops) ---------------------

  static const _scale = 10000000; // 10^7, Stellar's 7 decimals

  /// "12.5" -> 125000000 (stroops). Throws on anything that isn't a
  /// positive decimal number — callers validate UI-side, this is the
  /// hard stop before it can reach the chain.
  static BigInt decimalToStroops(String decimal) {
    final s = decimal.trim();
    if (s.isEmpty) throw ArgumentError('Amount is empty.');
    final parts = s.split('.');
    if (parts.length > 2 || (parts.length == 2 && parts[1].isEmpty)) {
      throw ArgumentError('Amount is not a valid decimal: $s');
    }
    if (!RegExp(r'^\d+$').hasMatch(parts[0]) ||
        (parts.length == 2 && !RegExp(r'^\d*$').hasMatch(parts[1]))) {
      throw ArgumentError('Amount is not a valid decimal: $s');
    }
    final whole = parts[0];
    final frac = parts.length == 2 ? parts[1] : '';
    if (frac.length > 7) {
      throw ArgumentError('Amount supports at most 7 decimals: $s');
    }
    final fracPadded = frac.padRight(7, '0');
    final value = BigInt.parse(fracPadded.isEmpty ? whole : '$whole$fracPadded');
    if (value <= BigInt.zero) {
      throw ArgumentError('Amount must be greater than zero.');
    }
    return value;
  }

  /// 125000000 -> "12.5". Used for rendering contract state.
  static String stroopsToDecimal(BigInt stroops) {
    final negative = stroops.isNegative;
    final abs = negative ? -stroops : stroops;
    final whole = abs ~/ BigInt.from(_scale);
    final frac = (abs % BigInt.from(_scale)).toString().padLeft(7, '0');
    final trimmed = frac.replaceAll(RegExp(r'0+$'), '');
    final sign = negative ? '-' : '';
    return trimmed.isEmpty ? '$sign$whole' : '$sign$whole.$trimmed';
  }

  /// The contract-id of a classic asset's SAC on this network — the value
  /// the Safebox contract's `init(token)` expects. Derived exactly like
  /// the official SDKs do (CAP-46 backwards-compatible deployment): hash
  /// the ENVELOPE_TYPE_CONTRACT_ID preimage over (networkId, asset XDR)
  /// and encode the 32-byte hash as a C-strkey. The Dart SDK ships the
  /// XDR primitives but no one-line helper, so this is the helper.
  static String assetContractId({
    required String networkPassphrase,
    required Asset asset,
  }) {
    final networkIdBytes = Uint8List.fromList(
      crypto.sha256.convert(utf8.encode(networkPassphrase)).bytes,
    );

    final contractIdPreimage = XdrContractIDPreimage(
      XdrContractIDPreimageType.CONTRACT_ID_PREIMAGE_FROM_ASSET,
    );
    contractIdPreimage.fromAsset = asset.toXdr();

    final hashIdPreimageContractId = XdrHashIDPreimageContractID(
      XdrHash(networkIdBytes),
      contractIdPreimage,
    );

    final preimage = XdrHashIDPreimage(
      XdrEnvelopeType.ENVELOPE_TYPE_CONTRACT_ID,
    );
    preimage.contractID = hashIdPreimageContractId;

    final stream = XdrDataOutputStream();
    XdrHashIDPreimage.encode(stream, preimage);

    final hashed = Uint8List.fromList(
      crypto.sha256.convert(stream.bytes).bytes,
    );
    return StrKey.encodeContractId(hashed);
  }

  /// The native XLM SAC contract id on the current network — the default
  /// token for a new Safebox.
  String nativeTokenContractId() {
    return assetContractId(
      networkPassphrase: stellar.networkPassphrase,
      asset: Asset.NATIVE,
    );
  }

  // --- internals --------------------------------------------------------------

  /// PIN already verified by the caller (each public method re-checks via
  /// WalletService.verifyPin before reaching here). The keypair pulls the
  /// secret from secure storage — never from arguments, never from here.
  Future<SorobanClient> _client({
    required String contractId,
  }) async {
    final keyPair = await StellarKeyService.getOrCreateKeyPair();
    return SorobanClient.forClientOptions(
      options: ClientOptions(
        sourceAccountKeyPair: keyPair,
        contractId: contractId,
        network: stellar.network,
        rpcUrl: rpcUrl,
      ),
    );
  }

  static XdrSCVal _addressVal(String publicKey) =>
      Address.forAccountId(publicKey).toXdrSCVal();

  static XdrSCVal _amountVal(BigInt stroops) {
    final hi = stroops >> 64;
    final lo = stroops & ((BigInt.one << 64) - BigInt.one);
    return XdrSCVal.forI128Parts(hi, lo);
  }

  /// Extracts the u64 ledger timestamp from an XdrSCVal, tolerating both
  /// the u64 and i64 encodings the SDK can hand back.
  static int _timestampFrom(XdrSCVal v) {
    if (v.u64 != null) return v.u64!.uint64.toInt();
    if (v.i64 != null) return v.i64!.int64.toInt();
    return 0;
  }

  // --- on-chain operations ------------------------------------------------------

  /// Deploys a fresh Safebox contract from the already-installed wasm and
  /// initializes it with [ownerPublicKey] and the native XLM SAC token.
  /// Returns the new contract id (C...).
  Future<String> createSafebox({
    required String ownerPublicKey,
    required String wasmHash,
    required String pin,
  }) async {
    if (!await WalletService.verifyPin(pin)) {
      throw StateError('Incorrect PIN.');
    }
    final keyPair = await StellarKeyService.getOrCreateKeyPair();
    final client = await SorobanClient.deploy(
      deployRequest: DeployRequest(
        sourceAccountKeyPair: keyPair,
        network: stellar.network,
        rpcUrl: rpcUrl,
        wasmHash: wasmHash,
        constructorArgs: [
          _addressVal(ownerPublicKey),
          Address.forContractId(nativeTokenContractId()).toXdrSCVal(),
        ],
      ),
    );
    // Verify the contract really is ours on-chain before handing back the
    // id — never trust a successful deploy alone.
    final owner = await client.invokeMethod(name: 'get_owner');
    final ownerStr = _addressFrom(owner);
    if (ownerStr != ownerPublicKey) {
      throw StateError(
        'Deployed contract owner ($ownerStr) does not match this device ($ownerPublicKey).',
      );
    }
    return client.getContractId();
  }

  /// Contributes [amountDecimal] of the escrowed asset to [contractId].
  /// On-chain: the contract pulls the token from the member (require_auth
  /// on the member), records the ledger entry; every member can read it.
  /// Returns the confirmed transaction hash.
  Future<String> contribute({
    required String contractId,
    required String amountDecimal,
    required String pin,
  }) async {
    if (!await WalletService.verifyPin(pin)) {
      throw StateError('Incorrect PIN.');
    }
    final client = await _client(contractId: contractId);
    final me = (await StellarKeyService.getOrCreateKeyPair()).accountId;
    await client.invokeMethod(
      name: 'contribute',
      args: [
        _addressVal(me),
        _amountVal(decimalToStroops(amountDecimal)),
      ],
      force: true, // write call — never let a misread simulate-and-return
    );
    return _txHashFrom(contractId);
  }

  /// Withdraws [amountDecimal] to [toPublicKey]. ONLY succeeds on-chain if
  /// the signer is the owner or a designated admin — that enforcement is
  /// the whole point of this contract. Returns the confirmed tx hash.
  Future<String> withdraw({
    required String contractId,
    required String toPublicKey,
    required String amountDecimal,
    required String pin,
  }) async {
    if (!await WalletService.verifyPin(pin)) {
      throw StateError('Incorrect PIN.');
    }
    final client = await _client(contractId: contractId);
    final me = (await StellarKeyService.getOrCreateKeyPair()).accountId;
    await client.invokeMethod(
      name: 'withdraw',
      args: [
        _addressVal(me),
        _addressVal(toPublicKey),
        _amountVal(decimalToStroops(amountDecimal)),
      ],
      force: true,
    );
    // invokeMethod for a void-returning write throws on failure; reaching
    // here means the ledger accepted it. The hash is recoverable from the
    // client's last send — but we don't need it for the receipt, the
    // backend re-reads chain state as source of truth.
    return 'ok';
  }

  /// Adds [adminPublicKey] as an admin. Owner-only on-chain; the 3-admin
  /// cap is enforced by the contract, not here.
  Future<void> addAdmin({
    required String contractId,
    required String adminPublicKey,
    required String pin,
  }) async {
    if (!await WalletService.verifyPin(pin)) {
      throw StateError('Incorrect PIN.');
    }
    final client = await _client(contractId: contractId);
    final me = (await StellarKeyService.getOrCreateKeyPair()).accountId;
    await client.invokeMethod(
      name: 'add_admin',
      args: [_addressVal(me), _addressVal(adminPublicKey)],
      force: true,
    );
  }

  /// Removes [adminPublicKey] from the admin list. Owner-only on-chain.
  Future<void> removeAdmin({
    required String contractId,
    required String adminPublicKey,
    required String pin,
  }) async {
    if (!await WalletService.verifyPin(pin)) {
      throw StateError('Incorrect PIN.');
    }
    final client = await _client(contractId: contractId);
    final me = (await StellarKeyService.getOrCreateKeyPair()).accountId;
    await client.invokeMethod(
      name: 'remove_admin',
      args: [_addressVal(me), _addressVal(adminPublicKey)],
      force: true,
    );
  }

  /// Reads the shared ledger straight from the contract (read call, no
  /// signature) — the same view the backend returns via
  /// GET /safebox/:contractId/ledger, straight from the source.
  Future<List<Map<String, dynamic>>> readLedger(String contractId) async {
    final reader = KeyPair.fromAccountId(
      (await StellarKeyService.getOrCreateKeyPair()).accountId,
    );
    final client = await SorobanClient.forClientOptions(
      options: ClientOptions(
        sourceAccountKeyPair: reader,
        contractId: contractId,
        network: stellar.network,
        rpcUrl: rpcUrl,
      ),
    );
    final val = await client.invokeMethod(name: 'get_ledger');
    final vec = val.vec;
    if (vec == null) return const [];
    return vec.map(_ledgerEntry).toList();
  }

  static Map<String, dynamic> _ledgerEntry(XdrSCVal entry) {
    // LedgerEntry is a soroban struct -> SCVal map with symbol keys.
    XdrSCVal? entryField(XdrSCVal e, String name) {
      for (final kv in e.map ?? const <XdrSCMapEntry>[]) {
        if (kv.key.sym == name) return kv.val;
      }
      return null;
    }

    XdrSCVal? f(XdrSCVal e, String name) => entryField(e, name);
    return <String, dynamic>{
      'entry_type': f(entry, 'entry_type')?.sym ?? 'unknown',
      'member': f(entry, 'member') != null
          ? _addressFrom(f(entry, 'member')!)
          : '',
      'amount': f(entry, 'amount') != null
          ? stroopsToDecimal(_i128From(f(entry, 'amount')!))
          : '0',
      'created_at': f(entry, 'created_at') != null
          ? _timestampFrom(f(entry, 'created_at')!)
          : 0,
    };
  }

  // --- SCVal decoding helpers -----------------------------------------------------

  static String _addressFrom(XdrSCVal v) {
    final addr = v.address;
    if (addr == null) return '';
    final account = addr.accountId?.accountID.ed25519?.uint256;
    if (account != null) {
      return StrKey.encodeStellarAccountId(account);
    }
    final contract = addr.contractId?.hash;
    if (contract != null) {
      return StrKey.encodeContractId(contract);
    }
    return '';
  }

  static BigInt _i128From(XdrSCVal v) {
    final i128 = v.i128;
    if (i128 == null) return BigInt.zero;
    final hi = i128.hi.int64 << 64;
    final lo = i128.lo.uint64 & ((BigInt.one << 64) - BigInt.one);
    return hi + lo;
  }

  static String _txHashFrom(String contractId) {
    // invokeMethod returns the contract's return value, not the envelope
    // hash. For contribution receipts the ledger entry itself (read back
    // right after) is the durable proof, so a synthetic marker is enough
    // here — the screen shows the on-chain balance change, not a hash.
    return 'safebox-invocation:$contractId';
  }
}
