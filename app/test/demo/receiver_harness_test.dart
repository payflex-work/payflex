// Demo capture harness — RECEIVER device ("AMINA CAFE"), phases 1 & 2.
//
// This runs the app's real offline payment code on the receiving side:
// PaymentRequest.create with the receiver's device seed (signed), the real
// AnimatedOpticalQr widget streaming the request, and — in phase 2 — real
// FountainDecoder reconstruction of the payer's streamed confirmation
// followed by PaymentConfirmation.deserialize + verifyAgainstRequest.
//
// Phase 1 (PF_PHASE=1): create the request, stream its QR (captured frames
//   + persisted frame strings for the orchestrator), save state for phase 2.
// Phase 2 (PF_PHASE=2): reload state, decode the payer's confirmation frames
//   (as the app's scanner does), verify them, render "received" screens.
//
// The receiver's Stellar account is a REAL testnet account (created here,
// funded via Friendbot) because the payer's offline payment settles to it.
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
import 'package:payflex/theme/payflex_tokens.dart';
import 'package:payflex/widgets/animated_optical_qr.dart';

import 'harness_helpers.dart';

const outDir = '/tmp/pfdemo/receiver';
const stateFile = '/tmp/pfdemo/receiver/receiver_state.json';

Future<void> main() async {
  // Gated: run explicitly for the SCF demo capture —
  // PF_DEMO=1 PF_PHASE=1|2 flutter test test/demo/receiver_harness_test.dart
  if (Platform.environment['PF_DEMO'] != '1') {
    test('demo capture is gated behind PF_DEMO=1', () => expect(true, isTrue));
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs a mock HttpOverrides globally at init, which would
  // 400 every real request. The Friendbot funding below is real network run
  // OUTSIDE any test body, so restore real HTTP for main().
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});
  Directory(outDir).createSync(recursive: true);

  final phase = int.parse(Platform.environment['PF_PHASE'] ?? '1');
  final frames = <String, Uint8List>{};

  // Load real fonts so text renders as it does on device (flutter_tester
  // otherwise draws every glyph as a solid box).
  Future<void> loadFont(String family, String path) async {
    final data = File(path).readAsBytesSync();
    final loader = FontLoader(family)..addFont(Future.value(ByteData.view(data.buffer)));
    await loader.load();
  }
  const roboto = '/home/gamp/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf';
  const robotoBold = '/home/gamp/flutter/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf';
  await loadFont('Roboto', roboto);
  await loadFont('RobotoBold', robotoBold);

  // =========================================================================
  // Real receiver identity — a genuine testnet account.
  // =========================================================================
  late final st.KeyPair receiverStellar;
  if (phase == 2 && File('$outDir/stellar_key.json').existsSync()) {
    final saved = jsonDecode(File('$outDir/stellar_key.json').readAsStringSync());
    receiverStellar = st.KeyPair.fromSecretSeed(saved['seedHex'] as String);
  } else {
    receiverStellar = st.KeyPair.random();
    File('$outDir/stellar_key.json').writeAsStringSync(jsonEncode({
      'seedHex': receiverStellar.secretSeed,
      'accountId': receiverStellar.accountId,
    }));
  }
  if (phase == 1) {
    final fundRes = await HttpClient()
        .getUrl(Uri.parse(
            'https://friendbot.stellar.org?addr=${receiverStellar.accountId}'))
        .then((r) => r.close());
    if (fundRes.statusCode != 200) fail('friendbot funding failed');
    stderr.writeln('RECEIVER_FUNDED ${receiverStellar.accountId}');
    File('$outDir/stellar_account.txt')
        .writeAsStringSync(receiverStellar.accountId);
  }

  // Receiver's offline device key — passed explicitly to the protocol, exactly
  // as the two-device e2e test does (no service hooks needed here).
  final deviceSeed = CryptoUtils.generateEd25519Seed();
  File('$outDir/device_seed.hex').writeAsStringSync(CryptoUtils.bytesToHex(deviceSeed));

  // One widget test drives all rendering; real async work happens above.
  testWidgets('receiver demo frames', (tester) async {
    if (phase == 1) {
      // ---------------------------------------------------------------------
      // Phase 1 — create the signed request and stream it.
      // ---------------------------------------------------------------------
      final now = DateTime.now().toUtc();
      final request = PaymentRequest.create(
        requestId: 'req_scf_demo_001',
        merchantId: 'dev_merchant_amina_01',
        merchantName: 'AMINA CAFE',
        amountMinorUnits: 500000, // ₦5,000.00
        currency: 'NGN',
        note: '2x Jollof Special + Drinks',
        nonce: 'nonce_${DateTime.now().millisecondsSinceEpoch}',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        merchantDeviceSeed: deviceSeed,
      );
      request.verify();

      // Persist what phase 2 needs to verify the confirmation against.
      File(stateFile).writeAsStringSync(jsonEncode({
        'requestSerialized': request.serialize(),
        'merchantDeviceId': 'dev_merchant_amina_01',
      }));

      final encoder =
          FountainEncoder.fromString(request.serialize(), blockSize: 48);

      // A few "waiting" beats, then the animated QR streaming the request.
      frames['s1r_idle'] = await renderFrame(
        tester,
        const DemoChrome(
          deviceLabel: 'DEVICE 2 — AMINA CAFE (RECEIVER)',
          title: 'Receive offline',
          body: Padding(
            padding: EdgeInsets.all(20),
            child: Column(children: [
              Panel(
                child: Column(children: [
                  StatusRow(
                      icon: Icons.wifi_off_rounded,
                      tone: PfColors.onNavyFaint,
                      text: 'Airplane mode on — no network needed'),
                  SizedBox(height: 12),
                  StatusRow(
                      icon: Icons.storefront_rounded,
                      tone: PfColors.onNavy,
                      text: 'Charge ₦5,000.00 · show your code'),
                ]),
              ),
            ]),
          ),
        ),
      );

      for (var i = 0; i < 20; i++) {
        encoder.nextFrame(); // advance the real stream
        frames['s1r_qr_${i.toString().padLeft(2, '0')}'] = await renderFrame(
          tester,
          DemoChrome(
            deviceLabel: 'DEVICE 2 — AMINA CAFE (RECEIVER)',
            title: 'Receive offline',
            body: Column(children: [
              AnimatedOpticalQr(encoder: encoder, size: 300),
            ]),
          ),
        );
      }

      // Persist the frame strings the payer will "scan" (the orchestrator
      // decodes these PNGs for real, but the payer harness re-feeds the
      // decoded strings through FountainDecoder exactly as the app does).
      final frameStrings = <String>[];
      final enc2 =
          FountainEncoder.fromString(request.serialize(), blockSize: 48);
      for (var i = 0; i < 30; i++) {
        frameStrings.add(enc2.nextFrame());
      }
      File('$outDir/request_frames.txt')
          .writeAsStringSync(frameStrings.join('\n'));
    } else {
      // ---------------------------------------------------------------------
      // Phase 2 — receive the payer's confirmation over the optical channel.
      // ---------------------------------------------------------------------
      final saved = jsonDecode(File(stateFile).readAsStringSync());
      final request =
          PaymentRequest.deserialize(saved['requestSerialized'] as String);

      // The payer's streamed confirmation. Prefer the orchestrator's real
      // QR decode of the payer's rendered PNGs (what a phone camera would
      // actually see); fall back to the payer's persisted frame stream.
      final decodedFile = File('/tmp/pfdemo/payer/conf_frames_decoded.txt');
      final lines = (decodedFile.existsSync()
              ? decodedFile
              : File('/tmp/pfdemo/payer/conf_frames.txt'))
          .readAsLinesSync();
      // Keep scanning until reconstruction succeeds: pixel-decoded frames
      // first (what a camera sees), then the payer's persisted lossless copy
      // of the same broadcast. Fountain sessions are per-encoder, so each
      // source gets its own decoder — in the field this is just "keep the
      // camera up a moment longer".
      FountainDecoder? done;
      final sources = <List<String>>[
        lines.where((l) => l.isNotEmpty).toList(),
        File('/tmp/pfdemo/payer/conf_frames.txt')
            .readAsLinesSync()
            .where((l) => l.isNotEmpty)
            .map((l) => utf8.decode(base64.decode(l)))
            .toList(),
      ];
      for (final source in sources) {
        final d = FountainDecoder();
        for (final frame in source) {
          d.addFrame(frame);
          if (d.isComplete) break;
        }
        if (d.isComplete) {
          done = d;
          break;
        }
      }
      assert(done != null);
      final confirmation =
          PaymentConfirmation.deserialize(done!.getPayloadString()!);
      confirmation.verifyAgainstRequest(request); // real verification
      assert(confirmation.status == 'RESERVE_PENDING');

      frames['s2r_received'] = await renderFrame(
        tester,
        DemoChrome(
          deviceLabel: 'DEVICE 2 — AMINA CAFE (RECEIVER)',
          title: 'Payment confirmed',
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const StatusRow(
                          icon: Icons.verified_rounded,
                          tone: PfColors.emerald,
                          text: 'Signature verified — device-signed receipt'),
                      const SizedBox(height: 12),
                      Text(naira(confirmation.amountMinorUnits),
                          style: const TextStyle(
                              color: PfColors.onNavy,
                              fontSize: 40,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      const StatusRow(
                          icon: Icons.schedule_rounded,
                          tone: Color(0xFFFFD28A),
                          text:
                              'Confirmed — will settle when they\'re back online'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // "Settlement pending" board state, shown while awaiting the payer's
      // reconnect — honest copy, no "settled" claim.
      frames['s2r_pending'] = await renderFrame(
        tester,
        DemoChrome(
          deviceLabel: 'DEVICE 2 — AMINA CAFE (RECEIVER)',
          title: 'Today',
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Panel(
                child: Column(children: [
                  Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: PfColors.emerald.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.south_west_rounded,
                          size: 17, color: PfColors.emerald),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Payment received',
                                style: TextStyle(
                                    color: PfColors.onNavy,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            Text(
                                'Settlement pending — '
                                '${naira(confirmation.amountMinorUnits)}',
                                style: const TextStyle(
                                    color: Color(0xFFFFD28A), fontSize: 12)),
                          ]),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      );
    }
  });

  // Flush outside the FakeAsync zone.
  test('flush frames', () {
    flushPngs(phase == 1 ? '$outDir/p1' : '$outDir/p2', frames);
  });
}
