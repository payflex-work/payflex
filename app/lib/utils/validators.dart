import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';

// Client-side validation mirroring backend/src/common/validation/validators.ts
// — the two sides MUST stay consistent (hardening brief §3): if the backend
// rejects an amount above some bound or a malformed key, the app should
// catch it here first with an inline error, never as a confusing server 400.
//
// Stellar payments are irreversible once confirmed, so recipient-key
// validation is a real safety feature, not UX polish.

/// Largest amount accepted anywhere: 1,000,000,000,000 (1e12).
const String kMaxStellarAmount = '1000000000000';

/// Stellar's native precision: at most 7 decimal places on any amount.
const int kMaxAmountDecimals = 7;

/// A Stellar text memo holds at most 28 bytes UTF-8 — anything longer is
/// rejected on-chain when the transaction is built, so we catch it here.
const int kMaxMemoBytes = 28;

/// Ed25519 account strkey: G… + 55 base32 chars (56 total).
const String kPublicKeyPattern = r'^G[A-Z2-7]{55}$';

/// Soroban contract id: C… + 55 base32 chars.
const String kContractIdPattern = r'^C[A-Z2-7]{55}$';

/// Horizon claimable-balance id: 00000000 + 64 lowercase hex (72 chars).
const String kClaimableBalanceIdPattern = r'^00000000[0-9a-f]{64}$';

/// A Stellar transaction hash: 64 lowercase hex characters.
const String kTxHashPattern = r'^[0-9a-f]{64}$';

/// PayTag: 3-20 lowercase alphanumerics/underscores (backend RegisterPayTagDto).
const String kPayTagPattern = r'^[a-z0-9_]{3,20}$';

/// Strips control characters (keeping tab/newline) and trims — mirrors
/// the backend's sanitizeText so nothing unrenderable reaches the wire.
String sanitizeText(String value) {
  return value.replaceAllMapped(
    RegExp('[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F\\u007F]'),
    (_) => '',
  ).trim();
}

/// True when [value] is a checksum-valid Ed25519 account strkey (G…).
/// Uses the Stellar SDK's own decoder — NOT just the shape regex — so a
/// typo'd key that happens to be 56 valid base32 chars is caught.
bool isValidStellarPublicKey(String value) {
  final v = value.trim();
  if (!RegExp(kPublicKeyPattern).hasMatch(v)) return false;
  try {
    return StrKey.isValidStellarAccountId(v);
  } catch (_) {
    return false;
  }
}

/// True when [value] is a checksum-valid Soroban contract id (C…).
bool isValidStellarContractId(String value) {
  final v = value.trim();
  if (!RegExp(kContractIdPattern).hasMatch(v)) return false;
  try {
    return StrKey.isValidContractId(v);
  } catch (_) {
    return false;
  }
}

/// True when [value] is a Horizon claimable-balance id (00000000…, 72 hex).
bool isValidClaimableBalanceId(String value) =>
    RegExp(kClaimableBalanceIdPattern).hasMatch(value.trim());

/// True when [value] is a 64-char lowercase hex transaction hash.
bool isValidStellarTxHash(String value) =>
    RegExp(kTxHashPattern).hasMatch(value.trim());

/// True when [value] is "XLM" or a 1-12 uppercase alphanumeric asset code
/// (Stellar's alphanum4/alphanum12 limit).
bool isValidAssetCode(String value) {
  final v = value.trim().toUpperCase();
  return v == 'XLM' || RegExp(r'^[A-Z0-9]{1,12}$').hasMatch(v);
}

/// True when [value] is a well-formed PayTag (3-20 lowercase/digits/_).
bool isValidPayTag(String value) => RegExp(kPayTagPattern).hasMatch(value.trim());

/// True when [value] is a strictly positive decimal string within Stellar's
/// rules: no sign, no exponent, at most 7 decimals, ≤ 1e12. "5.00" passes;
/// "-5", "0", "5e2", "5.12345678", "NaN" fail. Matches the backend's
/// IsStellarAmount exactly.
bool isValidStellarAmount(String value) {
  final v = value.trim();
  if (v.isEmpty || v.length > 20) return false;
  if (!RegExp(r'^\d+(\.\d{1,7})?$').hasMatch(v)) return false;
  final n = double.tryParse(v);
  if (n == null || !n.isFinite) return false;
  return n > 0 && n <= double.parse(kMaxStellarAmount);
}

