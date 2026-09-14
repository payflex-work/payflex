// Demo capture harness — PAYER device ("BABATUNDE"), the honest kind.
//
// This is the app's REAL offline payment code path, exercised for the SCF
// demo video: device-key-signed PaymentRequest parsing and verification,
// OfflineReserveService.spendFromReserve (chained signatures, monotonic
// sequence), PaymentConfirmation.serialize(), and the app's real
// AnimatedOpticalQr widget streaming the confirmation.
//
// The only simulated part is the transport: instead of photons, the QR
// frames the payer "sees" were rendered by the receiver harness and decoded
// for real in the orchestrator stage of this pipeline. No cryptographic step
// is mocked. Settlement in stage 4 is a REAL Stellar testnet transaction,
// built and signed exactly the way StellarClient.sendPaymentWithPin does it
// on device (build on-device → sign with the account key → submit to
// Horizon), with the memo tying the on-chain payment to the offline
// authorization so the backend can verify the link.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart' as st;

import 'package:payflex/protocol/crypto_utils.dart';
import 'package:payflex/protocol/fountain_coder.dart';
import 'package:payflex/protocol/payment_protocol.dart';
import 'package:payflex/services/offline_reserve_service.dart';
import 'package:payflex/theme/payflex_tokens.dart';
import 'package:payflex/utils/format.dart';
import 'package:payflex/widgets/animated_optical_qr.dart';

import 'harness_helpers.dart';

const outDir = '/tmp/pfdemo/payer';

