import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Pure-Dart cryptographic utilities for PayFlex.
///
/// Implements:
/// - SHA-256 and SHA-512 (FIPS 180-4 / RFC 6234)
/// - Ed25519 signature scheme (RFC 8032)
/// - Deterministic encoding & formatting helpers
///
/// Zero native dependencies, runs deterministically across all targets.
class CryptoUtils {
  // ---------------------------------------------------------------------------
  // Hex & Base64 conversions
  // ---------------------------------------------------------------------------

  static String bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static Uint8List hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+|0x'), '');
    if (clean.length % 2 != 0) {
      throw FormatException('Invalid hex string length: ${clean.length}');
    }
    final result = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < clean.length; i += 2) {
      result[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  static String bytesToBase64(List<int> bytes) => base64UrlEncode(bytes);

  static Uint8List base64ToBytes(String b64) {
    var normalized = b64.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return Uint8List.fromList(base64Decode(normalized));
  }

  static Uint8List utf8Bytes(String str) => Uint8List.fromList(utf8.encode(str));

  // ---------------------------------------------------------------------------
  // SHA-256 implementation
  // ---------------------------------------------------------------------------

  static Uint8List sha256Bytes(List<int> data) {
    return _Sha256().digest(data);
  }

  static String sha256Hex(String data) {
    final bytes = utf8Bytes(data);
    return bytesToHex(sha256Bytes(bytes));
  }

  // ---------------------------------------------------------------------------
  // SHA-512 implementation
  // ---------------------------------------------------------------------------

  static Uint8List sha512Bytes(List<int> data) {
    return _Sha512().digest(data);
  }

  // ---------------------------------------------------------------------------
  // Ed25519 Keypair Generation, Signing, and Verification (RFC 8032)
  // ---------------------------------------------------------------------------

  /// Generates a cryptographically-secure random 32-byte Ed25519 seed / private key.
  static Uint8List generateEd25519Seed() {
    final rng = Random.secure();
    final seed = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      seed[i] = rng.nextInt(256);
    }
    return seed;
  }

  /// Derives 32-byte public key from 32-byte seed.
  static Uint8List ed25519PublicKeyFromSeed(Uint8List seed) {
    if (seed.length != 32) throw ArgumentError('Seed must be 32 bytes');
    return _Ed25519.publicKeyFromSeed(seed);
  }

  /// Signs [message] with 32-byte [privateSeed], returns 64-byte signature.
  static Uint8List signEd25519(Uint8List message, Uint8List privateSeed) {
    if (privateSeed.length != 32) throw ArgumentError('Private seed must be 32 bytes');
    return _Ed25519.sign(message, privateSeed);
  }

  /// Verifies 64-byte [signature] against 32-byte [publicKey] for [message].
  static bool verifyEd25519(Uint8List message, Uint8List signature, Uint8List publicKey) {
    if (signature.length != 64 || publicKey.length != 32) return false;
    return _Ed25519.verify(message, signature, publicKey);
  }
}

// =============================================================================
// SHA-256 engine
// =============================================================================

