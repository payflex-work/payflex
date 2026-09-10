import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'crypto_utils.dart';

/// Exception thrown during optical fountain encoding or decoding.
class FountainException implements Exception {
  final String message;
  FountainException(this.message);

  @override
  String toString() => 'FountainException: $message';
}

/// A single encoded packet in the optical fountain stream.
class FountainPacket {
  static const String prefix = 'PF_FTN:1';

  final String sessionId;
  final int seq;
  final int k; // Total number of source blocks
  final int totalLength; // Total original payload length in bytes
  final String checksum; // First 8 chars of payload SHA-256
  final int seed; // PRNG seed used to determine degree and block indices
  final int degree; // Number of blocks XORed into this packet
  final List<int> blockIndices; // The source block indices included
  final Uint8List data; // XORed block data

  FountainPacket({
    required this.sessionId,
    required this.seq,
    required this.k,
    required this.totalLength,
    required this.checksum,
    required this.seed,
    required this.degree,
    required this.blockIndices,
    required this.data,
  });

  /// Serializes the packet to a compact QR-friendly string.
  /// Format: `PF_FTN:1:<sessionId>:<seq>:<k>:<totalLength>:<checksum>:<seed>:<base64Data>`
  String serialize() {
    final b64 = CryptoUtils.bytesToBase64(data);
    return '$prefix:$sessionId:$seq:$k:$totalLength:$checksum:$seed:$b64';
  }

  /// Parses a serialized fountain frame string.
  static FountainPacket? parse(String raw) {
    if (!raw.startsWith(prefix)) return null;
    final parts = raw.split(':');
    if (parts.length < 9) return null;

    final sessionId = parts[2];
    final seq = int.tryParse(parts[3]);
    final k = int.tryParse(parts[4]);
    final totalLength = int.tryParse(parts[5]);
    final checksum = parts[6];
    final seed = int.tryParse(parts[7]);
    final b64Data = parts[8];

    if (seq == null || k == null || totalLength == null || seed == null) {
      return null;
    }

    final data = CryptoUtils.base64ToBytes(b64Data);
    final (degree, indices) = FountainUtils.sampleDegreeAndIndices(seed, k);

    return FountainPacket(
      sessionId: sessionId,
      seq: seq,
      k: k,
      totalLength: totalLength,
      checksum: checksum,
      seed: seed,
      degree: degree,
      blockIndices: indices,
      data: data,
    );
  }
}

/// PRNG and degree distribution helpers for fountain coding.
class FountainUtils {
  /// Deterministic pseudo-random number generator based on xorshift32.
  static int xorshift32(int state) {
    var x = state & 0xFFFFFFFF;
    if (x == 0) x = 0x12345678;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= (x >>> 17) & 0xFFFFFFFF;
    x ^= (x << 5) & 0xFFFFFFFF;
    return x & 0xFFFFFFFF;
  }

  /// Derives the degree and source block indices deterministically from [seed] and [k].
  static (int degree, List<int> indices) sampleDegreeAndIndices(int seed, int k) {
    if (k <= 1) {
      return (1, [0]);
    }

    var prng = seed;

    // First sequence packets (seed < k) are systematic single blocks
    if (seed < k) {
      return (1, [seed % k]);
    }

    prng = xorshift32(prng);
    final rawProb = (prng & 0xFFFF) / 65536.0;

    // Robust soliton degree sampling
    int degree;
    if (rawProb < 0.40) {
      degree = 1;
    } else if (rawProb < 0.70) {
      degree = 2;
    } else if (rawProb < 0.85) {
      degree = 3;
    } else if (rawProb < 0.93) {
      degree = min(k, 4);
    } else if (rawProb < 0.97) {
      degree = min(k, max(5, k ~/ 2));
    } else {
      degree = k;
    }
    degree = max(1, min(k, degree));

    // Sample distinct indices using PRNG
    final available = List<int>.generate(k, (i) => i);
    final selected = <int>[];
    for (var i = 0; i < degree; i++) {
      prng = xorshift32(prng);
      final idx = (prng % available.length).abs();
      selected.add(available.removeAt(idx));
    }
    selected.sort();
    return (degree, selected);
  }
}

/// Loss-tolerant Luby Transform fountain encoder.
///
/// Converts a payment payload into a continuously emitted stream of QR-compatible
/// frames, allowing receivers to reconstruct the data even with packet loss and
/// out-of-order frame delivery.
class FountainEncoder {
  final Uint8List payload;
  final String sessionId;
  final int blockSize;
  final int k;
  final String checksum;
  final List<Uint8List> sourceBlocks;

