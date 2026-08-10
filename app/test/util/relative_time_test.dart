// RelativeTime.format: the short "2h"/"1d" style labels design/README.md
// §01's Recent section shows next to each row.

import 'package:app/src/util/relative_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 11, 12);

  test('under a minute reads "now"', () {
    expect(
      RelativeTime.format(now.subtract(const Duration(seconds: 5)), now: now),
      'now',
    );
  });

  test('a slightly-future timestamp (clock skew) also reads "now"', () {
    expect(
      RelativeTime.format(now.add(const Duration(seconds: 30)), now: now),
      'now',
    );
  });

  test('minutes bucket as "Nm"', () {
    expect(
      RelativeTime.format(now.subtract(const Duration(minutes: 1)), now: now),
      '1m',
    );
    expect(
      RelativeTime.format(now.subtract(const Duration(minutes: 45)), now: now),
      '45m',
    );
  });

  test('hours bucket as "Nh"', () {
    expect(
      RelativeTime.format(now.subtract(const Duration(hours: 1)), now: now),
      '1h',
    );
    expect(
      RelativeTime.format(now.subtract(const Duration(hours: 2)), now: now),
      '2h',
    );
    expect(
      RelativeTime.format(now.subtract(const Duration(hours: 23)), now: now),
      '23h',
    );
  });

  test('a full day rolls over from hours to days', () {
    expect(
      RelativeTime.format(now.subtract(const Duration(hours: 24)), now: now),
      '1d',
    );
  });

  test('days bucket as "Nd"', () {
    expect(
      RelativeTime.format(now.subtract(const Duration(days: 1)), now: now),
      '1d',
    );
    expect(
      RelativeTime.format(now.subtract(const Duration(days: 6)), now: now),
      '6d',
    );
  });

  test('a month or more bucket as "Nmo"', () {
    expect(
      RelativeTime.format(now.subtract(const Duration(days: 30)), now: now),
      '1mo',
    );
    expect(
      RelativeTime.format(now.subtract(const Duration(days: 90)), now: now),
      '3mo',
    );
  });

  test('a year or more buckets as "Ny"', () {
    expect(
      RelativeTime.format(now.subtract(const Duration(days: 365)), now: now),
      '1y',
    );
  });

  test('defaults `now` to the wall clock when not provided', () {
    final justNow = DateTime.now().subtract(const Duration(seconds: 1));
    expect(RelativeTime.format(justNow), 'now');
  });
}
