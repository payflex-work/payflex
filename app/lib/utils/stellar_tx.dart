import 'package:url_launcher/url_launcher.dart';
import '../services/api_client.dart';

/// Transaction-hash helpers for the "this payment is really on Stellar"
/// credibility layer. A tx hash is a 64-char lowercase hex string —
/// references like Safebox contract ids (C…) or PayFlex ids (uuids) do
/// NOT match, which is exactly the discrimination the confirmation screen
/// needs before offering an explorer link.
bool isStellarTxHash(String value) {
  final v = value.trim().toLowerCase();
  if (v.length != 64) return false;
  return RegExp(r'^[0-9a-f]+$').hasMatch(v);
}

/// Which network this build talks to, from the backend's /stellar/network
/// config — the app's ONE source of truth. Cached after the first call so
/// explorer links never add a round trip. Defaults to testnet (the demo
/// network) if the backend is unreachable, matching the app's own
/// testnet-first staging posture.
bool? _cachedTestnet;
Future<bool> resolveTestnet() async {
  if (_cachedTestnet != null) return _cachedTestnet!;
  try {
    final info = await ApiClient().getStellarNetwork();
    _cachedTestnet = (info['network'] as String? ?? 'testnet') == 'testnet';
  } catch (_) {
    _cachedTestnet = true;
  }
  return _cachedTestnet!;
}

/// Public explorers. StellarExpert is the primary surface; StellarChain
/// is kept as the technical fallback (different indexer, same data).
/// The network flag MUST come from [resolveTestnet] — never guessed.
Uri stellarExpertTxUrl(String hash, {required bool testnet}) => Uri.parse(
    'https://stellar.expert/explorer/${testnet ? 'testnet' : 'tx'}/tx/${hash.trim()}');

Uri stellarChainTxUrl(String hash, {required bool testnet}) =>
    Uri.parse('https://stellarchain.io/${testnet ? 'testnet/' : ''}tx/${hash.trim()}');

/// Best-effort external open. Returns false (and swallows the platform
/// error) so a missing browser/handler can never break a payment flow.
Future<bool> openStellarExplorer(
  String hash, {
  required bool testnet,
}) async {
  try {
    return await launchUrl(
      stellarExpertTxUrl(hash, testnet: testnet),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    try {
      return await launchUrl(
        stellarChainTxUrl(hash, testnet: testnet),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}