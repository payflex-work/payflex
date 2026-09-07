import 'package:intl/intl.dart';

/// Single shared money-formatting utility used app-wide.
/// Ensures consistent currency symbol placement, thousands separators,
/// and decimal handling across balances, amounts, and receipts.
class MoneyFormatter {
  static final _currencyFormat = NumberFormat.currency(
    symbol: '\$',
    decimalDigits: 2,
    name: 'USD',
  );

  static final _compactFormat = NumberFormat.compactCurrency(
    symbol: '\$',
    decimalDigits: 0,
  );

  static final _referenceFormat = NumberFormat('0000000000');

  /// Full currency string: $1,234.56
  static String format(double amount, {bool compact = false}) {
    return compact ? _compactFormat.format(amount) : _currencyFormat.format(amount);
  }

  /// Raw number with thousands separators only (no currency symbol)
  static String formatNumber(double amount) {
    return NumberFormat('#,##0.00').format(amount);
  }

  /// Returns the integer portion formatted for large balance display
  /// (e.g. the big number on wallet home).
  static String formatBalance(double amount) {
    final whole = amount.round();
    final decimal = amount - whole;
    final wholeStr = NumberFormat('#,##0').format(whole);
    if (decimal.abs() < 0.005) return wholeStr;
    final decimalStr = NumberFormat('.00#').format(decimal).replaceFirst('-', '');
    return '$wholeStr$decimalStr';
  }

  /// ISO currency code (used in receipt headers and reference strings)
  static const String currencyCode = 'USD';

  /// Generate a payment reference number: PFC-XXXXXXXXXX
  static String referenceNumber([int? seed]) {
    final n = seed ?? DateTime.now().millisecondsSinceEpoch & 0xFFFFFFF;
    return 'PFC-${_referenceFormat.format(n)}';
  }
}
