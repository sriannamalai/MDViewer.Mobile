// Thousands.format: the "1,140"-style grouped-digit strings
// design/README.md §03's outline-sheet header shows next to "words".

import 'package:app/src/util/thousands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single digits and small numbers are unchanged', () {
    expect(Thousands.format(0), '0');
    expect(Thousands.format(7), '7');
    expect(Thousands.format(42), '42');
    expect(Thousands.format(999), '999');
  });

  test('exactly one thousand gets a single separator', () {
    expect(Thousands.format(1000), '1,000');
    expect(Thousands.format(1140), '1,140');
    expect(Thousands.format(9999), '9,999');
  });

  test('multiple groups separate every three digits', () {
    expect(Thousands.format(10000), '10,000');
    expect(Thousands.format(100000), '100,000');
    expect(Thousands.format(1000000), '1,000,000');
    expect(Thousands.format(12345678), '12,345,678');
  });

  test('negative values keep the sign outside the grouping', () {
    expect(Thousands.format(-1234), '-1,234');
    expect(Thousands.format(-7), '-7');
  });
}