  int _seq = 0;

  FountainEncoder._({
    required this.payload,
    required this.sessionId,
    required this.blockSize,
    required this.k,
    required this.checksum,
    required this.sourceBlocks,
  });

  /// Initializes a fountain encoder for [payload].
  /// [blockSize] defaults to 48 bytes for optimal QR scanner density.
  factory FountainEncoder.fromBytes(
    Uint8List payload, {
    String? sessionId,
    int blockSize = 48,
  }) {
    if (payload.isEmpty) throw ArgumentError('Payload cannot be empty');

    final fullSha = CryptoUtils.sha256Hex(CryptoUtils.bytesToHex(payload));
    final checksum = fullSha.substring(0, 8);

    final sid = sessionId ??
        (Random().nextInt(0xFFFFFF) + 0x100000).toRadixString(16).substring(0, 6);

    final totalLen = payload.length;
    final k = (totalLen + blockSize - 1) ~/ blockSize;

    final blocks = <Uint8List>[];
    for (var i = 0; i < k; i++) {
      final start = i * blockSize;
      final end = min(start + blockSize, totalLen);
      final block = Uint8List(blockSize);
      block.setRange(0, end - start, payload.sublist(start, end));
      blocks.add(block);
    }

    return FountainEncoder._(
      payload: payload,
      sessionId: sid,
      blockSize: blockSize,
      k: k,
      checksum: checksum,
      sourceBlocks: blocks,
    );
  }

  factory FountainEncoder.fromString(
    String text, {
    String? sessionId,
    int blockSize = 48,
  }) {
    return FountainEncoder.fromBytes(
      CryptoUtils.utf8Bytes(text),
      sessionId: sessionId,
      blockSize: blockSize,
    );
  }

  /// Generates the next encoded packet in the infinite fountain stream.
  FountainPacket nextPacket() {
    final seq = _seq++;
    final seed = seq; // Seed starts deterministic per sequence

    final (degree, indices) = FountainUtils.sampleDegreeAndIndices(seed, k);

    // XOR the selected source blocks
    final combined = Uint8List(blockSize);
    for (final idx in indices) {
      final block = sourceBlocks[idx];
      for (var b = 0; b < blockSize; b++) {
        combined[b] ^= block[b];
      }
    }

    return FountainPacket(
      sessionId: sessionId,
      seq: seq,
      k: k,
      totalLength: payload.length,
      checksum: checksum,
      seed: seed,
      degree: degree,
      blockIndices: indices,
      data: combined,
    );
  }

  /// Generates the next QR frame string.
  String nextFrame() => nextPacket().serialize();

  /// Resets sequence counter.
  void reset() {
    _seq = 0;
  }
}

/// Decoding state representing an unreduced or partially reduced linear equation.
class _Equation {
  final Set<int> indices;
  final Uint8List data;

  _Equation(this.indices, this.data);
}

/// Peeling / Ripple elimination fountain decoder.
///
/// Accepts frames in arbitrary order, deduplicates, rejects cross-session packets,
/// and reconstructs the verified original payload upon solving all $K$ blocks.
class FountainDecoder {
  String? _activeSessionId;
  int? _k;
  int? _totalLength;
  String? _expectedChecksum;

  final Map<int, Uint8List> _solvedBlocks = {};
  final List<_Equation> _pendingEquations = [];
  final Set<int> _receivedSeeds = {};
  int _receivedFrameCount = 0;

  bool _complete = false;
  Uint8List? _reconstructedPayload;

  // Getters
  String? get activeSessionId => _activeSessionId;
  int get totalBlocks => _k ?? 0;
  int get solvedBlocksCount => _solvedBlocks.length;
  int get receivedFrameCount => _receivedFrameCount;
  bool get isComplete => _complete;
  double get progress => _k == null || _k == 0 ? 0.0 : (_solvedBlocks.length / _k!).clamp(0.0, 1.0);
  Uint8List? get reconstructedPayload => _reconstructedPayload;

  /// Feeds a raw QR code string or [FountainPacket] into the decoder.
  /// Returns `true` if this frame led to full completion.
  bool addFrame(String rawFrame) {
    final packet = FountainPacket.parse(rawFrame);
    if (packet == null) return false;
    return addPacket(packet);
  }

