import 'package:flutter_test/flutter_test.dart';
import 'package:payflex/stellar/stellar_key_service.dart';

void main() {
  setUp(() {
    final store = <String, String>{};
    StellarKeyService.secureReadHook = (key) async => store[key];
    StellarKeyService.secureWriteHook = (key, value) async => store[key] = value;
    StellarKeyService.resetCacheForTest();
  });

  tearDown(() {
    StellarKeyService.secureReadHook = null;
    StellarKeyService.secureWriteHook = null;
    StellarKeyService.resetCacheForTest();
  });

  test('has not opted in before any keypair is created', () async {
    expect(await StellarKeyService.hasOptedIn(), isFalse);
  });

  test('generates a real, valid StrKey-encoded keypair on first use', () async {
    final keyPair = await StellarKeyService.getOrCreateKeyPair();

    expect(keyPair.accountId, startsWith('G'));
    expect(keyPair.accountId.length, 56);
    expect(keyPair.secretSeed, startsWith('S'));
    expect(await StellarKeyService.hasOptedIn(), isTrue);
  });

  test('persists the same keypair across calls, not a fresh one each time', () async {
    final first = await StellarKeyService.getOrCreateKeyPair();
    StellarKeyService.resetCacheForTest(); // force a re-read from storage, not the in-memory cache
    final second = await StellarKeyService.getOrCreateKeyPair();

    expect(second.accountId, first.accountId);
    expect(second.secretSeed, first.secretSeed);
  });

  test('never writes the secret seed anywhere but the injected secure-storage hook', () async {
    final writes = <String, String>{};
    StellarKeyService.secureWriteHook = (key, value) async => writes[key] = value;

    final keyPair = await StellarKeyService.getOrCreateKeyPair();

    expect(writes.values, contains(keyPair.secretSeed));
    expect(writes.length, 1); // exactly one storage slot, no incidental extra writes
  });

  test('two devices (two service instances via reset) generate different keypairs', () async {
    final deviceAStore = <String, String>{};
    StellarKeyService.secureReadHook = (key) async => deviceAStore[key];
    StellarKeyService.secureWriteHook = (key, value) async => deviceAStore[key] = value;
    final deviceA = await StellarKeyService.getOrCreateKeyPair();

    StellarKeyService.resetCacheForTest();
    final deviceBStore = <String, String>{};
    StellarKeyService.secureReadHook = (key) async => deviceBStore[key];
    StellarKeyService.secureWriteHook = (key, value) async => deviceBStore[key] = value;
    final deviceB = await StellarKeyService.getOrCreateKeyPair();

    expect(deviceA.accountId, isNot(equals(deviceB.accountId)));
  });
}
