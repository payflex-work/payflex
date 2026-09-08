import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:payflex/protocol/fountain_coder.dart';

void main() {
  group('Optical Fountain Coder', () {
    const testPayload =
        '{"version":"pf-payreq-v1","requestId":"req_9988776655443322","merchantId":"usr_amina_42",'
        '"amountMinorUnits":750000,"currency":"NGN","note":"Market Supplies Bulk Order",'
        '"nonce":"nonce_11223344","createdAt":"2026-09-08T12:00:00.000Z"}';

    test('Encoder splits payload and generates valid FountainPackets', () {
      final encoder = FountainEncoder.fromString(testPayload, blockSize: 48);
      expect(encoder.k, greaterThan(1));
      expect(encoder.checksum.length, 8);

      final packet1 = encoder.nextPacket();
      expect(packet1.k, encoder.k);
      expect(packet1.seq, 0);

      final frameStr = packet1.serialize();
      expect(frameStr.startsWith(FountainPacket.prefix), isTrue);

      final parsed = FountainPacket.parse(frameStr);
      expect(parsed, isNotNull);
      expect(parsed!.sessionId, packet1.sessionId);
      expect(parsed.seq, packet1.seq);
      expect(parsed.checksum, packet1.checksum);
    });

    test('Decoder reconstructs payload from sequential frames', () {
      final encoder = FountainEncoder.fromString(testPayload, blockSize: 40);
      final decoder = FountainDecoder();

      var done = false;
      for (var i = 0; i < encoder.k + 5; i++) {
        final frame = encoder.nextFrame();
        done = decoder.addFrame(frame);
        if (done) break;
      }

      expect(done, isTrue);
      expect(decoder.isComplete, isTrue);
      expect(decoder.getPayloadString(), testPayload);
    });

    test('Decoder reconstructs payload from shuffled out-of-order frames', () {
      final encoder = FountainEncoder.fromString(testPayload, blockSize: 36);
      final decoder = FountainDecoder();

      // Collect 30 fountain frames
      final frames = <String>[];
      for (var i = 0; i < 30; i++) {
        frames.add(encoder.nextFrame());
      }

      // Shuffle frames randomly
      frames.shuffle(Random(42));

      var completed = false;
      for (final frame in frames) {
        if (decoder.addFrame(frame)) {
          completed = true;
          break;
        }
      }

      expect(completed, isTrue);
      expect(decoder.getPayloadString(), testPayload);
    });

    test('Decoder reconstructs payload despite 50% frame loss', () {
      final encoder = FountainEncoder.fromString(testPayload, blockSize: 32);
      final decoder = FountainDecoder();

      // Stream frames, dropping every second frame
      var completed = false;
      for (var i = 0; i < 40; i++) {
        final frame = encoder.nextFrame();
        if (i % 2 == 0) {
          // Received
          if (decoder.addFrame(frame)) {
            completed = true;
            break;
          }
        }
      }

      expect(completed, isTrue);
      expect(decoder.getPayloadString(), testPayload);
    });

    test('Decoder rejects frames from different sessions', () {
      // blockSize is deliberately small enough that k > 1 for this payload
      // — with k == 1 the very first (systematic) frame fully solves and
      // completes the decode, and addPacket's `if (_complete) return true`
      // fast path then short-circuits before the session check ever runs
      // on a second frame, making this test pass for the wrong reason.
      final encoder1 = FountainEncoder.fromString('Session 1 Data', sessionId: '111111', blockSize: 4);
      final encoder2 = FountainEncoder.fromString('Session 2 Data', sessionId: '222222', blockSize: 4);

      final decoder = FountainDecoder();

      // First frame sets session 1
      decoder.addFrame(encoder1.nextFrame());
      expect(decoder.activeSessionId, '111111');

      // Second session frame is rejected
      final accepted = decoder.addFrame(encoder2.nextFrame());
      expect(accepted, isFalse);
      expect(decoder.activeSessionId, '111111');
    });

    test('Decoder ignores duplicate identical frames', () {
      final encoder = FountainEncoder.fromString(testPayload, blockSize: 48);
      final decoder = FountainDecoder();

      final frame0 = encoder.nextFrame();
      expect(decoder.addFrame(frame0), isFalse);
      expect(decoder.receivedFrameCount, 1);

      // Re-feed same frame
      expect(decoder.addFrame(frame0), isFalse);
      expect(decoder.receivedFrameCount, 2);
    });
  });
}