Future<void> main() async {
  // Gated: this harness performs real network calls (Friendbot, Horizon)
  // and is run explicitly for the SCF demo capture: PF_DEMO=1 flutter test
  // test/demo/payer_harness_test.dart
  if (Platform.environment['PF_DEMO'] != '1') {
    test('demo capture is gated behind PF_DEMO=1', () => expect(true, isTrue));
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs a mock HttpOverrides globally at init, which would
  // 400 every real request. Friendbot funding and Horizon settlement below
  // are real network run OUTSIDE any test body, so restore real HTTP.
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});
  Directory(outDir).createSync(recursive: true);

  final frames = <String, Uint8List>{};

  // Real fonts, so the video looks like the app and not like tofu boxes.
  Future<void> loadFont(String family, String path) async {
    final data = File(path).readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(data.buffer)));
    await loader.load();
  }
  await loadFont('Roboto',
      '/home/gamp/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
  await loadFont('RobotoBold',
      '/home/gamp/flutter/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf');

  // -------------------------------------------------------------------------
  // Real payer identity: a genuine testnet account funded by Friendbot, so
  // stage 4's settlement is a genuine payment from a genuine account.
  // -------------------------------------------------------------------------
  final payerStellar = st.KeyPair.random();
  stderr.writeln('PAYER_STELLAR ${payerStellar.accountId}');
  final fundRes = await HttpClient()
      .getUrl(Uri.parse(
          'https://friendbot.stellar.org?addr=${payerStellar.accountId}'))
      .then((r) => r.close());
  if (fundRes.statusCode != 200) fail('friendbot funding failed');
  stderr.writeln('PAYER_FUNDED ${payerStellar.accountId}');

  // The offline protocol device key (independent of the account key, exactly
  // as the app does it: two identities, never crossed).
  final deviceSeed = CryptoUtils.generateEd25519Seed();

  // =========================================================================
  // STAGE 1 — Reserve provisioned while online (real service, real signing).
  // =========================================================================
  final payerReserve = OfflineReserveService();
  final store = <String, String>{};
  payerReserve.storageGetHook = (k) async => store[k];
  payerReserve.storageSetHook = (k, v) async => store[k] = v;

  const payerAppUserId = 'usr_demo_babatunde';
  final allowance = await payerReserve.provisionAllowance(
    appUserId: payerAppUserId,
    stellarPublicKey: payerStellar.accountId,
    amountMinorUnits: 2000000, // ₦20,000.00
    currency: 'NGN',
    validity: const Duration(hours: 24),
    explicitDeviceSeed: deviceSeed,
  );
  assert(allowance.remainingAmountMinorUnits == 2000000);

  // =========================================================================
  // STAGE 2 — OFFLINE. Decode the receiver's streamed request (real fountain
  // reconstruction of frames the receiver actually rendered), then verify it.
  // =========================================================================
  // What the payer "sees": prefer the orchestrator's real QR decode of the
  // receiver's rendered PNGs (pixels → jsQR → strings, what a phone camera
  // would produce); fall back to the receiver's persisted frame stream.
  final decodedReq = File('/tmp/pfdemo/request_frames_decoded.txt');
  final requestLines = (decodedReq.existsSync()
          ? decodedReq
          : File('/tmp/pfdemo/receiver/request_frames.txt'))
      .readAsLinesSync();
  final decoder = FountainDecoder();
  for (final frame in requestLines) {
    if (decoder.isComplete) break;
    decoder.addFrame(frame);
  }
  assert(decoder.isComplete);
  final request = PaymentRequest.deserialize(decoder.getPayloadString()!);
  request.verify(); // real device-signature + checksum + expiry verification
  assert(request.amountMinorUnits == 500000);

  // =========================================================================
  // STAGE 3 — authorize the offline spend (real chained signatures), then
  // broadcast the signed confirmation back over the optical channel using
  // the app's REAL AnimatedOpticalQr widget.
  // =========================================================================
  final spend = await payerReserve.spendFromReserve(
    request: request,
    explicitDeviceSeed: deviceSeed,
  );
  final allowanceAfter = await payerReserve.getActiveAllowance('NGN');
  final reserveLeftMinor = allowanceAfter!.remainingAmountMinorUnits;
  assert(reserveLeftMinor == 1500000);
  assert(spend.confirmation.status == 'RESERVE_PENDING');

  final confEncoder =
      FountainEncoder.fromString(spend.confirmation.serialize(), blockSize: 48);

  // =========================================================================
  // STAGE 4 — reconnect + REAL settlement on Stellar testnet.
  // =========================================================================
  final sdk = st.StellarSDK('https://horizon-testnet.stellar.org');
  final source = await sdk.accounts.account(payerStellar.accountId);
  final merchantAccountId =
      File('/tmp/pfdemo/receiver/stellar_account.txt').readAsStringSync().trim();

  final tx = st.TransactionBuilder(source)
      .addOperation(st.PaymentOperationBuilder(
              merchantAccountId, st.Asset.NATIVE, '1.5000000')
          .build())
      .addMemo(st.Memo.text(
          'offline ${shortRef(spend.authorization.authorizationId)}')) // ≤28 bytes, as the app's redemption does
      .build();
  tx.sign(payerStellar, st.Network.TESTNET); // the on-device signature
  final resp = await sdk.submitTransaction(tx); // real Horizon submission
  if (!resp.success) fail('settlement failed: ${resp.resultXdr}');
  final hash = resp.hash!;
  stderr.writeln('SETTLED $hash');
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) fail('bad hash shape');

  final onChainMemo =
      'offline ${shortRef(spend.authorization.authorizationId)}'; // matches the tx
  File('/tmp/pfdemo/payer/settlement.json').writeAsStringSync(jsonEncode({
    'hash': hash,
    'authorizationId': spend.authorization.authorizationId,
    'payerStellar': payerStellar.accountId,
    'merchantStellar': merchantAccountId,
    'amountXlm': '1.5000000',
    'memo': onChainMemo,
  }));

  // =========================================================================
  // Rendering pass — every screen above, in demo order.
  // =========================================================================
  testWidgets('payer demo frames', (tester) async {
    Widget chrome(Widget body) => DemoChrome(
          deviceLabel: 'DEVICE 1 — BABATUNDE (PAYER)',
          title: 'Pay offline',
          body: body,
        );

    // s1: reserve ready (two identical beats for dwell time).
    for (final name in ['s1a_reserve', 's1b_reserve']) {
      frames[name] = await renderFrame(
        tester,
        chrome(Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Available offline',
                        style: TextStyle(
                            color: PfColors.onNavyFaint, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(naira(allowance.remainingAmountMinorUnits),
                        style: const TextStyle(
                            color: PfColors.onNavy,
                            fontSize: 34,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    const StatusRow(
                        icon: Icons.verified_user_rounded,
                        tone: PfColors.emerald,
                        text: 'Device-signed allowance · NGN'),
                    const SizedBox(height: 6),
                    const StatusRow(
                        icon: Icons.wifi_off_rounded,
                        tone: PfColors.emerald,
                        text: 'Works with zero connectivity'),
                  ],
                ),
              ),
            ],
          ),
        )),
      );
    }

    // s2: scanning beats, then the decoded request.
    for (var i = 0; i < 4; i++) {
      frames['s2a_scanning_$i'] = await renderFrame(
        tester,
        chrome(Padding(
          padding: const EdgeInsets.all(20),
          child: Panel(
            child: Column(children: [
              const StatusRow(
                  icon: Icons.wifi_off_rounded,
                  tone: PfColors.onNavyFaint,
                  text: 'Airplane mode — optical link only'),
              const SizedBox(height: 12),
              StatusRow(
                  icon: Icons.camera_alt_rounded,
                  tone: PfColors.onNavy,
                  text:
                      'Receiving from AMINA CAFE… ${(i + 1) * 8}/${requestLines.length} frames'),
            ]),
          ),
        )),
      );
    }

    frames['s2b_request'] = await renderFrame(
      tester,
      chrome(Padding(
        padding: const EdgeInsets.all(20),
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(request.merchantName ?? 'AMINA CAFE',
                  style: const TextStyle(
                      color: PfColors.onNavyFaint, fontSize: 13)),
              const SizedBox(height: 4),
              Text(naira(request.amountMinorUnits),
                  style: const TextStyle(
                      color: PfColors.onNavy,
                      fontSize: 40,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(request.note ?? '',
                  style: const TextStyle(
                      color: PfColors.onNavyFaint, fontSize: 13)),
              const SizedBox(height: 14),
              const StatusRow(
                  icon: Icons.verified_rounded,
                  tone: PfColors.emerald,
                  text: 'Signature verified — request is authentic'),
            ],
          ),
        ),
      )),
    );

    // s3: confirmation broadcast via the app's real animated QR widget —
    // the widget advances the encoder on its own timer as it renders.
    for (var i = 0; i < 20; i++) {
      frames['s3_conf_${i.toString().padLeft(2, '0')}'] = await renderFrame(
        tester,
        chrome(Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Panel(
              child: Column(children: [
                StatusRow(
                    icon: Icons.wifi_off_rounded,
                    tone: PfColors.onNavyFaint,
                    text: 'Offline — handing the receipt back optically'),
                SizedBox(height: 10),
                StatusRow(
                    icon: Icons.task_alt_rounded,
                    tone: PfColors.emerald,
                    text: 'Confirmed — will settle when you\'re back online'),
              ]),
            ),
            const SizedBox(height: 14),
            AnimatedOpticalQr(encoder: confEncoder, size: 280),
          ]),
        )),
      );
    }

    // s3z: the payer's receipt.
    frames['s3z_receipt'] = await renderFrame(
      tester,
      chrome(Padding(
        padding: const EdgeInsets.all(20),
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Paid ${naira(request.amountMinorUnits)} — ${request.merchantName ?? 'AMINA CAFE'}',
                  style: const TextStyle(
                      color: PfColors.onNavy,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const StatusRow(
                  icon: Icons.schedule_rounded,
                  tone: Color(0xFFFFD28A),
                  text: 'Confirmed — will settle when you\'re back online'),
              const SizedBox(height: 8),
              StatusRow(
                  icon: Icons.account_balance_wallet_rounded,
                  tone: PfColors.onNavyFaint,
                  text: 'Reserve left: ${naira(reserveLeftMinor)}'),
            ],
          ),
        ),
      )),
    );

    // s4: reconnect → settled, with the real hash.
    frames['s4a_reconnecting'] = await renderFrame(
      tester,
      chrome(const Padding(
        padding: EdgeInsets.all(20),
        child: Panel(
          child: Column(children: [
            StatusRow(
                icon: Icons.wifi_rounded,
                tone: PfColors.onNavy,
                text: 'Connected — settling 1 offline payment…'),
          ]),
        ),
      )),
    );

    frames['s4b_settled'] = await renderFrame(
      tester,
      chrome(Padding(
        padding: const EdgeInsets.all(20),
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatusRow(
                  icon: Icons.check_circle_rounded,
                  tone: PfColors.emerald,
                  text: 'Settled — payment is on the ledger'),
              const SizedBox(height: 12),
              const Text('Stellar transaction',
                  style: TextStyle(color: PfColors.onNavyFaint, fontSize: 12)),
              const SizedBox(height: 2),
              Text(hash,
                  style: const TextStyle(
                      color: PfColors.onNavy,
                      fontSize: 11,
                      fontFamily: 'monospace')),
              const SizedBox(height: 12),
              const StatusRow(
                  icon: Icons.open_in_new_rounded,
                  tone: PfColors.onNavy,
                  text: 'View on StellarExpert →'),
            ],
          ),
        ),
      )),
    );
  });

  test('flush frames + confirmation stream', () {
    flushPngs('$outDir/frames', frames);
    // Persist the confirmation frame strings the receiver will "scan".
    final lines = <String>[];
    final enc2 =
        FountainEncoder.fromString(spend.confirmation.serialize(), blockSize: 48);
    for (var i = 0; i < 30; i++) {
      lines.add(base64.encode(utf8.encode(enc2.nextFrame())));
    }
    File('$outDir/conf_frames.txt').writeAsStringSync(lines.join('\n'));
    stderr.writeln('PAYER_DONE hash=$hash');
  });
}
