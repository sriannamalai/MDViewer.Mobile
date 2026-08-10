/// Formats an integer with comma thousands separators (`1140` →
/// `"1,140"`) — design/README.md §03's outline-sheet header ("1,140 words
/// · 5 min"). A pure string transform (no `intl` dependency) grouping
/// digits into runs of three from the right.
class Thousands {
  const Thousands._();

  /// Groups [value]'s digits with `,` every three places from the right.
  /// Negative values keep their sign outside the grouping (`-1234` →
  /// `"-1,234"`) — defensive: word counts are never negative in practice,
  /// but the transform stays correct rather than assuming the input's sign.
  static String format(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }

    return negative ? '-$buffer' : buffer.toString();
  }
}
