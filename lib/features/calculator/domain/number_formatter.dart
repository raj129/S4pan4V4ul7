/// Formats calculation results for display.
///
/// Uses up to [maxSignificantDigits] significant digits, thousands grouping
/// for the integer part, and falls back to scientific notation for very large
/// or very small magnitudes.
class NumberFormatter {
  const NumberFormatter({
    this.maxSignificantDigits = 12,
    this.groupSeparator = ',',
    this.decimalSeparator = '.',
  });

  final int maxSignificantDigits;
  final String groupSeparator;
  final String decimalSeparator;

  static const double _scientificUpperBound = 1e12;
  static const double _scientificLowerBound = 1e-9;

  String format(double value) {
    if (value.isNaN) return 'NaN';
    if (value.isInfinite) return value.isNegative ? '-∞' : '∞';
    if (value == 0) return '0';

    final magnitude = value.abs();
    if (magnitude >= _scientificUpperBound || magnitude < _scientificLowerBound) {
      return _formatScientific(value);
    }

    final plain = _trimTrailingZeros(
      _toFixedSignificant(value, maxSignificantDigits),
    );
    if (plain == '0' || plain == '-0') return '0';
    return _group(plain);
  }

  /// Formats without grouping — used where the value is fed back into an
  /// expression rather than shown as a standalone result.
  String formatRaw(double value) =>
      format(value).replaceAll(groupSeparator, '');

  String _toFixedSignificant(double value, int significantDigits) {
    final magnitude = value.abs();
    final exponent = magnitude == 0 ? 0 : _floorLog10(magnitude);
    final decimals = (significantDigits - 1 - exponent).clamp(0, 17).toInt();
    return value.toStringAsFixed(decimals);
  }

  int _floorLog10(double magnitude) {
    // Derive the exponent from the scientific rendering to avoid the rounding
    // drift of log10 near powers of ten.
    final scientific = magnitude.toStringAsExponential(15);
    final exponentPart = scientific.split('e').last;
    return int.parse(exponentPart);
  }

  String _formatScientific(double value) {
    var mantissaAndExponent = value.toStringAsExponential(
      maxSignificantDigits - 1,
    );
    final parts = mantissaAndExponent.split('e');
    final mantissa = _trimTrailingZeros(parts.first);
    final exponent = int.parse(parts.last);
    return '${mantissa}E$exponent';
  }

  String _trimTrailingZeros(String text) {
    if (!text.contains('.')) return text;
    var result = text.replaceFirst(RegExp(r'0+$'), '');
    if (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }
    return result.isEmpty ? '0' : result;
  }

  String _group(String plain) {
    final negative = plain.startsWith('-');
    final unsigned = negative ? plain.substring(1) : plain;
    final dotIndex = unsigned.indexOf('.');
    final integerPart = dotIndex == -1
        ? unsigned
        : unsigned.substring(0, dotIndex);
    final fractionPart = dotIndex == -1 ? '' : unsigned.substring(dotIndex + 1);

    final buffer = StringBuffer();
    for (var i = 0; i < integerPart.length; i++) {
      final remaining = integerPart.length - i;
      buffer.write(integerPart[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(groupSeparator);
      }
    }

    final grouped = buffer.toString();
    final sign = negative ? '-' : '';
    return fractionPart.isEmpty
        ? '$sign$grouped'
        : '$sign$grouped$decimalSeparator$fractionPart';
  }
}