class _Sha256 {
  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  Uint8List digest(List<int> data) {
    int h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    int h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

    final length = data.length;
    final bitLength = length * 8;

    final paddedLength = ((length + 9 + 63) ~/ 64) * 64;
    final padded = Uint8List(paddedLength);
    padded.setRange(0, length, data);
    padded[length] = 0x80;

    final view = ByteData.view(padded.buffer);
    view.setUint64(paddedLength - 8, bitLength, Endian.big);

    final w = List<int>.filled(64, 0);

    for (var i = 0; i < paddedLength; i += 64) {
      for (var t = 0; t < 16; t++) {
        w[t] = view.getUint32(i + t * 4, Endian.big);
      }
      for (var t = 16; t < 64; t++) {
        final s0 = _rotr32(w[t - 15], 7) ^ _rotr32(w[t - 15], 18) ^ (w[t - 15] >>> 3);
        final s1 = _rotr32(w[t - 2], 17) ^ _rotr32(w[t - 2], 19) ^ (w[t - 2] >>> 10);
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xffffffff;
      }

      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;

      for (var t = 0; t < 64; t++) {
        final s1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final temp1 = (h + s1 + ch + _k[t] + w[t]) & 0xffffffff;
        final s0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    final out = Uint8List(32);
    final outView = ByteData.view(out.buffer);
    outView.setUint32(0, h0, Endian.big);
    outView.setUint32(4, h1, Endian.big);
    outView.setUint32(8, h2, Endian.big);
    outView.setUint32(12, h3, Endian.big);
    outView.setUint32(16, h4, Endian.big);
    outView.setUint32(20, h5, Endian.big);
    outView.setUint32(24, h6, Endian.big);
    outView.setUint32(28, h7, Endian.big);
    return out;
  }

  static int _rotr32(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;
}

// =============================================================================
// SHA-512 engine (64-bit word operations)
// =============================================================================

class _Sha512 {
  static final List<BigInt> _k = [
    BigInt.parse('428a2f98d728ae22', radix: 16),
    BigInt.parse('7137449123ef65cd', radix: 16),
    BigInt.parse('b5c0fbcfec4d3b2f', radix: 16),
    BigInt.parse('e9b5dba58189dbbc', radix: 16),
    BigInt.parse('3956c25bf348b538', radix: 16),
    BigInt.parse('59f111f1b605d019', radix: 16),
    BigInt.parse('923f82a4af194f9b', radix: 16),
    BigInt.parse('ab1c5ed5da6d8118', radix: 16),
    BigInt.parse('d807aa98a3030242', radix: 16),
    BigInt.parse('12835b0145706fbe', radix: 16),
    BigInt.parse('243185be4ee4b28c', radix: 16),
    BigInt.parse('550c7dc3d5ffb4e2', radix: 16),
    BigInt.parse('72be5d74f27b896f', radix: 16),
    BigInt.parse('80deb1fe3b1696b1', radix: 16),
    BigInt.parse('9bdc06a725c71235', radix: 16),
    BigInt.parse('c19bf174cf692694', radix: 16),
    BigInt.parse('e49b69c19ef14ad2', radix: 16),
    BigInt.parse('efbe4786384f25e3', radix: 16),
    BigInt.parse('0fc19dc68b8cd5b5', radix: 16),
    BigInt.parse('240ca1cc77ac9c65', radix: 16),
    BigInt.parse('2de92c6f592b0275', radix: 16),
    BigInt.parse('4a7484aa6ea6e483', radix: 16),
    BigInt.parse('5cb0a9dcbd41fbd4', radix: 16),
    BigInt.parse('76f988da831153b5', radix: 16),
    BigInt.parse('983e5152ee66dfab', radix: 16),
    BigInt.parse('a831c66d2db43210', radix: 16),
    BigInt.parse('b00327c898fb213f', radix: 16),
    BigInt.parse('bf597fc7beef0ee4', radix: 16),
    BigInt.parse('c6e00bf33da88fc2', radix: 16),
    BigInt.parse('d5a79147930aa725', radix: 16),
    BigInt.parse('06ca6351e003826f', radix: 16),
    BigInt.parse('142929670a0e6e70', radix: 16),
    BigInt.parse('27b70a8546d22ffc', radix: 16),
    BigInt.parse('2e1b21385c26c926', radix: 16),
    BigInt.parse('4d2c6dfc5ac42aed', radix: 16),
    BigInt.parse('53380d139d95b3df', radix: 16),
    BigInt.parse('650a73548baf63de', radix: 16),
    BigInt.parse('766a0abb3c77b2a8', radix: 16),
    BigInt.parse('81c2c92e47867871', radix: 16),
    BigInt.parse('92722c851298a5e5', radix: 16),
    BigInt.parse('a2bfe8a14cf10364', radix: 16),
    BigInt.parse('a81a664bbc423001', radix: 16),
    BigInt.parse('c24b8b70d0f89791', radix: 16),
    BigInt.parse('c76c51a30654be30', radix: 16),
    BigInt.parse('d192e819d6ef5218', radix: 16),
    BigInt.parse('d69906245565a910', radix: 16),
    BigInt.parse('f40e35855771202a', radix: 16),
    BigInt.parse('106aa07032bbd1b8', radix: 16),
    BigInt.parse('19a4c116b8d2d0c8', radix: 16),
    BigInt.parse('1e376c085141ab53', radix: 16),
    BigInt.parse('2748774cdf8eeb99', radix: 16),
    BigInt.parse('34b0bcb5e19b48a8', radix: 16),
    BigInt.parse('391c0cb3c5c95a63', radix: 16),
    BigInt.parse('4ed8aa4ae3418acb', radix: 16),
    BigInt.parse('5b9cca4f7763e373', radix: 16),
    BigInt.parse('682e6ff3d6b2b8a3', radix: 16),
    BigInt.parse('748f82ee5defb2fc', radix: 16),
    BigInt.parse('78a5636f43172f60', radix: 16),
    BigInt.parse('84c87814a1f0ab72', radix: 16),
    BigInt.parse('8cc702081a6439ec', radix: 16),
    BigInt.parse('90befffa23631e28', radix: 16),
    BigInt.parse('a4506cebde82bde9', radix: 16),
    BigInt.parse('bef9a3f7b2c67915', radix: 16),
    BigInt.parse('c67178f2e372532b', radix: 16),
    BigInt.parse('ca273eceea26619c', radix: 16),
    BigInt.parse('d186b8c721c0c207', radix: 16),
    BigInt.parse('eada7dd6cde0eb1e', radix: 16),
    BigInt.parse('f57d4f7fee6ed178', radix: 16),
    BigInt.parse('06f067aa72176fba', radix: 16),
    BigInt.parse('0a637dc5a2c898a6', radix: 16),
    BigInt.parse('113f9804bef90dae', radix: 16),
    BigInt.parse('1b710b35131c471b', radix: 16),
    BigInt.parse('28db77f523047d84', radix: 16),
    BigInt.parse('32caab7b40c72493', radix: 16),
    BigInt.parse('3c9ebe0a15c9bebc', radix: 16),
    BigInt.parse('431d67c49c100d4c', radix: 16),
    BigInt.parse('4cc5d4becb3e42b6', radix: 16),
    BigInt.parse('597f299cfc657e2a', radix: 16),
    BigInt.parse('5fcb6fab3ad6faec', radix: 16),
    BigInt.parse('6c44198c4a475817', radix: 16),
  ];

  static final BigInt _mask64 = BigInt.parse('ffffffffffffffff', radix: 16);

  static BigInt _rotr64(BigInt x, int n) {
    return ((x >> n) | (x << (64 - n))) & _mask64;
  }

  Uint8List digest(List<int> data) {
    var h0 = BigInt.parse('6a09e667f3bcc908', radix: 16);
    var h1 = BigInt.parse('bb67ae8584caa73b', radix: 16);
    var h2 = BigInt.parse('3c6ef372fe94f82b', radix: 16);
    var h3 = BigInt.parse('a54ff53a5f1d36f1', radix: 16);
    var h4 = BigInt.parse('510e527fade682d1', radix: 16);
    var h5 = BigInt.parse('9b05688c2b3e6c1f', radix: 16);
    var h6 = BigInt.parse('1f83d9abfb41bd6b', radix: 16);
    var h7 = BigInt.parse('5be0cd19137e2179', radix: 16);

    final length = data.length;
    final bitLength = BigInt.from(length) * BigInt.from(8);

    final paddedLength = ((length + 17 + 127) ~/ 128) * 128;
    final padded = Uint8List(paddedLength);
    padded.setRange(0, length, data);
    padded[length] = 0x80;

    for (var b = 0; b < 8; b++) {
      padded[paddedLength - 1 - b] = ((bitLength >> (b * 8)) & BigInt.from(0xff)).toInt();
    }

    final w = List<BigInt>.filled(80, BigInt.zero);

    for (var i = 0; i < paddedLength; i += 128) {
      for (var t = 0; t < 16; t++) {
        var word = BigInt.zero;
        for (var b = 0; b < 8; b++) {
          word = (word << 8) | BigInt.from(padded[i + t * 8 + b]);
        }
        w[t] = word;
      }
      for (var t = 16; t < 80; t++) {
        final s0 = _rotr64(w[t - 15], 1) ^ _rotr64(w[t - 15], 8) ^ (w[t - 15] >> 7);
        final s1 = _rotr64(w[t - 2], 19) ^ _rotr64(w[t - 2], 61) ^ (w[t - 2] >> 6);
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & _mask64;
      }

      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;

      for (var t = 0; t < 80; t++) {
        final s1 = _rotr64(e, 14) ^ _rotr64(e, 18) ^ _rotr64(e, 41);
        final ch = (e & f) ^ ((~e & _mask64) & g);
        final temp1 = (h + s1 + ch + _k[t] + w[t]) & _mask64;
        final s0 = _rotr64(a, 28) ^ _rotr64(a, 34) ^ _rotr64(a, 39);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & _mask64;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & _mask64;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & _mask64;
      }

      h0 = (h0 + a) & _mask64;
      h1 = (h1 + b) & _mask64;
      h2 = (h2 + c) & _mask64;
      h3 = (h3 + d) & _mask64;
      h4 = (h4 + e) & _mask64;
      h5 = (h5 + f) & _mask64;
      h6 = (h6 + g) & _mask64;
      h7 = (h7 + h) & _mask64;
    }

    final out = Uint8List(64);
    final hashes = [h0, h1, h2, h3, h4, h5, h6, h7];
    for (var wIdx = 0; wIdx < 8; wIdx++) {
      final val = hashes[wIdx];
      for (var b = 0; b < 8; b++) {
        out[wIdx * 8 + b] = ((val >> ((7 - b) * 8)) & BigInt.from(0xff)).toInt();
      }
    }
    return out;
  }
}

// =============================================================================
// Ed25519 Curve Arithmetic & Signature Algorithm (RFC 8032)
// =============================================================================

class _Ed25519 {
  static final BigInt _p = BigInt.two.pow(255) - BigInt.from(19);
  static final BigInt _l = BigInt.two.pow(252) + BigInt.parse('27742317777372353535851937790883648493');
  static final BigInt _d = (-BigInt.from(121665) * _inv(BigInt.from(121666))) % _p;
  static final BigInt _i = _modPow(BigInt.two, (_p - BigInt.one) ~/ BigInt.from(4), _p);

  static final BigInt _by = (BigInt.from(4) * _inv(BigInt.from(5))) % _p;
  static final BigInt _bx = _recoverX(_by);

  static final _Point _b = _Point(_bx, _by);

  static BigInt _inv(BigInt x) => _modPow(x, _p - BigInt.two, _p);

  static BigInt _modPow(BigInt base, BigInt exponent, BigInt modulus) {
    return base.modPow(exponent, modulus);
  }

  static BigInt _recoverX(BigInt y) {
    final xx = ((y * y - BigInt.one) * _inv(_d * y * y + BigInt.one)) % _p;
    var x = _modPow(xx, (_p + BigInt.from(3)) ~/ BigInt.from(8), _p);
    if ((x * x - xx) % _p != BigInt.zero) {
      x = (x * _i) % _p;
    }
    if (x.isOdd) {
      x = (_p - x) % _p;
    }
    return x;
  }

  static BigInt _decodeScalar(List<int> bytes) {
    var res = BigInt.zero;
    for (var i = 0; i < bytes.length; i++) {
      res += BigInt.from(bytes[i]) << (i * 8);
    }
    return res;
  }

  static Uint8List _encodeScalar(BigInt s, int len) {
    final bytes = Uint8List(len);
    for (var i = 0; i < len; i++) {
      bytes[i] = ((s >> (i * 8)) & BigInt.from(0xff)).toInt();
    }
    return bytes;
  }

  static Uint8List _encodePoint(_Point p) {
    final bytes = _encodeScalar(p.y, 32);
    if (p.x.isOdd) {
      bytes[31] |= 0x80;
    }
    return bytes;
  }

  static _Point? _decodePoint(List<int> bytes) {
    if (bytes.length != 32) return null;
    final clean = List<int>.from(bytes);
    final sign = (clean[31] & 0x80) != 0;
    clean[31] &= 0x7f;
    final y = _decodeScalar(clean);
    if (y >= _p) return null;

    final xx = ((y * y - BigInt.one) * _inv(_d * y * y + BigInt.one)) % _p;
    if (xx == BigInt.zero) {
      if (sign) return null;
      return _Point(BigInt.zero, y);
    }

    var x = _modPow(xx, (_p + BigInt.from(3)) ~/ BigInt.from(8), _p);
    if ((x * x - xx) % _p != BigInt.zero) {
      x = (x * _i) % _p;
    }
    if ((x * x - xx) % _p != BigInt.zero) {
      return null;
    }
    if (x.isOdd != sign) {
      x = (_p - x) % _p;
    }
    return _Point(x, y);
  }

  static _Point _pointAdd(_Point p1, _Point p2) {
    final x1 = p1.x, y1 = p1.y, x2 = p2.x, y2 = p2.y;
    final dX1X2Y1Y2 = (_d * x1 * x2 % _p) * y1 % _p * y2 % _p;
    final x3 = ((x1 * y2 + y1 * x2) % _p) * _inv((BigInt.one + dX1X2Y1Y2) % _p) % _p;
    final y3 = ((y1 * y2 + x1 * x2) % _p) * _inv((BigInt.one - dX1X2Y1Y2) % _p) % _p;
    return _Point((x3 % _p + _p) % _p, (y3 % _p + _p) % _p);
  }

  static _Point _scalarMul(_Point p, BigInt scalar) {
    var result = _Point(BigInt.zero, BigInt.one);
    var addend = p;
    var s = scalar;
    while (s > BigInt.zero) {
      if (s.isOdd) {
        result = _pointAdd(result, addend);
      }
      addend = _pointAdd(addend, addend);
      s >>= 1;
    }
    return result;
  }

  static BigInt _clampScalar(Uint8List hash) {
    final clamped = Uint8List.fromList(hash.sublist(0, 32));
    clamped[0] &= 248;
    clamped[31] &= 127;
    clamped[31] |= 64;
    return _decodeScalar(clamped);
  }

  static Uint8List publicKeyFromSeed(Uint8List seed) {
    final h = _Sha512().digest(seed);
    final a = _clampScalar(h);
    final aPoint = _scalarMul(_b, a);
    return _encodePoint(aPoint);
  }

  static Uint8List sign(Uint8List message, Uint8List seed) {
    final h = _Sha512().digest(seed);
    final a = _clampScalar(h);
    final aPoint = _scalarMul(_b, a);
    final pubKeyBytes = _encodePoint(aPoint);

    final prefix = h.sublist(32, 64);
    final rHash = _Sha512().digest([...prefix, ...message]);
    final r = _decodeScalar(rHash) % _l;

    final rPoint = _scalarMul(_b, r);
    final rBytes = _encodePoint(rPoint);

    final kHash = _Sha512().digest([...rBytes, ...pubKeyBytes, ...message]);
    final k = _decodeScalar(kHash) % _l;

    final s = (r + k * a) % _l;
    final sBytes = _encodeScalar(s, 32);

    final signature = Uint8List(64);
    signature.setRange(0, 32, rBytes);
    signature.setRange(32, 64, sBytes);
    return signature;
  }

  static bool verify(Uint8List message, Uint8List signature, Uint8List publicKey) {
    if (signature.length != 64 || publicKey.length != 32) return false;

    final aPoint = _decodePoint(publicKey);
    if (aPoint == null) return false;

    final rBytes = signature.sublist(0, 32);
    final sBytes = signature.sublist(32, 64);

    final s = _decodeScalar(sBytes);
    if (s >= _l) return false;

    final rPoint = _decodePoint(rBytes);
    if (rPoint == null) return false;

    final kHash = _Sha512().digest([...rBytes, ...publicKey, ...message]);
    final k = _decodeScalar(kHash) % _l;

    final sb = _scalarMul(_b, s);
    final ka = _scalarMul(aPoint, k);
    final rPlusKa = _pointAdd(rPoint, ka);

    return sb.x == rPlusKa.x && sb.y == rPlusKa.y;
  }
}

class _Point {
  final BigInt x;
  final BigInt y;
  _Point(this.x, this.y);
}