/// Parses a valid amount string to double; returns null when invalid.
/// Only use after [isValidStellarAmount] — this is for display math.
double? parseStellarAmount(String value) {
  if (!isValidStellarAmount(value)) return null;
  return double.parse(value.trim());
}

/// UTF-8 byte length of [value] (memos are byte-capped, not char-capped).
int utf8Length(String value) => utf8.encode(value).length;

/// True when [value] fits inside a Stellar text memo (≤ 28 UTF-8 bytes).
bool isValidMemo(String value) => utf8Length(value.trim()) <= kMaxMemoBytes;

/// Human message for an invalid amount, or null when valid. Kept in one
/// place so every screen words it identically.
String? amountError(String value) {
  final v = value.trim();
  if (v.isEmpty) return 'Enter an amount.';
  if (double.tryParse(v) == null || !RegExp(r'^\d+(\.\d{1,7})?$').hasMatch(v)) {
    return 'Enter a valid amount (digits only, e.g. 5.00).';
  }
  if (double.parse(v) <= 0) return 'Amount must be greater than zero.';
  if (v.contains('.') && v.split('.').last.length > kMaxAmountDecimals) {
    return 'Stellar supports at most $kMaxAmountDecimals decimal places.';
  }
  if (double.parse(v) > double.parse(kMaxStellarAmount)) {
    return 'Amount is too large.';
  }
  return null;
}

/// Withdrawal-specific amount check: must be a valid amount AND within the
/// contract's available balance. The contract is the true enforcer on-chain;
/// this exists so the user hears "that's more than the pool holds" BEFORE
/// signing, not as a failed transaction after. Returns the error or null.
String? withdrawalAmountError(String value, double availableBalance) {
  final base = amountError(value);
  if (base != null) return base;
  final n = double.parse(value.trim());
  if (availableBalance > 0 && n > availableBalance) {
    return 'Amount exceeds the contract balance (${availableBalance.toStringAsFixed(2)} XLM).';
  }
  return null;
}

/// Human message for an invalid recipient key, or null when valid.
String? publicKeyError(String value) {
  final v = value.trim();
  if (v.isEmpty) return 'Enter the recipient\u2019s Stellar address.';
  if (!RegExp(kPublicKeyPattern).hasMatch(v)) {
    return 'Stellar addresses start with G and are 56 characters long.';
  }
  if (!isValidStellarPublicKey(v)) {
    return 'This address is malformed — check it against the sender before retrying.';
  }
  return null;
}

/// Input formatters for amount fields: digits and one decimal separator
/// only — a negative sign can never be typed, which kills the whole class
/// of negative-amount inputs at the keyboard level.
///
/// Implemented as a reject-the-edit formatter (returning the old value)
/// rather than [FilteringTextInputFormatter.allow]: a full-match allow
/// pattern silently DELETES the whole field when the user types a
/// character that breaks the pattern (the filtered value fails the match),
/// which is hostile UX. Here an invalid keystroke is simply ignored.
List<TextInputFormatter> amountInputFormatters({int maxDecimals = kMaxAmountDecimals}) {
  final pattern = RegExp('^\\d+(\\.\\d{0,$maxDecimals})?\$');
  return [
    TextInputFormatter.withFunction((oldValue, newValue) {
      final candidate = newValue.text;
      if (candidate.isEmpty) return newValue;
      return pattern.hasMatch(candidate) ? newValue : oldValue;
    }),
  ];
}

/// Input formatter for PayTag fields: lowercase letters, digits, underscore.
List<TextInputFormatter> payTagInputFormatters() => [
      FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
      LengthLimitingTextInputFormatter(20),
    ];

/// Input formatter for memo fields: hard cap at 28 bytes' worth of chars
/// (a char may be multi-byte, so the exact byte check still happens in
/// [isValidMemo] before submission).
List<TextInputFormatter> memoInputFormatters() => [
      LengthLimitingTextInputFormatter(kMaxMemoBytes),
    ];