  /// Processes an incoming [FountainPacket].
  bool addPacket(FountainPacket packet) {
    if (_complete) return true;

    // Session binding: lock to the first valid session
    if (_activeSessionId == null) {
      _activeSessionId = packet.sessionId;
      _k = packet.k;
      _totalLength = packet.totalLength;
      _expectedChecksum = packet.checksum;
    } else if (packet.sessionId != _activeSessionId) {
      // Ignore frames from other concurrent or past sessions
      return false;
    }

    _receivedFrameCount++;

    // Deduplicate identical seeds
    if (_receivedSeeds.contains(packet.seed)) {
      return false;
    }
    _receivedSeeds.add(packet.seed);

    // Create mutable equation copy
    final equationIndices = Set<int>.from(packet.blockIndices);
    final equationData = Uint8List.fromList(packet.data);

    // Subtract all already known source blocks
    _reduceEquationWithSolved(equationIndices, equationData);

    if (equationIndices.isEmpty) {
      // Redundant frame
      return false;
    }

    if (equationIndices.length == 1) {
      // Solved a new source block!
      _solveBlock(equationIndices.first, equationData);
    } else {
      // Store in pending equations
      _pendingEquations.add(_Equation(equationIndices, equationData));
    }

    return _checkCompletion();
  }

  void _reduceEquationWithSolved(Set<int> indices, Uint8List data) {
    final toRemove = <int>[];
    for (final idx in indices) {
      if (_solvedBlocks.containsKey(idx)) {
        final solvedData = _solvedBlocks[idx]!;
        for (var i = 0; i < data.length; i++) {
          data[i] ^= solvedData[i];
        }
        toRemove.add(idx);
      }
    }
    indices.removeAll(toRemove);
  }

  void _solveBlock(int blockIndex, Uint8List blockData) {
    if (_solvedBlocks.containsKey(blockIndex)) return;
    _solvedBlocks[blockIndex] = Uint8List.fromList(blockData);

    // Cascade: peel this new block from all pending equations
    var progress = true;
    while (progress) {
      progress = false;
      final newlySolved = <(int, Uint8List)>[];

      for (var i = _pendingEquations.length - 1; i >= 0; i--) {
        final eq = _pendingEquations[i];
        if (eq.indices.contains(blockIndex)) {
          eq.indices.remove(blockIndex);
          for (var b = 0; b < eq.data.length; b++) {
            eq.data[b] ^= blockData[b];
          }
        }

        if (eq.indices.isEmpty) {
          _pendingEquations.removeAt(i);
        } else if (eq.indices.length == 1) {
          newlySolved.add((eq.indices.first, eq.data));
          _pendingEquations.removeAt(i);
        }
      }

      for (final (idx, data) in newlySolved) {
        if (!_solvedBlocks.containsKey(idx)) {
          _solvedBlocks[idx] = Uint8List.fromList(data);
          blockIndex = idx;
          blockData = data;
          progress = true;
        }
      }
    }
  }

  bool _checkCompletion() {
    if (_k == null || _totalLength == null || _expectedChecksum == null) {
      return false;
    }

    if (_solvedBlocks.length >= _k!) {
      // Reconstruct payload
      final fullBytes = BytesBuilder();
      for (var i = 0; i < _k!; i++) {
        final block = _solvedBlocks[i];
        if (block == null) return false;
        fullBytes.add(block);
      }

      final rawPayload = fullBytes.toBytes().sublist(0, _totalLength!);
      final computedChecksum = CryptoUtils.sha256Hex(CryptoUtils.bytesToHex(rawPayload)).substring(0, 8);

      if (computedChecksum.toLowerCase() != _expectedChecksum!.toLowerCase()) {
        throw FountainException('Fountain payload checksum verification failed');
      }

      _reconstructedPayload = rawPayload;
      _complete = true;
      return true;
    }

    return false;
  }

  /// Returns the reconstructed payload as a UTF-8 string, or null if incomplete.
  String? getPayloadString() {
    if (!_complete || _reconstructedPayload == null) return null;
    return utf8.decode(_reconstructedPayload!);
  }

  /// Resets the decoder state to accept a new transmission.
  void reset() {
    _activeSessionId = null;
    _k = null;
    _totalLength = null;
    _expectedChecksum = null;
    _solvedBlocks.clear();
    _pendingEquations.clear();
    _receivedSeeds.clear();
    _receivedFrameCount = 0;
    _complete = false;
    _reconstructedPayload = null;
  }
}
